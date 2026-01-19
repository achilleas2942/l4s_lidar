#!/usr/bin/env python3
import argparse
import socket
import struct
import threading

import numpy as np
import rclpy
from rclpy.node import Node
from std_msgs.msg import Header
from sensor_msgs.msg import PointCloud2, PointField

from decompressors.draco_decompressor import DracoDecompressor

RTP_HEADER_SIZE = 12


def create_pointcloud2(points: np.ndarray, frame_id: str, stamp):
    header = Header()
    header.frame_id = frame_id
    header.stamp = stamp

    fields = [
        PointField(name='x', offset=0, datatype=PointField.FLOAT32, count=1),
        PointField(name='y', offset=4, datatype=PointField.FLOAT32, count=1),
        PointField(name='z', offset=8, datatype=PointField.FLOAT32, count=1),
    ]

    data = points.astype(np.float32).tobytes()

    return PointCloud2(
        header=header,
        height=1,
        width=points.shape[0],
        is_dense=True,
        is_bigendian=False,
        fields=fields,
        point_step=12,
        row_step=12 * points.shape[0],
        data=data,
    )


class PointCloudRtpReceiver(Node):
    def __init__(self, args):
        super().__init__('pointcloud_receiver')

        self.frame_id = args.frame_id
        self.decompressor = DracoDecompressor()

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        self.sock.bind(('0.0.0.0', args.port))
        self.sock.setblocking(False)

        self.publisher = self.create_publisher(PointCloud2, args.output_topic, 10)

        # RTP reassembly state
        self.last_timestamp = None
        self.last_seq = None
        self.frame_corrupt = False
        self.current_payload = bytearray()

        self.create_timer(0.001, self._poll_socket)

        self.get_logger().info(
            f"Listening on UDP {args.port}, publishing to {args.output_topic}"
        )

    @staticmethod
    def _seq_inc(prev, cur):
        return ((prev + 1) & 0xFFFF) == cur

    def _poll_socket(self):
        while True:
            try:
                data, _ = self.sock.recvfrom(65536)
            except BlockingIOError:
                break

            if len(data) < RTP_HEADER_SIZE:
                continue

            b1, b2, seq, timestamp, _ = struct.unpack('!BBHII', data[:12])
            version = b1 >> 6
            if version != 2:
                continue

            marker = (b2 & 0x80) != 0
            payload = data[RTP_HEADER_SIZE:]

            # New frame started unexpectedly → drop old one
            if self.last_timestamp is not None and timestamp != self.last_timestamp:
                self._reset_frame()

            # Sequence gap detection
            if self.last_seq is not None and not self._seq_inc(self.last_seq, seq):
                self.frame_corrupt = True

            self.current_payload.extend(payload)
            self.last_timestamp = timestamp
            self.last_seq = seq

            if marker:
                self._finalize_frame()

    def _finalize_frame(self):
        if not self.current_payload or self.frame_corrupt:
            if self.frame_corrupt:
                self.get_logger().warn("Dropping corrupted frame")
            self._reset_frame()
            return

        try:
            points = self.decompressor.decompress(bytes(self.current_payload))
            msg = create_pointcloud2(
                points,
                frame_id=self.frame_id,
                stamp=self.get_clock().now().to_msg()
            )
            self.publisher.publish(msg)
        except Exception as e:
            self.get_logger().error(f"Draco decode failed: {e}")

        self._reset_frame()

    def _reset_frame(self):
        self.current_payload.clear()
        self.last_timestamp = None
        self.last_seq = None
        self.frame_corrupt = False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=30000)
    parser.add_argument('--output-topic', default='/pointcloud_rx')
    parser.add_argument('--frame-id', default='map')
    args = parser.parse_args()

    rclpy.init()
    node = PointCloudRtpReceiver(args)

    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
