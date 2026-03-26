---
layout: default
title: SRMIC Hardware Config — Current Support, Scale-Out Path, and Residency Tier Sizing
description: SRMIC hardware configuration page covering the current distributed SRAM residency architecture, compact published baseline, scale-out path to larger HRM tiers, and forward-looking chipletized hardware direction for LLM decode acceleration.
---

# Hardware Config

## Hardware Config Overview

SRMIC’s core claim is architectural, not cosmetic: if decode is memory-bound, then package topology and residency organization matter directly. The hardware configuration therefore deserves its own top-level treatment rather than being buried inside the general architecture overview.

This page distinguishes three things explicitly:

1. what the current public SRMIC material supports today,
2. which larger configurations are structurally justified by the architecture and should scale next,
3. which hardware directions are forward-looking and still require additional quantitative validation.

<div class="metric-strip">
  <div class="metric-card">
    <span class="metric-label">Current Published Chiplet Sketch</span>
    <span class="metric-value">4 × 4</span>
  </div>
  <div class="metric-card">
    <span class="metric-label">Published Regions</span>
    <span class="metric-value">16</span>
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

## What the Current Architecture Supports

The current public SRMIC repository already describes a hardware organization with clear structural implications:

<div class="support-grid">
  <div class="support-card">
    <h3>Distributed Residency Regions</h3>
    <p>The architecture is built around HRM residency regions rather than a single shared SRAM slab. The public material already treats those regions as first-class service units.</p>
  </div>
  <div class="support-card">
    <h3>Chiplet Partitioning</h3>
    <p>The published hardware assumptions already decompose the package into chiplets and regions, which is the correct abstraction for scale-out packaging.</p>
  </div>
  <div class="support-card">
    <h3>Local Service to Adjacent Compute</h3>
    <p>Each region serves its local partition of active weights to adjacent tensor clusters. Hits are meant to stay local rather than forcing unnecessary global-fabric traversal.</p>
  </div>
  <div class="support-card">
    <h3>Per-Region Parallelism</h3>
    <p>The corrected v20 modeling statement is explicit: HRM service time is modeled per region, regions operate independently in parallel, and decode-step memory time is governed by the slowest active tier.</p>
  </div>
  <div class="support-card">
    <h3>Tiered Memory Hierarchy</h3>
    <p>SRMESH is the package fabric. HBM is the colder miss tier. CXL is the outer pooled warm tier. That hierarchy is already present in the public architecture description.</p>
  </div>
  <div class="support-card">
    <h3>Modular, Not Monolithic</h3>
    <p>Nothing in the public SRMIC framing depends on a single fixed die-size assumption. The architecture is already regional, modular, and chipletizable by construction.</p>
  </div>
</div>

## Current Published Compact Baseline

The current public repository contains a compact illustrative baseline that should be stated plainly:

| Attribute | Current Published Compact Baseline |
|---|---|
| Chiplets | 4 |
| Regions per chiplet | 4 |
| Total HRM regions | 16 |
| SRAM per region | 128 MB |
| Total HRM capacity | 2 GB |
| HBM aggregate bandwidth | 24,000 GB/s |
| SRMESH aggregate bandwidth | 48,000 GB/s |
| CXL bandwidth | 64 GB/s |
| Tensor clusters | 128 |

<div class="note-box">
  <h3>Compact Baseline, Not the Full Hardware Story</h3>
  <p>This 16-region, 2 GB HRM package is useful as a published analytical anchor. It is small enough to make the current model legible and concrete. It should not, however, be treated as the long-range public hardware story for SRMIC.</p>
</div>

## Why the Architecture Can Scale

The reason SRMIC can responsibly discuss larger hardware configurations is not wishful thinking. It is a consequence of how the public model is already structured.

<div class="fact-grid">
  <div class="fact-card">
    <h3>Per-Region Service Model Already Exists</h3>
    <p>The model does not treat HRM as one serial global pipe. The v20 correction explicitly models service time per region, which is exactly the form needed for regional scale-out reasoning.</p>
  </div>
  <div class="fact-card">
    <h3>Independent Parallel Regions</h3>
    <p>Because regions operate independently in parallel, scaling the residency layer is naturally expressed as more regions, larger regions, or both.</p>
  </div>
  <div class="fact-card">
    <h3>Locality-First Decode Service</h3>
    <p>The public description already says regional hits do not require global-fabric traversal. That locality-preserving property is what makes increased regionalization meaningful rather than merely decorative.</p>
  </div>
  <div class="fact-card">
    <h3>Chiplet-Region Decomposition Is the Right Abstraction</h3>
    <p>The package is already described in chiplets and regions. That decomposition is inherently more scalable than a monolithic SRAM island.</p>
  </div>
  <div class="fact-card">
    <h3>SRMESH-to-HBM Ratio Is a Governing Invariant</h3>
    <p>The public repository states the key invariant directly: <code>SRMESH_BW &gt;= HBM_BW</code>. With the current published ratio at 48 TB/s vs 24 TB/s, the architecture is already framed around protecting a high-bandwidth residency path as capacity scales.</p>
  </div>
  <div class="fact-card">
    <h3>Public Breadcrumbs Already Point Larger</h3>
    <p>The runtime validation section references a distributed 64-region HRM direction, and the README also states that a larger 32-node architecture is described in the whitepaper. That does not prove a finished 64 GB product, but it does show the architecture is already conceived beyond the smallest illustrative package.</p>
  </div>
</div>

## Near-Term Scale-Out Configurations

The following ladder is the defensible scale-out path implied by the current architecture. These are not all equally validated today, but they are not arbitrary either. Each one preserves the same residency-first thesis: regional parallelism, locality-first service, and bandwidth protection via SRMESH.

<div class="config-ladder">
  <div class="config-card">
    <div class="badge badge-low">Low Risk</div>
    <h3>Scale-Out A: 8 GB HRM</h3>
    <p class="config-meta">4 chiplets × 4 regions/chiplet × 512 MB/region</p>
    <p>This is the lowest-risk upscale from the published compact baseline. It preserves the same 16-region package topology while moving each region to a materially larger residency capacity.</p>
    <ul>
      <li>Architectural basis: same chiplet count, same regional decomposition, larger per-region working residency.</li>
      <li>Why it should work: it changes capacity without forcing a new control abstraction.</li>
      <li>Positioning: a practical near-term enlargement of the current public package story.</li>
    </ul>
  </div>
  <div class="config-card">
    <div class="badge badge-low">Strong Near-Term</div>
    <h3>Scale-Out B: 16 GB HRM</h3>
    <p class="config-meta">4 chiplets × 8 regions/chiplet × 512 MB/region</p>
    <p>This configuration doubles regionalization while keeping per-region capacity moderate. It is the first scale-out that begins to look like a serious residency layer rather than a compact analytical package.</p>
    <ul>
      <li>Architectural basis: more independent service regions with the same package-level residency thesis.</li>
      <li>Why it should work: the public model already reasons in terms of per-region parallel service and chiplet-region partitioning.</li>
      <li>Positioning: a strong near-term scale-out that still sits close to the current architectural framing.</li>
    </ul>
  </div>
  <div class="config-card">
    <div class="badge badge-medium">Recommended Public Baseline</div>
    <h3>Scale-Out C: 32 GB HRM</h3>
    <p class="config-meta">4 chiplets × 8 regions/chiplet × 1 GB/region</p>
    <p>This is the recommended serious public baseline direction. At this point SRMIC reads correctly as a large residency tier designed to absorb a meaningful decode working set, not as a small SRAM adjunct.</p>
    <ul>
      <li>Architectural basis: retains the regional/chiplet abstraction while substantially increasing useful residency capacity.</li>
      <li>Why it should work: it remains consistent with the region-parallel model and the broader public direction toward more regionalization.</li>
      <li>Positioning: the best public baseline for presenting SRMIC as a credible large-tier residency architecture.</li>
    </ul>
  </div>
  <div class="config-card">
    <div class="badge badge-future">Future-Facing</div>
    <h3>Scale-Out D: 64 GB HRM</h3>
    <p class="config-meta">8 chiplets × 8 regions/chiplet × 1 GB/region</p>
    <p>This is a plausible forward target rather than a fully proven public hardware baseline. It aligns with the architecture’s modular direction and with the repo’s own breadcrumbs toward broader regionalization.</p>
    <ul>
      <li>Architectural basis: continued chiplet replication and regional scaling under the same locality-first service model.</li>
      <li>Why it should work conceptually: the architecture is already modular by region and chiplet rather than bound to one fixed compact layout.</li>
      <li>Positioning: a forward-looking scale target that should remain explicitly marked as future-facing.</li>
    </ul>
  </div>
</div>

| Configuration | Capacity | Architectural Reading | Public Position |
|---|---:|---|---|
| Scale-Out A | 8 GB | Direct enlargement of the compact package | Lowest-risk upscale |
| Scale-Out B | 16 GB | Stronger regional residency tier with more service units | Strong near-term scale-out |
| Scale-Out C | 32 GB | Large residency layer consistent with SRMIC’s thesis | Recommended public baseline |
| Scale-Out D | 64 GB | Aggressive multi-chiplet extension of the same abstraction | Plausible future-facing target |

## Recommended Public Baseline and Forward Vision

The recommended public baseline direction for SRMIC should be **32 GB HRM**, with **64 GB+ HRM** presented as the forward scaling vision.

<div class="tier-summary">
  <h3>Recommended Positioning</h3>
  <p><strong>Recommended public baseline:</strong> 32 GB HRM.</p>
  <p><strong>Forward scaling vision:</strong> 64 GB+ HRM.</p>
  <p>32 GB is the right baseline because it communicates SRMIC as a substantive residency layer for decode acceleration, not a token SRAM scratch tier. 64 GB+ is consistent with the architecture’s modular direction, but should remain clearly framed as a strategic scale target rather than a finished public product claim.</p>
</div>

This framing is more faithful to the architecture:

1. it reflects SRMIC as a large on-package residency tier,
2. it preserves the region-first and chiplet-first organization already present in the public model,
3. it separates current support from future quantitative validation.

## What Is Not Yet Proven

The current public repository does **not** yet prove a finalized physical 32–64 GB package implementation.

It also does not yet quantify several scale-sensitive effects that matter more as the architecture grows:

<div class="support-grid">
  <div class="support-card">
    <h3>Contention and Banking Effects</h3>
    <p>The public analytical model does not yet include SRAM bank conflicts or detailed fabric arbitration behavior.</p>
  </div>
  <div class="support-card">
    <h3>Thermal and Sustained Bandwidth Effects</h3>
    <p>Thermal throttling and long-horizon sustained bandwidth behavior are explicitly listed as future modeling work.</p>
  </div>
  <div class="support-card">
    <h3>Multi-Tenant Residency Pressure</h3>
    <p>The current public quantitative story does not yet model multi-tenant HRM pressure or QoS-sensitive allocation under shared load.</p>
  </div>
  <div class="support-card">
    <h3>Long-Context and Prefetch Effects</h3>
    <p>KV growth at long context and prefetch effectiveness are also outside the current first-order public model.</p>
  </div>
</div>

These are future validation tasks, not contradictions. The right interpretation is: the structural scale-out story is already credible, while the second-order package effects still need more explicit public quantification.

## Modeling Note

<div class="disclaimer-box">
  <p><strong>Modeling Note:</strong> The current public SRMIC quantitative values are first-order architectural assumptions used to reason about topology, residency crossover behavior, and decode bottlenecks. They are useful for comparative hardware planning, but they are not a finalized silicon product specification or a cycle-accurate package signoff.</p>
</div>

[Back to Architecture →]({{ '/architecture/' | relative_url }})  
[View Performance Evaluation →]({{ '/results/' | relative_url }})
