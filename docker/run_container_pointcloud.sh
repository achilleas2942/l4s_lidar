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
USE_HOST_NETWORK=1
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
fi

if [ "${ENABLE_NET_ADMIN}" = "1" ]; then
  DOCKER_ARGS+=("--cap-add=NET_ADMIN")
fi

# -----------------
# Environment
# -----------------
DOCKER_ARGS+=(
  "-e" "PRINT_ENV=${PRINT_ENV}"
  "-e" "ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"
)

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

echo
echo "✅ Container exited"
