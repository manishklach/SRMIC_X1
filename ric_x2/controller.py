from .types import TraceEvent, AccessResult
from .occupancy import OccupancyTracker
from .collision import CollisionTracker
from .thrash import ThrashMonitor
from .remap import RemapEngine

class RICX2:
    """Unified controller for X1 (static) and X2 (reactive) modes."""
    def __init__(self, config, x2_mode: bool = True):
        self.cfg = config
        self.x2_mode = x2_mode
        self.occupancy = OccupancyTracker(config.NUM_REGIONS, config.region_capacity_bytes)
        self.collision = CollisionTracker(config.NUM_REGIONS)
        self.thrash = ThrashMonitor()
        self.remap = RemapEngine(config.MAX_CAM_ENTRIES, config.REMAP_COOLDOWN_STEPS)

    def _get_region(self, object_id: str) -> int:
        if self.x2_mode:
            override = self.remap.lookup(object_id)
            if override is not None: return override
        return hash(object_id) % self.cfg.NUM_REGIONS

    def handle_access(self, event: TraceEvent) -> AccessResult:
        rid = self._get_region(event.object_id)
        self.collision.record_attempt(rid, event.object_id, self.occupancy.regions[rid].resident_objects)

        if self.occupancy.is_resident(event.object_id, rid):
            return AccessResult.HIT

        # Miss handling
        # Simple Eviction/Promotion
        while self.occupancy.regions[rid].free_bytes < event.size_bytes:
            if not self.occupancy.regions[rid].resident_objects: break
            victim = next(iter(self.occupancy.regions[rid].resident_objects))
            self.occupancy.remove(victim, rid, event.size_bytes)
            self.thrash.record_eviction(victim, event.decode_step)

        # Reactive Remap Trigger (X2 only)
        if self.x2_mode and self.occupancy.regions[rid].occupancy_fraction > self.cfg.REMAP_OCC_THRESHOLD:
            target_rid = self.occupancy.get_coldest_region()
            self.remap.bind(event.object_id, target_rid, event.decode_step)

        self.occupancy.add(event, rid)
        return AccessResult.MISS_PROMOTED
