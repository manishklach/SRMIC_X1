
class SRMICDecodeSim:
    """
    v20: Bounded per-region working-set model

    Architectural correction:
      - The per-region working set is FIXED by model architecture.
      - HRM hit ratio controls what FRACTION of that fixed working set
        is served from SRAM versus HBM.
      - Higher hit ratio reduces HBM traffic without increasing the
        amount of work each region must perform for a single token step.

    Units:
      - bandwidths in GB/s
      - sizes in GB
      - times in seconds
    """
    def __init__(
        self,
        tensor_tops_int8=2560.0,
        hbm_bw_gbps=24000.0,
        cxl_bw_gbps=64.0,            # 512 Gbps ~= 64 GB/s
        srmesh_bw_gbps=48000.0,      # 2x HBM aggregate
        hrm_regions=16,
        hrm_size_gb=0.0,
        model_weight_gb=7.0,
        active_weight_fraction=0.12,
        kv_gb_per_token=0.000004,
        pages_per_token_cold=3,
        page_size_gb=0.002,
        transformer_op_multiplier=2.0,
        fixed_fabric_overhead_ms=0.003
    ):
        self.tensor_tops = tensor_tops_int8
        self.hbm_bw = hbm_bw_gbps
        self.cxl_bw = cxl_bw_gbps
        self.srmesh_bw = srmesh_bw_gbps
        self.hrm_regions = hrm_regions
        self.hrm_size = hrm_size_gb
        self.model_weight = model_weight_gb
        self.active_frac = active_weight_fraction
        self.kv_per_token = kv_gb_per_token
        self.pages_per_token_cold = pages_per_token_cold
        self.page_size_gb = page_size_gb
        self.transformer_op_multiplier = transformer_op_multiplier
        self.fixed_fabric_overhead_ms = fixed_fabric_overhead_ms

    def compute_time(self):
        ops_per_token = self.model_weight * 1e9 * self.transformer_op_multiplier
        return ops_per_token / (self.tensor_tops * 1e12)

    def memory_time(self):
        active_weights = self.model_weight * self.active_frac

        # Residency fraction
        if active_weights <= 0:
            hrm_hit = 0.0
        elif self.hrm_size >= active_weights:
            hrm_hit = 1.0
        else:
            hrm_hit = self.hrm_size / active_weights

        # FIXED per-region working set for this token step
        active_bytes_per_region = active_weights / max(self.hrm_regions, 1)

        # Fraction served from HRM
        hrm_bytes_per_region = active_bytes_per_region * hrm_hit

        # Misses served from HBM, aggregate across all regions
        hbm_bytes = active_weights * (1.0 - hrm_hit)

        # Bounded page-window cold traffic
        cxl_bytes = self.pages_per_token_cold * self.page_size_gb

        # HRM time: per-region service + small fixed hop overhead
        hrm_bw_per_region = self.srmesh_bw / max(self.hrm_regions, 1)
        if hrm_bytes_per_region > 0:
            hrm_time = (hrm_bytes_per_region / max(hrm_bw_per_region, 1e-12)) + \
                       (self.fixed_fabric_overhead_ms * 1e-3)
        else:
            hrm_time = 0.0

        hbm_time = hbm_bytes / max(self.hbm_bw, 1e-12)
        cxl_time = cxl_bytes / max(self.cxl_bw, 1e-12)
        kv_time = self.kv_per_token / max(self.srmesh_bw, 1e-12)

        bottleneck, bottleneck_time = max(
            [("hrm", hrm_time), ("hbm", hbm_time), ("cxl", cxl_time), ("kv", kv_time)],
            key=lambda x: x[1]
        )

        return {
            "mem_time_s": bottleneck_time,
            "hrm_hit_ratio": hrm_hit,
            "active_weights_gb": active_weights,
            "active_bytes_per_region_gb": active_bytes_per_region,
            "hrm_bytes_per_region_gb": hrm_bytes_per_region,
            "hbm_bytes_gb": hbm_bytes,
            "cxl_bytes_gb": cxl_bytes,
            "hrm_time_ms": hrm_time * 1e3,
            "hbm_time_ms": hbm_time * 1e3,
            "cxl_time_ms": cxl_time * 1e3,
            "kv_time_ms": kv_time * 1e3,
            "bottleneck": bottleneck
        }

    def run(self):
        compute_t = self.compute_time()
        mem = self.memory_time()
        decode_t = max(compute_t, mem["mem_time_s"])
        overall_bottleneck = "compute" if compute_t > mem["mem_time_s"] else mem["bottleneck"]

        return {
            "decode_latency_ms": decode_t * 1e3,
            "tokens_per_sec": 1.0 / max(decode_t, 1e-12),
            "hrm_hit_ratio": mem["hrm_hit_ratio"],
            "compute_time_ms": compute_t * 1e3,
            "memory_time_ms": mem["mem_time_s"] * 1e3,
            "active_weights_gb": mem["active_weights_gb"],
            "active_bytes_per_region_gb": mem["active_bytes_per_region_gb"],
            "hrm_bytes_per_region_gb": mem["hrm_bytes_per_region_gb"],
            "hbm_bytes_gb": mem["hbm_bytes_gb"],
            "cxl_bytes_gb": mem["cxl_bytes_gb"],
            "hrm_time_ms": mem["hrm_time_ms"],
            "hbm_time_ms": mem["hbm_time_ms"],
            "cxl_time_ms": mem["cxl_time_ms"],
            "kv_time_ms": mem["kv_time_ms"],
            "bottleneck": overall_bottleneck,
        }
