---
layout: default
title: SRMIC | Residency-First LLM Inference Architecture
---

<div class="hero">
  <h1>Residency-First LLM Inference</h1>
  <p class="hero-p">Eliminating the HBM bottleneck in Large Language Model decode via distributed on-package SRAM and real-time residency intelligence.</p>
  <div class="hero-btns">
    <a href="{{ '/architecture/' | relative_url }}" class="btn">Explore Architecture</a>
    <a href="{{ '/artifacts/' | relative_url }}" class="btn btn-secondary">Download Whitepapers</a>
  </div>
</div>

<div class="disclaimer-box">
  <p><strong>Modeling Scope:</strong> This project represents an analytical simulation and first-order latency model. It is designed for architectural exploration and bottleneck analysis, rather than cycle-accurate RTL verification.</p>
</div>

## What is SRMIC?

**SRMIC** (SRAM-centric Residency-first Memory-centric Inference) is a next-generation systems architecture designed to break the memory-bandwidth wall in Large Language Model (LLM) serving. 

Unlike conventional GPUs that rely on high-latency HBM fetches for every token generated, SRMIC prioritizes **weight residency** in a distributed, on-package SRAM tier (HRM). By keeping the model's active working set resident in fast SRAM, we enable ultra-low latency inference and massive throughput scaling that traditional memory hierarchies cannot match.

---

## The Problem: The HBM Bottleneck

Large Language Model (LLM) decode is **memory-bound, not compute-bound**. For each generated token, a bounded working set of weights must be fetched from memory. On conventional architectures, this working set lives in HBM. HBM bandwidth — not arithmetic throughput — determines decode latency and token-to-token jitter.

## The Solution: SRMIC

SRMIC proposes a distributed on-package SRAM layer (HRM) connected via a high-bandwidth regional fabric (SRMESH) to absorb HBM pressure on the critical decode path.

### Core Architecture Highlights

*   **HRM (Hybrid Residency Memory):** Distributed SRAM regions operating in parallel to serve active weights.
*   **SRMESH Fabric:** A massive aggregate bandwidth fabric (up to 48,000 GB/s) connecting HRM to tensor clusters.
*   **Residency Intelligence (RIC-X2):** A dynamic control plane that monitors regional telemetry and overrides placement decisions to maximize hit rates.

---

## Why Residency-First Matters

By prioritizing weight residency in fast SRAM, SRMIC achieves:
1.  **Lower Latency:** Dramatic reduction in token-to-token generation time.
2.  **Increased Throughput:** Offloading the HBM tier allows for higher concurrency across regions.
3.  **TCO Optimization:** High-performance inference on smaller, more efficient silicon footprints.

<div class="figure">
  <img src="{{ '/assets/images/studies/70b/70b_latency_vs_hrm.png' | relative_url }}" alt="70B Model Latency vs HRM Capacity">
  <p class="figcaption">Figure 1: Impact of HRM capacity on 70B model decode latency proxy. SRMIC-X2 maintains performance even at constrained SRAM capacities.</p>
</div>

[Explore the Project Roadmap →]({{ '/roadmap/' | relative_url }})
