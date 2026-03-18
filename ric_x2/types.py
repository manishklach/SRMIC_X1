from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, Set, Optional

class AccessResult(Enum):
    HIT = 1
    MISS_PROMOTED = 2
    MISS_BYPASSED = 3
    EVICTED = 4

@dataclass
class ObjectMetadata:
    """Historical telemetry for a specific weight tensor/page."""
    object_id: str
    size_bytes: int
    access_count: int = 0
    hit_count: int = 0
    last_step: int = -1
    last_evict_step: int = -1
    thrash_count: int = 0
    bypass_count: int = 0

@dataclass(frozen=True)
class TraceEvent:
    """Standardized event for the residency simulator."""
    decode_step: int
    object_id: str
    size_bytes: int
    layer_idx: Optional[int] = None
    phase: Optional[str] = None

@dataclass
class RegionState:
    """Physical state of an HRM SRAM region."""
    region_id: int
    capacity_bytes: int
    used_bytes: int = 0
    resident_objects: Set[str] = field(default_factory=set)
    
    @property
    def occupancy_fraction(self) -> float:
        return self.used_bytes / self.capacity_bytes if self.capacity_bytes > 0 else 0.0

    @property
    def free_bytes(self) -> int:
        return self.capacity_bytes - self.used_bytes
