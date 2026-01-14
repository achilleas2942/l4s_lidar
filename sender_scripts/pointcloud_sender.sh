#!/bin/bash
set -e

TOPIC=${TOPIC:-/lidar_points}
DST_IP=${DST_IP:-127.0.0.1}
DST_PORT=${DST_PORT:-30000}
COMP_MODULE=${COMP_MODULE:-draco_compressor}
COMP_CLASS=${COMP_CLASS:-DracoCompression}
QUANT_BITS=${QUANT_BITS:-12}
COMP_LEVEL=${COMP_LEVEL:-3}
WORKERS=${WORKERS:-1}

exec python3 pointcloud_sender.py \
  --topic "$TOPIC" \
  --dst_ip "$DST_IP" \
  --dst_port "$DST_PORT" \
  --compressor_module "$COMP_MODULE" \
  --compressor_class "$COMP_CLASS" \
  --quant_bits "$QUANT_BITS" \
  --comp_level "$COMP_LEVEL" \
  --workers "$WORKERS"
