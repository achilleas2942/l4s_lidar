#!/usr/bin/env python3
import argparse
import importlib
import socket
import struct
import random
import queue
import time
import threading
import sys
import joblib
import os

sys.path.append("/opt/pointcloud/sender_scripts")

from concurrent.futures import ThreadPoolExecutor

import numpy as np
import rclpy
from rclpy.node import Node
from std_msgs.msg import Float32
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
        self.desired_bps = 5_000_000
        self.frame_period = 1.0 / frame_rate
        self.pacing_safety = 0.99

    def run(self):
        while True:
            payload = self.payload_queue.get()
            if payload is None:
                break
            if not payload:
                continue
            self._send(payload)

    def _send(self, payload: bytes):
        bytes_per_sec = max(1.0, self.desired_bps / 8.0)
        max_frame_send_time = self.frame_period * self.pacing_safety
        offset = 0
        frame_start_time = time.perf_counter()

        while offset < len(payload):
            chunk = payload[offset:offset + self.max_payload]
            offset += len(chunk)
            is_last = offset >= len(payload)
            b1 = 0x80
            b2 = 96 | (0x80 if is_last else 0)
            header = struct.pack(
                "!BBHII",
                b1,
                b2,
                self.sequence & 0xFFFF,
                self.timestamp & 0xFFFFFFFF,
                self.ssrc
            )
            t0 = time.perf_counter()
            self.sock.sendto(header + chunk, self.dst_addr)
            self.sequence += 1

            ideal_elapsed = (offset / bytes_per_sec)
            actual_elapsed = time.perf_counter() - frame_start_time

            if actual_elapsed > max_frame_send_time:
                break

            if ideal_elapsed > actual_elapsed:
                time.sleep(ideal_elapsed - actual_elapsed)

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

        self.send_queue = queue.Queue(maxsize=args.queue_size)
        self.rtp_sender = RtpSender(
            (args.dst_ip, args.dst_port),
            self.send_queue,
            max_payload=args.max_payload,
            rtp_clock=args.rtp_clock,
            frame_rate=args.frame_rate
        )
        self.rtp_sender.start()

        # ----------------- Bitrate adaptation model ------------------
        base_dir = os.path.dirname(__file__)
        model_path = os.path.join(base_dir, args.model_path)

        self.poly, self.lr = joblib.load(model_path)

        self._quant_bits_list = np.array([8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24])
        self._comp_levels_list = np.array([0,1,2,3,4,5,6,7,8,9])

        self._grid = np.array([
            [q, c] for q in self._quant_bits_list for c in self._comp_levels_list
        ])

        fake_n = 30000
        grid3 = np.hstack([self._grid, np.full((len(self._grid), 1), fake_n)])
        Xg = self.poly.transform(grid3)
        self._pred_bps = self.lr.predict(Xg)

        # Use predicted bitrate for the actual initial compression params
        init_idx = np.abs(self._grid - [args.quant_bits, args.comp_level]).sum(axis=1).argmin()
        self.desired_bps = float(self._pred_bps[init_idx])
        self.rtp_sender.desired_bps = self.desired_bps

        self._frame_period = 1.0 / args.frame_rate
        self._enc_time_ema = 0.01
        self._ema_alpha = 0.3

        # ---------------- ROS subscriptions ---------------
        self.create_subscription(Float32, "/desired_bps", self._on_bitrate, 10)
        self.create_subscription(PointCloud2, args.topic, self._on_pointcloud, 10)

        self.get_logger().info("Adaptive modular pointcloud sender ready.")

    def _on_bitrate(self, msg: Float32):
        raw = float(msg.data)
        self.desired_bps = float(np.clip(raw, 1e6, 20e6))

        # Max payload bits that can be transmitted in the remaining frame budget
        send_budget_s = max(0.01, self._frame_period * 0.95 - self._enc_time_ema)
        max_payload_bps = (send_budget_s * self.desired_bps) * self.rtp_sender.frame_rate

        effective_cap = min(self.desired_bps, max_payload_bps)

        mask = self._pred_bps <= effective_cap
        if mask.any():
            candidates = np.where(mask)[0]
            idx = candidates[self._pred_bps[candidates].argmax()]
        else:
            idx = self._pred_bps.argmin()

        q, c = self._grid[idx]
        self.compressor.quant_bits = int(q)
        self.compressor.comp_level = int(c)
        self.rtp_sender.desired_bps = self.desired_bps
        self.get_logger().info(
            f"Bitrate target={self.desired_bps:.0f} → q={q}, c={c} "
            f"(enc_ema={self._enc_time_ema*1000:.1f}ms, send_budget={send_budget_s*1000:.1f}ms)"
        )

    def _on_pointcloud(self, msg: PointCloud2):
        try:
            points = self._pc2_to_xyz(msg)
            if points.size == 0:
                return

            mask = np.isfinite(points).all(axis=1)
            points = points[mask]

            if points.shape[0] == 0:
                self.get_logger().warn("All points invalid after NaN filtering, skipping frame")
                return

            self.get_logger().info(
                f"Points stats: min={points.min():.2f}, max={points.max():.2f}, "
                f"count={points.shape[0]}"
            )

            future = self.compress_pool.submit(self.compressor.compress, points)
            future.add_done_callback(self._on_compressed)

        except Exception as e:
            self.get_logger().error(f"PointCloud handling failed: {e}")

    def _on_compressed(self, future):
        try:
            payload, enc_ms = future.result()
            if not payload:
                return

            enc_s = enc_ms / 1000.0
            self._enc_time_ema = (self._ema_alpha * enc_s +
                                (1 - self._ema_alpha) * self._enc_time_ema)

            send_s = (len(payload) * 8) / max(1, self.rtp_sender.desired_bps)
            total_s = enc_s + send_s
            budget = self._frame_period * 0.95

            if total_s > budget:
                self.get_logger().warning(
                    f"Frame overbudget: enc={enc_ms:.1f}ms + send={send_s*1000:.1f}ms "
                    f"= {total_s*1000:.1f}ms > {budget*1000:.1f}ms, dropping"
                )
                return

            self.send_queue.put_nowait(payload)
            self.get_logger().info(
                f"Sent {len(payload)*8*10**-6:.2f} Mbit (enc {enc_ms:.1f} ms)"
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
    parser.add_argument("--model_path", default="helpers/compression2bitrate_model.pkl")
    parser.add_argument("--model_loader", default="joblib")
    args = parser.parse_args()

    rclpy.init()
    node = PointCloudSender(args)

    executor = rclpy.executors.MultiThreadedExecutor()
    executor.add_node(node)

    try:
        executor.spin()
    finally:
        node.compress_pool.shutdown(wait=True)
        executor.shutdown()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
