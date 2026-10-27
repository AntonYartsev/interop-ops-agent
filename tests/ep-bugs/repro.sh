#!/usr/bin/env bash
# Embedded Python bug repro: ./tests/ep-bugs/repro.sh [container]. Namespace USER, no network, no LLM.
set -uo pipefail
C="${1:-interop-ops-agent-iris-1}"
DIR="$(cd "$(dirname "$0")" && pwd)"
docker cp "$DIR/EPBug.Repro.cls" "$C:/tmp/EPBug.Repro.cls" >/dev/null
printf '%s\n' 'do $system.OBJ.Load("/tmp/EPBug.Repro.cls","ck-d")' 'write "LOADED",!' 'halt' \
  | docker exec -i "$C" iris session IRIS -U USER | tr -d '\r' | grep -E 'LOADED|ERROR'
# one clean process per case; AFTER is missing when the process died
run() {
  local out
  out="$(printf '%s\n' 'write "BEFORE",!' "try { $2 } catch ex { write \"CAUGHT \",ex.DisplayString(),! }" 'write "AFTER",!' 'halt' \
    | docker exec -i "$C" iris session IRIS -U USER 2>&1 | tr -d '\r' | grep -E '^(BEFORE|AFTER|CAUGHT|R=)' | tr '\n' ' ')"
  echo "$1: $out"
}
run "case1 high surrogate arg" 'write "R=",##class(EPBug.Repro).Len("a"_$c(55357)_"b"),!'
run "case1 low surrogate arg " 'write "R=",##class(EPBug.Repro).Len("a"_$c(56832)_"b"),!'
run "case1 control: valid pair" 'write "R=",##class(EPBug.Repro).Len("a"_$c(55357,56832)_"b"),!'
run "case1 compare: %SYS.Python" 'write "R=",##class(%SYS.Python).Import("builtins").len("a"_$c(55357)_"b"),!'
run "case2 return lone surrogate" 'set s=##class(EPBug.Repro).RetLone() write "R=",s," codes=" for i=1:1:$l(s) { write $a(s,i)," " } write !'
run "case3 2**62 (control)" 'write "R=",##class(EPBug.Repro).Pow2(62),!'
run "case3 2**63" 'write "R=",##class(EPBug.Repro).Pow2(63),!'
run "case3 2**70" 'write "R=",##class(EPBug.Repro).Pow2(70),!'
run "case3 builtins.pow(2,70)" 'write "R=",##class(%SYS.Python).Import("builtins").pow(2,70),!'
run "case4 ByRef value arg" 'set a=1 write "R=",##class(EPBug.Repro).TwoRef(a,2),!'
docker exec "$C" sh -c 'grep "caught signal 11" /usr/irissys/mgr/messages.log | tail -2'
