#!/usr/bin/env python3
"""
Draco compression module for pointcloud_sender.py

Usage:
    from compressors.draco_compressor import DracoCompression
    compressor = DracoCompression(quant_bits=12, comp_level=3)
    compressed_bytes, enc_ms = compressor.compress(points)
"""

import time
import numpy as np
from DracoPy import encode


class DracoCompression:
    def __init__(self, quant_bits=12, comp_level=3):
        """
        Parameters
        ----------
        quant_bits : int
            Number of quantization bits (higher = more precise)
        comp_level : int
            Compression level (higher = more aggressive compression)
        """
        self.quant_bits = quant_bits
        self.comp_level = comp_level

    def compress(self, points: np.ndarray) -> tuple[bytes, float]:
        """
        Compress Nx3 float32 point cloud array using Draco.

        Returns
        -------
        tuple[bytes, float]
            (compressed_bytes, elapsed_ms)
        """
        if points.size == 0:
            return b"", 0.0

        # Compute quantization range and origin
        mins = points.min(axis=0)
        maxs = points.max(axis=0)
        q_range = float((maxs - mins).max())
        q_origin = mins.tolist()

        t0 = time.perf_counter()
        compressed = encode(
            points=points,
            faces=None,
            quantization_bits=self.quant_bits,
            compression_level=self.comp_level,
            quantization_range=q_range,
            quantization_origin=q_origin,
            preserve_order=True,
            create_metadata=False
        )
        elapsed_ms = (time.perf_counter() - t0) * 1e3
        return compressed, elapsed_ms
