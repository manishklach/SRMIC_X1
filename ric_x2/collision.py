class CollisionTracker:
    """Detects mapping conflicts in HRM regions."""
    def __init__(self, num_regions: int):
        self.collision_counts = [0] * num_regions
        self.total_collisions = 0

    def record_attempt(self, rid: int, object_id: str, resident_set: set):
        # A collision is defined as targeting a region that already contains other data
        if len(resident_set) > 0 and object_id not in resident_set:
            self.collision_counts[rid] += 1
            self.total_collisions += 1

    def get_report(self):
        return {
            "total_collisions": self.total_collisions,
            "max_collisions_per_region": max(self.collision_counts) if self.collision_counts else 0
        }
