# SRMIC-X2 Figure and Visualization Plan

This plan outlines the visual assets required to support the SRMIC-X2 preprint, technical briefs, and strategic pitch decks.

| # | Figure Title | Purpose | Data Source | Usage | Priority |
|---| :--- | :--- | :--- | :--- | :--- |
| 1 | **X1 vs X2 Architecture Delta** | Highlight the new RIC-X2 block and Remap CAM. | Architectural Block Diagram | README / Tech Brief | **P0** |
| 2 | **The "Hero" Occupancy Heatmap** | Visually demonstrate load balancing (Stripe Reduction). | `sim_x2` Snapshot Trace | README / Buyer Memo | **P0** |
| 3 | **Per-Access Decision Flow** | Document the logic from request to Hit/Bypass/Promote. | `controller.py` logic | Technical Brief / Preprint | **P0** |
| 4 | **The Collision Ceiling** | Graph showing X1 hit-rate plateauing vs X2 climbing. | `results/x2_full/` | Preprint / Brief | **P1** |
| 5 | **Regret-Aware Utility Visual** | Illustrate how Access Count and Age combine into a score. | `ric_x2/admission.py` | Technical Brief | **P1** |
| 6 | **Thrash Reduction Bar Chart** | Compare "Rapid Re-access" events across X1, X2-Remap, X2-Full. | `experiments/run_x1_vs_x2.py`| Results Summary | **P1** |
| 7 | **Selective Replication Fanout** | Show one hot tensor mapping to multiple physical regions. | `ric_x2/replication.py` | Patent Docs / Brief | **P2** |
| 8 | **Latency Proxy Waterfall** | Breakdown of cycle gains from Remap vs Admission vs Replication. | `replication_eval.py` | Results Summary | **P1** |
| 9 | **Workload Sensitivity Matrix** | Heatmap showing X2 mechanism performance across trace families. | `results/x2_stress_test/` | Preprint | **P2** |
| 10 | **CAM Utilization Curve** | Prove that 256 entries is sufficient for 7B models. | `telemetry/metrics.py` | Technical Brief | **P2** |

## Implementation Details for Priority Figures

### Fig 2: The "Hero" Heatmap
*   **Format:** 2-panel heatmap.
*   **X-Axis:** Token index (0-100).
*   **Y-Axis:** Region ID (0-63).
*   **Color:** Occupancy percentage (0-100%).
*   **Visual Goal:** X1 shows "Dark Stripes" (overloaded) and "White Space" (idle). X2 shows a uniform color block.

### Fig 4: The Collision Ceiling
*   **Format:** Line chart.
*   **X-Axis:** HRM Capacity (GB).
*   **Y-Axis:** Useful Hit Rate (%).
*   **Visual Goal:** X1 line flattens at 65%. X2 line continues a monotonic climb toward 95%.

### Fig 8: Latency Proxy Waterfall
*   **Format:** Waterfall chart.
*   **Bars:** [X1 Baseline] -> [Remap Gain] -> [Admission Gain] -> [Replication Gain] -> [SRMIC-X2 Total].
*   **Visual Goal:** Demonstrate the additive value of each intelligence tier.
