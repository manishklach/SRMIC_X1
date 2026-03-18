import numpy as np
from typing import List
from .types import RegionState, TraceEvent

class OccupancyTracker:
    """Tracks byte-accurate usage across regions."""
    def __init__(self, num_regions: int, cap_bytes: int):
        self.regions = [RegionState(i, cap_bytes) for i in range(num_regions)]

    def is_resident(self, object_id: str, rid: int) -> bool:
        return object_id in self.regions[rid].resident_objects

    def add(self, event: TraceEvent, rid: int):
        self.regions[rid].resident_objects.add(event.object_id)
        self.regions[rid].used_bytes += event.size_bytes

    def remove(self, object_id: str, rid: int, size: int):
        if object_id in self.regions[rid].resident_objects:
            self.regions[rid].resident_objects.remove(object_id)
            self.regions[rid].used_bytes -= size

    def get_coldest_region(self) -> int:
        return int(np.argmin([r.used_bytes for r in self.regions]))

    def get_skew(self) -> float:
        occs = [r.occupancy_fraction for r in self.regions]
        return float(np.std(occs))
