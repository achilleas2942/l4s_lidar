#!/usr/bin/env bash
set -euo pipefail

#####################################
# Defaults (override via CLI args)
#####################################

PORT="${PORT:-30112}"
OUTPUT_TOPIC="${OUTPUT_TOPIC:-/pointcloud_rx}"
FRAME_ID="${FRAME_ID:-husky/os_sensor}"

#####################################
# Optional environment hook
#####################################
if [ -f "/etc/container.env" ]; then
  source /etc/container.env
fi

#####################################
# Info
#####################################
echo "========================================"
echo " PointCloud RTP Receiver (ROS2)"
echo "----------------------------------------"
echo " UDP Port     : ${PORT}"
echo " Output Topic : ${OUTPUT_TOPIC}"
echo " Frame ID     : ${FRAME_ID}"
echo "========================================"

#####################################
# Execute receiver
#####################################
exec python3 /opt/pointcloud/receiver_scripts/pointcloud_receiver.py \
  --port "${PORT}" \
  --output-topic "${OUTPUT_TOPIC}" \
  --frame-id "${FRAME_ID}"
