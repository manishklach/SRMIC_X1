import pandas as pd
from ric_x2.types import AccessResult

class X2Metrics:
    """Aggregates and serializes result data including Admission Control stats."""
    @staticmethod
    def summarize(controller, results, label, cfg):
        total = len(results)
        hits = results.count(AccessResult.HIT)
        promotions = results.count(AccessResult.MISS_PROMOTED)
        bypasses = results.count(AccessResult.MISS_BYPASSED)
        
        hit_rate = hits / total if total > 0 else 0
        bypass_rate = bypasses / (total - hits) if (total - hits) > 0 else 0
        
        latency = (hits * cfg.LATENCY_HIT) + \
                  (promotions * cfg.LATENCY_MISS_PROMOTED) + \
                  (bypasses * cfg.LATENCY_MISS_BYPASSED)

        return {
            "label": label,
            "total_accesses": total,
            "hit_rate": hit_rate,
            "bypass_rate": bypass_rate,
            "thrash_events": controller.thrash.thrash_count,
            "remap_count": controller.remap.remap_count,
            "bypass_count": controller.admission.total_bypasses,
            "occupancy_skew": controller.occupancy.get_skew(),
            "latency_proxy": latency,
            "regret_prevented": controller.admission.cumulative_regret_prevented
        }
