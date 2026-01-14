#!/usr/bin/env python3
import argparse
import socket
import struct
import threading
from collections import defaultdict

import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import PointCloud2, PointField
from sensor_msgs_py import point_cloud2

from draco_decompressor import DracoDecompressor

RTP_HEADER_SIZE = 12

class PointCloudRtpReceiver(Node):
    def __init__(self, args):
        super().__init__('pointcloud_rtp_receiver')

        self.port = args.port
        self.frame_id = args.frame_id
        self.decompressor = DracoDecompressor()

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(('0.0.0.0', self.port))
        self.sock.setblocking(True)

        self.publisher = self.create_publisher(
            PointCloud2,
            args.output_topic,
            10
        )

        self.buffers = defaultdict(dict)
        self.current_timestamp = None
        self.lock = threading.Lock()

        self.get_logger().info(
            f"Listening for RTP on UDP port {self.port}"
        )

        self.thread = threading.Thread(target=self._recv_loop, daemon=True)
        self.thread.start()

    def _recv_loop(self):
        while rclpy.ok():
            data, _ = self.sock.recvfrom(65536)
            self._handle_rtp_packet(data)

    def _handle_rtp_packet(self, packet: bytes):
        if len(packet) < RTP_HEADER_SIZE:
            return

        header = struct.unpack('!BBHII', packet[:12])
        seq = header[2]
        timestamp = header[3]
        payload = packet[12:]

        with self.lock:
            if self.current_timestamp is None:
                self.current_timestamp = timestamp

            if timestamp != self.current_timestamp:
                self._process_frame(self.current_timestamp)
                self.buffers.clear()
                self.current_timestamp = timestamp

            self.buffers[timestamp][seq] = payload

    def _process_frame(self, timestamp):
        packets = self.buffers.get(timestamp, {})
        if not packets:
            return

        ordered = b''.join(
            packets[k] for k in sorted(packets.keys())
        )

        try:
            points = self.decompressor.decompress(ordered)
        except Exception as e:
            self.get_logger().error(f"Decompression failed: {e}")
            return

        msg = self._points_to_pointcloud2(points)
        self.publisher.publish(msg)

        self.get_logger().info(
            f"Published point cloud: {points.shape[0]} points"
        )

    def _points_to_pointcloud2(self, points: np.ndarray) -> PointCloud2:
        header = rclpy.time.Time().to_msg()
        header.frame_id = self.frame_id

        return point_cloud2.create_cloud_xyz32(
            header,
            points.tolist()
        )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=30000)
    parser.add_argument('--output-topic', default='/pointcloud_rx')
    parser.add_argument('--frame-id', default='map')
    args = parser.parse_args()

    rclpy.init()
    node = PointCloudRtpReceiver(args)
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    main()
