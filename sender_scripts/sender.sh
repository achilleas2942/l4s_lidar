#!/usr/bin/env bash
set -euo pipefail

SESSION="ros_scream_sender_session"

# Source ROS and SCReAM environment
ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"

# -----------------------------
# Start tmux session
# -----------------------------
tmux new-session -d -s "$SESSION"

# -----------------------------
# Pane 0: SCReAM sender
# -----------------------------
tmux send-keys -t "$SESSION:0.0" "bash /opt/pointcloud/sender_scripts/scream_sender.sh" C-m

# -----------------------------
# Pane 1: PointCloud Python sender
# -----------------------------
tmux split-window -h -t "$SESSION:0"
tmux send-keys -t "$SESSION:0.1" "bash /opt/pointcloud/sender_scripts/pointcloud_sender.sh" C-m

# -----------------------------
# Optional monitoring panes (can be used later)
# -----------------------------
tmux split-window -v -t "$SESSION:0.1"
tmux send-keys -t "$SESSION:0.2" "echo 'Monitoring/logs pane 1'" C-m

tmux split-window -v -t "$SESSION:0.2"
tmux send-keys -t "$SESSION:0.3" "echo 'Monitoring/logs pane 2'" C-m

# -----------------------------
# Layout
# -----------------------------
tmux select-layout -t "$SESSION" tiled

# -----------------------------
# Attach
# -----------------------------
tmux attach-session -t "$SESSION"
