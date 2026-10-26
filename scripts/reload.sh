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
  'do ##class(InteropOps.Setup).Reload()' \
  'halt' \
  | docker exec -i "$CONTAINER_NAME" iris session IRIS -U IRISAPP >"$TMP_OUT" 2>&1 || true

cat "$TMP_OUT"

if grep -q "RELOAD_RESULT=OK" "$TMP_OUT"; then
  echo "RELOAD OK"
  exit 0
else
  echo "RELOAD FAIL"
  exit 1
fi
