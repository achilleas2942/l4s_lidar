#!/usr/bin/env bash
set -euo pipefail

# =====================================
# Configuration
# =====================================

IMAGE_NAME="ghcr.io/achilleas2942/l4s-ros"
IMAGE_TAG="pointcloud"

ROLE="${ROLE:-sender}"            # sender | receiver
CONTAINER_NAME="l4s-ros-${IMAGE_TAG}-${ROLE}"

# Runtime mode
INTERACTIVE=1            # 1 = interactive shell, 0 = non-interactive
DETACH=0                 # 1 = detached, 0 = foreground

# Networking (L4S / ROS friendly)
USE_HOST_NETWORK=0       # 1 for different hosts
USE_DOCKER_NETWORK=1     # 1 for same-host multi-container
ENABLE_NET_ADMIN=1

# Environment
PRINT_ENV=1
ROS_DOMAIN_ID=0

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST_SENDER_SCRIPTS="${REPO_ROOT}/sender_scripts"
HOST_RECEIVER_SCRIPTS="${REPO_ROOT}/receiver_scripts"
CONTAINER_SCRIPT_ROOT="/opt/pointcloud"

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
elif [ "${USE_DOCKER_NETWORK}" = "1" ]; then
  DOCKER_NETWORK="scream_net"
  docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1 || \
      docker network create "${DOCKER_NETWORK}"
  DOCKER_ARGS+=("--network=${DOCKER_NETWORK}")
  echo "Using Docker network: ${DOCKER_NETWORK}"

  # Set container hostnames for SCReAM communication
  if [ "${ROLE}" = "sender" ]; then
    export RECEIVER_HOST="l4s-ros-pointcloud-receiver"
    export RECEIVER_PORT=51000
  else
    export SENDER_HOST="l4s-ros-pointcloud-sender"
    export SENDER_PORT=51000
  fi
fi

# -----------------
# Capabilities
# -----------------
[ "${ENABLE_NET_ADMIN}" = "1" ] && DOCKER_ARGS+=("--cap-add=NET_ADMIN")

# -----------------
# Environment
# -----------------
DOCKER_ARGS+=(
  "-e" "PRINT_ENV=${PRINT_ENV}"
  "-e" "ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"
  "-e" "RECEIVER_HOST=${RECEIVER_HOST:-127.0.0.1}"
  "-e" "RECEIVER_PORT=${RECEIVER_PORT:-51000}"
  "-e" "SENDER_HOST=${SENDER_HOST:-127.0.0.1}"
  "-e" "SENDER_PORT=${SENDER_PORT:-51000}"
)

# -----------------
# Expose SCReAM ports
# -----------------
# SCReAM uses multiple UDP/TCP ports internally for RTP, RTCP, and codec control
if [ "${ROLE}" = "sender" ]; then
    # Map all typical sender ports
    for port in {30000..30009} {50000..50007}; do
        DOCKER_ARGS+=("-p" "${port}:${port}/udp")
    done
    for port in {30001..30009..2} {50001..50007..2}; do
        DOCKER_ARGS+=("-p" "${port}:${port}/tcp")
    done
else
    # Map all typical receiver ports
    for port in {51000..51009} {30112..30119}; do
        DOCKER_ARGS+=("-p" "${port}:${port}/udp")
    done
fi

# -----------------
# Role-based scripts
# -----------------
if [ "${ROLE}" = "sender" ]; then
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

else
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
echo "Image       : ${FULL_IMAGE_NAME}"
echo "Container   : ${CONTAINER_NAME}"
echo "Role        : ${ROLE}"
echo "Host Net    : ${USE_HOST_NETWORK}"
echo "NET_ADMIN   : ${ENABLE_NET_ADMIN}"
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
