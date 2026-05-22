#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/home/oleg/Documents/hse-llm-project/cluster-config/llm_proj_talos/kubeconfig}"
NAMESPACE="${NAMESPACE:-monitoring}"

REMOTE_HOST="${REMOTE_HOST:-10.19.87.6}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PASSWORD="${REMOTE_PASSWORD:-}"

PASS=0
FAIL=0

ok() { echo "[OK] $*"; PASS=$((PASS+1)); }
err() { echo "[FAIL] $*"; FAIL=$((FAIL+1)); }

run_check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$name"
  else
    err "$name"
  fi
}

# ---------- host checks ----------
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
if [[ -n "$REMOTE_PASSWORD" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "[verify] ERROR: sshpass not found" >&2
    exit 1
  fi
  SSH=(sshpass -p "$REMOTE_PASSWORD" ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST")
else
  SSH=(ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$REMOTE_HOST")
fi

run_check "nut-driver service active on host" "${SSH[@]}" "systemctl is-active --quiet nut-driver@nutdev1.service"
run_check "nut-server service active on host" "${SSH[@]}" "systemctl is-active --quiet nut-server.service"
run_check "NUT exposes at least one UPS" "${SSH[@]}" "upsc -l | grep -q nutdev1"
run_check "NUT responds for nutdev1" "${SSH[@]}" "upsc nutdev1@127.0.0.1 | grep -q '^ups.status:'"

# ---------- k8s checks ----------
export KUBECONFIG="$KUBECONFIG_PATH"
run_check "nut-ups-exporter deployment available" kubectl -n "$NAMESPACE" rollout status deployment/nut-ups-exporter --timeout=90s
run_check "ServiceMonitor exists" kubectl -n "$NAMESPACE" get servicemonitor nut-ups-exporter-metrics
run_check "PrometheusRule exists" kubectl -n "$NAMESPACE" get prometheusrule ups-alerts
run_check "AlertmanagerConfig exists" kubectl -n "$NAMESPACE" get alertmanagerconfig ups-email-alerts
run_check "Grafana UPS dashboard ConfigMap exists" kubectl -n "$NAMESPACE" get configmap dashboard-ups-monitoring

# ---------- Prometheus checks ----------
PROM_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$PROM_POD" ]]; then
  run_check "Prometheus has UPS metric network_ups_tools_battery_charge" \
    kubectl -n "$NAMESPACE" exec "$PROM_POD" -c prometheus -- sh -lc \
    "wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=network_ups_tools_battery_charge' | grep -q '\"status\":\"success\"'"
else
  err "Prometheus pod discovered"
fi

echo ""
echo "Checks passed: $PASS"
echo "Checks failed: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
