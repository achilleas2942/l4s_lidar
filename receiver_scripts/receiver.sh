#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.sh"

#####################################
# Defaults (override via args)
#####################################

LISTEN_PORT="${1:-51000}"

#####################################
# Timestamp (for logs)
#####################################

DATE="$(date +%y-%m-%d_%H%M%S)"
export DATE

#####################################
# Info
#####################################

echo "========================================"
echo " SCReAM LiDAR Receiver"
echo "----------------------------------------"
echo " Listening Port : $LISTEN_PORT"
echo " Date           : $DATE"
echo "========================================"

#####################################
# Start SCReAM receiver
#####################################

exec "$SCREAM_TARGET_DIR/scream_receiver" \
  "$LISTEN_PORT"
