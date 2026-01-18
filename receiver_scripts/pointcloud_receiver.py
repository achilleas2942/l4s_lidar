#!/usr/bin/env python3
import argparse
import socket
import struct
import threading

import numpy as np
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import PointCloud2, PointField
from std_msgs.msg import Header

from decompressors.draco_decompressor import DracoDecompressor

RTP_HEADER_SIZE = 12


def create_pointcloud2(points: np.ndarray, frame_id: str, stamp) -> PointCloud2:
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

        # UDP socket
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(('0.0.0.0', args.port))
        self.sock.setblocking(False)

        self.publisher = self.create_publisher(
            PointCloud2,
            args.output_topic,
            10
        )

        # RTP reassembly state
        self.last_timestamp = None
        self.last_seq = None
        self.frame_corrupt = False
        self.current_payload = bytearray()

        self.get_logger().info(f"Listening for RTP on UDP port {args.port}")

        self.create_timer(0.001, self._poll_socket)

    @staticmethod
    def _seq_inc(prev, cur) -> bool:
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

            # New timestamp mid-frame → flush
            if (self.last_timestamp is not None and
                timestamp != self.last_timestamp and
                not marker and
                self.current_payload):
                self.get_logger().warn(
                    "Timestamp changed mid-frame; flushing incomplete frame"
                )
                self._reset_reassembly()

            # Sequence continuity check
            if self.last_timestamp == timestamp and self.last_seq is not None:
                if not self._seq_inc(self.last_seq, seq):
                    self.frame_corrupt = True

            self.current_payload.extend(payload)
            self.last_timestamp = timestamp
            self.last_seq = seq

            if marker:
                self._decode_and_publish()
                self._reset_reassembly()

    def _reset_reassembly(self):
        self.current_payload.clear()
        self.last_timestamp = None
        self.last_seq = None
        self.frame_corrupt = False

    def _decode_and_publish(self):
        if not self.current_payload:
            return

        if self.frame_corrupt:
            self.get_logger().warn("Dropping corrupted frame")
            return

        points, dec_ms = self.decompressor.decompress(bytes(self.current_payload))
        if points.size == 0:
            return

        msg = create_pointcloud2(
            points,
            self.frame_id,
            self.get_clock().now().to_msg()
        )
        self.publisher.publish(msg)

        self.get_logger().info(
            f"Published {points.shape[0]} points (dec {dec_ms:.1f} ms)"
        )


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
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
