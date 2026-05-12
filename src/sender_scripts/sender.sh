#!/usr/bin/env bash
set -euo pipefail

SESSION="sender"

# Source ROS and SCReAM environment
ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"
ROS_ENV="export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"

# -----------------------------
# Start tmux session
# -----------------------------
tmux new-session -d -s "$SESSION"

# -----------------------------
# Pane 0: SCReAM sender
# -----------------------------
tmux send-keys -t "$SESSION:0.0" "bash /opt/pointcloud/sender_scripts/scream_sender.sh" C-m

# -----------------------------
# Pane 1: Pointcloud Python sender
# -----------------------------
tmux split-window -h -t "$SESSION:0"
tmux send-keys -t "$SESSION:0.1" "source ${ROS_SETUP} && ${ROS_ENV} && python3 /opt/pointcloud/sender_scripts/helpers/target_bitrate.py" C-m

# -----------------------------
# Optional monitoring panes (can be used later)
# -----------------------------
tmux split-window -v -t "$SESSION:0.1"
tmux send-keys -t "$SESSION:0.2" "source ${ROS_SETUP} && ${ROS_ENV} && bash /opt/pointcloud/sender_scripts/pointcloud_sender.sh" C-m

tmux split-window -v -t "$SESSION:0.2"
tmux send-keys -t "$SESSION:0.3" "source ${ROS_SETUP} && ${ROS_ENV}" C-m

# -----------------------------
# Layout & attach
# -----------------------------
tmux select-layout -t "$SESSION" tiled
tmux attach-session -t "$SESSION"
