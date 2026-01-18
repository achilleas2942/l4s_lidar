#!/usr/bin/env python3
import numpy as np
import time
from DracoPy import decode


class DracoDecompressor:
    def __init__(self):
        pass

    def decompress(self, compressed_bytes: bytes) -> tuple[np.ndarray, float]:
        """
        Decompress Draco-compressed point cloud.

        Args:
            compressed_bytes (bytes): Draco-compressed payload

        Returns:
            points (np.ndarray): Nx3 float32 array
            elapsed_ms (float): decompression time in milliseconds
        """
        if not compressed_bytes:
            return np.empty((0, 3), dtype=np.float32), 0.0

        t0 = time.perf_counter()

        try:
            decoded = decode(compressed_bytes)
            if decoded is None or decoded.points is None:
                return np.empty((0, 3), dtype=np.float32), 0.0

            points = np.asarray(decoded.points, dtype=np.float32)

            # Sanity check
            if points.ndim != 2 or points.shape[1] != 3:
                return np.empty((0, 3), dtype=np.float32), 0.0

        except Exception as e:
            # Let caller decide whether to log
            return np.empty((0, 3), dtype=np.float32), 0.0

        elapsed_ms = (time.perf_counter() - t0) * 1e3
        return points, elapsed_ms
