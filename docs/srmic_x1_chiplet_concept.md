---
layout: default
title: Chiplet Concept Study | SRMIC-X1
---

# SRMIC-X1 Chiplet Concept Study: Distributed SRAM Scaling

## 1. Overview
The SRMIC-X1 architecture is designed for scalability. For ultra-large models (70B+), a single die may not provide sufficient SRAM capacity. This concept study explores an interconnect-aware distributed SRAM tier across multiple dies.

## 2. Theoretical Scaling
The SRMESH fabric is scaled across a 4-chiplet MCM (Multi-Chip Module).

### Scaled Architecture Goals:
*   **Memory Footprint:** 1.0–2.0 GB of aggregate on-package SRAM.
*   **Inter-Die Bandwidth:** 2,048 GB/s low-latency die-to-die (D2D) fabric.
*   **Scale:** Support for dense LLMs up to 175B parameters.

## 3. Fabric Interconnect (SRMESH-D2D)
To maintain the residency-first advantage, the inter-die fabric must minimize latency for cross-chiplet HRM hits. 

| Feature | Target |
| :--- | :--- |
| **Bisection BW** | 2,048 GB/s |
| **Hop Latency** | < 10ns incremental |
| **Topology** | 2D Mesh or Ring |

## 4. Multi-Chiplet Residency Management
Future iterations will introduce QoS-aware residency management across the multi-die mesh.
