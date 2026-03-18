import pandas as pd
import json
from ric_x2.types import AccessResult

class X2Metrics:
    """Aggregates and serializes result data."""
    @staticmethod
    def summarize(controller, results, label, cfg):
        total = len(results)
        hits = results.count(AccessResult.HIT)
        promotions = results.count(AccessResult.MISS_PROMOTED)
        
        latency = (hits * cfg.LATENCY_HIT) + \
                  (promotions * cfg.LATENCY_MISS_PROMOTED) + \
                  ((total - hits - promotions) * cfg.LATENCY_MISS_BYPASSED)

        return {
            "label": label,
            "total_accesses": total,
            "hits": hits,
            "hit_rate": hits / total if total > 0 else 0,
            "thrash_events": controller.thrash.thrash_count,
            "remap_count": controller.remap.remap_count,
            "occupancy_skew": controller.occupancy.get_skew(),
            "latency_proxy": latency
        }
