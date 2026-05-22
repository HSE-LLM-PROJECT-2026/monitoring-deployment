#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/home/oleg/Documents/hse-llm-project/cluster-config/llm_proj_talos/kubeconfig}"
NAMESPACE="${NAMESPACE:-monitoring}"
TUYA_SECRET_NAME="${TUYA_SECRET_NAME:-tuya-smart-plug-exporter-config}"
TUYA_CONFIG_FILE="${TUYA_CONFIG_FILE:-$SCRIPT_DIR/tuya-exporter/config.yaml}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[monitoring] ERROR: command not found: kubectl" >&2
  exit 1
fi

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "[monitoring] ERROR: kubeconfig not found: $KUBECONFIG_PATH" >&2
  exit 1
fi

if [[ ! -f "$TUYA_CONFIG_FILE" ]]; then
  echo "[monitoring] ERROR: config file not found: $TUYA_CONFIG_FILE" >&2
  echo "[monitoring] Set TUYA_CONFIG_FILE=/path/to/config.yaml" >&2
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$NAMESPACE" create secret generic "$TUYA_SECRET_NAME" \
  --from-file=config.yaml="$TUYA_CONFIG_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[monitoring] Tuya secret synced: $NAMESPACE/$TUYA_SECRET_NAME"
echo "[monitoring] Source file: $TUYA_CONFIG_FILE"
