from collections import deque

class ThrashMonitor:
    """Tracks rapid evict-to-miss cycles."""
    def __init__(self, window: int = 100):
        self.eviction_log = deque(maxlen=window)
        self.thrash_count = 0

    def record_eviction(self, object_id: str, step: int):
        self.eviction_log.append((object_id, step))

    def is_thrashing(self, object_id: str, current_step: int, threshold: int) -> bool:
        for oid, step in self.eviction_log:
            if oid == object_id and (current_step - step) <= threshold:
                self.thrash_count += 1
                return True
        return False
