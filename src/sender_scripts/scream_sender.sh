#!/usr/bin/env bash
set -euo pipefail

# ------------------------------
# Configuration
# ------------------------------

SCREAM_TARGET_DIR="/opt/scream/bin"

# Use environment variables from run_container.sh
if ["USE_HOST_NETWORK"="${USE_HOST_NETWORK:-1}"]; then
  RECEIVER_IP="${RECEIVER_HOST:-127.0.0.1}"
else
  RECEIVER_IP="$(getent hosts "${RECEIVER_HOST:-127.0.0.1}" | awk '{print $1}')"  # receiver container hostname/IP
fi
SCREAM_PORT="${RECEIVER_PORT:-51000}"                                             # receiver port

DELAY_TARGET="${DELAY_TARGET:-0.06}"                                              # seconds
RATE_MIN="${RATE_MIN:-2000}"                                                      # kbps
RATE_INIT="${RATE_INIT:-5000}"                                                    # kbps
RATE_MAX="${RATE_MAX:-25000}"                                                     # kbps
RATE_SCALE="${RATE_SCALE:-1}"                                                     # scale factor
MAX_TOTAL_RATE="${MAX_TOTAL_RATE:-60000}"                                         # kbps
PACING_HEADROOM="${PACING_HEADROOM:-1.5}"                                         # pacing headroom
SENDPIPELINE="${SENDPIPELINE:-1}"                                                 # SCReAM send pipeline index

# Optional environment hooks
if [ -f "/etc/container.env" ]; then
    source /etc/container.env
fi

# ------------------------------
# Info
# ------------------------------
echo "========================================"
echo " SCReAM LiDAR Sender"
echo "----------------------------------------"
echo " Receiver IP        : ${RECEIVER_IP}"
echo " Receiver Port      : ${SCREAM_PORT}"
echo " Delay Target       : ${DELAY_TARGET} s"
echo " Rate (min/init/max): ${RATE_MIN} / ${RATE_INIT} / ${RATE_MAX} kbps"
echo " Max Total Rate     : ${MAX_TOTAL_RATE} kbps"
echo "========================================"

# ------------------------------
# Execute SCReAM sender
# ------------------------------
exec "${SCREAM_TARGET_DIR}/scream_sender" \
    -ect 1 \
    -delaytarget "${DELAY_TARGET}" \
    -priority 1.0 \
    -ratemin "${RATE_MIN}" \
    -rateinit "${RATE_INIT}" \
    -ratemax "${RATE_MAX}" \
    -ratescale "${RATE_SCALE}" \
    -maxtotalrate "${MAX_TOTAL_RATE}" \
    -pacingheadroom "${PACING_HEADROOM}" \
    "${SENDPIPELINE}" \
    "${RECEIVER_IP}" "${SCREAM_PORT}"
