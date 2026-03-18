from typing import Set, Optional
from .types import ObjectMetadata, RegionState

class ReplicationEngine:
    """Manages the creation and placement of object replicas."""
    def __init__(self, config):
        self.cfg = config
        self.total_replica_count = 0
        self.total_replica_hits = 0

    def should_replicate(self, obj: ObjectMetadata, region: RegionState) -> bool:
        """
        Policy: Replicate if object is ultra-hot and primary region is pressured.
        """
        if not self.cfg.REPLICATION_ENABLED:
            return False
            
        if self.total_replica_count >= self.cfg.MAX_TOTAL_REPLICAS:
            return False

        if len(obj.replica_rids) >= self.cfg.MAX_REPLICAS_PER_OBJECT:
            return False

        # Hotness signal: access frequency
        if obj.access_count < self.cfg.HOT_OBJECT_ACCESS_THRESHOLD:
            return False

        # Pressure signal: regional load
        if region.occupancy_fraction < self.cfg.REPLICATION_PRESSURE_THRESHOLD:
            return False

        return True

    def bind_replica(self, obj: ObjectMetadata, target_rid: int) -> bool:
        """Assigns a new replica location to the object."""
        if target_rid not in obj.replica_rids:
            obj.replica_rids.add(target_rid)
            self.total_replica_count += 1
            return True
        return False
