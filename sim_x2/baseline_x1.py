from ric_x2.controller import RICX2
from sim_x2.config import X2SimConfig

class BaselineX1(RICX2):
    """Legacy X1 behavior: Static Hashing, No Remapping."""
    def __init__(self, config: X2SimConfig):
        super().__init__(
            num_regions=config.NUM_REGIONS,
            cap_bytes=config.region_capacity_bytes,
            cam_size=0, # Disable CAM
            cooldown=100000,
            x2_mode=False
        )
