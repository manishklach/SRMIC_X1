import hashlib
from typing import Dict, Set
from .types import TraceEvent, AccessResult, ObjectMetadata
from .occupancy import OccupancyTracker
from .collision import CollisionTracker
from .thrash import ThrashMonitor
from .remap import RemapEngine
from .admission import AdmissionController
from .replication import ReplicationEngine

def deterministic_hash(string: str) -> int:
    """Ensures mapping is consistent across simulator runs and processes."""
    return int(hashlib.md5(string.encode()).hexdigest(), 16)

class RICX2:
    """Orchestrator for X2 Collision + Regret + Replication logic."""
    def __init__(self, config, x2_mode: bool = True):
        self.cfg = config
        self.x2_mode = x2_mode
        self.occupancy = OccupancyTracker(config.NUM_REGIONS, config.region_capacity_bytes)
        self.collision = CollisionTracker(config.NUM_REGIONS)
        self.thrash = ThrashMonitor()
        self.remap = RemapEngine(config.MAX_CAM_ENTRIES, config.REMAP_COOLDOWN_STEPS)
        self.admission = AdmissionController(config)
        self.replication = ReplicationEngine(config)
        self.metadata: Dict[str, ObjectMetadata] = {}

    def _get_metadata(self, object_id: str, size: int) -> ObjectMetadata:
        if object_id not in self.metadata:
            self.metadata[object_id] = ObjectMetadata(object_id, size)
        return self.metadata[object_id]

    def _get_region(self, object_id: str) -> int:
        if self.x2_mode:
            override = self.remap.lookup(object_id)
            if override is not None: return override
        return deterministic_hash(object_id) % self.cfg.NUM_REGIONS

    def handle_access(self, event: TraceEvent) -> AccessResult:
        base_rid = self._get_region(event.object_id)
        obj = self._get_metadata(event.object_id, event.size_bytes)
        obj.access_count += 1
        
        # 1. Parallel Residency Check (Base + Replicas)
        if self.occupancy.is_resident(event.object_id, base_rid):
            obj.hit_count += 1
            obj.last_step = event.decode_step
            return AccessResult.HIT

        # Check for replica hits
        for replica_rid in self.replication.get_replica_regions(event.object_id):
            if self.occupancy.is_resident(event.object_id, replica_rid):
                obj.replica_hit_count += 1
                self.replication.total_replica_hits += 1
                obj.last_step = event.decode_step
                return AccessResult.HIT_REPLICA

        # 2. Miss Path - Telemetry
        self.collision.record_attempt(base_rid, event.object_id, self.occupancy.regions[base_rid].resident_objects)
        is_thrash = self.thrash.is_thrashing(event.object_id, event.decode_step, self.cfg.THRASH_WINDOW_STEPS)
        if is_thrash: obj.thrash_count += 1

        # 3. Admission Decision
        if self.occupancy.regions[base_rid].free_bytes < event.size_bytes:
            if self.occupancy.regions[base_rid].resident_objects:
                v_id = next(iter(self.occupancy.regions[base_rid].resident_objects))
                v_obj = self._get_metadata(v_id, event.size_bytes)
                if self.x2_mode and self.cfg.ADMISSION_ENABLED:
                    if not self.admission.should_admit(obj, v_obj, self.occupancy.regions[base_rid], event.decode_step):
                        return AccessResult.MISS_BYPASSED

        # 4. Replication Logic (X2 only)
        if self.x2_mode and self.replication.should_replicate(obj, self.occupancy.regions[base_rid]):
            target_rid = self.occupancy.get_coldest_region()
            if self.replication.create_replica(event.object_id, target_rid):
                self._promote_to_region(event, target_rid)

        # 5. Reactive Remap Trigger (X2 only)
        if self.x2_mode and self.occupancy.regions[base_rid].occupancy_fraction > self.cfg.REMAP_OCC_THRESHOLD:
            target_rid = self.occupancy.get_coldest_region()
            self.remap.bind(event.object_id, target_rid, event.decode_step)

        # 6. Standard Promotion/Eviction
        self._promote_to_region(event, base_rid)
        obj.last_step = event.decode_step
        return AccessResult.MISS_PROMOTED

    def _promote_to_region(self, event: TraceEvent, rid: int):
        while self.occupancy.regions[rid].free_bytes < event.size_bytes:
            if not self.occupancy.regions[rid].resident_objects: break
            v_id = next(iter(self.occupancy.regions[rid].resident_objects))
            v_obj = self._get_metadata(v_id, event.size_bytes)
            self.occupancy.remove(v_id, rid, event.size_bytes)
            self.thrash.record_eviction(v_id, event.decode_step)
            v_obj.last_evict_step = event.decode_step
        self.occupancy.add(event, rid)
