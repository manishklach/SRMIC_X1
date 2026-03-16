# SRMIC-X1 Chiplet & Package Architecture Concept

## 1. Package Composition

SRMIC-X1 uses an advanced 2.5D/3D packaging strategy consisting of:

-   4 Compute Chiplets
-   32 Logical HRM Regions (implemented via SRAM chiplets or stacked
    SRAM tiles)
-   8 HBM stacks
-   Hierarchical SRMESH interconnect
-   Optional CXL controller chiplet

------------------------------------------------------------------------

## 2. Logical Package Layout

              +---------------------------------------------+
              |               SRMIC-X1 Package              |
              |                                             |
              |   HBM0  HBM1  HBM2  HBM3  HBM4  HBM5  HBM6  HBM7 |
              |                                             |
              |   [SRAM Quadrants - 32 Logical Regions]    |
              |                                             |
              |   +-------+   +-------+                    |
              |   |  C0   |---|  C1   |                    |
              |   +-------+   +-------+                    |
              |        |           |                       |
              |   +-------+   +-------+                    |
              |   |  C2   |---|  C3   |                    |
              |   +-------+   +-------+                    |
              |                                             |
              |         ======= SRMESH Fabric =======      |
              +---------------------------------------------+

------------------------------------------------------------------------

## 3. Chiplet Breakdown

### Compute Chiplets (4x)

Each compute chiplet contains: - 32--64 tensor clusters - Local
scheduler - 2--4 control cores - Fabric routing endpoints - Local HBM
channels

### SRAM / HRM Chiplets

Two implementation paths:

Option A -- 32 independent SRAM chiplets\
Option B -- 8 macro-SRAM chiplets, each exposing 4 logical regions

Option B is preferred for manufacturability and routing simplicity.

------------------------------------------------------------------------

## 4. Fabric Hierarchy (SRMESH-X)

Level 1 -- Local region interconnect\
Level 2 -- Quadrant routing between compute and HRM\
Level 3 -- Package-wide cross-quadrant transport

Traffic priority: 1. Active weight fetch 2. KV updates 3. Prompt reuse
4. HBM promotion 5. CXL cold pulls

------------------------------------------------------------------------

## 5. Thermal & Power Zoning

-   Compute chiplets placed centrally for heat spreading
-   HBM stacks evenly distributed
-   SRAM quadrants placed symmetrically
-   Fabric routing balanced for signal integrity

------------------------------------------------------------------------

## 6. Design Intent

SRMIC-X1 is designed as a flagship residency-optimized inference
platform.

The chiplet approach enables: - Scalable SRAM capacity - Scalable fabric
bandwidth - Modular compute scaling - Packaging flexibility
