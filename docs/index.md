---
layout: default
title: SRMIC | Residency-First LLM Inference Architecture
description: SRMIC is a residency-first SRAM-centric architecture for LLM decode acceleration, combining distributed HRM regions, SRMESH fabric, and a scale-out path toward larger on-package residency tiers.
---

<div class="hero">
  <div class="eyebrow">Residency-First Decode Architecture</div>
  <h1>SRMIC</h1>
  <p class="hero-p">A residency-first SRAM-centric architecture for reducing HBM bottlenecks in LLM decode.</p>
  <div class="hero-btns">
    <a href="{{ '/architecture/' | relative_url }}" class="btn">Explore Architecture</a>
    <a href="{{ '/hardware_config/' | relative_url }}" class="btn btn-secondary">Hardware Config</a>
    <a href="{{ '/artifacts/' | relative_url }}" class="btn btn-secondary">Technical Artifacts</a>
  </div>
</div>

<div class="disclaimer-box">
  <p><strong>Modeling Scope:</strong> SRMIC is an analytical simulation and first-order latency model designed for architectural exploration and bottleneck analysis. It is not a cycle-accurate RTL simulator.</p>
</div>

<div class="metric-strip">
  <div class="metric-card">
    <span class="metric-label">Current Published Baseline</span>
    <span class="metric-value">16 Regions</span>
  </div>
  <div class="metric-card">
    <span class="metric-label">Illustrative Package</span>
    <span class="metric-value">4 Chiplets</span>
  </div>
  <div class="metric-card">
    <span class="metric-label">HBM Aggregate BW</span>
    <span class="metric-value">24 TB/s</span>
  </div>
  <div class="metric-card">
    <span class="metric-label">SRMESH Aggregate BW</span>
    <span class="metric-value">48 TB/s</span>
  </div>
</div>

## What is SRMIC?

**SRMIC** (SRAM-centric Residency-first Memory-centric Inference) is a systems architecture designed to break the memory-bandwidth wall in Large Language Model (LLM) serving. 

SRMIC reduces decode-path HBM bottlenecks by keeping the active per-token weight working set in a distributed on-package SRAM layer (HRM) connected via a high-bandwidth regional fabric (SRMESH). By prioritizing weight residency in fast SRAM, SRMIC enables ultra-low latency inference and improved memory-path utilization.

<div class="fact-grid">
  <div class="fact-card">
    <h3>Residency Tier</h3>
    <p>SRMIC organizes the active decode working set into distributed HRM regions rather than treating SRAM as a tiny adjunct cache.</p>
  </div>
  <div class="fact-card">
    <h3>Package Fabric</h3>
    <p>SRMESH is modeled as the high-bandwidth on-package path that keeps hits local and limits HBM exposure on the critical decode path.</p>
  </div>
  <div class="fact-card">
    <h3>Scale Direction</h3>
    <p>The architecture is region- and chiplet-structured, which is why the hardware story is better described as a scale-out ladder than as a single fixed package.</p>
  </div>
</div>

---

## The Core Challenge: HBM Pressure

Large Language Model (LLM) decode is inherently **memory-bound**. For every token generated, the system must fetch a specific working set of weights. In conventional GPU architectures, this working set lives in HBM. HBM bandwidth — not arithmetic throughput — is the primary determinant of decode latency, power efficiency, and token-to-token jitter.

## The SRMIC Architecture

SRMIC introduces an intelligent residency tier between the compute clusters and HBM to absorb the critical path of decode traffic.

### Architectural Tiers
*   **SRMIC-X1 (Baseline):** A distributed on-package SRAM mesh (HRM) providing massive aggregate bandwidth (up to 48,000 GB/s) directly to tensor clusters.
*   **SRMIC-X2 (Intelligence):** A dynamic control plane (RIC-X2) that overrides static placement via residency telemetry, reactive remapping, and regret-aware admission control.
*   **Scale-Out Path:** [View Hardware Configurations and Sizing →]({{ '/hardware_config/' | relative_url }})
*   **Chiplet Concept (Future Scaling):** A roadmap for multi-die SRAM scaling to support 100B+ parameter models.

---

## Why Residency-First Matters

1.  **Latency Stability:** Reduces the impact of HBM contention on token generation.
2.  **Throughput Efficiency:** Offloading HBM allows for higher system-wide concurrency.
3.  **Architectural TCO:** Achieve flagship performance on more efficient, memory-centric silicon footprints.

<div class="figure">
  <img src="{{ '/assets/images/studies/70b/70b_latency_vs_hrm.png' | relative_url }}" alt="70B Model Latency vs HRM Capacity">
  <p class="figcaption">Figure 1: Analytical latency proxy scaling for 70B parameter models. SRMIC maintains performance even at constrained SRAM capacities.</p>
</div>

[View Detailed Results →]({{ '/results/' | relative_url }})
