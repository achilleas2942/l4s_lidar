#!/usr/bin/env bash
set -e

# ------------------------------
# Source ROS base
# ------------------------------
if [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
    source /opt/ros/${ROS_DISTRO}/setup.bash
fi

# ------------------------------
# Source workspace if present
# ------------------------------
if [ -f "/opt/pointcloud_ws/install/setup.bash" ]; then
    source /opt/pointcloud_ws/install/setup.bash
fi

# ------------------------------
# Optional user hooks
# ------------------------------
if [ -f "/etc/container.env" ]; then
    source /etc/container.env
fi

exec "$@"