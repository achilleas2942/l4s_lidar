#!/usr/bin/env python3
import argparse
import importlib
import socket
import struct
import random
import queue
import threading
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import PointCloud2


# ---------------- RTP Sender Thread ----------------
class RtpSender(threading.Thread):
    def __init__(self, dst_addr, payload_queue, max_payload=1200, rtp_clock=90000, frame_rate=10.0):
        super().__init__(daemon=True)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.dst_addr = dst_addr
        self.payload_queue = payload_queue
        self.sequence = 0
        self.timestamp = 0
        self.ssrc = random.getrandbits(32)
        self.max_payload = max_payload
        self.frame_rate = frame_rate
        self.rtp_clock = rtp_clock
        self.timestamp_step = int(rtp_clock / frame_rate)

    def run(self):
        while True:
            payload = self.payload_queue.get()
            if payload is None:
                break
            if len(payload) == 0:
                continue
            self._send(payload)

    def _send(self, payload: bytes):
        offset = 0
        while offset < len(payload):
            chunk = payload[offset:offset + self.max_payload]
            header = struct.pack(
                "!BBHII",
                0x80, 96,
                self.sequence & 0xFFFF,
                self.timestamp & 0xFFFFFFFF,
                self.ssrc
            )
            t0 = time.perf_counter()
            self.sock.sendto(header + chunk, self.dst_addr)
            self.sequence += 1
            offset += len(chunk)
            # pacing: simple sleep to match target frame rate
            send_budget = self.timestamp_step / self.rtp_clock
            elapsed = time.perf_counter() - t0
            if send_budget > elapsed:
                time.sleep(send_budget - elapsed)
        self.timestamp = (self.timestamp + self.timestamp_step) & 0xFFFFFFFF


# ---------------- ROS2 Sender Node ----------------
class PointCloudSender(Node):
    def __init__(self, args):
        super().__init__("pointcloud_sender")

        # ---------------- Load compressor dynamically ----------------
        module = importlib.import_module(args.compressor_module)
        compressor_cls = getattr(module, args.compressor_class)

        self.compress_pool = ThreadPoolExecutor(max_workers=args.workers)
        self.compressor = compressor_cls(args.quant_bits, args.comp_level)

        self.compress_queue = queue.Queue(maxsize=args.queue_size)
        self.send_queue = queue.Queue(maxsize=args.queue_size)

        self.rtp_sender = RtpSender(
            (args.dst_ip, args.dst_port),
            self.send_queue,
            max_payload=args.max_payload,
            rtp_clock=args.rtp_clock,
            frame_rate=args.frame_rate
        )
        self.rtp_sender.start()

        # ---------------- ROS subscription ----------------
        self.create_subscription(
            PointCloud2,
            args.topic,
            self._on_pointcloud,
            qos_profile=10
        )

        self.log_counter = 0
        self.log_interval = args.log_interval

        self.get_logger().info(
            f"Streaming {args.topic} → {args.dst_ip}:{args.dst_port} "
            f"with {args.workers} worker(s), compression ({args.quant_bits} bits, level {args.comp_level})"
        )

    def _on_pointcloud(self, msg: PointCloud2):
        if self.compress_pool is None:
            return

        try:
            points = self._pc2_to_xyz(msg)
            if points.size == 0:
                return

            future = self.compress_pool.submit(self.compressor.compress, points)
            future.add_done_callback(self._on_compressed)

        except RuntimeError as e:
            self.get_logger().warning(f"Executor error: {e}")

    def _on_compressed(self, future):
        try:
            payload, enc_ms = future.result()
            self.send_queue.put_nowait(payload)
            self.get_logger().info(
                f"Sent {len(payload)} bytes (enc {enc_ms:.1f} ms)"
            )
        except queue.Full:
            self.get_logger().warning("Send queue full, dropping frame")
        except Exception as e:
            self.get_logger().error(f"Compression failed: {e}")

    @staticmethod
    def _pc2_to_xyz(msg: PointCloud2) -> np.ndarray:
        step = msg.point_step
        data = msg.data
        n = len(data) // step
        if n == 0:
            return np.empty((0, 3), dtype=np.float32)

        offsets = {f.name: f.offset for f in msg.fields}
        pts = np.empty((n, 3), dtype=np.float32)
        for i in range(n):
            base = i * step
            pts[i, 0] = struct.unpack_from("f", data, base + offsets["x"])[0]
            pts[i, 1] = struct.unpack_from("f", data, base + offsets["y"])[0]
            pts[i, 2] = struct.unpack_from("f", data, base + offsets["z"])[0]
        return pts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", default="/lidar_points")
    parser.add_argument("--dst_ip", default="127.0.0.1")
    parser.add_argument("--dst_port", type=int, default=30000)
    parser.add_argument("--compressor_module", default="compressors.draco_compressor")
    parser.add_argument("--compressor_class", default="DracoCompression")
    parser.add_argument("--quant_bits", type=int, default=12)
    parser.add_argument("--comp_level", type=int, default=3)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--queue_size", type=int, default=4)
    parser.add_argument("--max_payload", type=int, default=1200)
    parser.add_argument("--rtp_clock", type=int, default=90000)
    parser.add_argument("--frame_rate", type=float, default=10.0)
    parser.add_argument("--log_interval", type=int, default=10)
    args = parser.parse_args()

    rclpy.init()
    node = PointCloudSender(args)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info("Shutting down PointCloudSender…")
    finally:
        node.compress_pool.shutdown(wait=True)
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
