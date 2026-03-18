import pandas as pd
from ric_x2.types import AccessResult

class X2Metrics:
    """Aggregates simulation results including Stress-Test specific counters."""
    @staticmethod
    def summarize(controller, results, label, cfg, workload_label=""):
        total = len(results)
        base_hits = results.count(AccessResult.HIT)
        replica_hits = results.count(AccessResult.HIT_REPLICA)
        hits = base_hits + replica_hits
        promotions = results.count(AccessResult.MISS_PROMOTED)
        bypasses = results.count(AccessResult.MISS_BYPASSED)
        
        hit_rate = hits / total if total > 0 else 0
        replica_hit_rate = replica_hits / total if total > 0 else 0
        
        # Latency including congestion penalty
        base_latency = (hits * cfg.LATENCY_HIT) + \
                       (promotions * cfg.LATENCY_MISS_PROMOTED) + \
                       (bypasses * cfg.LATENCY_MISS_BYPASSED)
        
        total_latency = base_latency + controller.step_congestion_penalties

        # Replica selected ratio (among total hits)
        replica_selected_ratio = replica_hits / hits if hits > 0 else 0

        return {
            "workload": workload_label,
            "label": label,
            "total_accesses": total,
            "hit_rate": hit_rate,
            "replica_hit_rate": replica_hit_rate,
            "replica_hits": replica_hits,
            "replica_selected_ratio": replica_selected_ratio,
            "replica_count": controller.replication.total_replica_count,
            "bypass_count": controller.admission.total_bypasses,
            "remap_count": controller.remap.remap_count,
            "occupancy_skew": controller.occupancy.get_skew(),
            "latency_proxy": total_latency,
            "congestion_penalty": controller.step_congestion_penalties,
            "regret_prevented": controller.admission.cumulative_regret_prevented
        }
