#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

log "Starting monitoring deployment from scratch"
log "Namespace: $NAMESPACE"
log "Kubeconfig: $KUBECONFIG_PATH"

setup
prepare_repos
ensure_namespace
pick_storage_overlay
build_dcgm_gpu_overlay
sync_postgres_exporter_secret
install_or_upgrade_charts
apply_service_monitors
apply_prometheus_rules
apply_probes
apply_alertmanager_configs
apply_tuya_exporter
apply_ups_exporter
apply_dashboards
print_status

log "Monitoring deployment completed."
