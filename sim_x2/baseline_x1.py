from ric_x2.controller import RICX2
import copy

class BaselineX1(RICX2):
    """
    Legacy X1 behavior: Static Hashing, No Remapping, No Admission Control.
    Ensures architectural isolation by explicitly overriding config flags.
    """
    def __init__(self, config):
        # Create a deep copy of config to prevent side-effects on other scenarios
        baseline_cfg = copy.deepcopy(config)
        baseline_cfg.ADMISSION_ENABLED = False
        
        super().__init__(
            config=baseline_cfg,
            x2_mode=False
        )
