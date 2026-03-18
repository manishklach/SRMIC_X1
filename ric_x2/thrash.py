from collections import deque
from .types import TensorMetadata

class ThrashTracker:
    """Monitors if objects are being evicted and re-accessed too quickly."""
    def __init__(self, window_size: int = 100):
        # Stores (tensor_id, eviction_token_idx)
        self.eviction_log = deque(maxlen=window_size)
        self.thrash_events = 0

    def record_eviction(self, tid: str, token_idx: int):
        self.eviction_log.append((tid, token_idx))

    def check_access(self, tid: str, token_idx: int, window: int) -> bool:
        """Returns True if this access is a 'thrash' (re-accessing recently evicted)."""
        for evicted_id, evict_idx in self.eviction_log:
            if evicted_id == tid and (token_idx - evict_idx) <= window:
                self.thrash_events += 1
                return True
        return False
