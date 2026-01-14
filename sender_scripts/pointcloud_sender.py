#!/usr/bin/env python3
import argparse
import importlib
import socket
import struct
import random
import queue
import threading
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import PointCloud2


# ---------------- RTP Sender Thread ----------------
class RtpSender(threading.Thread):
    def __init__(self, dst_addr, payload_queue, max_payload=1200):
        super().__init__(daemon=True)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.dst_addr = dst_addr
        self.payload_queue = payload_queue
        self.sequence = 0
        self.timestamp = 0
        self.ssrc = random.getrandbits(32)
        self.max_payload = max_payload

    def run(self):
        while True:
            payload = self.payload_queue.get()
            if payload is None:
                break
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
            self.sock.sendto(header + chunk, self.dst_addr)
            self.sequence += 1
            offset += len(chunk)
        self.timestamp += 3000


# ---------------- ROS2 Sender Node ----------------
class PointCloudSender(Node):
    def __init__(self, args):
        super().__init__("pointcloud_sender")

        # Dynamic compressor loading
        module = importlib.import_module(args.compressor_module)
        compressor_cls = getattr(module, args.compressor_class)

        self.executor = ProcessPoolExecutor(max_workers=args.workers)
        self.compressor = compressor_cls(args.quant_bits, args.comp_level)

        self.compress_queue = queue.Queue(maxsize=2)
        self.send_queue = queue.Queue(maxsize=2)

        self.rtp_sender = RtpSender(
            (args.dst_ip, args.dst_port),
            self.send_queue
        )
        self.rtp_sender.start()

        self.create_subscription(
            PointCloud2,
            args.topic,
            self._on_pointcloud,
            qos_profile=10
        )

        self.get_logger().info(
            f"Streaming {args.topic} → {args.dst_ip}:{args.dst_port}"
        )

    def _on_pointcloud(self, msg: PointCloud2):
        try:
            points = self._pc2_to_xyz(msg)
            if points.size == 0:
                return

            future = self.executor.submit(self.compressor.compress, points)
            future.add_done_callback(self._on_compressed)

        except queue.Full:
            self.get_logger().warn("Compression queue full, dropping frame")

    def _on_compressed(self, future):
        try:
            payload, enc_ms = future.result()
            self.send_queue.put_nowait(payload)
            self.get_logger().info(
                f"Sent {len(payload)} bytes (enc {enc_ms:.1f} ms)"
            )
        except queue.Full:
            self.get_logger().warn("Send queue full, dropping frame")

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
    parser.add_argument("--compressor_module", default="draco_compressor")
    parser.add_argument("--compressor_class", default="DracoCompression")
    parser.add_argument("--quant_bits", type=int, default=12)
    parser.add_argument("--comp_level", type=int, default=3)
    parser.add_argument("--workers", type=int, default=1)
    args = parser.parse_args()

    rclpy.init()
    node = PointCloudSender(args)
    rclpy.spin(node)
    rclpy.shutdown()


if __name__ == "__main__":
    main()
