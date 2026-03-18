from typing import Dict, List, Set, Optional
from .types import ObjectMetadata, RegionState

class ReplicationEngine:
    """Manages creation and placement of object replicas to mitigate hotspots."""
    def __init__(self, config):
        self.cfg = config
        self.replicas: Dict[str, Set[int]] = {} # object_id -> set(region_ids)
        self.total_replica_count = 0
        self.total_replica_hits = 0

    def is_replica_resident(self, object_id: str, region_id: int) -> bool:
        return region_id in self.replicas.get(object_id, set())

    def get_replica_regions(self, object_id: str) -> Set[int]:
        return self.replicas.get(object_id, set())

    def should_replicate(self, obj: ObjectMetadata, region: RegionState) -> bool:
        """
        Policy: Replicate if object is very hot (high utility) and 
        region is under high pressure.
        """
        if not self.cfg.REPLICATION_ENABLED:
            return False
            
        # Limit total replicas to prevent capacity dilution
        if self.total_replica_count >= self.cfg.MAX_TOTAL_REPLICAS:
            return False

        # Limit replicas per object
        current_replicas = self.replicas.get(obj.object_id, set())
        if len(current_replicas) >= self.cfg.MAX_REPLICAS_PER_OBJECT:
            return False

        # Utility Threshold Gating
        if obj.access_count < self.cfg.HOT_OBJECT_ACCESS_THRESHOLD:
            return False

        # Pressure Gating
        if region.occupancy_fraction < self.cfg.REPLICATION_PRESSURE_THRESHOLD:
            return False

        return True

    def create_replica(self, object_id: str, target_rid: int):
        if object_id not in self.replicas:
            self.replicas[object_id] = set()
        
        if target_rid not in self.replicas[object_id]:
            self.replicas[object_id].add(target_rid)
            self.total_replica_count += 1
            return True
        return False
