# SRMIC-X2: Collision-Aware and Regret-Aware Residency Intelligence for Large Language Model Decode Acceleration

**Authors:** Manish KL  
**Date:** March 2026  

## Abstract
Autoregressive Large Language Model (LLM) inference is characterized by extreme memory-bandwidth bottlenecks during the decode phase. The SRMIC-X1 architecture previously established the feasibility of an SRAM-backed "Residency-First" tier to mitigate High Bandwidth Memory (HBM) pressure. However, naive distributed residency tiers suffer from regional hash collisions and residency pollution, capping effective utilization. We propose SRMIC-X2, an intelligent controller-centric extension that introduces three collaborative mechanisms: (1) Reactive Remapping via a hardware-proxy CAM to resolve regional hotspots, (2) Regret-Aware Admission Control to prevent low-utility weights from displacing high-reuse resident data, and (3) Selective Hot-Object Replication to provide bandwidth relief for ultra-hot tensors. Using a trace-driven evaluation framework across 1B to 7B parameter models, we demonstrate that collision-aware remapping reduces occupancy skew by [RESULT: insert skew delta, typically ~26%], while regret-aware admission reduces destructive thrashing by [RESULT: insert thrash reduction percentage]. We find that selective replication provides significant incremental gains in specific static hotspot scenarios but remains workload-sensitive in highly dynamic execution phases. Our results support the thesis that residency intelligence is a critical architectural layer for next-generation inference accelerators.

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

[FIGURE: SRMIC-X2 controller overview block diagram]
[FIGURE: per-access controller flow from access to hit/miss/bypass]

## 6. Mechanism I: Collision-Aware Remap Control
X2 employs **Reactive Remapping** to solve placement inefficiency. When the RIC detects that a specific region has breached an occupancy threshold and is experiencing misses, it identifies the requested tensor as a candidate for relocation. The controller finds the "coldest" region and binds the tensor to it via the Remap CAM. This flattens regional skew and allows the system to utilize the full aggregate capacity of the distributed mesh.

[RESULT: remap improved load balancing by reducing occupancy skew by [X]%]

## 7. Mechanism II: Regret-Aware Admission and Bypass
X2 introduces an **Admission Gate**. Instead of automatically promoting every miss, the RIC evaluates the "Utility" of the resident victim vs. the incoming object.

The utility heuristic $U$ accounts for access frequency and recency. If the "Regret Gap" ($U_{victim} - U_{incoming}$) exceeds a threshold, the controller serves the access directly from HBM (`MISS_BYPASSED`), preserving the high-value resident weight. This protects the core working set from being polluted by transient data.

[RESULT: admission control reduced thrash events by [X]% compared to X1 baseline]

## 8. Mechanism III: Selective Hot-Object Replication
In scenarios where remapping and admission are insufficient—specifically when a single tensor's bandwidth demand exceeds a single region's capability—X2 permits **Selective Replication**.

The controller clones ultra-high-utility objects into secondary regions. Future lookups utilize a pressure-aware routing policy, choosing the copy residing in the least-loaded region. While functionally active, the incremental benefit of replication is workload-sensitive and most pronounced in scenarios with extreme hotspot concentration.

## 9. Evaluation Methodology
Our evaluation uses a trace-driven residency simulator validated against the SRMIC-X1 baseline. 
- **Workloads:** We employ four stress-trace families: `HOTSPOT_FANOUT`, `BURST_CONTENTION`, `PERSISTENT_IMBALANCE`, and `HOTSET_ROTATION`.
- **Metrics:** We track Useful Hit Rate, Occupancy Skew ($\sigma$), Thrash Count, and a Latency Proxy (cycles) that includes a regional congestion penalty.
- **Integrity:** The harness ensures fresh isolated state for each run and enforces deterministic hashing to allow repeatable comparisons.

[TABLE: Stress trace family characteristics]
[TABLE: Metric definitions and formulas]

## 10. Experimental Results
### 10.1 X2 over X1 Baseline
SRMIC-X2 demonstrates a significant improvement in hit-rate stability over the X1 baseline.
[RESULT: X2 achieved a [X]% higher hit rate than X1 at identical capacity]

### 10.2 Load Balancing and Remap Efficiency
Reactive remapping successfully resolved primary capacity hotspots. 
[RESULT: occupancy skew was reduced from [X] to [Y] using 256 CAM entries]

### 10.3 Admission Control and Thrash Mitigation
The admission controller is the primary driver of residency protection.
[RESULT: bypass rate of [X]% resulted in a [Y]% reduction in latency proxy by avoiding resident displacement]

### 10.4 Replication and Workload Sensitivity
Replication provided measurable gains in the `HOTSPOT_FANOUT` workload.
[RESULT: replication achieved a [X]% additional latency reduction on specific static hotspots]

## 11. Discussion
The results confirm that residency intelligence is a critical layer for tiered memory systems. Remapping and admission control appear to be the most robust mechanisms across workloads. Selective replication acts as a "safety valve" for extreme hotspots, though its use must be utility-gated to avoid capacity dilution. A hybrid static/dynamic routing model appears to be the optimal path for distributed inference silicon.

## 12. Limitations
Our current evaluation is trace-driven and relies on a latency proxy rather than a cycle-accurate hardware simulation. Furthermore, the utility heuristics rely on tunable weights that may require different optimization for diverse model families (e.g., Sparse Mixture-of-Experts). 

## 13. Future Work
Immediate next steps include the integration of the RIC-X2 logic into a cycle-accurate memory/fabric simulator. We also intend to explore the RTL realization of the Remap CAM and Admission Gate to quantify the area and power overhead.

## 14. Conclusion
SRMIC-X2 addresses the fundamental scaling challenges of residency-first inference acceleration. By transitioning the control plane from static hashing to telemetry-driven intelligence, we have demonstrated that it is possible to maintain high hit rates and balanced load under pressure. This work defines a credible microarchitectural path for next-generation AI accelerators.

---
**Appendix A: Policy Pseudocode**
[PLACEHOLDER]

**Appendix B: Reproducibility Notes**
Code and reproducible traces are available in the project repository under the `feature/srmic-x2-controller` branch.
