# SRMIC-X2: Collision-Aware and Regret-Aware Residency Intelligence for Large Language Model Decode Acceleration

**Authors:** Manish KL  
**Date:** March 2026  

## Abstract
Autoregressive large language model inference is limited by memory movement during decode rather than raw arithmetic throughput. Prior SRMIC-style residency-first designs show that a distributed SRAM tier can reduce HBM pressure, but static placement policies suffer from regional collisions, residency pollution, and uneven utilization. We present SRMIC-X2, a controller-centric extension that adds three mechanisms to a distributed residency system: reactive remapping to relieve placement hotspots, regret-aware admission control to avoid destructive promotions, and selective replication for concentrated demand. Our evaluation is intentionally tiered: analytical 7B and 70B studies motivate the scaling regime, deterministic synthetic stress traces isolate controller behavior, and initial real trace replay on public OPT models validates the policy direction on executed model traces. Across real-trace replay, the remap-plus-admission policy improves HBM-relative speedup from 1.29x to 1.71x on `OPT-125m` at 0.2 GB HRM, from 1.19x to 1.45x on `OPT-350m` at 0.4 GB HRM, and from 1.04x to 1.23x on `OPT-1.3b` at 0.8 GB HRM, relative to the legacy static policy. We find that remap plus admission is the most robust current policy tier, while replication is beneficial but secondary.

## 1. Introduction
The computational efficiency of Large Language Model (LLM) serving is currently dominated by the "Memory Wall." During the decode phase, the arithmetic intensity is low, meaning the tokens-per-second metric is dictated by the rate at which model weights can be fetched from High Bandwidth Memory (HBM).

The SRMIC-X1 architecture proposed a residency-first approach, using a distributed Hot Residency Memory (HRM) tier to cache the weights required for token generation. However, practical evaluation of X1 revealed that static hashing functions often lead to "regional hash collisions"—where multiple high-demand tensors (e.g., MLP weights) are co-located in the same physical SRAM region, causing localized thrashing while adjacent regions remain under-utilized.

In this paper, we introduce SRMIC-X2. X2 shifts the focus from the physical memory fabric to the Residency Intelligence Controller (RIC). We argue that a memory tier is only as effective as the policy governing its occupancy. SRMIC-X2 provides a dynamic control plane that load-balances the distributed mesh and protects resident "hot" weights from being displaced by transient or low-reuse data.

**Our contributions are as follows:**
- We define a collision-aware control architecture for distributed SRAM tiers.
- We implement and evaluate a regret-aware admission policy that uses historical utility to decide when to bypass the residency tier.
- We present a selective replication mechanism for hotspot mitigation and analyze its workload sensitivity.
- We provide a trace-driven evaluation framework that identifies the specific conditions under which intelligent control outperforms static baselines.

## 2. Background and Motivation
LLMs exhibit high temporal locality in their weight access patterns during decode: the same weights are fetched once per token. However, the spatial distribution of these weights across a distributed memory mesh is traditionally static. When multiple large weights hash to the same node, the resulting congestion creates a performance ceiling. 

Furthermore, naive promotion policies—where every cache miss results in a promotion—lead to residency pollution. In scenarios where SRAM capacity is constrained, promoting a new weight at the cost of evicting a weight needed immediately is an "Eviction Regret" event. Motivating X2 is the need for a controller that can predict this regret and proactively manage the residency set.

## 3. SRMIC-X1 Recap
SRMIC-X1 established the core concept of a tiered memory hierarchy for LLM inference, separating weights into a hot SRAM tier (HRM) and a cold HBM tier. It introduced the SRMESH interconnect, a high-bandwidth mesh supporting distributed regional access. While X1 demonstrated that SRAM residency could reduce HBM pressure, it relied on a rigid mathematical hashing policy for data placement.

Evaluations of X1 identified three primary weaknesses:
1. **Collisions:** Static hashing cannot adapt to tensor dimensions, leading to regional over-subscription.
2. **Thrash:** Indiscriminate promotions cause high-reuse data to be evicted prematurely.
3. **Imbalance:** Wide variance in occupancy across regions leaves aggregate bandwidth on the table.

## 4. Problem Statement: The Collision Ceiling
A "Naive Residency System" is one that employs static mapping and promotes on every miss. In such a system, the effective hit rate is limited not by total SRAM capacity, but by the "Collision Ceiling." Our results show that even when aggregate SRAM capacity exceeds the active working set, the hit rate can saturate prematurely due to mapping conflicts. This performance gap represents the primary bottleneck targeted by SRMIC-X2.

## 5. SRMIC-X2 Architecture Overview
SRMIC-X2 extends the Residency Intelligence Controller (RIC) with a two-tiered logic flow:

- **Fast Path (Cycle-Accurate):** Executes parallel lookups in a Static Hash engine and a 256-entry hardware-proxy Remap CAM. This ensures O(1) routing latency for both baseline and remapped data.
- **Slow Path (Policy Engine):** An engine that monitors telemetry (occupancy skew, miss rates, and eviction regret) to update the Remap CAM and trigger replication.

### Figure 1: SRMIC-X2 Controller Architecture
```text
      +-----------------------------------------------------------+
      |          RIC-X2 (Residency Intelligence Controller)       |
      |                                                           |
      |  +----------------+   +----------------+   +-----------+  |
      |  | Remap Engine   |   | Admission Ctrl |   | Repl. Mgr |  |
      |  | (256-entry CAM)|   | (Utility Gate) |   | (Cloning) |  |
      |  +--------+-------+   +--------+-------+   +-----+-----+  |
      |           |                    |                 |        |
      |  +--------v--------------------v-----------------v-----+  |
      |  |                 Control Logic Tier                  |  |
      |  |  (Telemetry Monitor, Skew Analytics, Regret Score)  |  |
      |  +--------------------------+--------------------------+  |
      +-----------------------------|-----------------------------+
                                    |
      +-----------------------------v-----------------------------+
      |                      HRM SRAM Tier                        |
      |  (64 Regions, 96 TB/s SRMESH, Collision-Aware Routing)    |
      +-----------------------------------------------------------+
```

### Figure 2: Per-Access Controller Flow
```text
          [ Start: Tensor Access Request ]
                      |
            +---------v---------+
            | 1. Parallel Route |<--- [ Remap CAM ]
            | (Hash vs CAM)     |
            +---------+---------+
                      | (Target Region ID)
            +---------v---------+
            | 2. Check Residency|
            | (Primary + Replicas)|
            +---------+---------+
             /        |        \
      (Hit) /         | (Miss)  \ (Hit Replica)
     +-----v---+      |      +---v-------+
     |   HIT   |      |      | HIT_REPL  |
     +---------+      |      +-----------+
                      |
            +---------v---------+
            | 3. Utility Gate   |
            | (Regret Check)    |
            +---------+---------+
             /        |        \
    (Bypass)/         | (Admit) \ (Remap Trigger)
    +------v---+      |      +---v-------+
    | BYPASS   |      |      | REMAP/PROM|
    | (HBM)    |      |      | (SRAM)    |
    +----------+      |      +-----------+
                      |
            [ 4. Evict & Promote ]
```

## 6. Mechanism I: Collision-Aware Remap Control
X2 employs **Reactive Remapping** to solve placement inefficiency. When the RIC detects that a specific region has breached an occupancy threshold and is experiencing misses, it identifies the requested tensor as a candidate for relocation. The controller finds the "coldest" region and binds the tensor to it via the Remap CAM. This flattens regional skew and allows the system to utilize the full aggregate capacity of the distributed mesh.
On the reference dense synthetic trace, remap + admission reduces occupancy skew from 0.262 to 0.250, while full X2 reduces it further to 0.147. On public real traces, remap activity remains active across all tested models, indicating that static placement pathologies persist outside synthetic stress cases.

## 7. Mechanism II: Regret-Aware Admission and Bypass
X2 introduces an **Admission Gate**. Instead of automatically promoting every miss, the RIC evaluates the "Utility" of the resident victim vs. the incoming object.

The utility heuristic $U$ accounts for access frequency and recency. If the "Regret Gap" ($U_{victim} - U_{incoming}$) exceeds a threshold, the controller serves the access directly from HBM (`MISS_BYPASSED`), preserving the high-value resident weight. This protects the core working set from being polluted by transient data.
In the current branch, admission is the most reliable source of real-trace gains. Across the three public OPT runs, the admission-enabled policy consistently produces the highest replay speedup and hit rate.

## 8. Mechanism III: Selective Hot-Object Replication
In scenarios where remapping and admission are insufficient—specifically when a single tensor's bandwidth demand exceeds a single region's capability—X2 permits **Selective Replication**.

The controller clones ultra-high-utility objects into secondary regions. Future lookups utilize a pressure-aware routing policy, choosing the copy residing in the least-loaded region. While functionally active, the incremental benefit of replication is workload-sensitive and most pronounced in scenarios with extreme hotspot concentration.

## 9. Evaluation Methodology
Our evaluation uses three evidence tiers, each answering a different question.
- **Tier 1: Analytical scaling studies.** Existing 7B and 70B studies characterize bandwidth/capacity trends and motivate why a residency controller matters at larger model sizes.
- **Tier 2: Deterministic synthetic workloads.** We employ three stress-trace families: `HOTSPOT_FANOUT`, `BURST_CONTENTION`, and `HOTSET_ROTATION` to isolate specific controller pathologies.
- **Tier 3: Real trace replay.** We capture decode-time weight-access traces from public Hugging Face models and replay the exact same trace through `srmic`, `x2_admission`, and `x2_full`.
- **Metrics:** We track Useful Hit Rate, Occupancy Skew ($\sigma$), Thrash Count, a Latency Proxy (cycles), and HBM-relative speedup from trace replay.
- **Integrity:** The harness now enforces deterministic hashing and deterministic victim selection to allow repeatable comparisons.

### Table 1: Synthetic Stress Families

| Workload | Intent | Main failure mode exercised |
| :--- | :--- | :--- |
| `HOTSPOT_FANOUT` | Concentrated demand on a tiny hot set | Single-region bandwidth saturation |
| `BURST_CONTENTION` | Short bursts over a moderate hot set | Overreaction to transient pressure |
| `HOTSET_ROTATION` | Hot identities change by phase | Stale residency and replica poisoning |

### Table 2: Metrics

| Metric | Definition | Purpose |
| :--- | :--- | :--- |
| Hit Rate | Fraction of accesses served from HRM | Primary residency efficiency measure |
| Occupancy Skew | Std. dev. of per-region occupancy | Placement balance |
| Latency Proxy | Access-weighted cycle model with congestion penalty | Relative controller comparison |
| Speedup vs HBM | Replay-derived HBM-relative speedup | Workload-level performance summary |

## 10. Experimental Results
### 10.1 Tier 1: Analytical Scaling Context
The analytical 7B and 70B studies are used in this paper as scaling context, not as direct X2 controller validation. They motivate the architectural regime in which residency intelligence matters: larger active working sets, tighter HRM budgets, and stronger sensitivity to placement inefficiency.

### 10.2 Tier 2: Controller Behavior on Synthetic Stress Workloads
SRMIC-X2 demonstrates a significant improvement in hit-rate stability over the X1 baseline on synthetic controller-focused workloads. The synthetic suite is used to isolate hotspot concentration, burst pressure, and rotating hot-set behavior under deterministic conditions.

### 10.3 Load Balancing and Remap Efficiency
Reactive remapping successfully resolved primary capacity hotspots. 
On the reference synthetic trace, occupancy skew improves from 0.262 in the baseline to 0.250 with remap + admission and to 0.147 with full X2 enabled. On real traces, remap activity remains substantial in the strongest policy mode, with 12 remaps on `OPT-125m` at 0.2 GB, 40 remaps on `OPT-350m` at 0.4 GB, and 25 remaps on `OPT-1.3b` at 0.8 GB.

### 10.4 Admission Control and Thrash Mitigation
The admission controller is the primary driver of residency protection.
The admission controller is the primary driver of the current real-trace gains. On `OPT-125m` at 0.2 GB, `x2_admission` issues 176 bypasses and reaches 55.5% hit rate versus 30.3% for `srmic`. On `OPT-350m` at 0.4 GB, it issues 460 bypasses and reaches 41.2% hit rate versus 21.1% for `srmic`. On `OPT-1.3b` at 0.8 GB, it issues 497 bypasses and reaches 25.2% hit rate versus 4.5% for `srmic`.

### 10.5 Tier 3: Initial Real-Trace Validation
The real-trace results are the key empirical validation tier for this paper. Across all three public-model runs, `x2_admission` outperforms both the legacy `srmic` policy and `x2_full`, indicating that remap + admission is presently the strongest default policy configuration.

### 10.6 Replication and Workload Sensitivity
Replication provided measurable gains in the `HOTSPOT_FANOUT` workload.
Replication still provides a measurable gain in the `HOTSPOT_FANOUT` workload, reducing synthetic latency proxy by 5.7%. However, in the initial real-trace experiments it trails `x2_admission`, reaching 1.54x versus 1.71x on `OPT-125m`, 1.41x versus 1.45x on `OPT-350m`, and 1.20x versus 1.23x on `OPT-1.3b`. Replication should therefore be positioned as a secondary optimization layer.

## 11. Discussion
The results confirm that residency intelligence is a meaningful layer for tiered memory systems. Across the current evidence tiers, remapping and admission control appear to be the most robust mechanisms. Selective replication acts as a safety valve for concentrated demand, but the present results do not justify making it the headline contribution. The safest interpretation is that SRMIC-X2 demonstrates a credible controller direction for distributed residency systems, with remap + admission as the strongest default policy and replication as a secondary refinement.

## 12. Limitations
Our current evaluation mixes three evidence tiers with different strengths. The 7B and 70B results are analytical rather than controller-empirical. The controller stress suite is synthetic by design. The real-trace results are currently limited to public OPT models through 1.3B and still rely on a latency proxy rather than a cycle-accurate hardware simulation. The utility heuristics also remain tunable and may require different optimization for diverse model families (e.g., Sparse Mixture-of-Experts). These limitations mean the paper should be interpreted as initial controller evidence rather than full architectural validation.

## 13. Future Work
Immediate next steps include the integration of the RIC-X2 logic into a cycle-accurate memory/fabric simulator. We also intend to explore the RTL realization of the Remap CAM and Admission Gate to quantify the area and power overhead.

## 14. Conclusion
SRMIC-X2 addresses the fundamental scaling challenges of residency-first inference acceleration. By transitioning the control plane from static hashing to telemetry-driven intelligence, we have demonstrated that it is possible to maintain high hit rates and balanced load under pressure. This work defines a credible microarchitectural path for next-generation AI accelerators.

---
**Appendix A: Policy Pseudocode**
```text
on access(object):
    rid = remap_cam.lookup(object) else static_hash(object)
    if object resident in primary or replica:
        route to least-loaded resident copy
        if object remains hot and pressure persists:
            consider bounded replication
        return HIT

    if region pressured:
        victim = deterministic victim selection
        if utility(victim) - utility(object) > threshold:
            return BYPASS

    if region remains overloaded:
        bind remap entry to colder region

    promote object
    return MISS_PROMOTED
```

**Appendix B: Reproducibility Notes**
Code, deterministic synthetic experiments, and public-model trace-replay studies are available in the project repository under the `feature/srmic-x2-controller` branch. The current real-trace results correspond to `facebook/opt-125m`, `facebook/opt-350m`, and `facebook/opt-1.3b` replayed through `srmic`, `x2_admission`, and `x2_full`.
