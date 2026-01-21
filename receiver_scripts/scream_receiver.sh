#!/usr/bin/env bash
set -euo pipefail

SCREAM_TARGET_DIR="/opt/scream/bin"

# ------------------------------
# Defaults
# ------------------------------
SENDER_IP="${1:-127.0.0.1}"
RTP_PORT="${2:-51000}"
RTCP_PORT="${3:-51000}"

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
echo " Sender IP   : $SENDER_IP"
echo " RTP Port    : $RTP_PORT"
echo " RTCP Port   : $RTCP_PORT"
echo " Date        : $DATE"
echo "========================================"

# ------------------------------
# Start receiver
# ------------------------------
exec "$SCREAM_TARGET_DIR/scream_receiver" \
  "$SENDER_IP" \
  "$RTP_PORT" \
  "$RTCP_PORT" \
  "$DATE"
