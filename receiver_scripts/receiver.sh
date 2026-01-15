#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/env.sh"
: "${SCREAM_TARGET_DIR:?SCREAM_TARGET_DIR not set. Check env.sh}"

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
# Sanity check
#####################################
if [ ! -x "$SCREAM_TARGET_DIR/scream_receiver" ]; then
  echo "❌ scream_receiver not found or not executable in $SCREAM_TARGET_DIR"
  exit 1
fi

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
