#!/usr/bin/env bash
set -euo pipefail

SESSION="ros_scream_receiver_session"

# Source ROS and SCReAM environment
ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"

# -----------------------------
# Start tmux session
# -----------------------------
tmux new-session -d -s "$SESSION" -n scream

# -----------------------------
# Pane 0: SCReAM receiver
# -----------------------------
tmux send-keys -t "$SESSION:0.0"  "bash /opt/pointcloud/receiver_scripts/scream_receiver.sh" C-m

# -----------------------------
# Pane 1: PointCloud Python receiver
# -----------------------------
tmux split-window -h -t "$SESSION:0"
tmux send-keys -t "$SESSION:0.1" "bash opt/pointcloud/receiver_scripts/pointcloud_receiver.sh " C-m

# -----------------------------
# Optional monitoring panes (can be used later)
# -----------------------------
tmux split-window -v -t "$SESSION:0.1"
tmux send-keys -t "$SESSION:0.2" "source /opt/ros/rolling/setup.bash && ros2 topic echo /pointcloud_rx" C-m

tmux split-window -v -t "$SESSION:0.2"
tmux send-keys -t "$SESSION:0.3" "source /opt/ros/rolling/setup.bash" C-m

# -----------------------------
# Layout & attach
# -----------------------------

tmux select-layout -t "$SESSION" tiled
tmux attach-session -t "$SESSION"
