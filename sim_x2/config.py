from dataclasses import dataclass

@dataclass
class X2SimConfig:
    """Central configuration for SRMIC-X2 MVP + Admission Control."""
    # Architecture
    NUM_REGIONS: int = 64
    REGION_CAPACITY_MB: int = 128
    
    # Latencies (Proxy cycles)
    LATENCY_HIT: int = 2
    LATENCY_MISS_PROMOTED: int = 6
    LATENCY_MISS_BYPASSED: int = 10
    
    # X2 Policy Defaults
    MAX_CAM_ENTRIES: int = 256
    REMAP_OCC_THRESHOLD: float = 0.90
    REMAP_COOLDOWN_STEPS: int = 50
    THRASH_WINDOW_STEPS: int = 10
    
    # Admission Control / Utility Heuristics
    ADMISSION_ENABLED: bool = True
    REGRET_THRESHOLD: float = 5.0
    MIN_OCCUPANCY_FOR_ADMISSION_CTRL: float = 0.80
    
    # Utility Weights
    W_ACCESS: float = 1.0
    W_RECENCY: float = 2.0
    W_HITS: float = 5.0
    W_THRASH: float = -10.0

    @property
    def region_capacity_bytes(self) -> int:
        return self.REGION_CAPACITY_MB * 1024 * 1024
