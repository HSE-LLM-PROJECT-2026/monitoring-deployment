#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/home/oleg/Documents/hse-llm-project/cluster-config/llm_proj_talos/kubeconfig}"
NAMESPACE="${NAMESPACE:-monitoring}"
RESEND_SECRET_NAME="${RESEND_SECRET_NAME:-resend-smtp-password}"
RESEND_API_KEY="${RESEND_API_KEY:-}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[monitoring] ERROR: command not found: kubectl" >&2
  exit 1
fi

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "[monitoring] ERROR: kubeconfig not found: $KUBECONFIG_PATH" >&2
  exit 1
fi

if [[ -z "$RESEND_API_KEY" ]]; then
  echo "[monitoring] ERROR: RESEND_API_KEY is empty" >&2
  echo "[monitoring] Usage: RESEND_API_KEY='<api-key>' ./create-resend-secret.sh" >&2
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$NAMESPACE" create secret generic "$RESEND_SECRET_NAME" \
  --from-literal=password="$RESEND_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[monitoring] Resend SMTP secret synced: $NAMESPACE/$RESEND_SECRET_NAME"
