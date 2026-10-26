#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-interop-ops-agent-iris-1}"

IPM_PREINSTALLED="NO"
IPM_INSTALL_WORKS="NO"
ZPM_LOAD_TRIVIAL_MODULE_XML="NO"
VERDICT="NO"
ERROR_TEXT=""

TMP_OUT="$(mktemp)"
cleanup() {
  rm -f "$TMP_OUT"
}
trap cleanup EXIT INT TERM

printf '%s\n' \
  'write "HAS_ZPM=",$select(##class(%Dictionary.CompiledClass).%ExistsId("%ZPM.PackageManager")||##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main"):"YES",1:"NO"),!' \
  'halt' \
  | docker exec -i "$CONTAINER_NAME" iris session IRIS -U IRISAPP >"$TMP_OUT" 2>&1 || true

if grep -q "HAS_ZPM=YES" "$TMP_OUT"; then
  IPM_PREINSTALLED="YES"
  IPM_INSTALL_WORKS="YES"
else
  IPM_PREINSTALLED="NO"
  docker exec -i "$CONTAINER_NAME" wget -q -O /tmp/zpm.xml https://github.com/intersystems/ipm/releases/latest/download/zpm.xml >"$TMP_OUT" 2>&1 || true
  printf '%s\n' \
    'set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck")' \
    'if (+sc=0) write "INSTALL_ERR=",$SYSTEM.Status.GetErrorText(sc),!' \
    'write "INSTALLED_ZPM=",$select(##class(%Dictionary.CompiledClass).%ExistsId("%ZPM.PackageManager")||##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main"):"YES",1:"NO"),!' \
    'halt' \
    | docker exec -i "$CONTAINER_NAME" iris session IRIS -U %SYS >>"$TMP_OUT" 2>&1 || true

  if grep -q "INSTALLED_ZPM=YES" "$TMP_OUT"; then
    IPM_INSTALL_WORKS="YES"
  else
    IPM_INSTALL_WORKS="NO"
    ERROR_TEXT="IPM install failed: $(cat "$TMP_OUT")"
  fi
fi

if [ "$IPM_PREINSTALLED" = "YES" ] || [ "$IPM_INSTALL_WORKS" = "YES" ]; then
  printf '%s\n' \
    'zn "%SYS"' \
    'do ##class(%IPM.Main).Shell("enable -map -globally")' \
    'zn "IRISAPP"' \
    'set sc=##class(%IPM.Main).Shell("load /home/irisowner/dev -v")' \
    'if (+sc=0) write "ZPM_LOAD_ERR=",$SYSTEM.Status.GetErrorText(sc),!' \
    'write "ZPM_LOAD_OK=",$select(+sc=1:"YES",1:"NO"),!' \
    'halt' \
    | docker exec -i "$CONTAINER_NAME" iris session IRIS -U IRISAPP >"$TMP_OUT" 2>&1 || true

  if grep -q "ZPM_LOAD_OK=YES" "$TMP_OUT"; then
    ZPM_LOAD_TRIVIAL_MODULE_XML="YES"
    VERDICT="YES"
  else
    ZPM_LOAD_TRIVIAL_MODULE_XML="NO"
    VERDICT="NO"
    ERROR_TEXT="zpm load failed: $(cat "$TMP_OUT")"
  fi
fi

echo "IPM_PREINSTALLED=${IPM_PREINSTALLED}"
echo "IPM_INSTALL_WORKS=${IPM_INSTALL_WORKS}"
echo "ZPM_LOAD_TRIVIAL_MODULE_XML=${ZPM_LOAD_TRIVIAL_MODULE_XML}"
echo "VERDICT=${VERDICT}"
if [ "$VERDICT" = "NO" ]; then
  echo "ERROR_TEXT=${ERROR_TEXT}"
fi
