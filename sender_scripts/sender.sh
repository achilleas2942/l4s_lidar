#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/env.sh"
: "${SCREAM_TARGET_DIR:?SCREAM_TARGET_DIR not set. Check env.sh}"

#####################################
# Defaults (can be overridden by args)
#####################################

RECEIVER_IP="${1:-192.168.1.150}" # Important to change to receiver address
SCREAM_PORT="${2:-51000}"

# SCReAM tuning (LiDAR-friendly)
DELAY_TARGET="${DELAY_TARGET:-0.06}"     # seconds
RATE_MIN="${RATE_MIN:-2000}"              # kbps
RATE_INIT="${RATE_INIT:-5000}"            # kbps
RATE_MAX="${RATE_MAX:-25000}"             # kbps
RATE_SCALE="${RATE_SCALE:-1}"             
MAX_TOTAL_RATE="${MAX_TOTAL_RATE:-60000}" # kbps
PACING_HEADROOM="${PACING_HEADROOM:-1.5}"

#####################################
# Sanity check
#####################################
if [ ! -x "$SCREAM_TARGET_DIR/scream_sender" ]; then
  echo "❌ scream_sender not found or not executable in $SCREAM_TARGET_DIR"
  exit 1
fi

#####################################
# Info
#####################################

echo "========================================"
echo " SCReAM LiDAR Sender"
echo "----------------------------------------"
echo " Receiver IP       : $RECEIVER_IP"
echo " Receiver Port     : $SCREAM_PORT"
echo " Delay Target      : $DELAY_TARGET s"
echo " Rate (min/init/max): $RATE_MIN / $RATE_INIT / $RATE_MAX kbps"
echo " Max Total Rate    : $MAX_TOTAL_RATE kbps"
echo "========================================"

#####################################
# Start SCReAM sender
#####################################

exec "$SCREAM_TARGET_DIR/scream_sender" \
  -ect 1 \
  -delaytarget "$DELAY_TARGET" \
  -priority 1.0 \
  -ratemin "$RATE_MIN" \
  -rateinit "$RATE_INIT" \
  -ratemax "$RATE_MAX" \
  -ratescale "$RATE_SCALE" \
  -maxtotalrate "$MAX_TOTAL_RATE" \
  -pacingheadroom "$PACING_HEADROOM" \
  1 \
  "$RECEIVER_IP" "$SCREAM_PORT"
