from typing import List, Dict
import pandas as pd
from ric_x2.types import AccessResult
from ric_x2.controller import RICX2

class X2Metrics:
    """Aggregates simulation results into actionable reports."""
    @staticmethod
    def summarize(controller: RICX2, results: List[AccessResult], label: str) -> Dict:
        total = len(results)
        hits = results.count(AccessResult.HIT)
        promos = results.count(AccessResult.MISS_PROMOTED)
        bypasses = results.count(AccessResult.MISS_BYPASSED)
        
        hit_rate = hits / total if total > 0 else 0
        collision_data = controller.collision.get_report()
        
        return {
            "label": label,
            "total_accesses": total,
            "hit_rate": hit_rate,
            "promotions": promos,
            "bypasses": bypasses,
            "remaps": controller.remap.total_remaps,
            "occupancy_skew": controller.occupancy.get_skew(),
            "total_collisions": collision_data["total_collisions"],
            "thrash_events": controller.thrash.thrash_events
        }
