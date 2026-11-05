#!/usr/bin/env bash
# Reviewer health check: prints OK/FAIL per item, exit 0 only if all pass. Never prints secrets.
set -uo pipefail
cd "$(dirname "$0")/.."
CONTAINER="${CONTAINER:-interop-ops-agent-iris-1}"
NS="${NS:-IRISAPP}"
WEB_PORT="${IRIS_PORT_WEB:-52273}"
EXPECTED_LOOKUP="${EXPECTED_LOOKUP:-9}"
FAILS=0
res() { printf '%-4s %s\n' "$1" "$2"; [ "$1" = "FAIL" ] && FAILS=$((FAILS+1)); return 0; }
# EXPECT_REPLAY=1: the provider kind must be REPLAY (FAIL otherwise); MOCK on a local host is allowed without it
EXPECT_REPLAY="${EXPECT_REPLAY:-0}"

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]; then
  res OK "container $CONTAINER running"
else
  res FAIL "container $CONTAINER not running (run ./run.sh)"
  echo "CHECK: FAIL"; exit 1
fi

OUT="$(mktemp)"
printf '%s\n' \
  'set st="" set sc=##class(Ens.Director).GetProductionStatus(.pn,.st) write "PROD=",pn,"|",st,!' \
  'set n=0,k="" for { set k=$order(^Ens.LookupTable("IOA.LabCodeMap",k)) quit:k=""  set n=n+1 } write "LOOKUP=",n,!' \
  'write "SOD=",$data(^Ens.LookupTable("IOA.LabCodeMap","SOD"))," HB=",$data(^Ens.LookupTable("IOA.LabCodeMap","HB")),!' \
  'write "MODE=",##class(InteropOps.Config.LLMConfig).Mode()," PROFILE=",##class(InteropOps.Config.LLMConfig).Profile(),!' \
  'do ##class(InteropOps.Config.LLMConfig).PrintStatus()' \
  'write "REPORT=",##class(%Dictionary.CompiledMethod).%ExistsId("InteropOps.Data.Decision||ReportJSON"),!' \
  'do ##class(InteropOps.Gate.GateTest).Run()' \
  'halt' \
  | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >"$OUT" 2>&1
val() { sed -n "s/^$1=//p" "$OUT" | tr -d '\r' | tail -n 1; }

PROD="$(val PROD)"
# Ens.Director status 1 = Running
if [ "${PROD%%|*}" = "InteropOps.Production" ] && [ "${PROD##*|}" = "1" ]; then
  res OK "production InteropOps.Production RUNNING"
else
  res FAIL "production not running (got: ${PROD:-none})"
fi

LOOKUP="$(val LOOKUP)"
SODHB="$(sed -n 's/^SOD=//p' "$OUT" | tr -d '\r' | tail -n 1)"
PATCHED=0
[ "$SODHB" = "1 HB=1" ] && PATCHED=2
[ "$SODHB" = "1 HB=0" ] || [ "$SODHB" = "0 HB=1" ] && PATCHED=1
if [ "$LOOKUP" = "$EXPECTED_LOOKUP" ]; then
  res OK "IOA.LabCodeMap has $LOOKUP seed codes"
elif [ -n "$LOOKUP" ] && [ "$LOOKUP" -eq $((EXPECTED_LOOKUP + PATCHED)) ] 2>/dev/null; then
  res OK "IOA.LabCodeMap has $EXPECTED_LOOKUP seed codes + $PATCHED applied by the last demo run"
else
  res FAIL "IOA.LabCodeMap has ${LOOKUP:-?} entries, expected $EXPECTED_LOOKUP seed codes (+ SOD/HB patches); run ./scripts/demo.sh --reset"
fi
# demo.sh resets (Setup.ResetDemo) before every run, so patches left by the last run are fine
if [ "$SODHB" = "0 HB=0" ]; then
  res OK "SOD and HB not mapped (clean state)"
else
  res OK "SOD/HB mapped by the last demo run (demo.sh resets them before the next run)"
fi

MODE_LINE="$(sed -n 's/^MODE=//p' "$OUT" | tr -d '\r' | tail -n 1)"
MODE="${MODE_LINE%% *}"
# Key: only YES/NO flags from PrintStatus, never values
KEY_PRESENT="$(val KEY_PRESENT)"
KEY_CONFIGURED="$(val KEY_CONFIGURED)"; KEY_CONFIGURED="${KEY_CONFIGURED%% *}"
KEY_VAR="$(val KEY_VAR)"
if [ "$KEY_PRESENT" = "YES" ]; then
  KEY_TXT="set in IRIS process"
elif [ "$KEY_CONFIGURED" = "YES" ]; then
  KEY_TXT="configured in .env only (container not recreated?)"
else
  KEY_TXT="unset"
fi
if [ "$MODE" = "REPLAY" ] || [ "$MODE" = "LIVE" ]; then
  res OK "mode $MODE_LINE, key${KEY_VAR:+ $KEY_VAR}: $KEY_TXT" | sed 's/ PROFILE=/, profile /'
else
  res FAIL "mode unresolved (LLMConfig missing?)"
fi
[ "$KEY_PRESENT" != "YES" ] && [ "$KEY_CONFIGURED" = "YES" ] && res WARN "key in .env but not in container -> ./run.sh (REPLAY does not need a key)"
KIND="$(val PROVIDER_KIND)"
MODE_WARNING="$(val MODE_WARNING)"
KIND_WARNING="$(val KIND_WARNING)"
# Warnings are informational (not counted as FAIL)
[ -n "$MODE_WARNING" ] && res WARN "$MODE_WARNING"
[ -n "$KIND_WARNING" ] && res WARN "$KIND_WARNING"
# FAIL only if REPLAY was expected (EXPECT_REPLAY=1) and kind is not REPLAY, or kind LIVE while Mode() is REPLAY
if [ "$EXPECT_REPLAY" = "1" ] && [ "$KIND" != "REPLAY" ]; then
  res FAIL "REPLAY expected (EXPECT_REPLAY=1), but provider kind is ${KIND:-?}"
elif [ "$MODE" = "REPLAY" ] && [ "$KIND" = "LIVE" ]; then
  res FAIL "Mode() is REPLAY, but provider kind is LIVE"
elif [ "$KIND" = "MOCK" ]; then
  res OK "provider kind MOCK (local mock, no paid calls)"
elif [ -n "$KIND" ]; then
  res OK "provider kind $KIND"
fi

[ "$(val REPORT)" = "1" ] && res OK "Decision.ReportJSON compiled" || res FAIL "Decision.ReportJSON missing (run ./scripts/reload.sh)"
GT="$(val GATE_TEST)"
[ "$GT" = "PASS" ] && res OK "gate/apply/DTL self-test (InteropOps.Gate.GateTest)" || res FAIL "gate/apply/DTL self-test: ${GT:-not run} (needs a demo.sh run first)"
rm -f "$OUT"

shopt -s nullglob
CASSETTES=( replay/C??.json )
CASES=( cases/C??-*.hl7 )
shopt -u nullglob
[ "${#CASES[@]}" -eq 12 ] && res OK "12 synthetic case files in cases/" || res FAIL "${#CASES[@]} case files in cases/, expected 12"
if [ "${#CASSETTES[@]}" -eq 12 ]; then
  res OK "12 REPLAY cassettes in replay/"
elif [ "$MODE" = "REPLAY" ]; then
  res FAIL "${#CASSETTES[@]}/12 REPLAY cassettes in replay/ (REPLAY needs all 12)"
else
  res OK "${#CASSETTES[@]}/12 cassettes (not required in LIVE)"
fi

# schema ioa-replay/1 + secret scan of replay/*.json; values are never printed (scripts/validate_replay.py)
VR="$(python3 scripts/validate_replay.py 2>&1)"; VRC=$?
VRS="$(printf '%s\n' "$VR" | sed -n 's/^VALIDATE_REPLAY: //p' | tail -n 1)"
if [ "$VRC" -eq 0 ]; then
  res OK "replay/ schema + secret scan: ${VRS:-ok}"
else
  res FAIL "replay/ schema + secret scan: ${VRS:-error} (details: python3 scripts/validate_replay.py)"
fi

for url in "http://localhost:${WEB_PORT}/csp/sys/UtilHome.csp" "http://localhost:${WEB_PORT}/csp/irisapp/EnsPortal.WFWorklist.zen?\$NAMESPACE=IRISAPP"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || echo 000)"
  case "$code" in 200|302|401) res OK "portal reachable ($code) $url" ;; *) res FAIL "portal not reachable ($code) $url" ;; esac
done

[ "$FAILS" -eq 0 ] && { echo "CHECK: OK"; exit 0; } || { echo "CHECK: FAIL ($FAILS)"; exit 1; }
