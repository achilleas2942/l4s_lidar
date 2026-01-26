# PointCloud Streaming with SCReAM + Draco (Docker)

This setup streams a ROS2 `PointCloud2` topic:

**ROS2 → Draco compression → RTP → SCReAM congestion control
→ Network →
Receiver → Decompression → ROS2**

Everything runs inside Docker containers using
**`run_container_pointcloud.sh`**.

------------------------------------------------------------------------

## Docker Image

    ghcr.io/achilleas2942/l4s-ros:pointcloud

The same image runs both roles:
- **Sender** → captures ROS pointcloud, compresses, streams
- **Receiver** → receives SCReAM/RTP, decompresses, republishes

------------------------------------------------------------------------

# Quick Start

## Same Machine (Docker network)

Terminal 1 --- Receiver:

``` bash
ROLE=receiver ./run_container_pointcloud.sh
```

Terminal 2 --- Sender:

``` bash
ROLE=sender ./run_container_pointcloud.sh
```

Docker creates an internal network (`scream_net`) and containers talk
via hostname.

------------------------------------------------------------------------

## Different Machines (Host Networking)

### On RECEIVER machine

``` bash
ROLE=receiver USE_HOST_NETWORK=1 SENDER_HOST_IP=<SENDER_IP> ./run_container_pointcloud.sh
```

### On SENDER machine

``` bash
ROLE=sender USE_HOST_NETWORK=1 RECEIVER_HOST_IP=<RECEIVER_IP> ./run_container_pointcloud.sh
```

> **Important**
> - `RECEIVER_HOST_IP` = IP of receiver machine (always include it by changing the <RECEIVER_IP>)
> - `SENDER_HOST_IP` = IP of sender machine (always include it by changing the <RECEIVER_IP>)

------------------------------------------------------------------------

# Roles

| ROLE     | Function                                                   |
|----------|------------------------------------------------------------|
| sender   | Subscribes to ROS topic → compresses → SCReAM/RTP send     |
| receiver | SCReAM/RTP receive → decompress → publishes ROS topic      |

------------------------------------------------------------------------

# Networking Modes


| Mode           |Variable                          | When to use                      |
|----------------|----------------------------------|----------------------------------|
| Docker network | `USE_DOCKER_NETWORK=1` (default) | Containers on same machine       |
| Host network   | `USE_HOST_NETWORK=1`             | Containers on different machines |

------------------------------------------------------------------------

# SCReAM Parameters (Congestion Control)

| Variable          | Default | Meaning                  |
|-------------------|---------|--------------------------|
| `DELAY_TARGET`    | 0.06    | Target queuing delay (s) |
| `RATE_MIN`        | 2000    | Minimum bitrate (kbps)   |
| `RATE_INIT`       | 5000    | Initial bitrate          |
| `RATE_MAX`        | 25000   | Max encoder rate         |
| `MAX_TOTAL_RATE`  | 60000   | Total allowed rate       |
| `PACING_HEADROOM` | 1.5     | SCReAM pacing margin     |

Example:

``` bash
RATE_MAX=40000 DELAY_TARGET=0.04 ROLE=sender ./run_container_pointcloud.sh
```

------------------------------------------------------------------------

# PointCloud Sender Parameters

| Variable      | Default                      |
|---------------|------------------------------|
| `TOPIC`       | `/husky/ouster/points`       |
| `FRAME_RATE`  | 10                           |
| `MAX_PAYLOAD` | 1200 bytes                   |
| `COMP_MODULE` | compressors.draco_compressor |
| `COMP_CLASS`  | DracoCompression             |
| `QUANT_BITS`  | 12                           |
| `COMP_LEVEL`  | 3                            |

Example:

``` bash
ROLE=sender TOPIC=/lidar_points FRAME_RATE=15 ./run_container_pointcloud.sh
```

------------------------------------------------------------------------

# PointCloud Receiver Parameters

| Variable       | Default         |
|----------------|-----------------|
| `PORT`         | 30112           |
| `OUTPUT_TOPIC` | pointcloud_rx   |
| `FRAME_ID`     | husky/os_sensor |

Example:

``` bash
ROLE=receiver OUTPUT_TOPIC=/cloud_rx FRAME_ID=lidar ./run_container_pointcloud.sh
```

------------------------------------------------------------------------

# Ports

The script automatically exposes all SCReAM RTP/RTCP ports required
for: - RTP media - RTCP control - Codec signaling

No manual port mapping required.

------------------------------------------------------------------------

# Run your code

Follow the logic of pointcloud_sender/receiver.py and create your own
code. Add your code to the mounted volumes (./l4s_lidar/sender_scripts
and ./l4s_lidar/receiver_scripts). Then edit sender.sh and receiver.sh
to execute your pointcloud_sender/receiver code.

------------------------------------------------------------------------

# What the Script Handles Automatically

✔ Docker network creation\
✔ Container cleanup\
✔ SCReAM host/IP routing\
✔ Port exposure\
✔ Environment variable forwarding\
✔ Sender/Receiver script mounting

------------------------------------------------------------------------

# Troubleshooting in Case of Error

| Issue               | Cause          | Fix
| --------------------|----------------|-------------------------------------------|
| No packets received | Wrong IP       | Check `RECEIVER_HOST_IP`/`SENDER_HOST_IP` |
| Segfault in SCReAM  | Port conflict  | Ensure no other process uses ports        |
| Empty clouds        | NaNs in input  | Sender filters NaNs before Draco          |
| Rotated cloud       | Frame mismatch | Apply TF or axis flip                     |

------------------------------------------------------------------------

# Stop Containers

Just CTRL+C --- containers run with `--rm`.
