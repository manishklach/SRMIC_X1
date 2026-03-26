# SRMIC-X1 v2.0 Hardened Addendum  
## Fabric Justification, SRAM Area Estimate, and Power Breakdown

This addendum strengthens three sections of the SRMIC-X1 flagship architecture specification:

1. **96 TB/s fabric justification**
2. **64 GB SRAM feasibility / area estimate**
3. **Power breakdown**

The goal is not to pretend the flagship package is easy. The goal is to show that the headline numbers are anchored in a defensible architectural decomposition.

---

# 1. 96 TB/s SRMESH-X Fabric Justification

The key clarification is that **96 TB/s is an internal aggregate service target**, not a claim that every byte crosses the full package backbone.

SRMIC-X1 has **64 logical HRM regions**. The fabric is hierarchical:

- **Level 1:** region-local / island-local service
- **Level 2:** island router fabric
- **Level 3:** package backbone

Most decode-critical accesses should terminate locally at Level 1 or Level 2. Only a subset of traffic crosses the package backbone.

## Back-of-envelope derivation

Assume each logical region exports **2 local data paths**, each with:

- **1024-bit width**
- **3.0 GHz fabric clock**
- **DDR-style transfer accounting (2 transfers/cycle)**

Per path bandwidth:

```text
1024 bits × 3.0 GHz × 2 = 6144 Gb/s
6144 Gb/s ÷ 8 = 768 GB/s
```

Per region bandwidth (2 paths):

```text
2 × 768 GB/s = 1536 GB/s = 1.536 TB/s
```

Across 64 logical regions:

```text
64 × 1.536 TB/s = 98.304 TB/s
```

So the **96 TB/s class target** is justified as a **region-level internal aggregate service budget**.

That is the right way to interpret the number.

## What this does *not* mean

It does **not** mean the chiplet-to-chiplet package backbone itself carries 96 TB/s of uniform all-to-all traffic. A more realistic split is:

- **Region-level internal aggregate service:** ~96 TB/s class
- **Island / quadrant aggregate routing:** materially lower
- **Package-crossing backbone bandwidth:** lower still, because most decode-critical traffic should remain local to a region or island

## Why this is architecturally valid

SRMIC-X1 is a residency-first architecture. If the working set is placed correctly:

- local region service dominates
- island-local fetches dominate next
- global cross-package movement is minimized

That is why it is correct to size **internal service bandwidth** much higher than **package-crossing bisection bandwidth**.

## Design implication

The real fabric requirement is not “build a flat 96 TB/s package crossbar.”

It is:

> build a hierarchy whose **effective hot-tier service bandwidth** materially exceeds HBM bandwidth, while keeping most decode-critical accesses local.

---

# 2. 64 GB SRAM Feasibility / Area Estimate

The architecture intentionally uses **64 GB minimum HRM** so that SRAM is the **primary execution substrate** for 70B-class decode rather than a marginal assist tier.

That said, 64 GB SRAM is a very large amount of on-package memory and must be treated honestly.

## Raw bitcell order-of-magnitude

64 GB = 512 Gbit.

For a high-density SRAM bitcell in an advanced logic-class process, a rough raw bitcell area range might be on the order of:

- **0.021–0.025 µm² per bit** (raw bitcell only, not full macro)

Raw bitcell area for 512 Gbit:

```text
512e9 bits × 0.021 µm² ≈ 10,752 mm² raw bitcell area
512e9 bits × 0.025 µm² ≈ 12,800 mm² raw bitcell area
```

This is **raw bitcell area only**.

Real SRAM macros require:

- wordline / bitline periphery
- redundancy / repair
- routing
- power grid
- control logic
- test structures

A realistic macro-level multiplier is often materially above raw bitcell area.

## Practical consequence

64 GB HRM is **not** a monolithic die story.

It is a:

- **macro-chiplet**
- **stacked SRAM tile**
- or **multi-die SRAM subsystem**

story.

That is exactly why SRMIC-X1 is framed as a flagship chiplet platform.

## Recommended physical realization

Keep the architecture at:

- **64 logical regions**
- **8 SRAM macro-chiplets**
- **8 GB logical capacity per macro-chiplet**

But implement each 8 GB macro-chiplet physically as a **stack or sub-assembly of smaller SRAM dice**.

A plausible decomposition is:

- **4 × 2 GB SRAM dice per macro-chiplet**, or
- **8 × 1 GB SRAM dice per macro-chiplet**

depending on process, yield, and bonding strategy.

## Startup-grade feasibility statement

The correct statement for technical conversations is:

> 64 GB HRM is ambitious but not contradictory. It requires aggressive macro-chiplet partitioning and likely stacked or subdivided SRAM implementation. This is a packaging challenge, not an architectural flaw.

## What should go in the main X1 spec

Add one explicit paragraph:

> SRMIC-X1 assumes 64 GB minimum HRM as a flagship target. This capacity is not intended for planar monolithic implementation. The credible realization path is 8 SRAM macro-chiplets or equivalent stacked SRAM islands, each exposing 8 logical regions. Physical implementation may use multiple smaller SRAM dice per macro-chiplet to manage yield, area, and leakage.

That keeps the ambition while making the feasibility story concrete.

---

# 3. Power Breakdown

The 1.0–1.5 kW package envelope must be supported by a rough breakdown. Without that, the thermal story feels underdeveloped.

Below is a first-order flagship estimate for SRMIC-X1.

## First-order package power budget

| Subsystem | Estimate (W) | Notes |
|---|---:|---|
| Compute chiplets | 450–650 W | 4 chiplets, tensor-heavy decode path |
| HBM stacks | 160–240 W | ~20–30 W per stack × 8 |
| HRM SRAM leakage | 150–300 W | strongly dependent on process, Vt mix, gating |
| HRM SRAM dynamic | 80–180 W | decode traffic, region activity, residency hit rate |
| SRMESH-X fabric + routers | 120–220 W | island routers, backbone movement, control overhead |
| Control / IO / CXL / misc | 40–80 W | runtime cores, management, PHY overhead |
| **Total** | **1000–1670 W** | targetable toward 1.0–1.5 kW with gating and optimization |

This is intentionally rough, but it is the right level for a flagship architecture discussion.

## Important implication

At 64 GB HRM, **leakage is first-order**.

That means the architecture should explicitly include:

- region-level power gating
- sub-array sleep modes
- decode-phase-aware wake-up policy
- cold-hot residency submodes

Without those, the SRAM tier is harder to defend thermally.

## Why this is still attractive

The energy argument is not that SRAM is free.

The argument is:

- HBM access energy is high
- repeated HBM movement dominates decode
- if HRM hit ratio is high, SRAM dynamic + leakage can still be superior to an HBM-dominant decode path in energy per token

That makes the right comparison:

> not absolute SRAM power versus zero,  
> but **SRMIC package power versus HBM-dominant baseline power at equal decode throughput**.

## Add this sentence to the main X1 document

> The flagship X1 package assumes 1.0–1.5 kW class operation. This is high but intentional. The design is not attempting to be a low-power edge device; it is a hyperscale decode platform. SRAM leakage is first-order at 64 GB, so region-level power management is treated as a core architectural requirement rather than an implementation afterthought.

---

# 4. Suggested Insertions into the Main X1 Spec

## 4.1 Add to the Fabric Section

> The quoted 96 TB/s SRMESH-X number should be understood as an internal aggregate service target across 64 logical regions, not as uniform chiplet-to-chiplet bisection bandwidth. A simple back-of-envelope shows the order of magnitude is reasonable: two 1024-bit local region data paths at 3.0 GHz DDR-equivalent provide ~1.536 TB/s per region, which aggregates to ~98.3 TB/s across 64 regions. The package backbone can be substantially lower, because the design objective is to keep decode-critical traffic region-local or island-local whenever possible.

## 4.2 Add to the Feasibility Section

> A 64 GB hot tier is too large for a monolithic SRAM die and is therefore explicitly a chiplet / stacked-memory design problem. The credible realization path is 8 SRAM macro-chiplets, each exposing 8 logical regions and implemented internally as multiple smaller SRAM dice or stacked SRAM tiles. This preserves the architectural intent while keeping yield and packaging options open.

## 4.3 Add to the Power Section

> The X1 package is expected to operate in the 1.0–1.5 kW class. Compute dominates dynamic power, but SRAM leakage becomes first-order at 64 GB. Accordingly, region-level power gating, sub-array sleep modes, and decode-phase-aware wake-up policies are treated as architectural requirements.

---

# 5. Bottom-Line Technical Position

These three additions materially strengthen the X1 document:

- **96 TB/s** is now framed as a justified internal service number
- **64 GB SRAM** is now explicitly a macro-chiplet / stacked SRAM problem, not an implied monolith
- **1.0–1.5 kW** is now attached to a subsystem-level breakdown

That moves X1 much closer to:

> “ready for a real technical conversation with a hyperscale infrastructure team.”
