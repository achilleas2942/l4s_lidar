#!/usr/bin/env bash
set -euo pipefail

# =====================================
# Configuration (edit here, not below)
# =====================================

IMAGE_NAME="ghcr.io/achilleas2942/l4s-lidar"
IMAGE_TAG="minimal"

# ROS distro: rolling | jazzy | humble | iron
ROS_DISTRO="rolling"

# Feature toggles (0 = off, 1 = on)
ENABLE_RUST=0
ENABLE_GST_DEV=0
ENABLE_GUI=0

# Docker build context
DOCKERFILE="Dockerfile.${IMAGE_TAG}"
BUILD_CONTEXT="."

# =====================================
# Derived values
# =====================================

FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

BUILD_ARGS=(
  "--build-arg" "ROS_DISTRO=${ROS_DISTRO}"
  "--build-arg" "ENABLE_RUST=${ENABLE_RUST}"
  "--build-arg" "ENABLE_GST_DEV=${ENABLE_GST_DEV}"
  "--build-arg" "ENABLE_GUI=${ENABLE_GUI}"
)

# =====================================
# Sanity checks
# =====================================

if ! command -v docker &> /dev/null; then
  echo "❌ Docker not found. Please install Docker first."
  exit 1
fi

echo "====================================="
echo "🐳 Building Docker Image"
echo "-------------------------------------"
echo "Image       : ${FULL_IMAGE_NAME}"
echo "ROS Distro  : ${ROS_DISTRO}"
echo "Rust        : ${ENABLE_RUST}"
echo "GST Dev     : ${ENABLE_GST_DEV}"
echo "GUI Support : ${ENABLE_GUI}"
echo "====================================="
echo

# =====================================
# Build
# =====================================

docker build \
  --pull \
  --progress=plain \
  "${BUILD_ARGS[@]}" \
  -t "${FULL_IMAGE_NAME}" \
  -f "${DOCKERFILE}" \
  "${BUILD_CONTEXT}"

echo
echo "✅ Build completed successfully!"
echo "➡ Image: ${FULL_IMAGE_NAME}"
