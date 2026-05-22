#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/home/oleg/Documents/hse-llm-project/cluster-config/llm_proj_talos/kubeconfig}"
NAMESPACE="${NAMESPACE:-monitoring}"
UPS_SECRET_NAME="${UPS_SECRET_NAME:-nut-ups-exporter-config}"
NUT_SERVER="${NUT_SERVER:-10.19.87.6}"
NUT_SERVERPORT="${NUT_SERVERPORT:-3493}"
NUT_USERNAME="${NUT_USERNAME:-exporter}"
NUT_PASSWORD="${NUT_PASSWORD:-exporter_ups_readonly_2026}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[monitoring] ERROR: command not found: kubectl" >&2
  exit 1
fi

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "[monitoring] ERROR: kubeconfig not found: $KUBECONFIG_PATH" >&2
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$NAMESPACE" create secret generic "$UPS_SECRET_NAME" \
  --from-literal=NUT_EXPORTER_SERVER="$NUT_SERVER" \
  --from-literal=NUT_EXPORTER_SERVERPORT="$NUT_SERVERPORT" \
  --from-literal=NUT_EXPORTER_USERNAME="$NUT_USERNAME" \
  --from-literal=NUT_EXPORTER_PASSWORD="$NUT_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[monitoring] UPS exporter secret synced: $NAMESPACE/$UPS_SECRET_NAME"
echo "[monitoring] NUT endpoint: ${NUT_SERVER}:${NUT_SERVERPORT}"
