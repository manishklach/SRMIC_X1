from dataclasses import dataclass

@dataclass
class X2SimConfig:
    """Central configuration for SRMIC-X2 with Stress-Test support."""
    # Architecture
    NUM_REGIONS: int = 64
    REGION_CAPACITY_MB: int = 32 # Increased from 4MB to allow multiple tensors
    
    # Latencies (Base)
    LATENCY_HIT: int = 2
    LATENCY_MISS_PROMOTED: int = 6
    LATENCY_MISS_BYPASSED: int = 10
    
    # Congestion Penalty
    CONGESTION_PENALTY_THRESHOLD: float = 0.70 # More aggressive penalty
    CONGESTION_PENALTY_CYCLES: int = 2
    
    # X2 Policy Defaults
    MAX_CAM_ENTRIES: int = 256
    REMAP_OCC_THRESHOLD: float = 0.85
    REMAP_COOLDOWN_STEPS: int = 50
    THRASH_WINDOW_STEPS: int = 10
    
    # Admission Control
    ADMISSION_ENABLED: bool = True
    REGRET_THRESHOLD: float = 5.0
    MIN_OCCUPANCY_FOR_ADMISSION_CTRL: float = 0.50
    
    # Replication Policy
    REPLICATION_ENABLED: bool = True
    MAX_TOTAL_REPLICAS: int = 64
    MAX_REPLICAS_PER_OBJECT: int = 2 # Allow 2 replicas for high fanout
    HOT_OBJECT_ACCESS_THRESHOLD: int = 5
    HOT_OBJECT_MIN_STEPS: int = 3
    REPLICATION_PRESSURE_THRESHOLD: float = 0.50
    REPLICA_IDLE_STEPS: int = 8
    
    # Routing Refinement
    PRESSURE_AWARE_ROUTING: bool = True
    
    # Utility Weights
    W_ACCESS: float = 1.0
    W_RECENCY: float = 2.0
    W_HITS: float = 5.0
    W_THRASH: float = -10.0

    @property
    def region_capacity_bytes(self) -> int:
        return self.REGION_CAPACITY_MB * 1024 * 1024
