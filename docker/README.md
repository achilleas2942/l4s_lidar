# L4S LiDAR – Docker Deployment

This setup streams ROS 2 `PointCloud2` topics over the network:

Everything runs inside Docker containers using **`run_container_pointcloud.sh`**.

---

## Directory Layout

```
./
├── build_scripts/
│   ├── create_image_stable.sh             # Builder for the stable image
│   ├── create_image_minimal.sh            # Builder for the minimal image
│   └── create_image_pointcloud.sh    # Builder for the pointcloud image
│
├── dockerfiles/
│   ├── Dockerfile.stable                  # Full SCReAM + GStreamer runtime
│   ├── Dockerfile.minimal                 # Minimal SCReAM runtime (base image)
│   └── Dockerfile.pointcloud         # PointCloud image on top of minimal
│
├── entrypoints/
│   ├── entrypoint_stable.sh               # Entrypoint for the stable image
│   ├── entrypoint_minimal.sh              # Entrypoint for the minimal image
│   └── entrypoint_pointcloud.sh      # Entrypoint for the pointcloud image
│
├── run_scripts/
│   └── run_container_pointcloud.sh   # Unified container launcher
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

> **Note:** To run `pointcloud` or `pointcloud_demo`, only the `minimal` base image needs to be built first.

The same image runs both roles:
- **Sender** — captures ROS 2 pointcloud, compresses, streams via SCReAM/RTP
- **Receiver** — receives SCReAM/RTP, decompresses, republishes as ROS 2 topic

---

## Build Images

From the `./docker/` directory:

```bash
./build_scripts/create_image_minimal.sh
./build_scripts/create_image_pointcloud.sh
```

## Pull Images (pre-built)

```bash
docker pull ghcr.io/achilleas2942/l4s-ros:minimal
docker pull ghcr.io/achilleas2942/l4s-ros:pointcloud
```

---

## Quick Start

### Same Machine (Docker network)

From the `./docker/` directory:

```bash
# Terminal 1 — Receiver
ROLE=receiver ./run_scripts/run_container_pointcloud.sh

# Terminal 2 — Sender
ROLE=sender ./run_scripts/run_container_pointcloud.sh
```

Docker creates an internal network (`scream_net`) and containers communicate via hostname.

### Different Machines (host networking)

```bash
# On the RECEIVER machine
ROLE=receiver USE_HOST_NETWORK=1 SENDER_HOST=<SENDER_IP> ./run_scripts/run_container_pointcloud.sh

# On the SENDER machine
ROLE=sender USE_HOST_NETWORK=1 RECEIVER_HOST=<RECEIVER_IP> ./run_scripts/run_container_pointcloud.sh
```

> Replace `<SENDER_IP>` and `<RECEIVER_IP>` with the actual machine IPs.

---

## Environment Variables

The run scripts inject environment variables into the containers. Override any of these at launch time or rely on the defaults.

### Role

| Variable | Values                | Description                       |
|----------|-----------------------|-----------------------------------|
| `ROLE`   | `sender` / `receiver` | Which side of the pipeline to run |

### Networking

| Variable             | Default     | Description                              |
|----------------------|-------------|------------------------------------------|
| `USE_DOCKER_NETWORK` | `1`         | Use Docker bridge network (same machine) |
| `USE_HOST_NETWORK`   | `0`         | Use host networking (different machines) |
| `SENDER_HOST`        | `127.0.0.1` | IP of the sender machine                 |
| `RECEIVER_HOST`      | `127.0.0.1` | IP of the receiver machine               |

### SCReAM Sender Parameters

| Variable          | Default | Description                    |
|-------------------|---------|--------------------------------|
| `DELAY_TARGET`    | `0.06`  | Target queuing delay (seconds) |
| `RATE_MIN`        | `2000`  | Minimum bitrate (kbps)         |
| `RATE_INIT`       | `5000`  | Initial bitrate (kbps)         |
| `RATE_MAX`        | `25000` | Maximum bitrate (kbps)         |
| `RATE_SCALE`      | `1`     | Scale factor                   |
| `MAX_TOTAL_RATE`  | `60000` | Total allowed rate (kbps)      |
| `PACING_HEADROOM` | `1.5`   | SCReAM pacing margin           |
| `SENDPIPELINE`    | `1`     | SCReAM send pipeline index     |
| `RECEIVER_PORT`   | `51000` | Receiver SCReAM RTP port       |

### SCReAM Receiver Parameters

| Variable          | Default | Description              |
|-------------------|---------|--------------------------|
| `SENDER_PORT`     | `51000` | Sender SCReAM RTP port   |
| `LOCAL_RTCP_PORT` | `51000` | Receiver local RTCP port |

### PointCloud Sender Parameters

| Variable       | Default                                 | Description                     |
|----------------|-----------------------------------------|---------------------------------|
| `TOPIC`        | `/husky/ouster/points`                  | ROS 2 topic to subscribe to     |
| `FRAME_RATE`   | `10`                                    | Expected sensor frame rate (Hz) |
| `MAX_PAYLOAD`  | `1200`                                  | Max RTP payload size (bytes)    |
| `COMP_MODULE`  | `compressors.draco_compressor`          | Compressor Python module        |
| `COMP_CLASS`   | `DracoCompression`                      | Compressor class name           |
| `QUANT_BITS`   | `12`                                    | Quantization bits               |
| `COMP_LEVEL`   | `3`                                     | Compression level               |
| `RTP_CLOCK`    | `90000`                                 | RTP clock rate                  |
| `DST_IP`       | `127.0.0.1`                             | Destination local IP            |
| `DST_PORT`     | `30000`                                 | Destination local port          |
| `WORKERS`      | `1`                                     | Compression worker threads      |
| `QUEUE_SIZE`   | `4`                                     | Send queue size                 |
| `MODEL_PATH`   | `helpers/compression2bitrate_model.pkl` | Bitrate prediction model path   |
| `MODEL_LOADER` | `joblib`                                | Model loader library            |

### PointCloud Receiver Parameters

| Variable       | Default           | Description                     |
|----------------|-------------------|---------------------------------|
| `PORT`         | `30112`           | Receiver listening port         |
| `OUTPUT_TOPIC` | `/pointcloud_rx`  | ROS 2 output topic              |
| `FRAME_ID`     | `husky/os_sensor` | Frame ID for published messages |

### Examples

```bash
# Override SCReAM parameters
RATE_MAX=40000 DELAY_TARGET=0.04 ROLE=sender ./run_scripts/run_container_pointcloud.sh

# Override pointcloud parameters
ROLE=sender TOPIC=/lidar_points FRAME_RATE=15 ./run_scripts/run_container_pointcloud.sh

# Override receiver parameters
ROLE=receiver OUTPUT_TOPIC=/cloud_rx FRAME_ID=lidar ./run_scripts/run_container_pointcloud.sh
```

---

## Ports

The script automatically exposes all SCReAM RTP/RTCP ports required for media, control, and codec signaling. No manual port mapping is needed.

---

## Run Your Own Code

1. Add your code to `./src/sender_scripts/` and `./src/receiver_scripts/`
2. Edit `sender.sh` and `receiver.sh` to launch your scripts
3. No image rebuild needed — scripts are volume-mounted into the container

---

## What the Script Handles Automatically

- Docker network creation and cleanup
- Container cleanup (`--rm`)
- SCReAM host/IP routing
- Port exposure
- Environment variable forwarding
- Script volume mounting

---

## Troubleshooting

| Issue               | Likely cause                         | Fix                                        |
|---------------------|--------------------------------------|--------------------------------------------|
| No packets received | Wrong IP                             | Check `RECEIVER_HOST` / `SENDER_HOST`      |
| Segfault in SCReAM  | Port conflict                        | Ensure no other process uses the ports     |
| Empty point clouds  | NaN values in input                  | Sender filters NaNs before Draco           |
| Frames dropped      | Encoding + send exceeds frame period | Reduce `QUANT_BITS` or increase `RATE_MAX` |

---

## Stop Containers

Press `Ctrl+C`. Containers run with `--rm` and are automatically removed.
