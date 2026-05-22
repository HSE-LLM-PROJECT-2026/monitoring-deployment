#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

DELETE_NAMESPACE="${DELETE_NAMESPACE:-false}"
WAIT_NAMESPACE_TIMEOUT="${WAIT_NAMESPACE_TIMEOUT:-300}"
AUTO_FIX_GRAFANA_GATEWAY="${AUTO_FIX_GRAFANA_GATEWAY:-true}"
GRAFANA_ROUTE_NAMESPACE="${GRAFANA_ROUTE_NAMESPACE:-hse-llm-project}"
GRAFANA_ROUTE_NAME="${GRAFANA_ROUTE_NAME:-grafana-route}"
GRAFANA_ROUTE_WAIT_TIMEOUT="${GRAFANA_ROUTE_WAIT_TIMEOUT:-180}"
CILIUM_OPERATOR_ROLLOUT_TIMEOUT="${CILIUM_OPERATOR_ROLLOUT_TIMEOUT:-300}"
DNS_AUTOSET_DIR="${DNS_AUTOSET_DIR:-$SCRIPT_DIR/../k8s-dns-pipeline/auto-set-domain-name}"
GRAFANA_REFERENCEGRANT_MANIFEST="${GRAFANA_REFERENCEGRANT_MANIFEST:-$DNS_AUTOSET_DIR/07-referencegrant-grafana.yaml}"
GRAFANA_HTTPROUTE_MANIFEST="${GRAFANA_HTTPROUTE_MANIFEST:-$DNS_AUTOSET_DIR/08-httproute-grafana.yaml}"

wait_for_namespace_deletion() {
  local deadline=$((SECONDS + WAIT_NAMESPACE_TIMEOUT))
  while ((SECONDS < deadline)); do
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
      log "Namespace '$NAMESPACE' deleted."
      return 0
    fi
    sleep 2
  done

  echo "[monitoring] ERROR: timeout while waiting namespace '$NAMESPACE' deletion (${WAIT_NAMESPACE_TIMEOUT}s)." >&2
  return 1
}

route_exists() {
  kubectl get httproute "$GRAFANA_ROUTE_NAME" -n "$GRAFANA_ROUTE_NAMESPACE" >/dev/null 2>&1
}

get_route_resolvedrefs_line() {
  kubectl get httproute "$GRAFANA_ROUTE_NAME" -n "$GRAFANA_ROUTE_NAMESPACE" \
    -o jsonpath='{range .status.parents[*].conditions[?(@.type=="ResolvedRefs")]}{.status}{"|"}{.reason}{"|"}{.message}{"\n"}{end}' 2>/dev/null || true
}

wait_for_route_resolvedrefs() {
  local deadline=$((SECONDS + GRAFANA_ROUTE_WAIT_TIMEOUT))
  local line status

  while ((SECONDS < deadline)); do
    line="$(get_route_resolvedrefs_line)"
    status="${line%%|*}"

    if [[ "$status" == "True" ]]; then
      log "HTTPRoute '$GRAFANA_ROUTE_NAMESPACE/$GRAFANA_ROUTE_NAME' is resolved."
      return 0
    fi

    sleep 3
  done

  line="$(get_route_resolvedrefs_line)"
  log "HTTPRoute '$GRAFANA_ROUTE_NAMESPACE/$GRAFANA_ROUTE_NAME' unresolved after ${GRAFANA_ROUTE_WAIT_TIMEOUT}s: ${line:-<no ResolvedRefs condition>}"
  return 1
}

restart_cilium_operator() {
  if ! kubectl get deployment cilium-operator -n kube-system >/dev/null 2>&1; then
    log "Skip cilium-operator restart: deployment not found in kube-system."
    return 0
  fi

  log "Restarting cilium-operator (gateway self-heal)"
  kubectl rollout restart deployment cilium-operator -n kube-system >/dev/null
  kubectl rollout status deployment cilium-operator -n kube-system --timeout="${CILIUM_OPERATOR_ROLLOUT_TIMEOUT}s" >/dev/null
}

reapply_grafana_gateway_manifests() {
  if [[ ! -f "$GRAFANA_REFERENCEGRANT_MANIFEST" || ! -f "$GRAFANA_HTTPROUTE_MANIFEST" ]]; then
    log "Skip grafana route reapply: manifests not found."
    log "Expected: $GRAFANA_REFERENCEGRANT_MANIFEST and $GRAFANA_HTTPROUTE_MANIFEST"
    return 0
  fi

  log "Reapplying Grafana gateway manifests"
  kubectl apply -f "$GRAFANA_REFERENCEGRANT_MANIFEST" -f "$GRAFANA_HTTPROUTE_MANIFEST" >/dev/null
}

heal_grafana_gateway_route_if_needed() {
  if [[ "$AUTO_FIX_GRAFANA_GATEWAY" != "true" ]]; then
    log "Grafana gateway auto-fix disabled (AUTO_FIX_GRAFANA_GATEWAY=$AUTO_FIX_GRAFANA_GATEWAY)."
    return 0
  fi

  if ! route_exists; then
    log "Skip grafana route health-check: route '$GRAFANA_ROUTE_NAMESPACE/$GRAFANA_ROUTE_NAME' not found."
    return 0
  fi

  log "Checking Grafana route health"
  if wait_for_route_resolvedrefs; then
    return 0
  fi

  log "Detected unresolved Grafana route. Running self-heal sequence."
  restart_cilium_operator
  reapply_grafana_gateway_manifests

  if wait_for_route_resolvedrefs; then
    log "Grafana route healed successfully."
    return 0
  fi

  echo "[monitoring] ERROR: Grafana route is still unresolved after self-heal." >&2
  return 1
}

log "Starting delete and redeploy"
log "Namespace: $NAMESPACE"
log "Kubeconfig: $KUBECONFIG_PATH"

setup

log "Step 1/3: delete monitoring stack"
DELETE_NAMESPACE="$DELETE_NAMESPACE" "$SCRIPT_DIR/delete-all.sh"

if [[ "$DELETE_NAMESPACE" == "true" ]]; then
  log "Waiting for namespace deletion before redeploy"
  wait_for_namespace_deletion
fi

log "Step 2/3: deploy monitoring stack from scratch"
"$SCRIPT_DIR/deploy-from-scratch.sh"

log "Step 3/3: refresh Grafana HTTPRoute manifests"
reapply_grafana_gateway_manifests

heal_grafana_gateway_route_if_needed

log "Delete and redeploy completed."
