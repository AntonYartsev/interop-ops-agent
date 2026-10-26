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

LIVE_FLAG=0
RESET_ONLY=0
AUTOAPPROVE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --live)
      LIVE_FLAG=1
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
    -h|--help)
      echo "Usage: $0 [--live] [--manual] [--reset]"
      echo "  --manual Disable auto-approve: pending_review cases (e.g. C01) wait in the Workflow Inbox for a human"
      echo "  --reset  Decision.Purge(), reload IOA.LabCodeMap from data/labcodemap.csv (drops agent patches),"
      echo "           move leftover files from cases/in to cases/archive/<timestamp>/ (nothing is deleted), then exit"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--live]" >&2
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

if [ "$LIVE_FLAG" -eq 1 ]; then
  DEMO_MODE="LIVE"
else
  DEMO_MODE="REPLAY"
fi

echo "Mode: ${DEMO_MODE} (profile=${ACTIVE_PROFILE}, autoapprove=${AUTOAPPROVE})"

if [ "$LIVE_FLAG" -eq 1 ] && [ -z "$ACTIVE_KEY_VAL" ]; then
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

if [ "$RESET_ONLY" -eq 1 ]; then
  RESET_OUT="$(mktemp)"
  printf '%s\n' \
    'do ##class(InteropOps.Data.Decision).Purge()' \
    'do ##class(InteropOps.Setup).LoadLabCodeMap()' \
    'do ##class(InteropOps.Config.LLMConfig).SetLive(0)' \
    'write "DECISIONS_LEFT=",##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM InteropOps_Data.Decision").%Next(),!' \
    'halt' \
    | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >"$RESET_OUT" 2>&1 || true
  grep -E 'LABCODEMAP_' "$RESET_OUT" | tr -d '\r' || true
  rm -f "$RESET_OUT"
  shopt -s nullglob
  LEFTOVER=( "${CASES_IN_HOST}"/* )
  shopt -u nullglob
  if [ "${#LEFTOVER[@]}" -gt 0 ]; then
    ARCH="cases/archive/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$ARCH"
    mv "${LEFTOVER[@]}" "$ARCH/"
    echo "Moved ${#LEFTOVER[@]} leftover file(s) from ${CASES_IN_HOST} to ${ARCH}"
  fi
  echo "RESET: OK (decisions purged, LabCodeMap reloaded, LIVE off)"
  exit 0
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
  'write "HAS_DECISION_REPORT=",(##class(%Dictionary.CompiledClass).%ExistsId("InteropOps.Data.Decision")&&##class(%Dictionary.CompiledMethod).%ExistsId("InteropOps.Data.Decision||ReportJSON")),!' \
  'halt' \
  | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >"$TMP_OUT" 2>&1 || true

if [ "$LIVE_FLAG" -eq 1 ] && ! grep -q "KEY_PRESENT=1" "$TMP_OUT"; then
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
  "do ##class(InteropOps.Config.LLMConfig).SetLive(${LIVE_FLAG})" \
  "do ##class(InteropOps.Config.LLMConfig).SetAutoApprove(${AUTOAPPROVE})" \
  'write "ACTIVE_LLM_MODE=",##class(InteropOps.Config.LLMConfig).Mode(),!' \
  'write "AUTOAPPROVE=",##class(InteropOps.Config.LLMConfig).AutoApprove(),!' \
  'halt' \
  | docker exec -i "$CONTAINER" iris session IRIS -U "$NS" >"$TMP_OUT" 2>&1 || true

ACTIVE_LLM_MODE="$(sed -n 's/^ACTIVE_LLM_MODE=//p' "$TMP_OUT" | tr -d '\r' | tail -n 1)"
if [ "$LIVE_FLAG" -eq 1 ] && [ "$ACTIVE_LLM_MODE" != "LIVE" ]; then
  echo "ERROR: --live requested, but resolved mode is ${ACTIVE_LLM_MODE:-REPLAY} (check ${ACTIVE_KEY_VAR} and REPLAY env)." >&2
  exit 1
fi

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
    REPORT_JSON_PAYLOAD="$json_payload" CASE_IDS_CSV="$CASE_IDS_CSV" python3 - << 'PYEOF'
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
for r in rows:
    if not isinstance(r, dict):
        continue
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
  printf '%s' "$REPORT_JSON" | WEB_PORT="$WEB_PORT" NS="$NS" EXPECTED_MAP_FILE="$EXPECTED_MAP_FILE" python3 "${SCRIPT_DIR}/score_demo.py"
else
  echo "python3 not found; raw ReportJSON:"
  echo "$REPORT_JSON"
fi
