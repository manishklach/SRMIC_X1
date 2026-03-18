from dataclasses import dataclass

@dataclass
class X2SimConfig:
    """Consolidated configuration for SRMIC-X2 simulation."""
    # Architecture
    NUM_REGIONS: int = 64
    REGION_CAPACITY_MB: int = 128
    
    # Latencies (Proxy cycles)
    LATENCY_HIT: int = 2
    LATENCY_MISS_PROMOTED: int = 6
    LATENCY_MISS_BYPASSED: int = 10
    
    # X2 Policy Settings
    MAX_CAM_ENTRIES: int = 256
    REMAP_OCCUPANCY_THRESHOLD: float = 0.90
    REMAP_COOLDOWN_TOKENS: int = 50
    THRASH_WINDOW_TOKENS: int = 10
    
    @property
    def region_capacity_bytes(self) -> int:
        return self.REGION_CAPACITY_MB * 1024 * 1024
