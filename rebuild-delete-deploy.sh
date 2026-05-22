#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="$(basename "$(cd "$SCRIPT_DIR/.." && pwd)")"
SKIP_BUILD="${SKIP_BUILD:-false}"
STEP_TIMEOUT_SECONDS="${STEP_TIMEOUT_SECONDS:-7200}"
BUILD_TIMEOUT_SECONDS="${BUILD_TIMEOUT_SECONDS:-7200}"
DELETE_TIMEOUT_SECONDS="${DELETE_TIMEOUT_SECONDS:-1800}"
DEPLOY_TIMEOUT_SECONDS="${DEPLOY_TIMEOUT_SECONDS:-3600}"
NETWORK_TIMEOUT_SECONDS="${NETWORK_TIMEOUT_SECONDS:-1800}"

log() {
  echo "[${SERVICE_NAME}] $*"
}

require_script() {
  local script_path="$1"
  [[ -x "$script_path" ]] || {
    echo "[${SERVICE_NAME}] ERROR: script not found or not executable: $script_path" >&2
    exit 1
  }
}

run_step() {
  local title="$1"
  local script_path="$2"
  local timeout_seconds="${3:-$STEP_TIMEOUT_SECONDS}"
  log "== $title (timeout: ${timeout_seconds}s) =="
  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "${timeout_seconds}s" "$script_path"
  else
    "$script_path"
  fi
}

BUILD_SCRIPT="$SCRIPT_DIR/build-and-push.sh"
DELETE_SCRIPT="$SCRIPT_DIR/delete-all.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-from-scratch.sh"
NETWORK_SCRIPT="$SCRIPT_DIR/deploy-network.sh"

require_script "$DELETE_SCRIPT"
require_script "$DEPLOY_SCRIPT"

if [[ "$SKIP_BUILD" == "true" ]]; then
  log "== Skip build (SKIP_BUILD=true) =="
elif [[ -x "$BUILD_SCRIPT" ]]; then
  run_step "Build and push image" "$BUILD_SCRIPT" "$BUILD_TIMEOUT_SECONDS"
else
  log "== Build step skipped: $BUILD_SCRIPT not found =="
fi

run_step "Delete current release" "$DELETE_SCRIPT" "$DELETE_TIMEOUT_SECONDS"
run_step "Deploy from scratch" "$DEPLOY_SCRIPT" "$DEPLOY_TIMEOUT_SECONDS"

if [[ -x "$NETWORK_SCRIPT" ]]; then
  run_step "Update HTTPRoute/network resources" "$NETWORK_SCRIPT" "$NETWORK_TIMEOUT_SECONDS"
else
  log "== Network step skipped: $NETWORK_SCRIPT not found =="
fi

log "Done: build -> delete -> deploy -> network update completed."
