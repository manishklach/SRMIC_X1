from typing import Dict, Optional, Set
from .types import TensorMetadata

class RemapPolicy:
    """Decides when and where to remap tensors to avoid hotspots."""
    def __init__(self, max_entries: int = 256, cooldown: int = 50):
        self.remap_table: Dict[str, int] = {} # tid -> rid
        self.max_entries = max_entries
        self.cooldown = cooldown
        self.last_remap_token: Dict[str, int] = {}
        self.total_remaps = 0

    def get_region_override(self, tid: str) -> Optional[int]:
        """Returns remapped region ID if present."""
        return self.remap_table.get(tid)

    def should_remap(self, tid: str, token_idx: int, region_occ: float, threshold: float) -> bool:
        """Logic: Remap if region is too full and we aren't in cooldown."""
        if region_occ < threshold:
            return False
        
        last_idx = self.last_remap_token.get(tid, -1000)
        if (token_idx - last_idx) < self.cooldown:
            return False
            
        if len(self.remap_table) >= self.max_entries and tid not in self.remap_table:
            return False
            
        return True

    def perform_remap(self, tid: str, target_rid: int, token_idx: int):
        self.remap_table[tid] = target_rid
        self.last_remap_token[tid] = token_idx
        self.total_remaps += 1
