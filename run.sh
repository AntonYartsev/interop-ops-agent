#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CURRENT_STEP="initializing"
on_error() {
  local exit_code=$?
  echo "ERROR during step: ${CURRENT_STEP} (exit code ${exit_code})" >&2
  echo "FINAL STATUS: FAIL"
  exit "$exit_code"
}
trap on_error ERR

TARBALL="${IRIS_IMAGE_TAR:-../irishealth_arm64-community-2026.3.0AI.154.0-docker.tar.gz}"
ORIG_IMAGE="docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0"
LOCAL_TAG="irishealth-aihub:2026.3.0AI.154.0"
PROJECT_NAME="interop-ops-agent"
CONTAINER_NAME="interop-ops-agent-iris-1"

CURRENT_STEP="checking local Docker images"
if docker image inspect "$ORIG_IMAGE" >/dev/null 2>&1 || docker image inspect "$LOCAL_TAG" >/dev/null 2>&1; then
  echo "Base image already loaded locally; skipping docker image load."
else
  CURRENT_STEP="checking image archive ${TARBALL}"
  if [ ! -f "$TARBALL" ]; then
    echo "Base image not loaded and archive not found at: $TARBALL (set IRIS_IMAGE_TAR=/path/to/archive.tar.gz)" >&2
    false
  fi
  CURRENT_STEP="loading Docker image from ${TARBALL}"
  docker image load -i "$TARBALL"
fi

CURRENT_STEP="ensuring local image tag ${LOCAL_TAG}"
if ! docker image inspect "$LOCAL_TAG" >/dev/null 2>&1; then
  docker tag "$ORIG_IMAGE" "$LOCAL_TAG"
  echo "Tagged ${ORIG_IMAGE} as ${LOCAL_TAG}"
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

check_port_free_or_owned "$IRIS_PORT_SUPER"
check_port_free_or_owned "$IRIS_PORT_WEB"
check_port_free_or_owned "$IRIS_PORT_AUX"

CURRENT_STEP="starting stack with docker compose -p ${PROJECT_NAME}"
docker compose -p "$PROJECT_NAME" up -d --build

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
