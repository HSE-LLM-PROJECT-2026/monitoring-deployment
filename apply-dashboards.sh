#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-monitoring}"
DASHBOARDS_DIR="${DASHBOARDS_DIR:-$SCRIPT_DIR/dashboards}"

log() {
  echo "[monitoring-dashboards] $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[monitoring-dashboards] ERROR: command not found: $1" >&2
    exit 1
  }
}

need_cmd kubectl

[[ -d "$DASHBOARDS_DIR" ]] || {
  echo "[monitoring-dashboards] ERROR: dashboards directory not found: $DASHBOARDS_DIR" >&2
  exit 1
}

shopt -s nullglob
files=("$DASHBOARDS_DIR"/*.json)
shopt -u nullglob

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "[monitoring-dashboards] ERROR: no dashboards found in $DASHBOARDS_DIR" >&2
  exit 1
fi

for path in "${files[@]}"; do
  filename="$(basename "$path")"
  basename_no_ext="${filename%.json}"
  slug="$(echo "$basename_no_ext" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr -cd 'a-z0-9-')"
  configmap_name="dashboard-$slug"

  kubectl create configmap "$configmap_name" \
    -n "$NAMESPACE" \
    --from-file="$filename=$path" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  kubectl label configmap "$configmap_name" \
    -n "$NAMESPACE" \
    grafana_dashboard=1 \
    --overwrite >/dev/null

  log "Applied dashboard configmap: $configmap_name"
done

log "All dashboards applied to namespace '$NAMESPACE'."
