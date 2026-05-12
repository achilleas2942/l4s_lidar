# L4S LiDAR – SCReAM & ROS 2 LiDAR PointCloud Streaming

This repository provides a **containerized, modular, real‑time pipeline** for streaming **ROS 2 LiDAR PointCloud2 messages** over the network using **SCReAM (Self‑Clocked Rate Adaptation for Multimedia)** with **L4S‑friendly congestion control** and **Draco compression**.

The design is inspired by and builds upon the SCReAM multicam examples, but is **cleanly separated**, **ROS‑native**, and optimized for **real‑time point cloud transmission**.

---

## High‑Level Architecture

```
LiDAR Sensor
   ↓  (ROS 2 PointCloud2)
pointcloud_sender.py + Draco compression
   ↓  (RTP packets)
SCReAM sender
   ↓  (UDP / L4S)
======================= NETWORK =======================
   ↓  (UDP / L4S)
SCReAM receiver
   ↓  (RTP packets)
pointcloud_receiver.py + Draco decompression
   ↓  (ROS 2 PointCloud2)
```

---

## Repository Layout

```
./
├── docker/
│   ├── build_scripts/
│   │   ├── create_image_stable.sh             # Builder for the stable image
│   │   ├── create_image_minimal.sh            # Builder for the minimal image
│   │   └── create_image_pointcloud.sh         # Builder for the pointcloud image
│   │
│   ├── dockerfiles/
│   │   ├── Dockerfile.stable                  # Full SCReAM + GStreamer runtime
│   │   ├── Dockerfile.minimal                 # Minimal SCReAM runtime (base image)
│   │   └── Dockerfile.pointcloud              # PointCloud image on top of minimal
│   │
│   ├── entrypoints/
│   │   ├── entrypoint_stable.sh               # Entrypoint for the stable image
│   │   ├── entrypoint_minimal.sh              # Entrypoint for the minimal image
│   │   └── entrypoint_pointcloud.sh           # Entrypoint for the pointcloud image
│   │
│   ├── run_scripts/
│   │   └── run_container_pointcloud.sh         # Unified container launcher
│   │
│   └── README.md
│
├── src/
│   ├── sender_scripts/
│   │   ├── sender.sh                                      # tmux‑based sender launcher
│   │   ├── scream_sender.sh                               # Native SCReAM sender wrapper
│   │   ├── pointcloud_sender.py                           # ROS 2 → Draco → RTP
│   │   ├── pointcloud_sender.sh                           # Runs pointcloud_sender.py
│   │   ├── compressors/
│   │   │   └── draco_compressor.py                        # Pointcloud compression with Draco
│   │   └── helpers/
│   │       ├── compression2bitrate_model.pkl              # Regression model: maps compression params to bitrate
│   │       └── target_bitrate.py                          # Target bitrate bridge from SCReAM
│   │
│   └── receiver_scripts/
│       ├── receiver.sh                                    # tmux‑based receiver launcher
│       ├── scream_receiver.sh                             # Native SCReAM receiver wrapper
│       ├── pointcloud_receiver.py                         # RTP → Draco → ROS 2
│       ├── pointcloud_receiver.sh                         # Runs pointcloud_receiver.py
│       └── decompressors/
│           └── draco_decompressor.py                      # Pointcloud decompression with Draco
│
└── README.md
```

---

## Docker Images

| Image             | Purpose                                                     | Base                   |
|-------------------|-------------------------------------------------------------|------------------------|
| `minimal`         | SCReAM sender/receiver binaries + GStreamer plugins         | `ros:rolling-ros-base` |
| `pointcloud`      | ROS 2 PointCloud streaming with Draco compression           | `minimal`              |
| `stable`          | Full SCReAM build with all GStreamer plugins (legacy/debug) | `ros:rolling-ros-base` |

> **Note:** To run `pointcloud`, only the `minimal` base image needs to be built first.

### Build (from `./docker/`)

```bash
./build_scripts/create_image_minimal.sh
./build_scripts/create_image_pointcloud.sh
```

### Pull (pre-built)

```bash
docker pull ghcr.io/achilleas2942/l4s-ros:minimal
docker pull ghcr.io/achilleas2942/l4s-ros:pointcloud
```

---

## Quick Start (Docker)

### Docker - read more [docker/README.md](./docker/README.md)

From the `./docker/` directory:

```bash
# Terminal 1 — Receiver
ROLE=receiver ./run_scripts/run_container_pointcloud.sh

# Terminal 2 — Sender
ROLE=sender ./run_scripts/run_container_pointcloud.sh
```

For different machines, use host networking:

```bash
# On the receiver machine
ROLE=receiver USE_HOST_NETWORK=1 SENDER_HOST=<SENDER_IP> ./run_scripts/run_container_pointcloud.sh

# On the sender machine
ROLE=sender USE_HOST_NETWORK=1 RECEIVER_HOST=<RECEIVER_IP> ./run_scripts/run_container_pointcloud.sh
```

---

## How It Works

### Sender Pipeline

1. `sender.sh` starts a tmux session with multiple panes
2. `scream_sender.sh` launches the native SCReAM sender binary for congestion control
3. `target_bitrate.py` reads the SCReAM target bitrate via UDP and publishes it as a ROS 2 topic (`/desired_bps`)
4. `pointcloud_sender.py` subscribes to a `PointCloud2` topic, compresses frames with Draco, and sends them as RTP packets

The sender uses **adaptive quality selection**: a regression model predicts the output bitrate for each combination of quantization bits and compression level. The sender picks the highest quality that fits within both the SCReAM bitrate target.

### Receiver Pipeline

1. `receiver.sh` starts a tmux session with multiple panes
2. `scream_receiver.sh` launches the native SCReAM receiver binary
3. `pointcloud_receiver.py` receives RTP packets, reassembles frames, decompresses Draco payloads, and publishes `PointCloud2`

---

## Compression

### Draco (default)

- Sender: `compressors/draco_compressor.py`
- Receiver: `decompressors/draco_decompressor.py`

The architecture is **pluggable** — additional compressors can be added by implementing the same interface and selecting them via the `COMP_MODULE` / `COMP_CLASS` environment variables.

---

## Customization

To use your own sender/receiver logic:

1. Add your code to `./src/sender_scripts/` and `./src/receiver_scripts/`
2. Edit `sender.sh` and `receiver.sh` to launch your scripts

Scripts are volume-mounted (Docker), so no image rebuild is needed for logic changes.

---

## Common Issues & Debugging

| Issue                                  | Likely cause                                            | Fix                                                               |
|----------------------------------------|---------------------------------------------------------|-------------------------------------------------------------------|
| SCReAM receiver segfaults              | Missing runtime libraries or `GST_PLUGIN_PATH` mismatch | `ldd /opt/scream/bin/scream_receiver` and check `GST_PLUGIN_PATH` |
| No packets received                    | Wrong IP/hostname                                       | Verify `RECEIVER_HOST` / `SENDER_HOST`                            |
| Empty point clouds                     | NaN/Inf values in input                                 | Sender filters these automatically; check source data             |
| Frames dropped on sender               | Encoding + transmission exceeds frame period            | Reduce `QUANT_BITS` or increase `RATE_MAX`                        |

---

## License & Credits

- SCReAM: Ericsson Research
- GStreamer
- ROS 2
- Draco: Google

> This repository adapts and extends SCReAM multicam examples for **ROS 2 LiDAR streaming**.

---

## Cite Real-time Point Cloud Data Transmission via L4S for 5G-Edge-Assisted Robotics:

```
[1] Damigos, G., Seisa, A.S., Stathoulopoulos, N., Sandberg, S. and Nikolakopoulos, G.,
2025. Real-time Point Cloud Data Transmission via L4S for 5G-Edge-Assisted Robotics.
arXiv preprint arXiv:2511.15677.
```
