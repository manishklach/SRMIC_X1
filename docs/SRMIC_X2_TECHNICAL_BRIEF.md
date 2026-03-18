# SRMIC-X2 Technical Brief: Collision-Aware Residency Control

## 1. Overview
SRMIC-X2 is an intelligent control-plane upgrade for the SRMIC inference accelerator. While X1 proved the feasibility of SRAM-backed decode acceleration, X2 provides the "Intelligence Layer" required to manage distributed memory hotspots at scale.

## 2. Microarchitectural Components

### 2.1 The Remap CAM (Fast-Path)
A 256-entry Content Addressable Memory (CAM) provides $O(1)$ overrides to the default static hash function. This allows the controller to move a tensor from a congested region to a cold region without modifying the model's global address space.

### 2.2 Regret-Aware Admission (Secondary Tier)
Unlike standard caches that promote on every miss, the RIC-X2 estimates the **Utility** of the resident victim vs. the incoming object. If the "Regret Gap" is too high, the controller serves the request from HBM, preserving the high-value residency.

### 2.3 Selective Replication (Tertiary Tier)
For "Ultra-Hot" tensors (e.g. KV-cache roots or specific Attention heads), the controller creates a bounded number of clones in alternate regions.
- **Pressure-Aware Routing:** The controller dynamically routes hits to the region with the lowest current utilization among all copies.

## 3. Why This Matters for Hyperscalers
Current LLM serving at batch=1 is strictly HBM-bound. Brute-force SRAM scaling is area-prohibitive. SRMIC-X2 allows a fixed SRAM budget to achieve **90%+ effective hit rates** by ensuring that every byte of SRAM is utilized efficiently, regardless of the model's internal hashing characteristics.

**Strategic Value:** This controller intelligence is high-value IP that is difficult to replicate with software-only solutions or generic cache controllers.
