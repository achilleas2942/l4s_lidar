#!/usr/bin/env bash
set -euo pipefail

###############################################
# L4S Kubernetes Orchestrator
###############################################

ACTION="${1:-deploy}"
NAMESPACE="${NAMESPACE:-l4s-lidar}"

# ========= User-supplied environment =========
# Node placement (defaults can be overridden)
NODE_SENDER="${NODE_SENDER:-cpr-a200-0779}"
NODE_RECEIVER="${NODE_RECEIVER:-ki20erk3shusky1}"

# Optional (for secrets; if omitted, secret is skipped):
API_TOKEN="${API_TOKEN:-}"
PASSWORD="${PASSWORD:-}"

# ========= Paths =========
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFESTS_ROOT="${REPO_ROOT}/deploy/manifests"
COMMON_DIR="${MANIFESTS_ROOT}/common"
SENDER_DIR="${MANIFESTS_ROOT}/sender"
RECEIVER_DIR="${MANIFESTS_ROOT}/receiver"

SENDER_SCRIPTS_DIR="${REPO_ROOT}/src/sender_scripts"
RECEIVER_SCRIPTS_DIR="${REPO_ROOT}/src/receiver_scripts"

# ========= Binaries check =========
need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing required binary: $1"; exit 1; }; }
need kubectl
if [[ "$ACTION" == "tmux" ]]; then need tmux; fi

# ========= Defaults (can be overridden via env) =========
# Cross-pod service discovery
: "${SENDER_HOST_IP:=l4s-lidar-sender}"
: "${RECEIVER_HOST_IP:=l4s-lidar-receiver}"
: "${SENDER_PORT:=51000}"
: "${RECEIVER_PORT:=51000}"

# SCReAM sender / receiver parameters
: "${DELAY_TARGET:=0.06}"                         # seconds
: "${RATE_MIN:=2000}"                             # kbps
: "${RATE_INIT:=5000}"                            # kbps
: "${RATE_MAX:=25000}"                            # kbps
: "${RATE_SCALE:=1}"                              # scale factor
: "${MAX_TOTAL_RATE:=60000}"                      # kbps
: "${PACING_HEADROOM:=1.5}"                       # pacing headroom
: "${SENDPIPELINE:=1}"                            # SCReAM send pipeline index
: "${LOCAL_RTCP_PORT:=51000}"                     # receiver local RTCP port

# Pointcloud sender parameters
: "${QUEUE_SIZE:=4}"                              # sender queue size
: "${MAX_PAYLOAD:=1200}"                          # sender max RTP payload size
: "${RTP_CLOCK:=90000}"                           # sender RTP clock rate
: "${FRAME_RATE:=10}"                             # sender frame rate
: "${TOPIC:=/husky/ouster/points}"                # sender topic
: "${DST_IP:=127.0.0.1}"                          # destination IP
: "${DST_PORT:=30000}"                            # destination port
: "${COMP_MODULE:=compressors.draco_compressor}"  # sender compressor module
: "${COMP_CLASS:=DracoCompression}"               # sender compressor class
: "${QUANT_BITS:=12}"                             # sender quantization bits
: "${COMP_LEVEL:=3}"                              # sender compression level
: "${WORKERS:=1}"                                 # sender worker threads

# Receiver
: "${PORT:=30112}"
: "${OUTPUT_TOPIC:=pointcloud_rx}"
: "${FRAME_ID:=husky/os_sensor}"

# ========= Labels used in manifests =========
SENDER_APP_LABEL="app.kubernetes.io/name=l4s-lidar-sender"
RECEIVER_APP_LABEL="app.kubernetes.io/name=l4s-lidar-receiver"

# ========= Helpers =========
title() { echo -e "\n\033[1m$*\033[0m"; }
note()  { echo -e "💡 $*"; }
warn()  { echo -e "⚠️  $*"; }
info()  { echo -e "➤ $*"; }

apply_dir() { kubectl apply -f "$1"; }

wait_ready() {
  local label="$1"
  info "Waiting for pods with label: $label"
  kubectl wait --for=condition=Ready pod -n "$NAMESPACE" -l "$label" --timeout=180s
}

pod_name() {
  local label="$1"
  kubectl get pod -n "$NAMESPACE" -l "$label" -o jsonpath='{.items[0].metadata.name}'
}

patch_node_selector() {
  local deploy="$1" node="$2"
  info "Patching nodeSelector of deployment/$deploy to host: $node"
  kubectl patch deployment "$deploy" -n "$NAMESPACE" \
    --type='json' \
    -p="[
      {\"op\":\"add\",\"path\":\"/spec/template/spec/nodeSelector\",\"value\":{}},
      {\"op\":\"replace\",\"path\":\"/spec/template/spec/nodeSelector\",\"value\":{\"kubernetes.io/hostname\":\"$node\"}}
    ]"
}

set_env_for() {
  local deploy="$1"; shift
  local env_args=()
  for key in "$@"; do
    local val; val="$(eval "echo \${$key-}")"
    if [[ -n "${val}" ]]; then env_args+=("${key}=${val}"); fi
  done
  if [[ ${#env_args[@]} -gt 0 ]]; then
    info "Setting env on deployment/$deploy: ${env_args[*]}"
    kubectl set env -n "$NAMESPACE" "deployment/${deploy}" "${env_args[@]}"
  else
    note "No environment overrides provided for deployment/$deploy"
  fi
}

ensure_namespace() {
  kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"
}

ensure_secret() {
  if [[ -n "${API_TOKEN:-}" && -n "${PASSWORD:-}" ]]; then
    title "🔐 Creating/updating secret l4s-lidar-common-secret"
    kubectl create secret generic l4s-lidar-common-secret \
      --from-literal=API_TOKEN="${API_TOKEN}" \
      --from-literal=PASSWORD="${PASSWORD}" \
      -n "$NAMESPACE" \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    note "Skipping secret creation (API_TOKEN/PASSWORD not set)"
  fi
}

build_script_configmaps() {
  title "🧱 Building ConfigMaps from local scripts"
  if [[ ! -d "$SENDER_SCRIPTS_DIR" ]]; then
    echo "❌ Not found: $SENDER_SCRIPTS_DIR"; exit 1
  fi
  if [[ ! -d "$RECEIVER_SCRIPTS_DIR" ]]; then
    echo "❌ Not found: $RECEIVER_SCRIPTS_DIR"; exit 1
  fi

  # Sender scripts → ConfigMap
  kubectl create configmap l4s-lidar-sender-scripts \
    --from-file="$SENDER_SCRIPTS_DIR" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

  # Receiver scripts → ConfigMap
  kubectl create configmap l4s-lidar-receiver-scripts \
    --from-file="$RECEIVER_SCRIPTS_DIR" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

  note "ConfigMaps created: l4s-lidar-sender-scripts, l4s-lidar-receiver-scripts"
}

deploy_all() {
  # Validate nodes
  kubectl get node "$NODE_SENDER" >/dev/null 2>&1 || { echo "❌ NODE_SENDER '$NODE_SENDER' not found"; exit 1; }
  kubectl get node "$NODE_RECEIVER" >/dev/null 2>&1 || { echo "❌ NODE_RECEIVER '$NODE_RECEIVER' not found"; exit 1; }

  ensure_namespace
  build_script_configmaps

  title "🚀 Applying common manifests"
  apply_dir "$COMMON_DIR"

  title "🚀 Deploying sender"
  apply_dir "$SENDER_DIR"

  title "🚀 Deploying receiver"
  apply_dir "$RECEIVER_DIR"

  title "🚀 Patching nodeSelectors"
  patch_node_selector "l4s-lidar-sender"   "$NODE_SENDER"
  patch_node_selector "l4s-lidar-receiver" "$NODE_RECEIVER"

  title "🔐 Ensuring secrets"
  ensure_secret

  title "🚀 Injecting dynamic environment parameters"
  COMMON_ENV_KEYS=( SENDER_HOST_IP RECEIVER_HOST_IP SENDER_PORT RECEIVER_PORT )

  SENDER_ENV_KEYS=(
    "${COMMON_ENV_KEYS[@]}"
    DELAY_TARGET RATE_MIN RATE_INIT RATE_MAX RATE_SCALE
    MAX_TOTAL_RATE PACING_HEADROOM SENDPIPELINE
    TOPIC DST_IP DST_PORT COMP_MODULE COMP_CLASS QUANT_BITS COMP_LEVEL WORKERS
    QUEUE_SIZE MAX_PAYLOAD RTP_CLOCK FRAME_RATE
    LOCAL_RTCP_PORT
  )

  RECEIVER_ENV_KEYS=(
    "${COMMON_ENV_KEYS[@]}"
    LOCAL_RTCP_PORT
    PORT OUTPUT_TOPIC FRAME_ID
  )

  set_env_for "l4s-lidar-sender"   "${SENDER_ENV_KEYS[@]}"
  set_env_for "l4s-lidar-receiver" "${RECEIVER_ENV_KEYS[@]}"

  title "⏳ Waiting for pods to become Ready"
  wait_ready "$SENDER_APP_LABEL"
  wait_ready "$RECEIVER_APP_LABEL"

  SENDER_POD="$(pod_name "$SENDER_APP_LABEL")"
  RECEIVER_POD="$(pod_name "$RECEIVER_APP_LABEL")"

  title "✅ Deployed"
  echo "Sender pod   : ${SENDER_POD}"
  echo "Receiver pod : ${RECEIVER_POD}"
  note  "Use './run_k8s.sh logs' to stream logs, or './run_k8s.sh tmux' for a 4-pane session."
}

restart_all() {
  title "🔄 Rolling restart of sender & receiver"
  kubectl rollout restart deployment/l4s-lidar-sender   -n "$NAMESPACE"
  kubectl rollout restart deployment/l4s-lidar-receiver -n "$NAMESPACE"
  wait_ready "$SENDER_APP_LABEL"
  wait_ready "$RECEIVER_APP_LABEL"
  info "Restart complete."
}

logs_all() {
  title "📄 Streaming logs (Ctrl+C to stop)"
  SENDER_POD="$(pod_name "$SENDER_APP_LABEL")"
  RECEIVER_POD="$(pod_name "$RECEIVER_APP_LABEL")"
  echo "Receiver logs:"
  kubectl logs -f "$RECEIVER_POD" -n "$NAMESPACE" &
  sleep 1
  echo "Sender logs:"
  kubectl logs -f "$SENDER_POD" -n "$NAMESPACE"
}

tmux_mode() {
  need tmux
  title "🪟 Starting tmux session 'l4s-lidar'"
  SENDER_POD="$(pod_name "$SENDER_APP_LABEL")"
  RECEIVER_POD="$(pod_name "$RECEIVER_APP_LABEL")"

  tmux new-session -d -s l4s-lidar "kubectl logs -f ${RECEIVER_POD} -n ${NAMESPACE}"
  tmux rename-window "receiver-logs"

  tmux split-window -h "kubectl logs -f ${SENDER_POD} -n ${NAMESPACE}"
  tmux select-pane -t 0

  tmux split-window -v "kubectl exec -it ${RECEIVER_POD} -n ${NAMESPACE} -- bash"
  tmux select-pane -t 1
  tmux split-window -v "kubectl exec -it ${SENDER_POD} -n ${NAMESPACE} -- bash"

  tmux select-layout tiled
  tmux display-message "Use Ctrl-B twice if you run tmux *inside* the pod shells."
  tmux attach -t l4s-lidar
}

destroy_all() {
  title "🗑  Deleting namespace '${NAMESPACE}' (everything under it)"
  kubectl delete namespace "$NAMESPACE" --ignore-not-found
  info "Waiting for namespace deletion..."
  for i in {1..60}; do
    if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
      info "Namespace deleted."
      return
    fi
    sleep 2
  done
  warn "Namespace still terminating; control plane will finish cleanup."
}

usage() {
  cat <<'EOF'
Usage:
  NODE_SENDER=<node> NODE_RECEIVER=<node> ./run_k8s.sh [deploy]
  ./run_k8s.sh restart
  ./run_k8s.sh logs
  ./run_k8s.sh tmux
  ./run_k8s.sh destroy_all

Environment (selected):
  # Required for 'deploy'
  NODE_SENDER (default: cpr-a200-0779)
  NODE_RECEIVER (default: ki20erk3shusky1)

  # Cross-pod discovery:
  SENDER_HOST_IP= l4s-lidar-sender     (default)
  RECEIVER_HOST_IP= l4s-lidar-receiver (default)
  SENDER_PORT=51000  RECEIVER_PORT=51000

  # SCReAM + PointCloud:
  DELAY_TARGET RATE_MIN RATE_INIT RATE_MAX RATE_SCALE
  MAX_TOTAL_RATE PACING_HEADROOM SENDPIPELINE LOCAL_RTCP_PORT
  TOPIC DST_IP DST_PORT COMP_MODULE COMP_CLASS QUANT_BITS COMP_LEVEL WORKERS
  QUEUE_SIZE MAX_PAYLOAD RTP_CLOCK FRAME_RATE
  PORT OUTPUT_TOPIC FRAME_ID

  # Optional secrets (if both set, secret will be created/updated)
  API_TOKEN=... PASSWORD=...

Notes:
- Scripts are sourced from your repo:
    src/sender_scripts  → ConfigMap l4s-lidar-sender-scripts → mounted at /opt/pointcloud/sender_scripts
    src/receiver_scripts → ConfigMap l4s-lidar-receiver-scripts → mounted at /opt/pointcloud/receiver_scripts
- Edit scripts locally, rerun 'deploy' to update ConfigMaps and roll pods.
EOF
}

case "$ACTION" in
  deploy)       deploy_all ;;
  restart)      restart_all ;;
  logs)         logs_all ;;
  tmux)         tmux_mode ;;
  destroy_all)  destroy_all ;;
  -h|--help|help) usage ;;
  *) echo "Unknown action: $ACTION"; usage; exit 1 ;;
esac