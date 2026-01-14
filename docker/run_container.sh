#!/usr/bin/env bash
set -euo pipefail

# =====================================
# Configuration (edit here)
# =====================================

IMAGE_NAME="ghcr.io/achilleas2942/l4s-lidar"
IMAGE_TAG="minimal"

CONTAINER_NAME="l4s_lidar_${IMAGE_TAG}"

# Runtime mode
INTERACTIVE=1       # 1 = bash shell, 0 = run CMD only
DETACH=0            # 1 = -d, 0 = foreground

# Networking (L4S / ROS friendly)
USE_HOST_NETWORK=1
ENABLE_NET_ADMIN=1

# X11 / GUI support
ENABLE_GUI=0

# Volumes
MOUNT_WORKSPACE=0
HOST_WORKSPACE="${HOME}/ros2_ws"
CONTAINER_WORKSPACE="/workspace"

# Environment
PRINT_ENV=1
ROS_DOMAIN_ID=0

# =====================================
# Derived values
# =====================================

FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

DOCKER_ARGS=()

# -----------------
# Mode flags
# -----------------
if [ "$INTERACTIVE" = "1" ]; then
  DOCKER_ARGS+=("-it")
fi

if [ "$DETACH" = "1" ]; then
  DOCKER_ARGS+=("-d")
fi

# -----------------
# Networking
# -----------------
if [ "$USE_HOST_NETWORK" = "1" ]; then
  DOCKER_ARGS+=("--network=host")
fi

if [ "$ENABLE_NET_ADMIN" = "1" ]; then
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
# Volumes
# -----------------
if [ "$MOUNT_WORKSPACE" = "1" ]; then
  mkdir -p "${HOST_WORKSPACE}"
  DOCKER_ARGS+=(
    "-v" "${HOST_WORKSPACE}:${CONTAINER_WORKSPACE}"
    "-w" "${CONTAINER_WORKSPACE}"
  )
fi

# -----------------
# GUI / X11
# -----------------
if [ "$ENABLE_GUI" = "1" ]; then
  xhost +local:docker >/dev/null 2>&1 || true
  DOCKER_ARGS+=(
    "-e" "DISPLAY=${DISPLAY}"
    "-v" "/tmp/.X11-unix:/tmp/.X11-unix:rw"
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
echo "Host Net    : ${USE_HOST_NETWORK}"
echo "NET_ADMIN   : ${ENABLE_NET_ADMIN}"
echo "GUI         : ${ENABLE_GUI}"
echo "Workspace   : ${HOST_WORKSPACE}"
echo "====================================="
echo

docker run --rm \
  --name "${CONTAINER_NAME}" \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  "${DOCKER_ARGS[@]}" \
  "${FULL_IMAGE_NAME}" \
  bash

echo
echo "✅ Container exited"
