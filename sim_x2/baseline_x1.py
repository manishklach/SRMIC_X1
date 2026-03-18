from ric_x2.controller import RICX2

class BaselineX1(RICX2):
    """Wrapper to force X1 behavior."""
    def __init__(self, config):
        super().__init__(config, x2_mode=False)
