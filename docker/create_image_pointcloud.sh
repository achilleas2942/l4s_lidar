#!/usr/bin/env bash
set -euo pipefail

# =====================================
# Configuration (edit here)
# =====================================

IMAGE_NAME="ghcr.io/achilleas2942/l4s-ros"
IMAGE_TAG="pointcloud"

# ROS distro: rolling | jazzy | humble | iron
ROS_DISTRO="rolling"

# Dockerfile
DOCKERFILE="Dockerfile.${IMAGE_TAG}"
BUILD_CONTEXT="."

# =====================================
# Derived values
# =====================================

FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

BUILD_ARGS=(
  "--build-arg" "ROS_DISTRO=${ROS_DISTRO}"
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
