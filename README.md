# SCReAM + ROS 2 LiDAR PointCloud Streaming

This repository provides a **containerized, modular, real‑time pipeline** for streaming **ROS 2 LiDAR PointCloud2 messages** over the network using **SCReAM (Self‑Clocked Rate Adaptation for Multimedia)** with **L4S‑friendly congestion control** and **Draco compression**.

The design is inspired by and builds upon the SCReAM multicam examples, but is **cleanly separated**, **ROS‑native**, and optimized for **real‑time point cloud transmission**.

---

## High‑Level Architecture

```
LiDAR Sensor
   ↓  (ROS2 PointCloud2)
pointcloud_sender.py
   ↓  (Draco compression)
RTP packets
   ↓
SCReAM sender
   ↓  (UDP / L4S)
================ NETWORK ================
   ↓
SCReAM receiver
   ↓  (RTP reassembly)
RTP packets
   ↓
pointcloud_receiver.py
   ↓  (Draco decompression)
LiDAR messages
   ↓  (ROS2 PointCloud2)
```

---

## Repository Structure

```
.
├── deploy/
|   ├── helm/
│   |
|   ├── kustomize/
|   |
|   └── manifests/
|
├── docker/
|   ├── build_scripts
│   |   ├── create_image_stable.sh          # Builder for the stable image
│   |   ├── create_image_minimal.sh         # Builder for the minimal image
│   |   └── create_image_pointcloud.sh      # Builder for the pointcloud image
|   |
|   ├── dockerfiles/
│   |   ├── Dockerfile.stable               # Full SCReAM + GStreamer runtime
│   |   ├── Dockerfile.minimal              # Minimal SCReAM runtime (base image)
│   |   └── Dockerfile.pointcloud           # PointCloud image on top of minimal
|   |
|   ├── entrypoints/
│   |   ├── entrypoint_stable.sh
│   |   ├── entrypoint_minimal.sh
│   |   ├── entrypoint_pointcloud.sh
|   |
|   └── run_scripts/
│       └── run_container_pointcloud.sh     # Unified container launcher
│
├── src/
|   ├── sender_scripts/
│   |   ├── sender.sh                       # tmux‑based sender launcher
│   |   ├── scream_sender.sh                # Native SCReAM sender wrapper
│   |   ├── pointcloud_sender.py            # ROS2 → Draco → RTP
│   |   ├── pointcloud_sender.sh            # Runs pointcloud_sender.py
│   |   └── compressors/
│   |       └── draco_compressor.py
│   |
|   └── receiver_scripts/
│       ├── receiver.sh                     # tmux‑based receiver launcher
│       ├── scream_receiver.sh              # Native SCReAM receiver wrapper
│       ├── pointcloud_receiver.py          # RTP → Draco → ROS2
│       ├── pointcloud_receiver.sh          # Runs pointcloud_receiver.py
│       └── decompressors/
│           └── draco_decompressor.py
│   
└── README.md
```

---

## Docker Images Overview

### 1. **stable** image
**Purpose:**
- Builds SCReAM completely from source
- Includes GStreamer plugins, SCReAM sender/receiver binaries

**Used for:**
- Development
- Debugging
- Reference runtime

---

### 2. **minimal** image
**Purpose:**
- Minimal runtime for SCReAM
- No ROS‑specific dependencies
- Small footprint

**Contains:**
- `scream_sender`
- `scream_receiver`
- `gstscream` plugins

This image is the **base** for pointcloud streaming.

---

### 3. **pointcloud** image
**Purpose:**
- ROS 2 PointCloud streaming
- Draco compression
- tmux‑based orchestration

**Adds on top of minimal:**
- ROS 2 message types (`sensor_msgs`, `rclpy`)
- Python dependencies (`numpy`, `DracoPy`)
- tmux

---

## Build Images

From the `docker/` directory:

```bash
./build_scripts/create_image_stable.sh
./build_scripts/create_image_minimal.sh
./build_scripts/create_image_pointcloud.sh
```

---

## Running Containers (Mote details on how to run the containers [here](./docker/README.md))

### `run_container_pointcloud.sh`
A **single entry point** to run sender or receiver containers.

Key features:
- Role‑based execution (`sender` or `receiver`)
- Volume‑mounted scripts (no rebuild needed for logic changes)

Run the following bash script on the sender from the `docker/` directory:

```bash
ROLE="sender" ./run_scripts/run_container_pointcloud.sh
```

Run the following bash script on the receiver  from the `docker/` directory::

```bash
ROLE="receiver" ./run_scripts/run_container_pointcloud.sh
```

---

## Sender Side

### sender.sh (tmux launcher)
Starts a tmux session with multiple panes, typically:

- SCReAM sender
- pointcloud_sender.py
- Optional monitoring panes

### scream_sender.sh
Wrapper for the native SCReAM sender binary.

Responsibilities:
- Configure SCReAM rate control
- Launch `scream_sender`

### pointcloud_sender.py
ROS 2 node that:
- Subscribes to `PointCloud2`
- Compresses frames (Draco)
- Sends compressed frames via RTP

Key properties:
- Multithreaded compression
- Backpressure via bounded queues
- Frame dropping instead of blocking (real‑time safe)

---

## Receiver Side

### receiver.sh (tmux launcher)
Creates a tmux session with:

- SCReAM receiver
- pointcloud_receiver.py
- Optional monitoring panes

### scream_receiver.sh
Wrapper for the native SCReAM receiver binary.

### pointcloud_receiver.py
ROS 2 node that:
- Receives RTP packets
- Reassembles frames
- Decompresses Draco payloads
- Publishes `PointCloud2`

Designed for:
- Packet loss tolerance
- Frame‑level isolation
- Real‑time publication

---

## Compression / Decompression

### Draco
Currently supported compressor.

- `compressors/draco_compressor.py`
- `decompressors/draco_decompressor.py`

The architecture is **pluggable**:
- Additional compressors can be added later
- Selection via Python imports

---

## Real‑Time Design Principles

- No blocking in ROS callbacks
- Bounded queues (drop instead of stall)
- Separate threads for:
  - ROS
  - Compression
  - Networking
- tmux for visibility and debugging

---

## Common Issues & Debugging

### SCReAM receiver segfaults
Usually caused by:
- Missing runtime libraries
- Incorrect `GST_PLUGIN_PATH`
- Debug/release mismatch

Verify with:
```bash
ldd /opt/scream/bin/scream_receiver
GST_DEBUG=3 /opt/scream/bin/scream_receiver 51000
```

---

## License & Credits

- SCReAM: Ericsson Research
- GStreamer
- ROS 2
- Draco: Google

This repository adapts and extends SCReAM multicam examples for **ROS 2 LiDAR streaming**.

