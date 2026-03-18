from typing import Dict, List
from .types import TensorMetadata

class CollisionTracker:
    """Tracks mapping conflicts where multiple tensors target the same region."""
    def __init__(self, num_regions: int):
        self.num_regions = num_regions
        self.collision_counts = [0] * num_regions
        self.total_collisions = 0

    def record_attempt(self, rid: int, tensor_id: str, resident_tensors: set):
        """Logic: If region has other tensors and we are adding a new one, it's a potential collision."""
        if len(resident_tensors) > 0 and tensor_id not in resident_tensors:
            self.collision_counts[rid] += 1
            self.total_collisions += 1

    def get_report(self) -> Dict:
        return {
            "total_collisions": self.total_collisions,
            "max_collisions_per_region": max(self.collision_counts) if self.collision_counts else 0
        }
