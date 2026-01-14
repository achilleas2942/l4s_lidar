#!/usr/bin/env python3
import numpy as np
import time
from DracoPy import encode

class DracoCompression:
    def __init__(self, quant_bits=12, comp_level=3):
        self.quant_bits = quant_bits
        self.comp_level = comp_level

    def compress(self, points: np.ndarray) -> tuple[bytes, float]:
        """
        Compress Nx3 float32 array using Draco.
        Returns (compressed_bytes, elapsed_ms)
        """
        if points.size == 0:
            return b"", 0.0

        mins = points.min(axis=0)
        maxs = points.max(axis=0)
        q_range = float((maxs - mins).max())
        q_origin = mins.tolist()

        t0 = time.time()
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
        elapsed_ms = (time.time() - t0) * 1e3
        return compressed, elapsed_ms
