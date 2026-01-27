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
tmux send-keys -t "$SESSION:0.2" "source /opt/ros/rolling/setup.bash && ros2 bag play -l /opt/pointcloud/sender_scripts/rosbag2_2025_06_27-12_05_56_0.db3" C-m

tmux split-window -v -t "$SESSION:0.2"
tmux send-keys -t "$SESSION:0.3" "source /opt/ros/rolling/setup.bash" C-m

# -----------------------------
# Layout & attach
# -----------------------------
tmux select-layout -t "$SESSION" tiled
tmux attach-session -t "$SESSION"
