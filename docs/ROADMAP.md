---
layout: default
title: SRMIC Project Roadmap | Future Scaling
---

# Project Roadmap

The SRMIC architecture is designed to evolve alongside LLM model size and deployment complexity. 

## 1. SRMIC-X2 Integration (Q3 2026)
Moving the **RIC-X2 intelligence tier** from synthetic-trace validation to full RTL integration. This includes:
*   **Hardware CAM Hardening:** Finalizing the area/power profile for the associative remap tables.
*   **Utility Calibration:** Developing per-model family "admission weights" to optimize hit rates for 7B–70B+ model families.

## 2. Chiplet-Based Scaling Concept
For ultra-large models (70B+), a single die may not provide sufficient SRAM capacity. The **SRMIC Chiplet Concept** proposes an interconnect-aware distributed SRAM tier across multiple dies.

<div class="artifact-card">
  <span class="label label-concept">Concept</span>
  <h3>SRMIC Chiplet Concept Study</h3>
  <p>Theoretical scaling of the SRMESH fabric across a 4-chiplet MCM (Multi-Chip Module).</p>
  <a href="https://github.com/manishklach/SRMIC_X1/blob/master/SRMIC_X1_Chiplet_Concept.md" class="btn btn-secondary">Read Study</a>
</div>

### Scaled Architecture Goals:
*   **Memory Footprint:** 1.0–2.0 GB of aggregate on-package SRAM.
*   **Inter-Die Bandwidth:** 2,048 GB/s low-latency die-to-die (D2D) fabric.
*   **Scale:** Support for dense LLMs up to 175B parameters.

## 3. Multi-Tenant Residency Management
Future iterations will introduce **QoS-aware residency**. In multi-tenant environments, the RIC-X2 will prioritize the working sets of high-priority request streams, ensuring predictable token-to-token generation times even under shared resource contention.

## 4. Software Stack Integration (SRMIC Runtime)
Development of a native **SRMIC-Aware Compiler** to automatically partition and schedule model weights into the HRM tier. This will eliminate the need for manual architectural tuning and provide a seamless "drop-in" experience for existing PyTorch/JAX models.

[Back to Home →]({{ '/' | relative_url }})
