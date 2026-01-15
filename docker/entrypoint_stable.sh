#!/usr/bin/env bash
set -e

# ------------------------------
# Source ROS environment
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

# ------------------------------
# Print runtime info (optional)
# ------------------------------
if [ "${PRINT_ENV:-0}" = "1" ]; then
    echo "ROS_DISTRO=${ROS_DISTRO}"
    echo "GStreamer version:"
    gst-launch-1.0 --version || true
fi

# ------------------------------
# Execute CMD
# ------------------------------
exec "$@"
