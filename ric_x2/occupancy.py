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
        region = self.regions[rid]
        existing_size = region.resident_sizes.get(event.object_id)
        if existing_size is not None:
            region.used_bytes -= existing_size
        else:
            region.resident_objects.add(event.object_id)

        region.resident_sizes[event.object_id] = event.size_bytes
        region.used_bytes += event.size_bytes

    def get_object_size(self, object_id: str, rid: int) -> int:
        return self.regions[rid].resident_sizes[object_id]

    def remove(self, object_id: str, rid: int) -> int:
        region = self.regions[rid]
        if object_id not in region.resident_objects:
            return 0

        size = region.resident_sizes.pop(object_id)
        region.resident_objects.remove(object_id)
        region.used_bytes -= size
        return size

    def get_resident_objects_by_coldness(self, rid: int) -> List[str]:
        region = self.regions[rid]
        return sorted(
            region.resident_objects,
            key=lambda object_id: (
                region.resident_sizes[object_id],
                object_id,
            ),
        )

    def get_coldest_region(self) -> int:
        return int(np.argmin([r.used_bytes for r in self.regions]))

    def get_skew(self) -> float:
        occs = [r.occupancy_fraction for r in self.regions]
        return float(np.std(occs))
