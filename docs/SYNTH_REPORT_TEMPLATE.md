# SRMIC Synthesis Report

**Date:** YYYY-MM-DD
**Top Module:** srmic_top

## 1. Overview
This report captures the synthesis sanity checks performed on the SRMIC RTL prototype using Yosys.

## 2. Resource Statistics
| Resource Type | Count | Notes |
|---|---|---|
| Total Cells | [insert] | Excludes memory macros |
| Estimated Area Proxy | [insert] | Generic techmap logic elements |
| Flip-flops (DFFs) | [insert] | Total sequential state |

## 3. Memory Inference
| Memory Structure | Size | Inferred Type |
|---|---|---|
| Promotion FIFO | 16 entries | [insert] |
| HRM Tag Array | 64 entries x 4 regions | [insert] |

## 4. Warnings and Exceptions
* **[Warning 1]**: (Explanation of why this warning is acceptable, e.g., unused debug ports).
* **[Warning 2]**: ...

## 5. Prototype Limitations
* SRAM Macros: The `hrm_region` tag array and valid bits are currently inferred as registers. In a production ASIC flow, these must be mapped to high-density SRAM macros via a technology-specific wrapper.
* Mesh Scalability: The current top-level instantiates a small mesh segment. Scaling to the full 32+ region architecture will require hierarchical synthesis partitioning.
