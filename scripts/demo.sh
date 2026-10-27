#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_DIR"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

LIVE_FLAG=""   # "" = keep live as seeded from env by the reset (IOA_LIVE, else 0); 1 = --live; 0 = --replay
RESET_ONLY=0
NO_RESET=0
AUTOAPPROVE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --live|--replay)
      want=1; [ "$1" = "--replay" ] && want=0
      if [ -n "$LIVE_FLAG" ] && [ "$LIVE_FLAG" != "$want" ]; then
        echo "ERROR: --live and --replay are mutually exclusive" >&2
        exit 1
      fi
      LIVE_FLAG=$want
      shift
      ;;
    --manual)
      AUTOAPPROVE=0
      shift
      ;;
    --reset)
      RESET_ONLY=1
      shift
      ;;
    --no-reset)
      NO_RESET=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--live | --replay] [--manual] [--reset | --no-reset]"
      echo "  Every run starts with a full reset: InteropOps.Setup.ResetDemo() (cancel open IOA-Reviewers Workflow tasks,"
      echo "  Decision.Purge, reload IOA.LabCodeMap from data/labcodemap.csv, kill ^IOA.UnitFactor and ^IOA.Batch,"
      echo "  live/record seeded from IOA_LIVE/IOA_RECORD, 0 when unset) and leftover files in cases/in are moved to"
      echo "  cases/archive/<timestamp>/ (nothing is deleted)."
      echo "  --live     LIVE for this run (paid API calls; needs the profile key and REPLAY unset)"
      echo "  --replay   REPLAY for this run, whatever IOA_LIVE says"
      echo "             Neither: the env-derived value after the reset. live is set back to 0 when the script exits."
      echo "  --manual   Disable auto-approve: pending_review cases (e.g. C01) wait in the Workflow Inbox for a human"
      echo "  --reset    Only do the reset, then exit"
      echo "  --no-reset Debugging: keep agent patches (LabCodeMap, ^IOA.UnitFactor) from earlier runs;"
      echo "             Decision rows are still purged so the table shows only this run"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--live | --replay] [--manual] [--reset | --no-reset]" >&2
      exit 1
      ;;
  esac
done

ACTIVE_PROFILE="$(printf '%s' "${LLM_PROFILE:-openai}" | tr '[:upper:]' '[:lower:]')"
if [ "$ACTIVE_PROFILE" = "openrouter" ]; then
  ACTIVE_PROFILE="openrouter"
  ACTIVE_KEY_VAR="OPENROUTER_API_KEY"
  ACTIVE_KEY_VAL="${OPENROUTER_API_KEY:-}"
else
  ACTIVE_PROFILE="openai"
  ACTIVE_KEY_VAR="OPENAI_API_KEY"
  ACTIVE_KEY_VAL="${OPENAI_API_KEY:-}"
fi

if [ "$LIVE_FLAG" = "1" ] && [ -z "$ACTIVE_KEY_VAL" ]; then
  echo "ERROR: --live requested, but ${ACTIVE_KEY_VAR} is unset. Refusing to run in LIVE mode." >&2
  exit 1
fi

CONTAINER="${CONTAINER:-interop-ops-agent-iris-1}"
NS="${NS:-IRISAPP}"
WEB_PORT="${WEB_PORT:-${IRIS_PORT_WEB:-52273}}"
CASES_SRC="${CASES_SRC:-cases}"
CASES_IN_HOST="${CASES_IN_HOST:-cases/in}"
CASE_GLOB="${CASE_GLOB:-C??-*.hl7}"
REPORT_CMD="${REPORT_CMD:-##class(InteropOps.Data.Decision).ReportJSON()}"
EXPECTED_REPLAY_DIR="${EXPECTED_REPLAY_DIR:-replay}"
EXPECTED_MAP_FILE="${EXPECTED_MAP_FILE:-cases/expected.json}"
TIMEOUT="${TIMEOUT:-180}"

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo "false")" != "true" ]; then
  echo "Container ${CONTAINER} is not running. Start the stack first with ./run.sh" >&2
  exit 1
fi

do_reset() {
  local out
  out="$(printf '%s\n' \
    'do ##class(InteropOps.Setup).ResetDemo()' \
    'halt' \
    | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" 2>&1 | tr -d '\r' || true)"
  RESET_OUT="$out"
  printf '%s\n' "$out" | grep -E '^(RESET_|LABCODEMAP_)' | tr '\n' ' ' | sed 's/ $//' || true
  echo
  if ! printf '%s\n' "$out" | grep -q '^RESET_DECISIONS_LEFT=0'; then
    echo "ERROR: reset failed (InteropOps.Setup.ResetDemo missing or Decision rows left)" >&2
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q '^RESET_DEV_MOCK=1'; then
    echo "WARNING: ^IOA.Dev(\"mock_base_url\") is set: agent cases run against the dev mock (MOCK)" >&2
  fi
  shopt -s nullglob
  local leftover=( "${CASES_IN_HOST}"/* )
  shopt -u nullglob
  if [ "${#leftover[@]}" -gt 0 ]; then
    local arch
    arch="cases/archive/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$arch"
    mv "${leftover[@]}" "$arch/"
    echo "Moved ${#leftover[@]} leftover file(s) from ${CASES_IN_HOST} to ${arch}"
  fi
}

if [ "$RESET_ONLY" -eq 1 ]; then
  do_reset
  echo "RESET: OK (open review tasks cancelled, decisions purged, LabCodeMap reloaded, ^IOA.UnitFactor and ^IOA.Batch cleared, $(printf '%s\n' "$RESET_OUT" | sed -n 's/^RESET_FLAGS_FROM_ENV=//p' | head -n 1))"
  exit 0
fi

if [ "$NO_RESET" -eq 1 ]; then
  echo "Reset: skipped (--no-reset; patches from earlier runs are kept)"
else
  do_reset
fi

TMP_OUT="$(mktemp)"
cleanup_live() {
  rm -f "$TMP_OUT"
  printf '%s\n' \
    'do ##class(InteropOps.Config.LLMConfig).SetLive(0)' \
    'halt' \
    | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >/dev/null 2>&1 || true
}
trap cleanup_live EXIT INT TERM

printf '%s\n' \
  'do ##class(InteropOps.Setup).SyncEnvToGlobal()' \
  'write "KEY_PRESENT=",##class(InteropOps.Config.LLMConfig).KeyPresent(),!' \
  'do ##class(InteropOps.Config.LLMConfig).Resolve(.ioacfg) write "KEY_CONFIGURED=",+$get(ioacfg("keyConfigured")),!' \
  'write "HAS_DECISION_REPORT=",(##class(%Dictionary.CompiledClass).%ExistsId("InteropOps.Data.Decision")&&##class(%Dictionary.CompiledMethod).%ExistsId("InteropOps.Data.Decision||ReportJSON")),!' \
  'halt' \
  | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >"$TMP_OUT" 2>&1 || true

# Key flags only (1/0), never values. REPLAY does not need a key, so this is a hint, not an error.
if ! grep -q "KEY_PRESENT=1" "$TMP_OUT" && grep -q "KEY_CONFIGURED=1" "$TMP_OUT"; then
  echo "HINT: key in .env but not in container -> ./run.sh" >&2
fi
if [ "$LIVE_FLAG" = "1" ] && ! grep -q "KEY_PRESENT=1" "$TMP_OUT"; then
  echo "ERROR: --live requested, but active profile key (${ACTIVE_KEY_VAR}) is unset in IRIS. Refusing LIVE mode." >&2
  exit 1
fi

if ! grep -q "HAS_DECISION_REPORT=1" "$TMP_OUT"; then
  echo "core not deployed yet: InteropOps.Data.Decision.ReportJSON missing"
  echo "STATUS: SKIPPED"
  exit 0
fi

shopt -s nullglob
CASE_FILES=( "${CASES_SRC}"/${CASE_GLOB} )
shopt -u nullglob

if [ "${#CASE_FILES[@]}" -eq 0 ]; then
  echo "core not deployed yet: no case files matching ${CASES_SRC}/${CASE_GLOB}"
  echo "STATUS: SKIPPED"
  exit 0
fi

printf '%s\n' \
  'do ##class(InteropOps.Data.Decision).Purge()' \
  "$( [ -n "$LIVE_FLAG" ] && echo "do ##class(InteropOps.Config.LLMConfig).SetLive(${LIVE_FLAG})" )" \
  "do ##class(InteropOps.Config.LLMConfig).SetAutoApprove(${AUTOAPPROVE})" \
  'write "ACTIVE_LLM_MODE=",##class(InteropOps.Config.LLMConfig).Mode(),!' \
  'write "AUTOAPPROVE=",##class(InteropOps.Config.LLMConfig).AutoApprove(),!' \
  'write "ACTIVE_KIND=",##class(InteropOps.Agent.ProviderFactory).Kind(),!' \
  'write "MODE_WARNING=",##class(InteropOps.Config.LLMConfig).ModeWarning(),!' \
  'write "MOCK_URL=",$get(^IOA.Dev("mock_base_url")),!' \
  'write "KIND_WARNING=",##class(InteropOps.Agent.ProviderFactory).KindWarning(),!' \
  'write "ACTIVE_MODEL=",##class(InteropOps.Config.LLMConfig).Model(),!' \
  'write "ACTIVE_RECORD=",##class(InteropOps.Config.LLMConfig).RecordEnabled(),!' \
  'halt' \
  | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >"$TMP_OUT" 2>&1 || true

ACTIVE_LLM_MODE="$(sed -n 's/^ACTIVE_LLM_MODE=//p' "$TMP_OUT" | tr -d '\r' | tail -n 1)"
if [ "$LIVE_FLAG" = "1" ] && [ "$ACTIVE_LLM_MODE" != "LIVE" ]; then
  echo "ERROR: --live requested, but resolved mode is ${ACTIVE_LLM_MODE:-REPLAY} (check ${ACTIVE_KEY_VAR} and REPLAY env)." >&2
  exit 1
fi
ACTIVE_KIND="$(sed -n 's/^ACTIVE_KIND=//p' "$TMP_OUT" | tr -d '\r' | tail -n 1)"
ACTIVE_MODEL="$(sed -n 's/^ACTIVE_MODEL=//p' "$TMP_OUT" | tr -d '\r' | tail -n 1)"
ACTIVE_RECORD="$(sed -n 's/^ACTIVE_RECORD=//p' "$TMP_OUT" | tr -d '\r' | tail -n 1)"
# What IRIS itself reports (not what the flags asked for), so an accidental MOCK or LIVE is visible
echo "IRIS Mode(): ${ACTIVE_LLM_MODE:-?}  provider kind (ProviderFactory.Kind()): ${ACTIVE_KIND:-?}  record: ${ACTIVE_RECORD:-?}"
# Why IRIS fell back (texts name variables only, never key values)
ACTIVE_MODE_WARNING="$(sed -n 's/^MODE_WARNING=//p' "$TMP_OUT" | tr -d '\r' | tail -n 1)"
ACTIVE_KIND_WARNING="$(sed -n 's/^KIND_WARNING=//p' "$TMP_OUT" | tr -d '\r' | tail -n 1)"
[ -n "$ACTIVE_MODE_WARNING" ] && echo "WARN: $ACTIVE_MODE_WARNING" >&2
[ -n "$ACTIVE_KIND_WARNING" ] && echo "WARN: $ACTIVE_KIND_WARNING" >&2
if [ -z "$ACTIVE_KIND" ] || [ -z "$ACTIVE_LLM_MODE" ]; then
  echo "WARNING: could not read Mode()/Kind() from IRIS (session output in ${TMP_OUT})." >&2
elif [ "$ACTIVE_KIND" = "MOCK" ]; then
  echo "WARNING: provider kind is MOCK (^IOA.Dev(\"mock_base_url\") is set): the agent talks to a local mock, not to cassettes or a real LLM." >&2
  echo "         ResetDemo clears ^IOA.Dev; it was skipped (--no-reset) or the override was set after it." >&2
fi
case "$LIVE_FLAG" in
  1) LIVE_SRC="--live" ;;
  0) LIVE_SRC="--replay" ;;
  *) LIVE_SRC="env (IOA_LIVE) after reset" ;;
esac
ACTIVE_MOCK_URL="$(sed -n 's/^MOCK_URL=//p' "$TMP_OUT" | tr -d '\r' | tail -n 1)"
if [ "$ACTIVE_KIND" = "MOCK" ]; then
  echo "##################################################################"
  echo "##                                                              ##"
  echo "##   M O C K   -   local mock LLM, no paid calls                ##"
  echo "##                                                              ##"
  echo "##################################################################"
  echo "MOCK: calls local mock at ${ACTIVE_MOCK_URL:-?}, no paid calls (dummy key; real key not sent)"
  echo "MOCK: IRIS Mode()=${ACTIVE_LLM_MODE:-?}, record=${ACTIVE_RECORD:-0}"
elif [ "$ACTIVE_LLM_MODE" = "LIVE" ]; then
  # Estimate only: token usage recorded in the cassettes x assumed prices (PRICE_IN / PRICE_OUT, USD per 1M tokens)
  EST_USD="$(PRICE_IN="${PRICE_IN:-${LLM_PRICE_IN_PER_M:-0.75}}" PRICE_OUT="${PRICE_OUT:-${LLM_PRICE_OUT_PER_M:-4.50}}" python3 - "$EXPECTED_REPLAY_DIR" <<'PY' 2>/dev/null || echo "?"
import glob, json, os, sys
tin = tout = 0
for f in glob.glob(os.path.join(sys.argv[1], "C*.json")):
    try:
        u = json.load(open(f)).get("usage") or {}
    except Exception:
        continue
    tin += int(u.get("prompt_tokens") or 0)
    tout += int(u.get("completion_tokens") or 0)
print("%.2f (%dk in / %dk out tokens at $%s / $%s per 1M, assumed)" % (
    (tin * float(os.environ["PRICE_IN"]) + tout * float(os.environ["PRICE_OUT"])) / 1e6,
    round(tin / 1000), round(tout / 1000), os.environ["PRICE_IN"], os.environ["PRICE_OUT"]))
PY
)"
  echo "##################################################################"
  echo "##                                                              ##"
  echo "##   L I V E   -   real, paid LLM API calls                     ##"
  echo "##                                                              ##"
  echo "##################################################################"
  echo "LIVE: will call ${ACTIVE_MODEL:-?} (${ACTIVE_PROFILE}), est. cost ~\$${EST_USD} (estimate, not a quote)"
  echo "LIVE: source=${LIVE_SRC}, record=${ACTIVE_RECORD:-0}"
  if [ -z "$LIVE_FLAG" ] && [ -t 0 ]; then
    echo "LIVE comes from IOA_LIVE, not from --live. Ctrl-C within 5 s to abort (or use --replay)."
    sleep 5
  fi
else
  echo "=== REPLAY: no LLM API calls (cassettes in ${EXPECTED_REPLAY_DIR}/; mode=${ACTIVE_LLM_MODE:-REPLAY}, source=${LIVE_SRC}) ==="
fi
echo "Mode: ${ACTIVE_KIND:-${ACTIVE_LLM_MODE:-REPLAY}} (provider kind; profile=${ACTIVE_PROFILE}, autoapprove=${AUTOAPPROVE})"

mkdir -p "$CASES_IN_HOST"

CASE_IDS=()
for src_file in "${CASE_FILES[@]}"; do
  base_name="$(basename "$src_file")"
  stem="${base_name%.hl7}"
  short_id="${stem%%-*}"
  CASE_IDS+=( "$short_id" )
  cp "$src_file" "${CASES_IN_HOST}/${base_name}"
done

CASE_IDS_CSV="$(IFS=,; echo "${CASE_IDS[*]}")"

fetch_report_json() {
  printf '%s\n' \
    "write \"__JSON_BEGIN__\",! do ${REPORT_CMD} write !,\"__JSON_END__\",!" \
    'halt' \
    | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >"$TMP_OUT" 2>/dev/null || true
  awk '/^__JSON_BEGIN__/{flag=1; next} /^__JSON_END__/{flag=0} flag' "$TMP_OUT" | tr -d '\r'
}

check_all_cases_present() {
  local json_payload="$1"
  if command -v python3 >/dev/null 2>&1; then
    REPORT_JSON_PAYLOAD="$json_payload" CASE_IDS_CSV="$CASE_IDS_CSV" AUTOAPPROVE="$AUTOAPPROVE" python3 - << 'PYEOF'
import json
import os
import re
import sys

raw = os.environ.get("REPORT_JSON_PAYLOAD", "").strip()
target_ids = [c.strip().upper() for c in os.environ.get("CASE_IDS_CSV", "").split(",") if c.strip()]
if not raw:
    sys.exit(1)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)

rows = []
if isinstance(data, list):
    rows = data
elif isinstance(data, dict):
    for k in ("decisions", "rows", "items", "cases", "data", "results"):
        if isinstance(data.get(k), list):
            rows = data[k]
            break
    else:
        for k, v in data.items():
            if isinstance(v, dict):
                item = dict(v)
                item.setdefault("caseId", k)
                rows.append(item)

seen = set()
auto = os.environ.get("AUTOAPPROVE", "0") == "1"
for r in rows:
    if not isinstance(r, dict):
        continue
    status = str(r.get("FinalStatus") or r.get("finalStatus") or "").lower()
    if auto and status == "pending_review":
        continue  # auto-approve still running: the human:auto row is not written yet
    cid = str(
        r.get("caseId")
        or r.get("CaseId")
        or r.get("case_id")
        or r.get("case")
        or r.get("Case")
        or r.get("id")
        or r.get("file")
        or ""
    ).strip()
    if not cid:
        continue
    seen.add(cid.upper())
    m = re.match(r"^(C\d{2})", cid, re.IGNORECASE)
    if m:
        seen.add(m.group(1).upper())

if all(t in seen for t in target_ids):
    sys.exit(0)
sys.exit(1)
PYEOF
  elif command -v jq >/dev/null 2>&1; then
    local cid
    for cid in "${CASE_IDS[@]}"; do
      if ! echo "$json_payload" | grep -qi "$cid"; then
        return 1
      fi
    done
    return 0
  else
    local cid
    for cid in "${CASE_IDS[@]}"; do
      if ! echo "$json_payload" | grep -qi "$cid"; then
        return 1
      fi
    done
    return 0
  fi
}

ELAPSED=0
REPORT_JSON="[]"
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  REPORT_JSON="$(fetch_report_json)"
  if [ -n "$REPORT_JSON" ] && check_all_cases_present "$REPORT_JSON"; then
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$REPORT_JSON" | WEB_PORT="$WEB_PORT" NS="$NS" EXPECTED_MAP_FILE="$EXPECTED_MAP_FILE" CONFIG_MODE="${ACTIVE_KIND:-}" python3 "${SCRIPT_DIR}/score_demo.py"
else
  echo "python3 not found; raw ReportJSON:"
  echo "$REPORT_JSON"
fi
