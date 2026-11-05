#!/usr/bin/env bash
# Clean run from scratch, as a judge would do it:
#   1. docker compose -p interop-ops-agent down -v   (containers, network and anonymous
#                          volumes of THIS project only; images and the repo bind mount are kept)
#   2. ./run.sh           (load/tag image if needed, compose up, compile, start the production)
#   3. scripts/demo.sh --replay   (12 cases from cassettes, no LLM API calls)
#   4. EXPECT_REPLAY=1 scripts/check.sh   (provider kind must be REPLAY)
#   5. scripts/smoke_generic.sh   (a non-Cnn file name/MSH-10 gets a CaseId and a final rules decision; runs
#                                  after check, removes its own Decision row, so the 12-case score is unaffected)
# Each step and the total are timed. Last line:
#   CLEAN_RUN: OK  score 12/12  mode REPLAY  llm_calls 0  smoke OK  total 4m12s
#   CLEAN_RUN: FAIL  step <name>  ...
# Step 1 destroys the IRIS container state, so it only runs with --yes. Without --yes the script runs the
# read-only safety checks, prints what it would do and exits 2. Bash 3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_DIR"

PROJECT="interop-ops-agent"
CONTAINER="interop-ops-agent-iris-1"
LABEL="com.docker.compose.project"
YES=0
for a in "$@"; do
  case "$a" in
    --yes) YES=1 ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      echo "Usage: $0 [--yes]"
      exit 0
      ;;
    *) echo "Unknown option: $a (usage: $0 [--yes])" >&2; exit 1 ;;
  esac
done

fmt() { printf '%dm%02ds' $(( $1 / 60 )) $(( $1 % 60 )); }
fail() { echo "CLEAN_RUN: FAIL  step $1  ($2)  total $(fmt $SECONDS)"; exit 1; }

# ---- safety checks (read-only docker queries; nothing is exec'ed in a container) ----
command -v docker >/dev/null 2>&1 || fail safety "docker not found"
docker info >/dev/null 2>&1 || fail safety "docker daemon not reachable"
grep -q "^name: ${PROJECT}\$" docker-compose.yml || fail safety "docker-compose.yml project name is not ${PROJECT}"
if grep -Eq '^[[:space:]]*external:[[:space:]]*true' docker-compose.yml; then
  fail safety "docker-compose.yml declares an external volume/network (could be shared with another project)"
fi

PROBLEMS=""
# the fixed container name must belong to this project (or not exist)
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  owner="$(docker inspect -f "{{index .Config.Labels \"${LABEL}\"}}" "$CONTAINER" 2>/dev/null)"
  [ "$owner" = "$PROJECT" ] || PROBLEMS="${PROBLEMS}container ${CONTAINER} belongs to project '${owner}'; "
fi
OUR_CONTAINERS="$(docker ps -a --filter "label=${LABEL}=${PROJECT}" --format '{{.Names}}' | tr '\n' ' ')"
OUR_NETWORKS="$(docker network ls --filter "label=${LABEL}=${PROJECT}" --format '{{.Name}}' | tr '\n' ' ')"
OUR_VOLUMES="$(docker volume ls --filter "label=${LABEL}=${PROJECT}" --format '{{.Name}}' | tr '\n' ' ')"
# anonymous volumes of our containers (removed by down -v)
for c in $OUR_CONTAINERS; do
  for v in $(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$c" 2>/dev/null); do
    case " $OUR_VOLUMES " in *" $v "*) ;; *) OUR_VOLUMES="${OUR_VOLUMES}${v} " ;; esac
  done
done
# no container of another project may use our networks or volumes
for n in $OUR_NETWORKS; do
  for c in $(docker ps -a --filter "network=${n}" --format '{{.Names}}'); do
    p="$(docker inspect -f "{{index .Config.Labels \"${LABEL}\"}}" "$c" 2>/dev/null)"
    [ "$p" = "$PROJECT" ] || PROBLEMS="${PROBLEMS}network ${n} is used by ${c} (project '${p}'); "
  done
done
for v in $OUR_VOLUMES; do
  for c in $(docker ps -a --filter "volume=${v}" --format '{{.Names}}'); do
    p="$(docker inspect -f "{{index .Config.Labels \"${LABEL}\"}}" "$c" 2>/dev/null)"
    [ "$p" = "$PROJECT" ] || PROBLEMS="${PROBLEMS}volume ${v} is used by ${c} (project '${p}'); "
  done
done
OTHER_PROJECTS="$(docker ps -a --format "{{.Label \"${LABEL}\"}}" | grep -v "^${PROJECT}\$" | grep -v '^$' | sort -u | tr '\n' ' ')"

echo "Project:            ${PROJECT}"
echo "Containers removed: ${OUR_CONTAINERS:-none}"
echo "Networks removed:   ${OUR_NETWORKS:-none}"
echo "Volumes removed:    ${OUR_VOLUMES:-none}"
echo "Kept:               images, repo files (bind mount ./), other compose projects: ${OTHER_PROJECTS:-none}"
if [ -n "$PROBLEMS" ]; then
  fail safety "another compose project would be affected: ${PROBLEMS}"
fi
echo "Safety: OK (only project ${PROJECT} is affected)"

if [ "$YES" -ne 1 ]; then
  echo "DRY RUN: would run, in order:"
  echo "  1. docker compose -p ${PROJECT} down -v"
  echo "  2. ./run.sh                  -> image load/tag if needed, compose up -d --build, compile, start production"
  echo "  3. scripts/demo.sh --replay  -> 12 cases from replay/ cassettes, no LLM API calls"
  echo "  4. EXPECT_REPLAY=1 scripts/check.sh -> FAIL unless provider kind is REPLAY"
  echo "  5. scripts/smoke_generic.sh  -> one generic lab-feed-<date>.hl7 (no Cnn ids), final rules decision, cleans up its row"
  echo "Step 1 deletes the IRIS container state of ${PROJECT}. Re-run with --yes to do it."
  echo "CLEAN_RUN: NOT RUN (dry run, no --yes)"
  exit 2
fi

LOG_DIR="$(mktemp -d)"
TIMES=""
step() { # $1 = name, rest = command
  local name="$1"; shift
  local t0=$SECONDS
  echo "== ${name}: $*"
  "$@" >"${LOG_DIR}/${name}.log" 2>&1
  local rc=$?
  local dt=$(( SECONDS - t0 ))
  TIMES="${TIMES}${name} $(fmt $dt)  "
  if [ $rc -ne 0 ]; then
    tail -n 20 "${LOG_DIR}/${name}.log" | grep -Eiv 'api_key=|sk-' || true
    fail "$name" "exit ${rc} after $(fmt $dt); log ${LOG_DIR}/${name}.log"
  fi
  echo "   ok in $(fmt $dt)"
}

step clean docker compose -p "${PROJECT}" down -v
step run ./run.sh
step demo ./scripts/demo.sh --replay
step check env EXPECT_REPLAY=1 ./scripts/check.sh
step smoke ./scripts/smoke_generic.sh

DEMO_LOG="${LOG_DIR}/demo.log"
SCORE="$(sed -n 's/^correct \([0-9]*\/[0-9]*\).*/\1/p' "$DEMO_LOG" | tail -n 1)"
MODE="$(sed -n 's/^Mode: \([A-Z]*\) (from Decision rows.*/\1/p' "$DEMO_LOG" | tail -n 1)"
CALLS="$(sed -n 's/^Mode: .*LLM calls: \([0-9]*\).*/\1/p' "$DEMO_LOG" | tail -n 1)"
grep -q '^CHECK: OK' "${LOG_DIR}/check.log" || fail check "CHECK: OK missing; log ${LOG_DIR}/check.log"
grep -q '^SMOKE_GENERIC: OK' "${LOG_DIR}/smoke.log" || fail smoke "SMOKE_GENERIC: OK missing; log ${LOG_DIR}/smoke.log"
case "$SCORE" in ""|0/*) fail demo "score ${SCORE:-?} (no score line)";; esac
[ "${SCORE%/*}" = "${SCORE#*/}" ] || fail demo "score ${SCORE} (expected all cases correct)"
[ "$MODE" = "REPLAY" ] || fail demo "mode ${MODE:-?} (expected REPLAY)"
[ "${CALLS:-x}" = "0" ] || fail demo "llm_calls ${CALLS:-?} (expected 0)"
echo "Steps: ${TIMES}"
echo "CLEAN_RUN: OK  score ${SCORE:-?}  mode ${MODE}  llm_calls ${CALLS}  smoke OK  total $(fmt $SECONDS)"
