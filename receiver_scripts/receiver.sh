#!/usr/bin/env bash
set -euo pipefail

#####################################
# Config
#####################################

SESSION="pointcloud_rx"

# Default ports (override via args)
SCREAM_PORT="${1:-51000}"
ROS_OUTPUT_TOPIC="${2:-/pointcloud_rx}"
FRAME_ID="${3:-map}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#####################################
# Safety
#####################################

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "⚠️  tmux session '$SESSION' already exists."
  echo "Attach with: tmux attach -t $SESSION"
  exit 0
fi

#####################################
# Start tmux
#####################################

tmux new-session -d -s "$SESSION" -n scream

#####################################
# Pane 0 — SCReAM receiver
#####################################

tmux send-keys -t "$SESSION:scream" \
  "cd $SCRIPT_DIR && ./scream_receiver.sh $SCREAM_PORT" C-m

#####################################
# Pane 1 — ROS2 pointcloud receiver
#####################################

tmux split-window -h -t "$SESSION:scream"

tmux send-keys -t "$SESSION:scream.1" \
  "cd $SCRIPT_DIR && ./pointcloud_receiver.sh \
    --port $SCREAM_PORT \
    --output-topic $ROS_OUTPUT_TOPIC \
    --frame-id $FRAME_ID" C-m

#####################################
# Layout & attach
#####################################

tmux select-layout -t "$SESSION" even-horizontal
tmux attach -t "$SESSION"
