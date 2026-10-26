#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-interop-ops-agent-iris-1}"

TMP_OUT="$(mktemp)"
cleanup() {
  rm -f "$TMP_OUT"
}
trap cleanup EXIT INT TERM

printf '%s\n' \
  'do $SYSTEM.OBJ.ImportDir("/irisdev/app/src","*.cls","ck",.e,1)' \
  'do ##class(InteropOps.Config.LLMConfig).CheckSwitching()' \
  'do ##class(InteropOps.Config.LLMConfig).PrintStatus()' \
  'halt' \
  | docker exec -i "$CONTAINER_NAME" iris session IRIS -U IRISAPP >"$TMP_OUT" 2>&1 || true

cat "$TMP_OUT"
grep -q "CHECK_SWITCHING=PASS" "$TMP_OUT"
