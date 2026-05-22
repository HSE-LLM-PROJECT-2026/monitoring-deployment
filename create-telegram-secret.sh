#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/home/oleg/Documents/hse-llm-project/cluster-config/llm_proj_talos/kubeconfig}"
NAMESPACE="${NAMESPACE:-monitoring}"
TELEGRAM_SECRET_NAME="${TELEGRAM_SECRET_NAME:-telegram-ups-bot-token}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[monitoring] ERROR: command not found: kubectl" >&2
  exit 1
fi

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "[monitoring] ERROR: kubeconfig not found: $KUBECONFIG_PATH" >&2
  exit 1
fi

if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
  echo "[monitoring] ERROR: TELEGRAM_BOT_TOKEN is empty" >&2
  echo "[monitoring] Usage: TELEGRAM_BOT_TOKEN='<token>' ./create-telegram-secret.sh" >&2
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$NAMESPACE" create secret generic "$TELEGRAM_SECRET_NAME" \
  --from-literal=token="$TELEGRAM_BOT_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[monitoring] Telegram secret synced: $NAMESPACE/$TELEGRAM_SECRET_NAME"
