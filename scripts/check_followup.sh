#!/usr/bin/env bash
# Acceptance check for "the next message with the same change is fixed by the lookup and never reaches the LLM".
#   1. demo.sh --case C01 --replay: the agent proposes SOD -> 2951-2, auto-approve applies it, the batch is reprocessed.
#   2. The same C01 file is sent again, without a reset.
#   3. The new Decision row must be: Source rules, LLMCalls 0, FinalStatus passed.
# Last line: FOLLOWUP: OK | FOLLOWUP: FAIL (...)
set -euo pipefail
cd "$(dirname "$0")/.."
CONTAINER="${CONTAINER:-interop-ops-agent-iris-1}"
NS="${NS:-IRISAPP}"
TIMEOUT="${TIMEOUT:-120}"

isql() {  # one SQL row of the latest C01 Decision: ID|Source|LLMCalls|FinalStatus|Reason
  printf '%s\n' \
    'set r=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 ID,Source,LLMCalls,FinalStatus,Reason FROM InteropOps_Data.Decision WHERE CaseId=? ORDER BY ID DESC","C01") if r.%Next() { write "ROW=",r.ID,"|",r.Source,"|",+r.LLMCalls,"|",r.FinalStatus,"|",$extract(r.Reason,1,160),! }' \
    'halt' | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" 2>/dev/null | tr -d '\r' | sed -n 's/^ROW=//p' | tail -n 1
}

./scripts/demo.sh --case C01 --replay >/dev/null || { echo "FOLLOWUP: FAIL (demo.sh --case C01 did not score 1/1)"; exit 1; }
FIRST="$(isql)"
[ "$(cut -d'|' -f4 <<<"$FIRST")" = "applied" ] || { echo "FOLLOWUP: FAIL (first C01 run not applied: $FIRST)"; exit 1; }
echo "first run:  $FIRST"

cp cases/C01-new-code-sod.hl7 "cases/in/C01-new-code-sod.hl7"
T0=$SECONDS; ROW="$FIRST"
while [ $(( SECONDS - T0 )) -lt "$TIMEOUT" ]; do
  ROW="$(isql)"
  if [ "$(cut -d'|' -f1 <<<"$ROW")" != "$(cut -d'|' -f1 <<<"$FIRST")" ] && [ "$(cut -d'|' -f4 <<<"$ROW")" != "pending_review" ]; then break; fi
  sleep 2
done
echo "second run: $ROW"
IFS='|' read -r ID SRC CALLS FINAL _ <<<"$ROW"
if [ "$ID" = "$(cut -d'|' -f1 <<<"$FIRST")" ]; then echo "FOLLOWUP: FAIL (no new row in ${TIMEOUT}s)"; exit 1; fi
if [ "$SRC" = "rules" ] && [ "$CALLS" = "0" ] && [ "$FINAL" = "passed" ]; then echo "FOLLOWUP: OK"; exit 0; fi
echo "FOLLOWUP: FAIL (source=$SRC llm_calls=$CALLS final=$FINAL; expected rules / 0 / passed)"; exit 1
