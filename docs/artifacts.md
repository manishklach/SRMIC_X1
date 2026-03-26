---
layout: default
title: Technical Artifacts | SRMIC
---

# Technical Artifacts

The SRMIC project provides a structured range of technical documentation, from high-level whitepapers to low-level formal specifications.

## 1. Primary Whitepaper
The authoritative deep-dive into the residency-first architectural philosophy.

<div class="artifact-card">
  <span class="label label-current">Whitepaper</span>
  <h3>SRMIC Architecture Whitepaper (30 Pages)</h3>
  <p>Comprehensive systems analysis of the SRMIC memory-centric architecture, regional fabric design, and HRM tier.</p>
  <a href="{{ '/assets/pdfs/SRMIC_Architecture_Whitepaper_30pg.pdf' | relative_url }}" class="btn">Download PDF</a>
</div>

---

## 2. Technical Specifications
Formal documentation for the current modeled hardware baseline.

<div class="artifact-card">
  <span class="label label-spec">System Spec</span>
  <h3>SRMIC Integrated Architecture Spec (v2.0)</h3>
  <p>Interface definitions, register maps, and subsystem requirements for the baseline v2.0 implementation.</p>
  <a href="{{ '/assets/pdfs/SRMIC_X1_Integrated_Architecture_Spec_v2_0.pdf' | relative_url }}" class="btn">Download PDF</a>
</div>

<div class="artifact-card">
  <span class="label label-spec">Formal Spec</span>
  <h3>SRMIC Formal Specification (TLM)</h3>
  <p>Transaction-level model (TLM) used for architectural verification and RTL-equivalence checking.</p>
  <a href="{{ '/srmic_x1_formal_spec/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

---

## 3. Residency Intelligence (SRMIC-X2)
Experimental artifacts for the dynamic intelligence tier and the RIC-X2 controller.

<div class="artifact-card">
  <span class="label label-current">Experimental</span>
  <h3>RIC-X2 Executive Summary</h3>
  <p>A high-level overview of the Residency Intelligence Controller and its impact on load balancing.</p>
  <a href="{{ '/srmic_x2_executive_summary/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

<div class="artifact-card">
  <span class="label label-current">Experimental</span>
  <h3>RIC-X2 Microarchitecture Deep-Dive</h3>
  <p>Details on the remap CAM, utility-gated admission logic, and pressure-aware routing.</p>
  <a href="{{ '/srmic_x2_microarchitecture/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

---

## 4. Future Scaling Concepts
Research studies into the long-term scalability of the SRMIC architecture.

<div class="artifact-card">
  <span class="label label-concept">Concept Study</span>
  <h3>SRMIC Chiplet Concept Study</h3>
  <p>Theoretical scaling analysis of the SRMESH fabric across a multi-chiplet MCM (Multi-Chip Module).</p>
  <a href="{{ '/srmic_x1_chiplet_concept/' | relative_url }}" class="btn btn-secondary">Read Online</a>
</div>

[View Project Roadmap →]({{ '/roadmap/' | relative_url }})
