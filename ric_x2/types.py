from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Dict, Set, Optional

class AccessResult(Enum):
    HIT = auto()
    MISS_PROMOTED = auto()
    MISS_BYPASSED = auto()
    EVICTED = auto()

@dataclass(frozen=True)
class TensorMetadata:
    """Represents an object (weight/page) in the trace."""
    tensor_id: str
    size_bytes: int
    layer_idx: Optional[int] = None
    phase_tag: Optional[str] = None

@dataclass
class RegionState:
    """State of a single HRM SRAM region."""
    region_id: int
    capacity_bytes: int
    used_bytes: int = 0
    resident_tensors: Set[str] = field(default_factory=set)
    hit_count: int = 0
    miss_count: int = 0
    
    @property
    def free_bytes(self) -> int:
        return self.capacity_bytes - self.used_bytes

    @property
    def occupancy_fraction(self) -> float:
        return self.used_bytes / self.capacity_bytes if self.capacity_bytes > 0 else 0.0
