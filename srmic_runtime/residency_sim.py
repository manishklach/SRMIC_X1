from collections import OrderedDict, defaultdict
import math

class HRMResidencySimulator:
    """
    Software model of the SRMIC-X1 HRM residency manager.
    Models distributed regional SRAM buckets with configurable eviction policies.
    """
    def __init__(self, hrm_budget_gb, num_regions=64, policy="srmic", page_size_mb=2, pin_steps=10):
        self.hrm_budget_bytes = int(hrm_budget_gb * 1024**3)
        self.num_regions = num_regions
        self.policy = policy
        self.page_size_bytes = int(page_size_mb * 1024**2)
        self.pin_steps = pin_steps
        
        self.budget_per_region = self.hrm_budget_bytes // num_regions
        
        # State per region: region_id -> OrderedDict({tensor_name: {'size': size, 'last_access': idx, 'hits': count, 'promoted_at': idx}})
        self.regions = [OrderedDict() for _ in range(num_regions)]
        self.occupancy = [0 for _ in range(num_regions)]
        
        # Global stats
        self.hits = 0
        self.misses = 0
        self.promotions = 0
        self.demotions = 0
        self.current_token_idx = 0
        
        # Access counting for hotness
        self.global_access_counts = defaultdict(int)

    def _get_region(self, tensor_name):
        # Deterministic mapping of tensor to region
        return hash(tensor_name) % self.num_regions

    def access(self, tensor_name, size_bytes, token_idx):
        self.current_token_idx = token_idx
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

    def promote(self, tensor_name, size_bytes, region_id, token_idx):
        region = self.regions[region_id]
        
        # Room check (by bytes)
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

    def demote(self, region_id, token_idx):
        region = self.regions[region_id]
        if not region:
            return
        
        victim_name = None
        
        if self.policy == "lru":
            # First one in OrderedDict is the least recently used/added
            victim_name = next(iter(region))
            
        elif self.policy == "hotness":
            # Evict lowest access count
            victim_name = min(region.keys(), key=lambda k: region[k]['hits'])
            
        elif self.policy == "srmic":
            # Protect recently promoted pages (pinned for pin_steps)
            # Try to find an unpinned victim
            unpinned = [k for k, v in region.items() if (token_idx - v['promoted_at']) > self.pin_steps]
            if unpinned:
                # Use LRU among unpinned
                victim_name = unpinned[0]
            else:
                # All pinned? Force evict oldest (LRU)
                victim_name = next(iter(region))
        
        if victim_name:
            self.occupancy[region_id] -= region[victim_name]['size']
            del region[victim_name]
            self.demotions += 1

    def get_stats(self):
        total_access = self.hits + self.misses
        hit_rate = self.hits / total_access if total_access > 0 else 0
        total_occ = sum(self.occupancy)
        
        return {
            "hit_rate": hit_rate,
            "miss_rate": 1.0 - hit_rate,
            "promotions": self.promotions,
            "demotions": self.demotions,
            "hrm_occupancy_gb": total_occ / 1024**3,
            "hrm_budget_gb": self.hrm_budget_bytes / 1024**3
        }

    def reset(self):
        self.__init__(self.hrm_budget_bytes / 1024**3, self.num_regions, self.policy)
