#!/usr/bin/env bash
set -euo pipefail

# ======================================
# Configuration (can be overridden via env)
# ======================================
TOPIC=${TOPIC:-/husky/ouster/points}                      # sender topic
DST_IP=${DST_IP:-127.0.0.1}                               # destination IP
DST_PORT=${DST_PORT:-30000}                               # destination port    
COMP_MODULE=${COMP_MODULE:-compressors.draco_compressor}  # sender compressor module
COMP_CLASS=${COMP_CLASS:-DracoCompression}                # sender compressor class  
QUANT_BITS=${QUANT_BITS:-12}                              # sender quantization bits
COMP_LEVEL=${COMP_LEVEL:-3}                               # sender compression level
WORKERS=${WORKERS:-1}                                     # sender worker threads
QUEUE_SIZE=${QUEUE_SIZE:-10}                              # sender queue size
MAX_PAYLOAD=${MAX_PAYLOAD:-1200}                          # sender max RTP payload size
RTP_CLOCK=${RTP_CLOCK:-90000}                             # sender RTP clock rate
FRAME_RATE=${FRAME_RATE:-10}                              # sender frame rate

# ======================================
# Info
# ======================================
echo "========================================"
echo "🚀 Starting PointCloud Sender"
echo "----------------------------------------"
echo "Topic            : ${TOPIC}"
echo "Compressor       : ${COMP_MODULE}.${COMP_CLASS}"
echo "Quantization Bits: ${QUANT_BITS}"
echo "Compression Level: ${COMP_LEVEL}"
echo "RTP Clock        : ${RTP_CLOCK:-90000}"
echo "Frame Rate       : ${FRAME_RATE:-10} Hz"
echo "========================================"

# ======================================
# Execute Python sender
# ======================================
exec python3 /opt/pointcloud/sender_scripts/pointcloud_sender.py \
    --topic "${TOPIC}" \
    --dst_ip "${DST_IP}" \
    --dst_port "${DST_PORT}" \
    --compressor_module "${COMP_MODULE}" \
    --compressor_class "${COMP_CLASS}" \
    --quant_bits "${QUANT_BITS}" \
    --comp_level "${COMP_LEVEL}" \
    --workers "${WORKERS}" \
    --queue_size "${QUEUE_SIZE}" \
    --max_payload "${MAX_PAYLOAD}" \
    --rtp_clock "${RTP_CLOCK}" \
    --frame_rate "${FRAME_RATE}"