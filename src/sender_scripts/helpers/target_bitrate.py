#!/usr/bin/env python3
import socket
import struct
import rclpy
from rclpy.node import Node
from std_msgs.msg import Float32

PORT = 30001  # port where SCReAM publishes logs
BUF_SIZE = 1024

class TargetBitrateNode(Node):
    def __init__(self):
        super().__init__('target_bitrate')
        self.publisher_ = self.create_publisher(Float32, '/desired_bps', 10)

        # UDP socket
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(('0.0.0.0', PORT))
        self.sock.setblocking(False)

        self.get_logger().info(f"Listening for bitrate on UDP port {PORT}")

        # periodic polling
        self.timer = self.create_timer(0.01, self._poll)

    def _poll(self):
        try:
            data, addr = self.sock.recvfrom(BUF_SIZE)
        except BlockingIOError:
            return

        if len(data) < 4:
            self.get_logger().warn(f"Ignoring invalid packet ({len(data)} bytes)")
            return

        # Big-endian uint32
        (rate_raw,) = struct.unpack('!I', data[:4])
        rate = float(rate_raw)

        msg = Float32()
        msg.data = rate
        self.publisher_.publish(msg)

        self.get_logger().info(f"Rate={rate/1_000_000:.2f} Mbps from {addr}")


def main(args=None):
    rclpy.init(args=args)
    node = TargetBitrateNode()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
