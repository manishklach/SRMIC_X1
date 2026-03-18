from collections import OrderedDict, defaultdict
from typing import Dict, List, Any, Optional, Union
import math

class HRMResidencySimulator:
    """
    Software model of the SRMIC-X1 HRM residency manager.
    Models distributed regional SRAM buckets with configurable eviction policies.
    """
    def __init__(self, hrm_budget_gb: float, num_regions: int = 64, policy: str = "srmic", page_size_mb: int = 2, pin_steps: int = 10):
        """
        Initializes the simulator with a budget, region count, and eviction policy.
        """
        self.hrm_budget_bytes: int = int(hrm_budget_gb * 1024**3)
        self.num_regions: int = num_regions
        self.policy: str = policy
        self.page_size_bytes: int = int(page_size_mb * 1024**2)
        self.pin_steps: int = pin_steps
        
        self.budget_per_region: int = self.hrm_budget_bytes // num_regions
        
        # State per region: region_id -> OrderedDict({tensor_name: metadata})
        self.regions: List[OrderedDict[str, Dict[str, Union[int, float]]]] = [OrderedDict() for _ in range(num_regions)]
        self.occupancy: List[int] = [0 for _ in range(num_regions)]
        
        # Global stats
        self.hits: int = 0
        self.misses: int = 0
        self.promotions: int = 0
        self.demotions: int = 0
        self.current_token_idx: int = 0
        
        # Track unique tensors seen to compute working set
        self.seen_tensors: Dict[str, int] = {}

    def _get_region(self, tensor_name: str) -> int:
        """
        Deterministic mapping of tensor to region using a consistent hash.
        """
        return hash(tensor_name) % self.num_regions

    def access(self, tensor_name: str, size_bytes: int, token_idx: int) -> str:
        """
        Main entry point for accessing a tensor. Triggers hit or miss/promote logic.
        """
        self.current_token_idx = token_idx
        self.seen_tensors[tensor_name] = size_bytes
        region_id = self._get_region(tensor_name)
        region = self.regions[region_id]
        
        if tensor_name in region:
            self.hits += 1
            # Update metadata
            region[tensor_name]['last_access'] = token_idx
            region[tensor_name]['hits'] += 1
            
            if self.policy == "lru":
                region.move_to_end(tensor_name)
            return "hit"
        else:
            self.misses += 1
            self.promote(tensor_name, size_bytes, region_id, token_idx)
            return "miss"

    def promote(self, tensor_name: str, size_bytes: int, region_id: int, token_idx: int) -> None:
        """
        Handles promotion of a missing tensor into the specified region.
        """
        region = self.regions[region_id]
        
        # Room check (by bytes). Evict until enough space.
        while self.occupancy[region_id] + size_bytes > self.budget_per_region and region:
            self.demote(region_id, token_idx)
            
        if self.occupancy[region_id] + size_bytes <= self.budget_per_region:
            region[tensor_name] = {
                'size': size_bytes,
                'last_access': token_idx,
                'hits': 1,
                'promoted_at': token_idx
            }
            self.occupancy[region_id] += size_bytes
            self.promotions += 1

    def demote(self, region_id: int, token_idx: int) -> Optional[str]:
        """
        Evicts a tensor from a region based on the configured policy.
        """
        region = self.regions[region_id]
        if not region:
            return None
        
        victim_name = None
        
        if self.policy == "lru":
            # First one in OrderedDict is the least recently used/added
            victim_name = next(iter(region))
            
        elif self.policy == "hotness":
            # Evict lowest access count
            victim_name = min(region.keys(), key=lambda k: region[k]['hits'])
            
        elif self.policy == "srmic":
            # Protect recently promoted pages (pinned for pin_steps)
            # Find an unpinned victim (promoted more than pin_steps ago)
            unpinned = [k for k, v in region.items() if (token_idx - v['promoted_at']) > self.pin_steps]
            if unpinned:
                # Use LRU (oldest) among unpinned
                victim_name = unpinned[0]
            else:
                # All pinned? Force evict oldest (LRU) as safety fallback
                victim_name = next(iter(region))
        
        if victim_name:
            self.occupancy[region_id] -= region[victim_name]['size']
            del region[victim_name]
            self.demotions += 1
            return victim_name
        return None

    def get_stats(self) -> Dict[str, Any]:
        """
        Returns a dictionary containing hit/miss stats and current occupancy.
        """
        total_access = self.hits + self.misses
        hit_rate = self.hits / total_access if total_access > 0 else 0
        total_occ = sum(self.occupancy)
        working_set_size_gb = sum(self.seen_tensors.values()) / 1024**3
        
        return {
            "hit_rate": hit_rate,
            "miss_rate": 1.0 - hit_rate,
            "promotion_count": self.promotions,
            "demotion_count": self.demotions,
            "working_set_size_gb": working_set_size_gb,
            "hrm_occupancy_gb": total_occ / 1024**3
        }

    def reset(self) -> None:
        """
        Resets the simulator state.
        """
        self.__init__(self.hrm_budget_bytes / 1024**3, self.num_regions, self.policy)
