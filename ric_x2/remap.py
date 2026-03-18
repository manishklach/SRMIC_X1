from typing import Dict, Optional

class RemapEngine:
    """Software-modeled hardware Remap CAM."""
    def __init__(self, max_entries: int, cooldown: int):
        self.cam: Dict[str, int] = {}
        self.max_entries = max_entries
        self.cooldown = cooldown
        self.last_remap_step: Dict[str, int] = {}
        self.remap_count = 0

    def lookup(self, object_id: str) -> Optional[int]:
        return self.cam.get(object_id)

    def bind(self, object_id: str, rid: int, current_step: int) -> bool:
        last = self.last_remap_step.get(object_id, -self.cooldown - 1)
        if (current_step - last) < self.cooldown:
            return False
        
        if len(self.cam) < self.max_entries:
            self.cam[object_id] = rid
            self.last_remap_step[object_id] = current_step
            self.remap_count += 1
            return True
        return False
