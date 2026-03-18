from .types import ObjectMetadata, RegionState

class AdmissionController:
    """Decides whether a miss deserves SRAM promotion or should be bypassed."""
    def __init__(self, config):
        self.cfg = config
        self.total_bypasses = 0
        self.cumulative_regret_prevented = 0.0

    def estimate_utility(self, obj: ObjectMetadata, current_step: int) -> float:
        """Lightweight heuristic for object value."""
        if obj.access_count == 0:
            return 0.0
            
        # Recency score: higher for more recent accesses
        age = max(0, current_step - obj.last_step)
        recency_score = 1.0 / (1.0 + age)
        
        utility = (self.cfg.W_ACCESS * obj.access_count) + \
                  (self.cfg.W_RECENCY * recency_score) + \
                  (self.cfg.W_HITS * obj.hit_count) + \
                  (self.cfg.W_THRASH * obj.thrash_count)
        
        return float(utility)

    def should_admit(self, incoming: ObjectMetadata, victim: ObjectMetadata, 
                     region: RegionState, current_step: int) -> bool:
        """
        Policy: Bypass if victim_utility - incoming_utility > threshold.
        Only activates when region is under pressure.
        """
        if not self.cfg.ADMISSION_ENABLED:
            return True
            
        if region.occupancy_fraction < self.cfg.MIN_OCCUPANCY_FOR_ADMISSION_CTRL:
            return True # Plenty of space, always admit

        u_incoming = self.estimate_utility(incoming, current_step)
        u_victim = self.estimate_utility(victim, current_step)
        
        regret_gap = u_victim - u_incoming
        
        if regret_gap > self.cfg.REGRET_THRESHOLD:
            self.total_bypasses += 1
            self.cumulative_regret_prevented += regret_gap
            incoming.bypass_count += 1
            return False # BYPASS
            
        return True # ADMIT
