#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/home/oleg/Documents/hse-llm-project/cluster-config/llm_proj_talos/kubeconfig}"
NAMESPACE="${NAMESPACE:-monitoring}"
PSA_LEVEL="${PSA_LEVEL:-privileged}"

KPS_RELEASE="${KPS_RELEASE:-kube-prometheus-stack}"
KPS_CHART="${KPS_CHART:-prometheus-community/kube-prometheus-stack}"
KPS_CHART_VERSION="${KPS_CHART_VERSION:-82.16.1}"

LOKI_RELEASE="${LOKI_RELEASE:-loki}"
LOKI_CHART="${LOKI_CHART:-grafana/loki-stack}"
LOKI_CHART_VERSION="${LOKI_CHART_VERSION:-2.10.3}"

DCGM_RELEASE="${DCGM_RELEASE:-dcgm-exporter}"
DCGM_CHART="${DCGM_CHART:-nvidia-dcgm/dcgm-exporter}"
DCGM_CHART_VERSION="${DCGM_CHART_VERSION:-4.8.1}"

BLACKBOX_RELEASE="${BLACKBOX_RELEASE:-blackbox-exporter}"
BLACKBOX_CHART="${BLACKBOX_CHART:-prometheus-community/prometheus-blackbox-exporter}"
BLACKBOX_CHART_VERSION="${BLACKBOX_CHART_VERSION:-11.9.1}"

POSTGRES_EXPORTER_RELEASE="${POSTGRES_EXPORTER_RELEASE:-postgres-exporter}"
POSTGRES_EXPORTER_CHART="${POSTGRES_EXPORTER_CHART:-prometheus-community/prometheus-postgres-exporter}"
POSTGRES_EXPORTER_CHART_VERSION="${POSTGRES_EXPORTER_CHART_VERSION:-7.5.2}"

VALUES_KPS="${VALUES_KPS:-$SCRIPT_DIR/values.kube-prometheus-stack.yaml}"
VALUES_KPS_STORAGE_PVC="${VALUES_KPS_STORAGE_PVC:-$SCRIPT_DIR/values.kube-prometheus-stack.storage-pvc.yaml}"
VALUES_KPS_STORAGE_EMPTYDIR="${VALUES_KPS_STORAGE_EMPTYDIR:-$SCRIPT_DIR/values.kube-prometheus-stack.storage-emptydir.yaml}"
VALUES_LOKI="${VALUES_LOKI:-$SCRIPT_DIR/values.loki-stack.yaml}"
VALUES_DCGM="${VALUES_DCGM:-$SCRIPT_DIR/values.dcgm-exporter.yaml}"
VALUES_BLACKBOX="${VALUES_BLACKBOX:-$SCRIPT_DIR/values.blackbox-exporter.yaml}"
VALUES_POSTGRES_EXPORTER="${VALUES_POSTGRES_EXPORTER:-$SCRIPT_DIR/values.prometheus-postgres-exporter.yaml}"

PROMETHEUS_FORCE_EMPTYDIR="${PROMETHEUS_FORCE_EMPTYDIR:-false}"
PROMETHEUS_STORAGE_CLASS="${PROMETHEUS_STORAGE_CLASS:-}"

POSTGRES_SOURCE_NAMESPACE="${POSTGRES_SOURCE_NAMESPACE:-hse-llm-project}"
POSTGRES_SOURCE_SECRET="${POSTGRES_SOURCE_SECRET:-postgresql}"
POSTGRES_SOURCE_PASSWORD_KEY="${POSTGRES_SOURCE_PASSWORD_KEY:-password}"
POSTGRES_EXPORTER_DSN_SECRET_NAME="${POSTGRES_EXPORTER_DSN_SECRET_NAME:-postgres-exporter-dsn}"
POSTGRES_EXPORTER_DB_HOST="${POSTGRES_EXPORTER_DB_HOST:-postgresql.hse-llm-project.svc.cluster.local}"
POSTGRES_EXPORTER_DB_PORT="${POSTGRES_EXPORTER_DB_PORT:-5432}"
POSTGRES_EXPORTER_DB_NAME="${POSTGRES_EXPORTER_DB_NAME:-default}"
POSTGRES_EXPORTER_DB_USER="${POSTGRES_EXPORTER_DB_USER:-admin}"
POSTGRES_EXPORTER_DB_PASSWORD="${POSTGRES_EXPORTER_DB_PASSWORD:-admin}"
POSTGRES_EXPORTER_SSLMODE="${POSTGRES_EXPORTER_SSLMODE:-disable}"
POSTGRES_EXPORTER_ENABLED="${POSTGRES_EXPORTER_ENABLED:-true}"
POSTGRES_EXPORTER_FAIL_ON_MISSING_SECRET="${POSTGRES_EXPORTER_FAIL_ON_MISSING_SECRET:-false}"
POSTGRES_EXPORTER_USE_SOURCE_SECRET="${POSTGRES_EXPORTER_USE_SOURCE_SECRET:-false}"

SERVICEMONITORS_DIR="${SERVICEMONITORS_DIR:-$SCRIPT_DIR/servicemonitors}"
PROBES_DIR="${PROBES_DIR:-$SCRIPT_DIR/probes}"
PROMETHEUS_RULES_DIR="${PROMETHEUS_RULES_DIR:-$SCRIPT_DIR/prometheus-rules}"
ALERTMANAGER_CONFIGS_DIR="${ALERTMANAGER_CONFIGS_DIR:-$SCRIPT_DIR/alertmanagerconfigs}"
DASHBOARDS_SCRIPT="${DASHBOARDS_SCRIPT:-$SCRIPT_DIR/apply-dashboards.sh}"
TUYA_EXPORTER_DIR="${TUYA_EXPORTER_DIR:-$SCRIPT_DIR/tuya-exporter}"
TUYA_EXPORTER_ENABLED="${TUYA_EXPORTER_ENABLED:-auto}"
TUYA_EXPORTER_CONFIG_SECRET_NAME="${TUYA_EXPORTER_CONFIG_SECRET_NAME:-tuya-smart-plug-exporter-config}"
UPS_EXPORTER_DIR="${UPS_EXPORTER_DIR:-$SCRIPT_DIR/ups-exporter}"
UPS_EXPORTER_ENABLED="${UPS_EXPORTER_ENABLED:-auto}"
UPS_EXPORTER_CONFIG_SECRET_NAME="${UPS_EXPORTER_CONFIG_SECRET_NAME:-nut-ups-exporter-config}"
EMAIL_ALERTS_ENABLED="${EMAIL_ALERTS_ENABLED:-auto}"
EMAIL_ALERTS_SMTP_SECRET_NAME="${EMAIL_ALERTS_SMTP_SECRET_NAME:-resend-smtp-password}"

STORAGE_OVERLAY_FILE=""
DCGM_GPU_OVERLAY_FILE="/tmp/dcgm-gpu-selector-values.yaml"

log() {
  echo "[monitoring] $*"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[monitoring] ERROR: command not found: $1" >&2
    exit 1
  }
}

require_files() {
  local path
  for path in "$VALUES_KPS" "$VALUES_KPS_STORAGE_PVC" "$VALUES_KPS_STORAGE_EMPTYDIR" "$VALUES_LOKI" "$VALUES_DCGM" "$VALUES_BLACKBOX" "$VALUES_POSTGRES_EXPORTER"; do
    [[ -f "$path" ]] || {
      echo "[monitoring] ERROR: required file not found: $path" >&2
      exit 1
    }
  done
}

setup() {
  need_cmd helm
  need_cmd kubectl
  need_cmd base64

  [[ -f "$KUBECONFIG_PATH" ]] || {
    echo "[monitoring] ERROR: kubeconfig not found: $KUBECONFIG_PATH" >&2
    exit 1
  }

  require_files

  export KUBECONFIG="$KUBECONFIG_PATH"
}

prepare_repos() {
  log "Updating Helm repositories"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add nvidia-dcgm https://nvidia.github.io/dcgm-exporter/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null
}

ensure_namespace() {
  log "Ensuring namespace '$NAMESPACE' with PodSecurity level '$PSA_LEVEL'"
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace "$NAMESPACE" \
    "pod-security.kubernetes.io/enforce=$PSA_LEVEL" \
    "pod-security.kubernetes.io/audit=$PSA_LEVEL" \
    "pod-security.kubernetes.io/warn=$PSA_LEVEL" \
    --overwrite >/dev/null
}

pick_storage_overlay() {
  if [[ "$PROMETHEUS_FORCE_EMPTYDIR" == "true" ]]; then
    STORAGE_OVERLAY_FILE="$VALUES_KPS_STORAGE_EMPTYDIR"
    log "Prometheus storage forced to emptyDir"
    return
  fi

  if kubectl get sc -o name | grep -q .; then
    STORAGE_OVERLAY_FILE="$VALUES_KPS_STORAGE_PVC"

    if [[ -z "$PROMETHEUS_STORAGE_CLASS" ]]; then
      PROMETHEUS_STORAGE_CLASS="$( (kubectl get sc -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' || true) | head -n1 )"
      if [[ -z "$PROMETHEUS_STORAGE_CLASS" ]]; then
        PROMETHEUS_STORAGE_CLASS="$(kubectl get sc -o jsonpath='{.items[0].metadata.name}')"
      fi
    fi

    log "StorageClass detected. Prometheus PVC mode enabled (storageClass=$PROMETHEUS_STORAGE_CLASS)."
  else
    STORAGE_OVERLAY_FILE="$VALUES_KPS_STORAGE_EMPTYDIR"
    PROMETHEUS_STORAGE_CLASS=""
    log "No StorageClass detected. Prometheus emptyDir mode enabled."
  fi
}

build_dcgm_gpu_overlay() {
  rm -f "$DCGM_GPU_OVERLAY_FILE"

  local labeled_nodes
  labeled_nodes="$(kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sed '/^$/d')"

  if [[ -n "$labeled_nodes" ]]; then
    cat > "$DCGM_GPU_OVERLAY_FILE" <<'YAML'
nodeSelector:
  nvidia.com/gpu.present: "true"
YAML
    log "dcgm-exporter will use nodeSelector nvidia.com/gpu.present=true"
    return
  fi

  local gpu_count_nodes
  gpu_count_nodes="$(kubectl get nodes -l 'nvidia.com/gpu.count' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sed '/^$/d')"

  if [[ -n "$gpu_count_nodes" ]]; then
    cat > "$DCGM_GPU_OVERLAY_FILE" <<'YAML'
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: nvidia.com/gpu.count
              operator: Exists
YAML
    log "dcgm-exporter will use nodeAffinity with nvidia.com/gpu.count label (Exists)"
    return
  fi

  mapfile -t gpu_hostnames < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | awk '/gpu/')

  if [[ "${#gpu_hostnames[@]}" -eq 0 ]]; then
    echo "[monitoring] ERROR: failed to detect GPU nodes (no nvidia.com/gpu.present=true and no node names containing 'gpu')." >&2
    exit 1
  fi

  {
    echo "affinity:"
    echo "  nodeAffinity:"
    echo "    requiredDuringSchedulingIgnoredDuringExecution:"
    echo "      nodeSelectorTerms:"
    echo "        - matchExpressions:"
    echo "            - key: kubernetes.io/hostname"
    echo "              operator: In"
    echo "              values:"
    local node
    for node in "${gpu_hostnames[@]}"; do
      echo "                - $node"
    done
  } > "$DCGM_GPU_OVERLAY_FILE"

  log "dcgm-exporter will use GPU node affinity by hostnames: ${gpu_hostnames[*]}"
}

sync_postgres_exporter_secret() {
  if [[ "$POSTGRES_EXPORTER_ENABLED" != "true" ]]; then
    log "Postgres exporter is disabled (POSTGRES_EXPORTER_ENABLED=$POSTGRES_EXPORTER_ENABLED)"
    return
  fi

  local password
  password="$POSTGRES_EXPORTER_DB_PASSWORD"
  if [[ "$POSTGRES_EXPORTER_USE_SOURCE_SECRET" == "true" ]]; then
    local password_b64
    if ! password_b64="$(kubectl get secret "$POSTGRES_SOURCE_SECRET" -n "$POSTGRES_SOURCE_NAMESPACE" -o jsonpath="{.data.${POSTGRES_SOURCE_PASSWORD_KEY}}" 2>/dev/null)"; then
      if [[ "$POSTGRES_EXPORTER_FAIL_ON_MISSING_SECRET" == "true" ]]; then
        echo "[monitoring] ERROR: secret '$POSTGRES_SOURCE_SECRET' not found in namespace '$POSTGRES_SOURCE_NAMESPACE'." >&2
        exit 1
      fi
      log "WARNING: secret '$POSTGRES_SOURCE_SECRET' not found in namespace '$POSTGRES_SOURCE_NAMESPACE'. postgres-exporter will be skipped."
      POSTGRES_EXPORTER_ENABLED="false"
      return
    fi

    if [[ -z "$password_b64" ]]; then
      if [[ "$POSTGRES_EXPORTER_FAIL_ON_MISSING_SECRET" == "true" ]]; then
        echo "[monitoring] ERROR: key '$POSTGRES_SOURCE_PASSWORD_KEY' not found in secret '$POSTGRES_SOURCE_SECRET' (namespace '$POSTGRES_SOURCE_NAMESPACE')." >&2
        exit 1
      fi
      log "WARNING: key '$POSTGRES_SOURCE_PASSWORD_KEY' not found in secret '$POSTGRES_SOURCE_SECRET'. postgres-exporter will be skipped."
      POSTGRES_EXPORTER_ENABLED="false"
      return
    fi

    password="$(printf '%s' "$password_b64" | base64 -d)"
  else
    log "Postgres exporter uses direct DB credentials from env (source secret disabled)."
  fi

  local dsn
  dsn="postgresql://${POSTGRES_EXPORTER_DB_USER}:${password}@${POSTGRES_EXPORTER_DB_HOST}:${POSTGRES_EXPORTER_DB_PORT}/${POSTGRES_EXPORTER_DB_NAME}?sslmode=${POSTGRES_EXPORTER_SSLMODE}"

  kubectl create secret generic "$POSTGRES_EXPORTER_DSN_SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-literal=DATA_SOURCE_NAME="$dsn" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  log "Synchronized DSN secret '$POSTGRES_EXPORTER_DSN_SECRET_NAME' in namespace '$NAMESPACE'"
}

install_or_upgrade_charts() {
  local kps_storage_class_args=()
  if [[ "$STORAGE_OVERLAY_FILE" == "$VALUES_KPS_STORAGE_PVC" && -n "$PROMETHEUS_STORAGE_CLASS" ]]; then
    kps_storage_class_args=(
      --set-string "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=$PROMETHEUS_STORAGE_CLASS"
    )
  fi

  log "Installing/upgrading $KPS_RELEASE ($KPS_CHART:$KPS_CHART_VERSION)"
  helm upgrade --install "$KPS_RELEASE" "$KPS_CHART" \
    --version "$KPS_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$VALUES_KPS" \
    -f "$STORAGE_OVERLAY_FILE" \
    "${kps_storage_class_args[@]}"

  log "Installing/upgrading $LOKI_RELEASE ($LOKI_CHART:$LOKI_CHART_VERSION)"
  helm upgrade --install "$LOKI_RELEASE" "$LOKI_CHART" \
    --version "$LOKI_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$VALUES_LOKI"

  log "Installing/upgrading $DCGM_RELEASE ($DCGM_CHART:$DCGM_CHART_VERSION)"
  helm upgrade --install "$DCGM_RELEASE" "$DCGM_CHART" \
    --version "$DCGM_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$VALUES_DCGM" \
    -f "$DCGM_GPU_OVERLAY_FILE"

  log "Installing/upgrading $BLACKBOX_RELEASE ($BLACKBOX_CHART:$BLACKBOX_CHART_VERSION)"
  helm upgrade --install "$BLACKBOX_RELEASE" "$BLACKBOX_CHART" \
    --version "$BLACKBOX_CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    -f "$VALUES_BLACKBOX"

  if [[ "$POSTGRES_EXPORTER_ENABLED" == "true" ]]; then
    log "Installing/upgrading $POSTGRES_EXPORTER_RELEASE ($POSTGRES_EXPORTER_CHART:$POSTGRES_EXPORTER_CHART_VERSION)"
    helm upgrade --install "$POSTGRES_EXPORTER_RELEASE" "$POSTGRES_EXPORTER_CHART" \
      --version "$POSTGRES_EXPORTER_CHART_VERSION" \
      --namespace "$NAMESPACE" \
      --create-namespace \
      -f "$VALUES_POSTGRES_EXPORTER" \
      --set-string "config.datasourceSecret.name=$POSTGRES_EXPORTER_DSN_SECRET_NAME"
  else
    log "Skipping postgres-exporter installation because it is disabled."
  fi
}

apply_service_monitors() {
  [[ -d "$SERVICEMONITORS_DIR" ]] || {
    echo "[monitoring] ERROR: servicemonitors directory not found: $SERVICEMONITORS_DIR" >&2
    exit 1
  }

  log "Applying ServiceMonitor manifests"
  kubectl apply -f "$SERVICEMONITORS_DIR"
}

apply_prometheus_rules() {
  [[ -d "$PROMETHEUS_RULES_DIR" ]] || {
    echo "[monitoring] ERROR: prometheus-rules directory not found: $PROMETHEUS_RULES_DIR" >&2
    exit 1
  }

  log "Applying PrometheusRule manifests"
  kubectl apply -f "$PROMETHEUS_RULES_DIR"
}

wait_for_probe_crd() {
  local attempts=30
  local sleep_seconds=2
  local i
  for ((i = 1; i <= attempts; i++)); do
    if kubectl get crd probes.monitoring.coreos.com >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
  done
  echo "[monitoring] ERROR: CRD probes.monitoring.coreos.com is not available." >&2
  return 1
}

apply_probes() {
  [[ -d "$PROBES_DIR" ]] || {
    echo "[monitoring] ERROR: probes directory not found: $PROBES_DIR" >&2
    exit 1
  }

  wait_for_probe_crd

  log "Applying Probe manifests"
  kubectl apply -f "$PROBES_DIR"
}

apply_alertmanager_configs() {
  local mode
  mode="$(printf '%s' "$EMAIL_ALERTS_ENABLED" | tr '[:upper:]' '[:lower:]')"

  if [[ "$mode" == "false" || "$mode" == "0" || "$mode" == "off" || "$mode" == "no" ]]; then
    log "Skipping AlertmanagerConfig deployment (EMAIL_ALERTS_ENABLED=$EMAIL_ALERTS_ENABLED)."
    return
  fi

  [[ -d "$ALERTMANAGER_CONFIGS_DIR" ]] || {
    echo "[monitoring] ERROR: alertmanagerconfigs directory not found: $ALERTMANAGER_CONFIGS_DIR" >&2
    exit 1
  }

  if ! kubectl get secret "$EMAIL_ALERTS_SMTP_SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    if [[ "$mode" == "auto" ]]; then
      log "Skipping AlertmanagerConfig in auto mode: secret '$EMAIL_ALERTS_SMTP_SECRET_NAME' not found in namespace '$NAMESPACE'."
      return
    fi
    echo "[monitoring] ERROR: email alerts are enabled but secret '$EMAIL_ALERTS_SMTP_SECRET_NAME' is missing in namespace '$NAMESPACE'." >&2
    echo "[monitoring] Create it first with ./create-resend-secret.sh." >&2
    exit 1
  fi

  log "Applying AlertmanagerConfig manifests (mode=$EMAIL_ALERTS_ENABLED)"
  kubectl apply -f "$ALERTMANAGER_CONFIGS_DIR"
}

apply_tuya_exporter() {
  local mode
  mode="$(printf '%s' "$TUYA_EXPORTER_ENABLED" | tr '[:upper:]' '[:lower:]')"

  if [[ "$mode" == "false" || "$mode" == "0" || "$mode" == "off" || "$mode" == "no" ]]; then
    log "Skipping Tuya exporter deployment (TUYA_EXPORTER_ENABLED=$TUYA_EXPORTER_ENABLED)."
    return
  fi

  [[ -d "$TUYA_EXPORTER_DIR" ]] || {
    echo "[monitoring] ERROR: tuya-exporter directory not found: $TUYA_EXPORTER_DIR" >&2
    exit 1
  }

  if ! kubectl get secret "$TUYA_EXPORTER_CONFIG_SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    if [[ "$mode" == "auto" ]]; then
      log "Skipping Tuya exporter deployment in auto mode: secret '$TUYA_EXPORTER_CONFIG_SECRET_NAME' not found in namespace '$NAMESPACE'."
      return
    fi
    echo "[monitoring] ERROR: Tuya exporter is enabled but secret '$TUYA_EXPORTER_CONFIG_SECRET_NAME' is missing in namespace '$NAMESPACE'." >&2
    echo "[monitoring] Create it first with key 'config.yaml'." >&2
    exit 1
  fi

  log "Applying Tuya exporter manifests (mode=$TUYA_EXPORTER_ENABLED)"
  kubectl apply -f "$TUYA_EXPORTER_DIR"
  kubectl rollout status deployment/tuya-smart-plug-exporter -n "$NAMESPACE" --timeout=180s >/dev/null
}

apply_ups_exporter() {
  local mode
  mode="$(printf '%s' "$UPS_EXPORTER_ENABLED" | tr '[:upper:]' '[:lower:]')"

  if [[ "$mode" == "false" || "$mode" == "0" || "$mode" == "off" || "$mode" == "no" ]]; then
    log "Skipping UPS exporter deployment (UPS_EXPORTER_ENABLED=$UPS_EXPORTER_ENABLED)."
    return
  fi

  [[ -d "$UPS_EXPORTER_DIR" ]] || {
    echo "[monitoring] ERROR: ups-exporter directory not found: $UPS_EXPORTER_DIR" >&2
    exit 1
  }

  if ! kubectl get secret "$UPS_EXPORTER_CONFIG_SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    if [[ "$mode" == "auto" ]]; then
      log "Skipping UPS exporter deployment in auto mode: secret '$UPS_EXPORTER_CONFIG_SECRET_NAME' not found in namespace '$NAMESPACE'."
      return
    fi
    echo "[monitoring] ERROR: UPS exporter is enabled but secret '$UPS_EXPORTER_CONFIG_SECRET_NAME' is missing in namespace '$NAMESPACE'." >&2
    echo "[monitoring] Create it first with ./create-ups-secret.sh." >&2
    exit 1
  fi

  log "Applying UPS exporter manifests (mode=$UPS_EXPORTER_ENABLED)"
  kubectl apply -f "$UPS_EXPORTER_DIR"
  kubectl rollout status deployment/nut-ups-exporter -n "$NAMESPACE" --timeout=180s >/dev/null
}

delete_tuya_exporter() {
  if [[ -d "$TUYA_EXPORTER_DIR" ]]; then
    kubectl delete -f "$TUYA_EXPORTER_DIR" --ignore-not-found >/dev/null || true
  fi
}

delete_ups_exporter() {
  if [[ -d "$UPS_EXPORTER_DIR" ]]; then
    kubectl delete -f "$UPS_EXPORTER_DIR" --ignore-not-found >/dev/null || true
  fi
}

delete_alertmanager_configs() {
  if [[ -d "$ALERTMANAGER_CONFIGS_DIR" ]]; then
    kubectl delete -f "$ALERTMANAGER_CONFIGS_DIR" --ignore-not-found >/dev/null || true
  fi
}

apply_dashboards() {
  [[ -x "$DASHBOARDS_SCRIPT" ]] || {
    echo "[monitoring] ERROR: dashboards script not executable: $DASHBOARDS_SCRIPT" >&2
    exit 1
  }

  "$DASHBOARDS_SCRIPT"
}

print_status() {
  log "Monitoring namespace pods:"
  kubectl get pods -n "$NAMESPACE"

  log "ServiceMonitors in monitoring namespace:"
  kubectl get servicemonitor -n "$NAMESPACE" || true

  log "ServiceMonitors in project namespace:"
  kubectl get servicemonitor -n hse-llm-project

  log "Probes in monitoring namespace:"
  kubectl get probe -n "$NAMESPACE" || true

  log "Grafana service:"
  kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=grafana
}

require_existing_releases() {
  local release
  for release in "$KPS_RELEASE" "$LOKI_RELEASE" "$DCGM_RELEASE" "$BLACKBOX_RELEASE"; do
    if ! helm status "$release" -n "$NAMESPACE" >/dev/null 2>&1; then
      echo "[monitoring] ERROR: release '$release' not found in namespace '$NAMESPACE'. Run ./deploy-from-scratch.sh first." >&2
      exit 1
    fi
  done
  if [[ "$POSTGRES_EXPORTER_ENABLED" == "true" ]]; then
    if ! helm status "$POSTGRES_EXPORTER_RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
      echo "[monitoring] ERROR: release '$POSTGRES_EXPORTER_RELEASE' not found in namespace '$NAMESPACE'. Run ./deploy-from-scratch.sh first." >&2
      exit 1
    fi
  fi
}
