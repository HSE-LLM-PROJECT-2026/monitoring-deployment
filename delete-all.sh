#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

DELETE_NAMESPACE="${DELETE_NAMESPACE:-false}"

log "Deleting monitoring stack resources"
setup

kubectl delete -f "$SERVICEMONITORS_DIR" --ignore-not-found >/dev/null || true
kubectl delete -f "$PROMETHEUS_RULES_DIR" --ignore-not-found >/dev/null || true
kubectl delete -f "$PROBES_DIR" --ignore-not-found >/dev/null || true
delete_alertmanager_configs
delete_tuya_exporter
delete_ups_exporter
kubectl delete secret "$POSTGRES_EXPORTER_DSN_SECRET_NAME" -n "$NAMESPACE" --ignore-not-found >/dev/null || true

helm uninstall "$POSTGRES_EXPORTER_RELEASE" -n "$NAMESPACE" >/dev/null 2>&1 || true
helm uninstall "$BLACKBOX_RELEASE" -n "$NAMESPACE" >/dev/null 2>&1 || true
helm uninstall "$DCGM_RELEASE" -n "$NAMESPACE" >/dev/null 2>&1 || true
helm uninstall "$LOKI_RELEASE" -n "$NAMESPACE" >/dev/null 2>&1 || true
helm uninstall "$KPS_RELEASE" -n "$NAMESPACE" >/dev/null 2>&1 || true

if [[ "$DELETE_NAMESPACE" == "true" ]]; then
  kubectl delete namespace "$NAMESPACE" --ignore-not-found >/dev/null || true
fi

log "Delete completed."
