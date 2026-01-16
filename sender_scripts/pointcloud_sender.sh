#!/usr/bin/env bash
set -euo pipefail

# ======================================
# Configuration (can be overridden via env)
# ======================================
TOPIC=${TOPIC:-/lidar_points}
DST_IP=${DST_IP:-127.0.0.1}
DST_PORT=${DST_PORT:-30000}
COMP_MODULE=${COMP_MODULE:-compressors.draco_compressor}
COMP_CLASS=${COMP_CLASS:-DracoCompression}
QUANT_BITS=${QUANT_BITS:-12}
COMP_LEVEL=${COMP_LEVEL:-3}
WORKERS=${WORKERS:-1}

# ======================================
# Info
# ======================================
echo "========================================"
echo "🚀 Starting PointCloud Sender"
echo "Topic          : $TOPIC"
echo "Destination IP : $DST_IP"
echo "Destination Port : $DST_PORT"
echo "Compressor     : $COMP_MODULE.$COMP_CLASS"
echo "Quant Bits     : $QUANT_BITS"
echo "Compression Lv : $COMP_LEVEL"
echo "Workers        : $WORKERS"
echo "========================================"

# ======================================
# Execute Python sender
# ======================================
exec python3 /opt/pointcloud/sender_scripts/pointcloud_sender.py \
    --topic "$TOPIC" \
    --dst_ip "$DST_IP" \
    --dst_port "$DST_PORT" \
    --compressor_module "$COMP_MODULE" \
    --compressor_class "$COMP_CLASS" \
    --quant_bits "$QUANT_BITS" \
    --comp_level "$COMP_LEVEL" \
    --workers "$WORKERS"
