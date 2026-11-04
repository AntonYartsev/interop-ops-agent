#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
mkdir -p cases/in cases/archive   # gitignored runtime dirs; IOA.In.CaseFile needs both

CURRENT_STEP="initializing"
on_error() {
  local exit_code=$?
  echo "ERROR during step: ${CURRENT_STEP} (exit code ${exit_code})" >&2
  echo "FINAL STATUS: FAIL"
  exit "$exit_code"
}
trap on_error ERR

# --- Arguments and server guard. Runs before any docker command. ---
# ./run.sh         local stack (Mac/Linux), iris ports published on the host (51272/52273/52280)
# ./run.sh --demo  server stack: -f docker-compose.yml -f deploy/docker-compose.demo.yml (iris ports removed,
#                  Caddy on 80/443 in front of the web port; needs DEMO_DOMAIN and ACME_EMAIL, see deploy/README.md)
DEMO_OVERLAY="deploy/docker-compose.demo.yml"
USE_DEMO=0
for arg in "$@"; do
  case "$arg" in
    --demo) USE_DEMO=1 ;;
    -h|--help)
      echo "Usage: ./run.sh [--demo]"
      echo "  (no flag)  local stack, iris ports published on the host"
      echo "  --demo     server stack with ${DEMO_OVERLAY} (no iris ports on the host, Caddy on 80/443)"
      exit 0 ;;
    *) echo "Unknown option: ${arg} (see ./run.sh --help)" >&2; exit 2 ;;
  esac
done
# DEMO_DOMAIN set in the environment or in .env (value never printed) = this is a server: refuse without the overlay
demo_domain_set() {
  [ -n "${DEMO_DOMAIN:-}" ] && return 0
  [ -f .env ] && grep -Eq "^[[:space:]]*(export[[:space:]]+)?DEMO_DOMAIN=[\"']?[^\"'[:space:]#]" .env
}
COMPOSE_FILES=()
if [ "$USE_DEMO" -eq 0 ]; then
  if demo_domain_set; then
    echo "REFUSED: DEMO_DOMAIN is set (environment or .env), so this looks like the public demo server." >&2
    echo "         Plain ./run.sh would publish the iris ports 51272/52273/52280 on all interfaces." >&2
    echo "         Use ./run.sh --demo (adds ${DEMO_OVERLAY}), or unset DEMO_DOMAIN for a local run." >&2
    echo "FINAL STATUS: FAIL"
    exit 3
  fi
  if [ "$(uname -s)" = "Linux" ]; then
    echo "WARNING: Linux host without --demo: iris ports 51272/52273/52280 are published on all interfaces." >&2
    echo "         On a public server use ./run.sh --demo (deploy/README.md)." >&2
  fi
else
  if [ ! -f "$DEMO_OVERLAY" ]; then
    echo "REFUSED: --demo needs ${DEMO_OVERLAY}, not found." >&2
    echo "FINAL STATUS: FAIL"
    exit 3
  fi
  if ! demo_domain_set; then
    echo "REFUSED: --demo needs DEMO_DOMAIN (and ACME_EMAIL) in .env or the environment (deploy/README.md e)." >&2
    echo "FINAL STATUS: FAIL"
    exit 3
  fi
  COMPOSE_FILES=(-f docker-compose.yml -f "$DEMO_OVERLAY")
  echo "Demo mode: docker compose ${COMPOSE_FILES[*]} (iris ports not published, Caddy on 80/443)"
fi

# Default archive by host architecture (both are published on the EAP portal for build 154); IRIS_IMAGE_TAR overrides.
case "$(uname -m)" in
  arm64|aarch64) DEFAULT_TAR="../irishealth_arm64-community-2026.3.0AI.154.0-docker.tar.gz" ;;
  *)             DEFAULT_TAR="../irishealth-community-2026.3.0AI.154.0-docker.tar.gz" ;;
esac
TARBALL="${IRIS_IMAGE_TAR:-$DEFAULT_TAR}"
# Name the ARM64 archive loads as (seen here). After a load, the name from the "Loaded image:" line of
# docker image load is used instead, so another archive (x64) works without knowing its name in advance.
ORIG_IMAGE="docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0"
SRC_IMAGE="$ORIG_IMAGE"
LOCAL_TAG="irishealth-aihub:2026.3.0AI.154.0"
PROJECT_NAME="interop-ops-agent"
CONTAINER_NAME="interop-ops-agent-iris-1"

CURRENT_STEP="checking local Docker images"
if docker image inspect "$LOCAL_TAG" >/dev/null 2>&1 || docker image inspect "$ORIG_IMAGE" >/dev/null 2>&1; then
  echo "Base image already loaded locally; skipping docker image load."
else
  CURRENT_STEP="checking image archive ${TARBALL}"
  if [ ! -f "$TARBALL" ]; then
    echo "Base image not loaded and archive not found at: $TARBALL (set IRIS_IMAGE_TAR=/path/to/archive.tar.gz)" >&2
    false
  fi
  CURRENT_STEP="loading Docker image from ${TARBALL}"
  LOAD_OUT="$(docker image load -i "$TARBALL")"
  printf '%s\n' "$LOAD_OUT"
  LOADED_NAME="$(printf '%s\n' "$LOAD_OUT" | sed -n 's/^Loaded image: //p' | tail -n 1)"
  if [ -n "$LOADED_NAME" ]; then SRC_IMAGE="$LOADED_NAME"; fi
fi

CURRENT_STEP="ensuring local image tag ${LOCAL_TAG}"
if ! docker image inspect "$LOCAL_TAG" >/dev/null 2>&1; then
  docker tag "$SRC_IMAGE" "$LOCAL_TAG"
  echo "Tagged ${SRC_IMAGE} as ${LOCAL_TAG}"
else
  echo "Tag ${LOCAL_TAG} already exists; keeping existing tag."
fi

CURRENT_STEP="ensuring .env exists and merging missing keys from .env.example"
if [ ! -f .env ]; then
  cp .env.example .env
  chmod 600 .env
  echo "Created .env from .env.example (chmod 600)"
else
  chmod 600 .env
  while IFS= read -r env_line || [ -n "$env_line" ]; do
    case "$env_line" in
      ""|\#*) continue ;;
      *=*)
        env_key="${env_line%%=*}"
        if [ -n "$env_key" ] && ! grep -q "^${env_key}=" .env; then
          printf '\n%s\n' "$env_line" >> .env
          echo "Appended missing key to .env: ${env_key}"
        fi
        ;;
    esac
  done < .env.example
  chmod 600 .env
fi

# On Linux the bind-mounted repo belongs to the host user; the file service runs as irisowner (uid 51773)
# and must read, delete and archive files here. Docker Desktop (Mac) maps ownership, so it needs nothing.
if [ "$(uname -s)" = "Linux" ]; then
  chmod a+rwx cases/in cases/archive
fi

# --- live_env_check (begin) ---
# Warn when IOA_LIVE in .env differs from the running container. Compose puts IOA_LIVE into the container
# environment at creation, and that wins over the mounted .env, so an edited .env needs a recreate.
# Reads ONLY the IOA_LIVE line of .env and ONLY the IOA_LIVE entry of the container env (never the full Env,
# which holds the API key). Prints only the two 0/1 values. Silent when the container is not running.
ioa_live_01() {
  case "$(printf '%s' "$1" | tr -d '"'"'"'\r ' | tr '[:upper:]' '[:lower:]')" in
    1|true|yes) echo 1 ;;
    *) echo 0 ;;
  esac
}
live_env_check() { # $1 = .env file, $2 = container name; DOCKER_BIN overrides docker (tests)
  local env_file="$1" container="$2" docker_bin="${DOCKER_BIN:-docker}" env_raw ctr_raw env_val ctr_val
  [ -f "$env_file" ] || return 0
  [ "$("$docker_bin" inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" = "true" ] || return 0
  env_raw="$(sed -n 's/^IOA_LIVE=//p' "$env_file" | tail -n 1)"
  ctr_raw="$("$docker_bin" inspect --format '{{range .Config.Env}}{{if eq (index (split . "=") 0) "IOA_LIVE"}}{{.}}{{end}}{{end}}' "$container" 2>/dev/null | sed -n 's/^IOA_LIVE=//p' | tail -n 1)"
  env_val="$(ioa_live_01 "$env_raw")"
  ctr_val="$(ioa_live_01 "$ctr_raw")"
  if [ "$env_val" != "$ctr_val" ]; then
    echo "WARNING: IOA_LIVE in .env = ${env_val}, in the running container = ${ctr_val}."
    echo "         ./run.sh recreates the container with the .env value (docker compose up -d below);"
    echo "         without recreating: ./scripts/demo.sh --live or ./scripts/demo.sh --replay for one run."
  fi
  return 0
}
# --- live_env_check (end) ---
CURRENT_STEP="checking IOA_LIVE in .env against the running container"
live_env_check .env "$CONTAINER_NAME"

CURRENT_STEP="reading host port configuration from .env"
set -a
# shellcheck disable=SC1091
. ./.env
set +a

if [ -n "${OPENAI_API_KEY:-}" ]; then
  echo "OPENAI_API_KEY: set"
else
  echo "OPENAI_API_KEY: unset"
fi
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  echo "OPENROUTER_API_KEY: set"
else
  echo "OPENROUTER_API_KEY: unset"
fi

IRIS_PORT_SUPER="${IRIS_PORT_SUPER:-51272}"
IRIS_PORT_WEB="${IRIS_PORT_WEB:-52273}"
IRIS_PORT_AUX="${IRIS_PORT_AUX:-52280}"

CURRENT_STEP="checking host port availability (${IRIS_PORT_SUPER}, ${IRIS_PORT_WEB}, ${IRIS_PORT_AUX})"
check_port_free_or_owned() {
  local port="$1"
  local own_running="false"
  if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")" = "true" ]; then
    if docker port "$CONTAINER_NAME" 2>/dev/null | grep -Eq ":${port}$"; then
      own_running="true"
    fi
  fi

  if [ "$own_running" = "true" ]; then
    return 0
  fi

  local other_container
  other_container="$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E ":${port}->" | awk '{print $1}' | grep -v "^${CONTAINER_NAME}$" || true)"
  if [ -n "$other_container" ]; then
    echo "Host port ${port} is already held by another container: ${other_container}" >&2
    return 1
  fi

  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"${port}" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
      echo "Host port ${port} is already in use on the host (not held by ${CONTAINER_NAME})." >&2
      return 1
    fi
  fi

  return 0
}

if [ "$USE_DEMO" -eq 0 ]; then
  check_port_free_or_owned "$IRIS_PORT_SUPER"
  check_port_free_or_owned "$IRIS_PORT_WEB"
  check_port_free_or_owned "$IRIS_PORT_AUX"
fi

CURRENT_STEP="starting stack with docker compose -p ${PROJECT_NAME}${COMPOSE_FILES[*]+ ${COMPOSE_FILES[*]}}"
# ${arr[@]+...}: an empty array is "unbound" under set -u in bash 3.2 (macOS)
docker compose -p "$PROJECT_NAME" ${COMPOSE_FILES[@]+"${COMPOSE_FILES[@]}"} up -d --build

CURRENT_STEP="waiting for ${CONTAINER_NAME} to become healthy (timeout 300s)"
ELAPSED=0
TIMEOUT=300
HEALTH_STATUS="starting"
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  HEALTH_STATUS="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing")"
  if [ "$HEALTH_STATUS" = "healthy" ]; then
    break
  fi
  if [ "$HEALTH_STATUS" = "unhealthy" ] || [ "$HEALTH_STATUS" = "exited" ] || [ "$HEALTH_STATUS" = "dead" ]; then
    echo "Container ${CONTAINER_NAME} entered state: ${HEALTH_STATUS}" >&2
    docker logs --tail 50 "$CONTAINER_NAME" >&2 || true
    false
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ "$HEALTH_STATUS" != "healthy" ]; then
  echo "Timed out after ${TIMEOUT}s waiting for ${CONTAINER_NAME} health (status=${HEALTH_STATUS})" >&2
  false
fi

CURRENT_STEP="reloading and compiling src via scripts/reload.sh"
./scripts/reload.sh

CURRENT_STEP="running InitAndStartProduction in IRISAPP"
INIT_TMP="$(mktemp)"
printf '%s\n' \
  'do $SYSTEM.OBJ.ImportDir("/irisdev/app/src","*.cls","ck",.e,1)' \
  'do ##class(InteropOps.Setup).InitAndStartProduction()' \
  'halt' \
  | docker exec -i "$CONTAINER_NAME" iris session IRIS -U IRISAPP >"$INIT_TMP" 2>&1 || true
INIT_OUT="$(cat "$INIT_TMP")"
rm -f "$INIT_TMP"
echo "$INIT_OUT"

echo "$INIT_OUT" | grep -q "PRODUCTION_STATUS=RUNNING"
echo "$INIT_OUT" | grep -q "DEEPSEE_ENABLED=1"

RESOLVED_PROFILE="$(echo "$INIT_OUT" | sed -n 's/^LLM_PROFILE=//p' | tr -d '\r' | tail -n 1)"
RESOLVED_MODE="$(echo "$INIT_OUT" | sed -n 's/^LLM_MODE=//p' | tr -d '\r' | tail -n 1)"

PORTAL_URL="http://localhost:${IRIS_PORT_WEB}/csp/sys/UtilHome.csp"
PRODUCTION_URL="http://localhost:${IRIS_PORT_WEB}/csp/irisapp/EnsPortal.ProductionConfig.zen?\$NAMESPACE=IRISAPP&PRODUCTION=InteropOps.Production"
WORKFLOW_URL="http://localhost:${IRIS_PORT_WEB}/csp/irisapp/EnsPortal.WFWorklist.zen?\$NAMESPACE=IRISAPP"

if [ "$USE_DEMO" -eq 1 ]; then
  echo "------------------------------------------------------------"
  echo "Demo mode: the web port is not published on the host, so the localhost HTTP checks are skipped."
  echo "Check https://<DEMO_DOMAIN>/ through Caddy (deploy/README.md, f and g)."
  echo "LLM Profile:           ${RESOLVED_PROFILE}"
  echo "LLM Mode:              ${RESOLVED_MODE}"
  echo "------------------------------------------------------------"
  echo "FINAL STATUS: OK"
  exit 0
fi

CURRENT_STEP="HTTP-checking Management Portal URL (${PORTAL_URL})"
PORTAL_HTTP="$(curl -s -o /dev/null -w '%{http_code}' -u _SYSTEM:SYS "$PORTAL_URL")"
if [ "$PORTAL_HTTP" != "200" ] && [ "$PORTAL_HTTP" != "302" ]; then
  echo "Unexpected HTTP status ${PORTAL_HTTP} from Management Portal: ${PORTAL_URL}" >&2
  false
fi

CURRENT_STEP="HTTP-checking Workflow Inbox URL (${WORKFLOW_URL})"
WF_HTTP="$(curl -s -o /dev/null -w '%{http_code}' -u _SYSTEM:SYS "$WORKFLOW_URL")"
if [ "$WF_HTTP" != "200" ] && [ "$WF_HTTP" != "302" ]; then
  echo "Unexpected HTTP status ${WF_HTTP} from Workflow Inbox: ${WORKFLOW_URL}" >&2
  false
fi

echo "------------------------------------------------------------"
echo "Management Portal URL: ${PORTAL_URL}"
echo "Production URL:        ${PRODUCTION_URL}"
echo "Workflow Inbox URL:    ${WORKFLOW_URL}"
echo "LLM Profile:           ${RESOLVED_PROFILE}"
echo "LLM Mode:              ${RESOLVED_MODE}"
echo "------------------------------------------------------------"
echo "FINAL STATUS: OK"
