from typing import Dict, List, Optional
from .types import TensorMetadata, AccessResult, RegionState
from .occupancy import OccupancyTracker
from .collision import CollisionTracker
from .thrash import ThrashTracker
from .remap import RemapPolicy

class RICX2:
    """The central orchestrator for SRMIC-X2 policy logic."""
    def __init__(self, num_regions: int, cap_bytes: int, cam_size: int, cooldown: int, x2_mode: bool = True):
        self.occupancy = OccupancyTracker(num_regions, cap_bytes)
        self.collision = CollisionTracker(num_regions)
        self.thrash = ThrashTracker()
        self.remap = RemapPolicy(cam_size, cooldown)
        self.x2_mode = x2_mode
        self.num_regions = num_regions

    def handle_access(self, tensor: TensorMetadata, token_idx: int, remap_threshold: float = 0.9) -> AccessResult:
        """Process a single tensor access through the residency hierarchy."""
        # 1. Routing (Fast Path)
        rid = None
        if self.x2_mode:
            rid = self.remap.get_region_override(tensor.tensor_id)
        
        if rid is None:
            # Deterministic base hash (X1 style)
            rid = hash(tensor.tensor_id) % self.num_regions

        # 2. Collision Tracking
        self.collision.record_attempt(rid, tensor.tensor_id, self.occupancy.regions[rid].resident_tensors)

        # 3. Hit/Miss Check
        if self.occupancy.is_resident(tensor.tensor_id, rid):
            self.occupancy.regions[rid].hit_count += 1
            return AccessResult.HIT

        # 4. Miss Handling (Promotion)
        self.occupancy.regions[rid].miss_count += 1
        
        # Check for thrash (Recently evicted re-access)
        is_thrash = self.thrash.check_access(tensor.tensor_id, token_idx, 10) # Fixed window for MVP

        # Simplified Eviction logic for MVP (Evict LRU-ish: just evict enough space)
        while self.occupancy.regions[rid].free_bytes < tensor.size_bytes:
            # For MVP, just evict first one found (Random/FIFO for simplicity)
            if not self.occupancy.regions[rid].resident_tensors:
                break
            victim_id = next(iter(self.occupancy.regions[rid].resident_tensors))
            self.occupancy.remove(victim_id, rid, tensor.size_bytes) # Assume fixed size for MVP
            self.thrash.record_eviction(victim_id, token_idx)

        # 5. Admission (Promotion)
        self.occupancy.add(tensor, rid)

        # 6. Policy Update (X2 Mode: Evaluate Remap)
        if self.x2_mode:
            region_occ = self.occupancy.regions[rid].occupancy_fraction
            if self.remap.should_remap(tensor.tensor_id, token_idx, region_occ, remap_threshold):
                target_rid = self.occupancy.get_coldest_region()
                self.remap.perform_remap(tensor.tensor_id, target_rid, token_idx)

        return AccessResult.MISS_PROMOTED
