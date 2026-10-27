#!/usr/bin/env bash
# Run ON THE SERVER. Loads the IRIS ARM64 archive and tags it as the Dockerfile base (same logic as ../run.sh).
# Copy first, from your workstation:
#   scp irishealth_arm64-community-2026.3.0AI.154.0-docker.tar.gz deploy/load-image.sh <user>@<server>:~/
# Usage: ./load-image.sh [archive]
set -euo pipefail
TARBALL="${1:-$HOME/irishealth_arm64-community-2026.3.0AI.154.0-docker.tar.gz}"
ORIG_IMAGE="docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0"
LOCAL_TAG="irishealth-aihub:2026.3.0AI.154.0"   # = ARG IMAGE default in Dockerfile
SRC_IMAGE="$ORIG_IMAGE"

if docker image inspect "$LOCAL_TAG" >/dev/null 2>&1; then
  echo "Tag $LOCAL_TAG already exists; nothing to do."
  exit 0
fi
if ! docker image inspect "$ORIG_IMAGE" >/dev/null 2>&1; then
  [ -f "$TARBALL" ] || { echo "Archive not found: $TARBALL" >&2; exit 1; }
  LOAD_OUT="$(docker image load -i "$TARBALL")"
  printf '%s\n' "$LOAD_OUT"
  LOADED_NAME="$(printf '%s\n' "$LOAD_OUT" | sed -n 's/^Loaded image: //p' | tail -n 1)"
  [ -z "$LOADED_NAME" ] || SRC_IMAGE="$LOADED_NAME"
fi
docker tag "$SRC_IMAGE" "$LOCAL_TAG"
echo "Tagged $SRC_IMAGE as $LOCAL_TAG"
