#!/usr/bin/env python3
import numpy as np
from DracoPy import decode

class DracoDecompressor:
    def decompress(self, compressed_bytes: bytes) -> np.ndarray:
        """
        Returns Nx3 float32 numpy array
        """
        decoded = decode(compressed_bytes)
        points = np.asarray(decoded.points, dtype=np.float32)
        return points
