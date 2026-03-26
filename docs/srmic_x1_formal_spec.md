# SRMIC-X1 Formal Architecture Specification

## 1. Product Definition

**Name:** SRMIC-X1\
**Class:** Residency-First Inference Accelerator\
**Primary Workload:** Decode-heavy LLM serving (13B--70B models)

SRMIC-X1 is designed to reduce HBM bottlenecks during transformer decode
by serving the active per-token working set from distributed on-package
SRAM regions connected by a high-bandwidth fabric.

------------------------------------------------------------------------

## 2. Target Envelope (Ambitious Configuration)

  Parameter          Target
  ------------------ ------------------------------------
  Package Class      Multi-chiplet, advanced interposer
  Target Power       800--1200 W
  HBM Bandwidth      24 TB/s
  SRMESH Bandwidth   48--72 TB/s
  HRM Total Size     32 GB
  HRM Regions        32
  HRM per Region     1 GB
  Compute Chiplets   4
  Tensor Clusters    128--256 total
  CXL Warm Tier      64--256 GB/s

------------------------------------------------------------------------

## 3. Memory Hierarchy

### Tier 0 -- Local Execution Storage

Registers, local SRAM, tensor staging buffers

### Tier 1 -- HRM (Hot Residency Memory)

32 GB distributed SRAM across 32 regions

### Tier 2 -- HBM

Primary cold and overflow model storage

### Tier 3 -- CXL Warm Tier

Large-model assist and cold-page staging

------------------------------------------------------------------------

## 4. Architectural Invariants

1.  SRMESH bandwidth must exceed HBM bandwidth.
2.  Per-region working set is bounded by model partitioning.
3.  Decode-critical traffic must terminate in HRM when possible.
4.  CXL cold pulls must remain bounded by page-window limits.
5.  Peak performance saturates when HRM fully covers active working set.

------------------------------------------------------------------------

## 5. Expected Performance

  Model                  Expected Speedup
  ---------------------- -------------------------------
  13B                    1.3--1.6×
  70B                    1.7--2.0×
  Larger staged models   Up to bandwidth ratio ceiling

Peak speedup ≈ SRMESH_BW / HBM_BW

------------------------------------------------------------------------

## 6. Design Intent

SRMIC-X1 is not a general GPU replacement.\
It is a decode-optimized inference accelerator designed for low-latency
memory-bound transformer workloads.

------------------------------------------------------------------------

## 7. Roadmap Phases

Phase A -- Architecture lock\
Phase B -- Area & power feasibility\
Phase C -- Chiplet interface definition\
Phase D -- Extended simulation & contention modeling\
Phase E -- IP & positioning
