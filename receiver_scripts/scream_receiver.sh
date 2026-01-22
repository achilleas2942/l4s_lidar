#!/usr/bin/env bash
set -euo pipefail

SCREAM_TARGET_DIR="/opt/scream/bin"

# Use environment variables from run_container.sh
SENDER_IP="$(getent hosts "${SENDER_HOST:-127.0.0.1}" | awk '{print $1}')"       # sender container hostname/IP
RTP_PORT="${SENDER_PORT:-51000}"            # sender RTP port
RTCP_PORT="${LOCAL_RTCP_PORT:-51000}"       # receiver local RTCP port

DATE="$(date +%y-%m-%d_%H%M%S)"

# ------------------------------
# Sanity check
# ------------------------------
if [ ! -x "$SCREAM_TARGET_DIR/scream_receiver" ]; then
  echo "❌ scream_receiver not found in $SCREAM_TARGET_DIR"
  exit 1
fi

# ------------------------------
# Info
# ------------------------------
echo "========================================"
echo " SCReAM LiDAR Receiver"
echo "----------------------------------------"
echo " Sender IP   : ${SENDER_IP}"
echo " RTP Port    : ${RTP_PORT}"
echo " RTCP Port   : ${RTCP_PORT}"
echo " Date        : ${DATE}"
echo "========================================"

# ------------------------------
# Start SCReAM receiver
# ------------------------------
exec "${SCREAM_TARGET_DIR}/scream_receiver" \
    "${SENDER_IP}" \
    "${RTP_PORT}" \
    "${RTCP_PORT}" \
    "${DATE}"
