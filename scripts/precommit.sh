#!/usr/bin/env bash
# Pre-commit check, run by hand before `git commit` (no git hook is installed):
#   ./scripts/precommit.sh
# Reads the STAGED content from the git index in memory (no temp files):
#   staged replay/*.json -> ioa-replay/1 schema + secret scan (sk- keys, Bearer, Authorization, key env values);
#   every other staged file -> sk- keys and key env values; a staged .env fails without being read.
# Never prints matched values. Exit 0 = OK.
set -uo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/validate_replay.py --staged
