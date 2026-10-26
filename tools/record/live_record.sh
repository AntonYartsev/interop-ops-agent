#!/bin/bash
# ONE paid recording run (LIVE + record on, via LLMConfig.SetLive/SetRecord). Run from anywhere. Spends API credit: run it only on purpose.
# Env: MAX_CALLS (40) MAX_USD (0.10) TIMEOUT (900 s) PRICE_IN / PRICE_OUT (USD per 1M tokens, assumed 0.75 / 4.50: check your price list)
# Saves the live/record state at start and restores exactly that on exit (undefined stays undefined), prints Mode(),
# then validates replay/C*.json. Never prints env or keys.
R=$(cd "$(dirname "$0")/../.." && pwd); C=${CONTAINER:-interop-ops-agent-iris-1}
MAX_CALLS=${MAX_CALLS:-40}; MAX_USD=${MAX_USD:-0.10}; TIMEOUT=${TIMEOUT:-900}
PRICE_IN=${PRICE_IN:-0.75}; PRICE_OUT=${PRICE_OUT:-4.50}
IDS="C01 C02 C03 C04 C05 C06 C07 C08 C09 C10 C11 C12"
iris() { { cat; echo; echo halt; } | docker exec -i "$C" iris session IRIS -U IRISAPP 2>&1 | tr -d '\r' | grep -v '^IRISAPP>$' | sed 's/^IRISAPP>//'; }
# original state: <name>=<value> or <name>=UNDEF, read from ^IOA.Config
ORIG=$(echo 'for n="live","record" { write "ORIG_",n,"=",$select($data(^IOA.Config(n))#2:^IOA.Config(n),1:"UNDEF"),! }' | iris | grep '^ORIG_')
OL=$(echo "$ORIG" | sed -n 's/^ORIG_live=//p'); OR=$(echo "$ORIG" | sed -n 's/^ORIG_record=//p')
restore_cmd() { # $1 = name, $2 = SetLive|SetRecord, $3 = original value
  if [ "$3" = UNDEF ] || [ -z "$3" ]; then echo "kill ^IOA.Config(\"$1\")"; else echo "do ##class(InteropOps.Config.LLMConfig).$2($3)"; fi
}
revert() {
  trap - EXIT INT TERM
  { restore_cmd live SetLive "$OL"; restore_cmd record SetRecord "$OR"; echo 'write "MODE_AFTER=",##class(InteropOps.Config.LLMConfig).Mode(),!'; } | iris | grep MODE_AFTER
  n=0; bad=0
  for f in "$R"/replay/C*.json; do n=$((n+1)); python3 "$R/scripts/validate_replay.py" "$f" >/dev/null 2>&1 || { bad=$((bad+1)); echo "VALIDATE_FAIL $f"; }; done
  echo "VALIDATE files=$n failed=$bad"
}
trap revert EXIT INT TERM
(cd "$R" && ./scripts/demo.sh --reset | tail -1)
MARK=$(mktemp); sleep 1
PRE=$(printf '%s\n' 'kill ^IOA.UnitFactor' 'kill ^IOA.Budget' 'kill ^IOA.Dev' 'do ##class(InteropOps.Config.LLMConfig).SetAutoApprove(1)' 'do ##class(InteropOps.Config.LLMConfig).SetRecord(1)' 'do ##class(InteropOps.Config.LLMConfig).SetLive(1)' 'write "PRE|",##class(InteropOps.Config.LLMConfig).Mode(),"|",##class(InteropOps.Config.LLMConfig).Model(),"|",##class(InteropOps.Config.LLMConfig).Profile(),"|",##class(InteropOps.Config.LLMConfig).RecordEnabled(),"|",##class(InteropOps.Config.LLMConfig).AutoApprove(),"|",$data(^IOA.Dev),"|",+$get(^IOA.Budget("calls")),!' | iris | grep '^PRE|')
echo "MODE_BEFORE $PRE  (mode|model|profile|record|autoapprove|dev|budget_calls)"
[ "$PRE" = "PRE|LIVE|${EXPECT_MODEL:-gpt-5.4-mini}|openai|1|1|0|0" ] || { echo "ABORT: pre-flight failed, no cases dropped, no paid call"; exit 3; }
START=$(echo 'write "MAXID=",+$order(^InteropOps.Data.DecisionD(""),-1),!' | iris | sed -n 's/^MAXID=//p')
# one line per case: CASE|FinalStatus|Source of the LAST row after START; then BUDGET|calls|tokens_in|tokens_out
cat > /tmp/ioa_poll.$$ <<Q
for c="C01","C02","C03","C04","C05","C06","C07","C08","C09","C10","C11","C12" { set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 FinalStatus,Source FROM InteropOps_Data.Decision WHERE CaseId=? AND ID>? ORDER BY ID DESC",c,$START) if rs.%Next() { write "ROW|",c,"|",rs.FinalStatus,"|",rs.Source,! } }
write "BUDGET|",+\$get(^IOA.Budget("calls")),"|",+\$get(^IOA.Budget("tokens_in")),"|",+\$get(^IOA.Budget("tokens_out")),!
Q
for c in $IDS; do cp "$R"/cases/$c-*.hl7 "$R"/cases/in/; done
t=0; rc=1
while [ $t -lt "$TIMEOUT" ]; do
  out=$(iris < /tmp/ioa_poll.$$ | grep -E '^(ROW|BUDGET)\|')
  IFS='|' read -r _ calls tin tout <<< "$(echo "$out" | grep '^BUDGET')"
  usd=$(awk -v a="${tin:-0}" -v b="${tout:-0}" -v pi="$PRICE_IN" -v po="$PRICE_OUT" 'BEGIN{printf "%.4f",(a*pi+b*po)/1e6}')
  if [ "${calls:-0}" -gt "$MAX_CALLS" ] || awk -v u="$usd" -v m="$MAX_USD" 'BEGIN{exit !(u>m)}'; then
    echo "ABORT: budget exceeded (calls=$calls max=$MAX_CALLS usd=$usd max=$MAX_USD)"; rc=2; break
  fi
  done_n=0; pend=""
  for c in $IDS; do
    line=$(echo "$out" | grep "^ROW|$c|"); st=$(echo "$line" | cut -d'|' -f3); src=$(echo "$line" | cut -d'|' -f4)
    case "$st" in applied|passed|quarantined|escalated|rejected) ;; *) pend="$pend $c"; continue;; esac
    if [ "$src" != "rules" ] && ! [ "$R/replay/$c.json" -nt "$MARK" ]; then pend="$pend $c(cassette)"; continue; fi
    done_n=$((done_n+1))
  done
  [ $done_n -eq 12 ] && { rc=0; break; }
  sleep 3; t=$((t+3))
done
[ $rc -eq 1 ] && echo "ABORT: timeout ${TIMEOUT}s, not final:$pend"
echo "RESULT rc=$rc final=$done_n/12 calls=${calls:-?} tokens=${tin:-?}/${tout:-?} est_usd=${usd:-?} waited=${t}s"
rm -f "$MARK" /tmp/ioa_poll.$$
exit $rc
