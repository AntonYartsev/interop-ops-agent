#!/usr/bin/env bash
# Smoke test: a case file WITHOUT a Cnn name (generic lab feed) still gets a CaseId and a final, rules-only decision.
#   - builds cases/archive/smoke-<ts>/lab-feed-<YYYYMMDD>.hl7 from cases/C06-duplicate-flood.hl7 (synthetic):
#     every MSH-10 C06-MSGnnn is rewritten (the 50x duplicated C06-MSG031 -> MSG<YYYYMMDD>-0001, the rest
#     -> MSG<YYYYMMDD>-0002..), no Cnn prefix left anywhere, \r segment separators kept.
#     Rule A1 (identical duplicate MSH-10) decides it: quarantine, never reaches the agent, no LLM call.
#   - copies it into cases/in, polls the Decision table up to SMOKE_TIMEOUT s (default 60) for a NEW row with
#     MSH10 MSG<YYYYMMDD>-0001 and asserts: CaseId non-empty and not Cnn, FinalStatus final (not pending_review),
#     LLMCalls=0, Mode REPLAY and ProviderFactory.Kind() REPLAY.
#   - cleanup: deletes only that row by id (Data.Decision.DeleteSmokeRow, also kills ^IOA.Batch of its CaseId) and
#     moves the file (leftover in cases/in, or the copy the file service archived) into cases/archive/smoke-<ts>/.
#     Nothing is rm'ed. Refuses to run with recording on (would write a cassette) or with files waiting in cases/in.
# Last line: SMOKE_GENERIC: OK | SMOKE_GENERIC: FAIL <reason>. Exit 0 only on OK. Bash 3.2 compatible.
set -uo pipefail
cd "$(dirname "$0")/.."
CONTAINER="${CONTAINER:-interop-ops-agent-iris-1}"
NS="${NS:-IRISAPP}"
TIMEOUT="${SMOKE_TIMEOUT:-60}"
CASES_IN_HOST="${CASES_IN_HOST:-cases/in}"
SRC="cases/C06-duplicate-flood.hl7"
DAY="$(date +%Y%m%d)"
TS="$(date +%Y%m%d-%H%M%S)"
MSH10="MSG${DAY}-0001"
NAME="lab-feed-${DAY}.hl7"
ARCH="cases/archive/smoke-${TS}"
OUT="$(mktemp)"
ROW_ID=""

result() { # $1 = OK|FAIL, $2 = reason
  if [ "$1" = "OK" ]; then echo "SMOKE_GENERIC: OK${2:+  $2}"; else echo "SMOKE_GENERIC: FAIL $2"; fi
}

iris() { # one ObjectScript command per argument line
  { printf '%s\n' "$@"; printf '%s\n' 'halt'; } | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >"$OUT" 2>&1
}
val() { sed -n "s/^$1=//p" "$OUT" | tr -d '\r' | tail -n 1; }

cleanup() {
  if [ -n "$ROW_ID" ]; then
    iris "do ##class(InteropOps.Data.Decision).DeleteSmokeRow(${ROW_ID},\"${MSH10}\")"
    echo "cleanup: $(sed -n 's/^SMOKE_DELETED=/row deleted: /p' "$OUT" | tr -d '\r' | tail -n 1)"
  fi
  mkdir -p "$ARCH"
  [ -f "${CASES_IN_HOST}/${NAME}" ] && mv "${CASES_IN_HOST}/${NAME}" "${ARCH}/leftover-${NAME}"
  # the file service archives a consumed file into cases/archive/ (name may get a timestamp suffix)
  for f in cases/archive/"${NAME}"*; do
    [ -f "$f" ] && mv "$f" "${ARCH}/"
  done
  mv "$OUT" "${ARCH}/iris-last-session.txt" 2>/dev/null
}

fail() { cleanup; result FAIL "$1"; exit 1; }

[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ] || { result FAIL "container $CONTAINER not running"; exit 1; }
[ -f "$SRC" ] || { result FAIL "$SRC missing"; exit 1; }
shopt -s nullglob
WAITING=( "${CASES_IN_HOST}"/* )
shopt -u nullglob
[ "${#WAITING[@]}" -eq 0 ] || { result FAIL "${CASES_IN_HOST} not empty (${#WAITING[@]} file(s)); run after demo.sh finished"; exit 1; }

# Preconditions in IRIS: REPLAY, recording off, highest Decision id before the drop
iris 'write "MODE=",##class(InteropOps.Config.LLMConfig).Mode(),!' \
  'write "KIND=",##class(InteropOps.Agent.ProviderFactory).Kind(),!' \
  'write "RECORD=",+##class(InteropOps.Config.LLMConfig).RecordEnabled(),!' \
  'set mx=0,st=##class(%SQL.Statement).%New(),sc=st.%Prepare("SELECT MAX(ID) AS M FROM InteropOps_Data.Decision") if sc { set rs=st.%Execute() if rs.%Next() { set mx=+rs.M } } write "MAXID=",mx,!'
MODE="$(val MODE)"; KIND="$(val KIND)"; RECORD="$(val RECORD)"; MAXID="$(val MAXID)"
[ -n "$MAXID" ] || { result FAIL "could not query IRIS (session output: $(head -c 300 "$OUT" | tr -d '\r'))"; exit 1; }
[ "$RECORD" = "0" ] || { result FAIL "recording is on (would write a cassette); SetRecord(0) first"; exit 1; }
[ "$MODE" = "REPLAY" ] && [ "$KIND" = "REPLAY" ] || { result FAIL "mode ${MODE:-?} / kind ${KIND:-?}, expected REPLAY / REPLAY"; exit 1; }

# Build the generic file (kept in the smoke archive dir as the source copy)
mkdir -p "$ARCH" "$CASES_IN_HOST"
python3 - "$SRC" "${ARCH}/source-${NAME}" "$DAY" <<'PY' || fail "could not build ${NAME}"
import re, sys
src, dst, day = sys.argv[1], sys.argv[2], sys.argv[3]
d = open(src, "rb").read()
def rw(m):
    n = int(m.group(1))
    k = 1 if n == 31 else (n + 1 if n < 31 else n)
    return ("MSG%s-%04d" % (day, k)).encode()
out = re.sub(rb"C06-MSG(\d{3})", rw, d)
assert b"\n" not in out and out.count(b"\r") == d.count(b"\r"), "segment separators changed"
assert not re.search(rb"C\d\d[-_.]", out), "Cnn prefix left"
assert out.count(("|MSG%s-0001|" % day).encode()) >= 2, "no duplicate MSH-10"
open(dst, "wb").write(out)
PY
cp "${ARCH}/source-${NAME}" "${CASES_IN_HOST}/${NAME}" || fail "copy into ${CASES_IN_HOST} failed"
echo "dropped ${CASES_IN_HOST}/${NAME} (MSH-10 ${MSH10}), waiting up to ${TIMEOUT}s"

ROW=""
T0=$SECONDS
while [ $(( SECONDS - T0 )) -lt "$TIMEOUT" ]; do
  sleep 3
  iris "set st=##class(%SQL.Statement).%New(),sc=st.%Prepare(\"SELECT TOP 1 ID FROM InteropOps_Data.Decision WHERE MSH10=? AND ID>? ORDER BY ID DESC\") if sc { set rs=st.%Execute(\"${MSH10}\",${MAXID}) if rs.%Next() { set o=##class(InteropOps.Data.Decision).%OpenId(rs.ID) write \"ROW=\",o.%Id(),\"|\",o.CaseId,\"|\",o.FinalStatus,\"|\",+o.LLMCalls,\"|\",o.Mode,\"|\",o.Source,\"|\",o.Action,! } }"
  ROW="$(val ROW)"
  if [ -n "$ROW" ]; then
    ROW_ID="${ROW%%|*}"
    # quarantine is final at once; wait a little more only if a review row shows up
    case "$ROW" in *"|pending_review|"*) continue ;; esac
    break
  fi
done
[ -n "$ROW" ] || fail "no Decision row with MSH10 ${MSH10} within ${TIMEOUT}s"

IFS='|' read -r R_ID R_CASE R_FINAL R_CALLS R_MODE R_SOURCE R_ACTION <<EOF2
$ROW
EOF2
echo "row: id=${R_ID} CaseId=${R_CASE} FinalStatus=${R_FINAL} LLMCalls=${R_CALLS} Mode=${R_MODE} Source=${R_SOURCE} Action=${R_ACTION}"
iris 'write "KIND=",##class(InteropOps.Agent.ProviderFactory).Kind(),!'
KIND="$(val KIND)"

[ -n "$R_CASE" ] || fail "CaseId empty"
case "$R_CASE" in C[0-9][0-9]|c[0-9][0-9]) fail "CaseId ${R_CASE} looks like a demo case" ;; esac
case "$R_FINAL" in passed|quarantined|escalated|applied|rejected) ;; *) fail "FinalStatus '${R_FINAL}' not final" ;; esac
[ "$R_CALLS" = "0" ] || fail "LLMCalls=${R_CALLS} (expected 0)"
[ "$R_MODE" = "REPLAY" ] || fail "Mode=${R_MODE} (expected REPLAY)"
[ "$KIND" = "REPLAY" ] || fail "provider kind ${KIND:-?} (expected REPLAY)"

cleanup
result OK "CaseId ${R_CASE}, ${R_ACTION} -> ${R_FINAL}, LLMCalls 0, REPLAY"
exit 0
