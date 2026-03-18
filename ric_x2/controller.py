import hashlib
from typing import Dict, Set, List, Tuple
from .types import TraceEvent, AccessResult, ObjectMetadata
from .occupancy import OccupancyTracker
from .collision import CollisionTracker
from .thrash import ThrashMonitor
from .remap import RemapEngine
from .admission import AdmissionController
from .replication import ReplicationEngine

def deterministic_hash(string: str) -> int:
    return int(hashlib.md5(string.encode()).hexdigest(), 16)

class RICX2:
    """Orchestrator for X2 logic with Evaluation-Hardened Accounting."""
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
        
        # Snapshot of congestion penalties per access
        self.step_congestion_penalties = 0

    def _get_metadata(self, object_id: str, size: int) -> ObjectMetadata:
        if object_id not in self.metadata:
            self.metadata[object_id] = ObjectMetadata(object_id, size)
        return self.metadata[object_id]

    def _get_base_region(self, object_id: str) -> int:
        if self.x2_mode:
            override = self.remap.lookup(object_id)
            if override is not None: return override
        return deterministic_hash(object_id) % self.cfg.NUM_REGIONS

    def handle_access(self, event: TraceEvent) -> AccessResult:
        base_rid = self._get_base_region(event.object_id)
        obj = self._get_metadata(event.object_id, event.size_bytes)
        obj.access_count += 1
        
        # 1. Evaluate All Resident Locations
        resident_rids = []
        if self.occupancy.is_resident(event.object_id, base_rid):
            resident_rids.append(base_rid)
        
        for r_rid in obj.replica_rids:
            if self.occupancy.is_resident(event.object_id, r_rid):
                resident_rids.append(r_rid)
        
        # 2. Replica-Aware Routing Decision
        target_rid = base_rid # Default
        hit_result = None
        
        if resident_rids:
            if self.x2_mode and self.cfg.PRESSURE_AWARE_ROUTING:
                # Select the least loaded region among resident copies
                target_rid = min(resident_rids, key=lambda r: self.occupancy.regions[r].used_bytes)
            else:
                # Prefer primary (X1 behavior)
                target_rid = base_rid if base_rid in resident_rids else resident_rids[0]
            
            # Record hit
            if target_rid == base_rid:
                obj.hit_count += 1
                hit_result = AccessResult.HIT
            else:
                obj.replica_hit_count += 1
                self.replication.total_replica_hits += 1
                hit_result = AccessResult.HIT_REPLICA
            
            obj.last_step = event.decode_step
            obj.replica_selected_count += (1 if target_rid != base_rid else 0)
            
            # Check congestion penalty for the chosen region
            if self.occupancy.regions[target_rid].occupancy_fraction > self.cfg.CONGESTION_PENALTY_THRESHOLD:
                self.step_congestion_penalties += self.cfg.CONGESTION_PENALTY_CYCLES
            
            # X2 Opportunity: If we hit but the region is congested, consider replicating to a colder one
            if self.x2_mode and self.replication.should_replicate(obj, self.occupancy.regions[target_rid]):
                cold_rid = self.occupancy.get_coldest_region()
                if cold_rid not in resident_rids:
                    if self.replication.bind_replica(obj, cold_rid):
                        self._promote_to_region(event, cold_rid)
                
            return hit_result

        # 3. Miss Path
        obj.replica_lookup_count += len(obj.replica_rids)
        self.collision.record_attempt(base_rid, event.object_id, self.occupancy.regions[base_rid].resident_objects)
        is_thrash = self.thrash.is_thrashing(event.object_id, event.decode_step, self.cfg.THRASH_WINDOW_STEPS)
        if is_thrash: obj.thrash_count += 1

        if self.x2_mode and self.cfg.ADMISSION_ENABLED:
            if self.occupancy.regions[base_rid].free_bytes < event.size_bytes:
                if self.occupancy.regions[base_rid].resident_objects:
                    v_id = next(iter(self.occupancy.regions[base_rid].resident_objects))
                    v_obj = self._get_metadata(v_id, event.size_bytes)
                    if not self.admission.should_admit(obj, v_obj, self.occupancy.regions[base_rid], event.decode_step):
                        return AccessResult.MISS_BYPASSED

        # 4. Replication Decision Logic
        if self.x2_mode and self.replication.should_replicate(obj, self.occupancy.regions[base_rid]):
            # Only replicate to regions that don't already have a copy
            potential_rid = self.occupancy.get_coldest_region()
            if potential_rid != base_rid and potential_rid not in obj.replica_rids:
                if self.replication.bind_replica(obj, potential_rid):
                    self._promote_to_region(event, potential_rid)

        # 5. Reactive Remap Trigger
        if self.x2_mode and self.occupancy.regions[base_rid].occupancy_fraction > self.cfg.REMAP_OCC_THRESHOLD:
            cold_rid = self.occupancy.get_coldest_region()
            self.remap.bind(event.object_id, cold_rid, event.decode_step)

        # 6. Final Promotion to Primary
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
