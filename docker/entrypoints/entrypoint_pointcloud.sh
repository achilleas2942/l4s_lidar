#!/usr/bin/env bash
set -e

# ------------------------------
# Source ROS base
# ------------------------------
if [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
    source /opt/ros/${ROS_DISTRO}/setup.bash
fi

# ------------------------------
# Optional user hooks
# ------------------------------
if [ -f "/etc/container.env" ]; then
    source /etc/container.env
fi

exec "$@"