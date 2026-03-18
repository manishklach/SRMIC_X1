import numpy as np
from typing import List, Dict
from .types import RegionState, TensorMetadata

class OccupancyTracker:
    """Tracks physical bytes and residency state across HRM regions."""
    def __init__(self, num_regions: int, cap_bytes: int):
        self.regions = [RegionState(i, cap_bytes) for i in range(num_regions)]
        self.tensor_to_region: Dict[str, int] = {}

    def is_resident(self, tid: str, rid: int) -> bool:
        return tid in self.regions[rid].resident_tensors

    def add(self, tensor: TensorMetadata, rid: int):
        """Adds tensor to region and updates accounting."""
        self.regions[rid].resident_tensors.add(tensor.tensor_id)
        self.regions[rid].used_bytes += tensor.size_bytes
        self.tensor_to_region[tensor.tensor_id] = rid

    def remove(self, tid: str, rid: int, size: int):
        """Removes tensor from region."""
        if tid in self.regions[rid].resident_tensors:
            self.regions[rid].resident_tensors.remove(tid)
            self.regions[rid].used_bytes -= size
            if tid in self.tensor_to_region:
                del self.tensor_to_region[tid]

    def get_skew(self) -> float:
        """Computes occupancy standard deviation across all regions."""
        occs = [r.occupancy_fraction for r in self.regions]
        return float(np.std(occs))

    def get_coldest_region(self) -> int:
        """Finds region with most free space."""
        return int(np.argmin([r.used_bytes for r in self.regions]))
