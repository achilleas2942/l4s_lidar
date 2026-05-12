#!/usr/bin/env bash
set -euo pipefail

# =====================================
# Configuration
# =====================================

IMAGE_NAME="ghcr.io/achilleas2942/l4s-ros"
IMAGE_TAG="pointcloud"

ROLE="${ROLE:-sender}"                                      # sender | receiver
CONTAINER_NAME="l4s-ros-${IMAGE_TAG}-${ROLE}"

# Runtime mode
INTERACTIVE=1                                               # 1 = interactive shell, 0 = non-interactive
DETACH=0                                                    # 1 = detached, 0 = foreground

# Networking (L4S / ROS friendly)
ENABLE_NET_ADMIN=1
USE_DOCKER_NETWORK="${USE_DOCKER_NETWORK:-1}"               # 1 for same-host multi-container
USE_HOST_NETWORK="${USE_HOST_NETWORK:-0}"                   # 1 for different hosts
RECEIVER_HOST="${RECEIVER_HOST:-127.0.0.1}"                 # [IMPORTANT!] Set the receiver host IP for sender
SENDER_HOST="${SENDER_HOST:-127.0.0.1}"                     # [IMPORTANT!] Set the sender host IP for receiver

# Environment
PRINT_ENV=1
ROS_DOMAIN_ID=0

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

HOST_SENDER_SCRIPTS="${REPO_ROOT}/src/sender_scripts"
HOST_RECEIVER_SCRIPTS="${REPO_ROOT}/src/receiver_scripts"
CONTAINER_SCRIPT_ROOT="/opt/pointcloud"

# SCREaM sender / receiver parameters
DELAY_TARGET="${DELAY_TARGET:-0.06}"                        # seconds
RATE_MIN="${RATE_MIN:-2000}"                                # kbps
RATE_INIT="${RATE_INIT:-5000}"                              # kbps
RATE_MAX="${RATE_MAX:-25000}"                               # kbps
RATE_SCALE="${RATE_SCALE:-1}"                               # scale factor
MAX_TOTAL_RATE="${MAX_TOTAL_RATE:-60000}"                   # kbps
PACING_HEADROOM="${PACING_HEADROOM:-1.5}"                   # pacing headroom
SENDPIPELINE="${SENDPIPELINE:-1}"                           # SCReAM send pipeline index
LOCAL_RTCP_PORT="${LOCAL_RTCP_PORT:-51000}"                 # receiver local RTCP port
RECEIVER_PORT="${RECEIVER_PORT:-51000}"                     # receiver SCReAM RTP port
SENDER_PORT="${SENDER_PORT:-51000}"                         # sender SCReAM RTP port

# POINTCLOUD sender / receiver parameters
QUEUE_SIZE="${QUEUE_SIZE:-4}"                               # sender queue size
MAX_PAYLOAD="${MAX_PAYLOAD:-1200}"                          # sender max RTP payload size
RTP_CLOCK="${RTP_CLOCK:-90000}"                             # sender RTP clock rate
FRAME_RATE="${FRAME_RATE:-10}"                              # sender frame rate
TOPIC="${TOPIC:-/husky/ouster/points}"                      # sender topic
DST_IP="${DST_IP:-127.0.0.1}"                               # destination IP
DST_PORT="${DST_PORT:-30000}"                               # destination port
COMP_MODULE="${COMP_MODULE:-compressors.draco_compressor}"  # sender compressor module
COMP_CLASS="${COMP_CLASS:-DracoCompression}"                # sender compressor class
QUANT_BITS="${QUANT_BITS:-12}"                              # sender quantization bits
COMP_LEVEL="${COMP_LEVEL:-3}"                               # sender compression level
WORKERS="${WORKERS:-1}"                                     # sender worker threads
PORT="${PORT:-30112}"                                       # receiver listening port
OUTPUT_TOPIC="${OUTPUT_TOPIC:-/pointcloud_rx}"              # receiver output topic
FRAME_ID="${FRAME_ID:-husky/os_sensor}"                     # receiver frame ID

# =====================================
# Sanity checks
# =====================================
if ! command -v docker &> /dev/null; then
  echo "❌ Docker not found"
  exit 1
fi

if [[ "${ROLE}" != "sender" && "${ROLE}" != "receiver" ]]; then
  echo "❌ ROLE must be 'sender' or 'receiver'"
  exit 1
fi

# =====================================
# Derived values
# =====================================
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
DOCKER_ARGS=()

# -----------------
# Mode flags
# -----------------
if [ "${INTERACTIVE}" = "1" ]; then
  DOCKER_ARGS+=("-it")
fi

if [ "${DETACH}" = "1" ]; then
  DOCKER_ARGS+=("-d")
fi

# -----------------
# Networking
# -----------------
if [ "${USE_HOST_NETWORK}" = "1" ]; then
  DOCKER_ARGS+=("--network=host")
  echo "Using host networking (multi-host)"
  if [ "${ROLE}" = "sender" ]; then
    export RECEIVER_HOST="${RECEIVER_HOST}"
  else
    export SENDER_HOST="${SENDER_HOST}"
  fi
elif [ "${USE_DOCKER_NETWORK}" = "1" ]; then
  DOCKER_NETWORK="scream_net"
  docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1 || \
      docker network create "${DOCKER_NETWORK}"
  DOCKER_ARGS+=("--network=${DOCKER_NETWORK}")
  echo "Using Docker network: ${DOCKER_NETWORK}"

  # Set container hostnames for SCReAM communication
  if [ "${ROLE}" = "sender" ]; then
    export RECEIVER_HOST="l4s-ros-${IMAGE_TAG}-receiver"
  else
    export SENDER_HOST="l4s-ros-${IMAGE_TAG}-sender"
  fi
fi

# -----------------
# Capabilities
# -----------------
[ "${ENABLE_NET_ADMIN}" = "1" ] && DOCKER_ARGS+=("--cap-add=NET_ADMIN")

if [ "${ROLE}" = "sender" ]; then
  # -----------------
  # Expose SCReAM ports
  # -----------------
  # SCReAM uses multiple UDP/TCP ports internally for RTP, RTCP, and codec control
  # Map all typical sender ports
  for port in {30000..30009} {50000..50007}; do
      DOCKER_ARGS+=("-p" "${port}:${port}/udp")
  done
  for port in {30001..30009..2} {50001..50007..2}; do
      DOCKER_ARGS+=("-p" "${port}:${port}/tcp")
  done
  # -----------------
  # Environment
  # -----------------
  DOCKER_ARGS+=(
    "-e" "PRINT_ENV=${PRINT_ENV}"
    "-e" "ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"
    "-e" "RECEIVER_HOST=${RECEIVER_HOST:-127.0.0.1}"
    "-e" "USE_HOST_NETWORK=${USE_HOST_NETWORK}"
  )
  # -----------------
  # Role-based scripts
  # -----------------
  if [ ! -d "${HOST_SENDER_SCRIPTS}" ]; then
    echo "❌ sender_scripts directory not found: ${HOST_SENDER_SCRIPTS}"
    exit 1
  fi
  DOCKER_ARGS+=(
    "-v" "${HOST_SENDER_SCRIPTS}:${CONTAINER_SCRIPT_ROOT}/sender_scripts:ro"
  )
  ENTRYPOINT_CMD=(
    "bash"
    "${CONTAINER_SCRIPT_ROOT}/sender_scripts/sender.sh"
  )
  # -----------------
  # SCReAM parameters
  # -----------------
  DOCKER_ARGS+=(
    "-e" "DELAY_TARGET=${DELAY_TARGET}"
    "-e" "RATE_MIN=${RATE_MIN}"
    "-e" "RATE_INIT=${RATE_INIT}"
    "-e" "RATE_MAX=${RATE_MAX}"
    "-e" "RATE_SCALE=${RATE_SCALE}"
    "-e" "MAX_TOTAL_RATE=${MAX_TOTAL_RATE}"
    "-e" "PACING_HEADROOM=${PACING_HEADROOM}"
    "-e" "SENDPIPELINE=${SENDPIPELINE}"
    "-e" "RECEIVER_PORT=${RECEIVER_PORT:-51000}"
  )
  # -----------------
  # Pointcloud parameters
  # -----------------
  DOCKER_ARGS+=(
    "-e" "TOPIC=${TOPIC}"
    "-e" "DST_IP=${DST_IP}"
    "-e" "DST_PORT=${DST_PORT}"
    "-e" "COMP_MODULE=${COMP_MODULE}"
    "-e" "COMP_CLASS=${COMP_CLASS}"
    "-e" "QUANT_BITS=${QUANT_BITS}"
    "-e" "COMP_LEVEL=${COMP_LEVEL}"
    "-e" "WORKERS=${WORKERS}"
    "-e" "QUEUE_SIZE=${QUEUE_SIZE}"
    "-e" "MAX_PAYLOAD=${MAX_PAYLOAD}"
    "-e" "RTP_CLOCK=${RTP_CLOCK}"
    "-e" "FRAME_RATE=${FRAME_RATE}"
  )
else
  # -----------------
  # Expose SCReAM ports
  # -----------------
  # Map all typical receiver ports
  for port in {51000..51009} {30112..30119}; do
      DOCKER_ARGS+=("-p" "${port}:${port}/udp")
  done
  # -----------------
  # Environment
  # -----------------
  DOCKER_ARGS+=(
    "-e" "PRINT_ENV=${PRINT_ENV}"
    "-e" "ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"
    "-e" "SENDER_HOST=${SENDER_HOST:-127.0.0.1}"
    "-e" "USE_HOST_NETWORK=${USE_HOST_NETWORK}"
  )
  # -----------------
  # Role-based scripts
  # -----------------
  if [ ! -d "${HOST_RECEIVER_SCRIPTS}" ]; then
    echo "❌ receiver_scripts directory not found: ${HOST_RECEIVER_SCRIPTS}"
    exit 1
  fi
  DOCKER_ARGS+=(
    "-v" "${HOST_RECEIVER_SCRIPTS}:${CONTAINER_SCRIPT_ROOT}/receiver_scripts:ro"
  )
  ENTRYPOINT_CMD=(
    "bash"
    "${CONTAINER_SCRIPT_ROOT}/receiver_scripts/receiver.sh"
  )
  # -----------------
  # SCReAM parameters
  # -----------------
  DOCKER_ARGS+=(
    "-e" "LOCAL_RTCP_PORT=${LOCAL_RTCP_PORT:-51000}"
    "-e" "SENDER_PORT=${SENDER_PORT:-51000}"
  )
  # Pointcloud parameters
  # -----------------
  DOCKER_ARGS+=(
    "-e" "PORT=${PORT}"
    "-e" "OUTPUT_TOPIC=${OUTPUT_TOPIC}"
    "-e" "FRAME_ID=${FRAME_ID}"
  )
fi

# -----------------
# Cleanup existing container
# -----------------
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "🧹 Removing existing container: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}"
fi

# =====================================
# Run
# =====================================
echo "====================================="
echo "🚀 Running Docker Container"
echo "-------------------------------------"
echo "Image        : ${FULL_IMAGE_NAME}"
echo "Container    : ${CONTAINER_NAME}"
echo "Role         : ${ROLE}"
if [ "${ROLE}" = "sender" ]; then
  echo "RECEIVER_HOST: ${RECEIVER_HOST}"
elif [ "${ROLE}" = "receiver" ]; then
  echo "SENDER_HOST  : ${SENDER_HOST}"
fi
echo "====================================="
echo

docker run --rm \
  --name "${CONTAINER_NAME}" \
  "${DOCKER_ARGS[@]}" \
  "${FULL_IMAGE_NAME}" \
  "${ENTRYPOINT_CMD[@]}"

if docker network ls | grep -q scream_net | awk '{print $2}'; then 
  docker network rm "${DOCKER_NETWORK}"
fi
echo
echo "✅ Container exited"
