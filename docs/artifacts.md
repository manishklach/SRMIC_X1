---
layout: default
title: Technical Artifacts | SRMIC Documentation
---

# Technical Artifacts

The SRMIC project provides a structured range of technical documentation, from high-level architectural whitepapers to low-level formal specifications and experimental studies.

## Core System & Publications
Materials defining the primary residency-first architectural framework.

<div class="artifact-card">
  <span class="label label-current">Whitepaper</span>
  <h3>SRMIC Architecture Whitepaper (30 Pages)</h3>
  <p>The primary deep-dive into the SRMIC philosophy, detailing the distributed SRAM mesh and regional fabric interconnects.</p>
  <a href="{{ '/assets/pdfs/SRMIC_Architecture_Whitepaper_30pg.pdf' | relative_url }}" class="btn">Download PDF</a>
</div>

<div class="artifact-card">
  <span class="label label-spec">Technical Specification</span>
  <h3>SRMIC Integrated Architecture Spec (v2.0)</h3>
  <p>Detailed interface definitions, register maps, and subsystem requirements for the baseline v2.0 hardware implementation.</p>
  <a href="{{ '/assets/pdfs/SRMIC_X1_Integrated_Architecture_Spec_v2_0.pdf' | relative_url }}" class="btn">Download PDF</a>
</div>

<div class="artifact-card">
  <span class="label label-spec">Hardware Addendum</span>
  <h3>SRMIC Hardened Architecture Addendum</h3>
  <p>A technical supplement focusing on fabric justification, power breakdowns, and physical area estimates for the 64GB HRM configuration.</p>
  <a href="{{ '/srmic_x1_v2_0_hardened_addendum/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

---

## Experimental & Formal Artifacts
Technical validation materials and experimental logic enhancements.

<div class="artifact-card">
  <span class="label label-spec">Formal Artifact</span>
  <h3>SRMIC Formal Specification (TLM)</h3>
  <p>A Transaction-Level Model (TLM) used for verifying residency invariants and ensuring deterministic state transitions.</p>
  <a href="{{ '/srmic_x1_formal_spec/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

<div class="artifact-card">
  <span class="label label-current">Experimental Tier</span>
  <h3>RIC-X2 Residency Intelligence Summary</h3>
  <p>Analysis of the dynamic control plane enhancements, including reactive remapping and regret-aware admission control.</p>
  <a href="{{ '/srmic_x2_executive_summary/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

<div class="artifact-card">
  <span class="label label-current">Experimental Tier</span>
  <h3>RIC-X2 Microarchitecture Deep-Dive</h3>
  <p>Detailed logic for the associative remap CAMs and the pressure-aware routing heuristics used in the X2 tier.</p>
  <a href="{{ '/srmic_x2_microarchitecture/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

---

## Future Scaling Concepts
Research studies into the long-term extensibility of the SRMIC architecture.

<div class="artifact-card">
  <span class="label label-concept">Future Scaling Concept</span>
  <h3>SRMIC Chiplet Concept Study</h3>
  <p>A theoretical scaling analysis of the SRMESH fabric across multi-die MCM (Multi-Chip Module) topologies for ultra-large models.</p>
  <a href="{{ '/srmic_x1_chiplet_concept/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

[View Project Roadmap →]({{ '/roadmap/' | relative_url }})
