# Changelog

All notable changes to this project will be documented in this file.

## [v3.0.0] - 2026-03-18

### SRMIC-X2: Intelligent Residency Tier

This major release introduces the **SRMIC-X2 architecture**, transitioning the memory tier from a static data store to an **intelligent, collision-aware residency system**.

### Added
- **RIC-X2 Intelligence Layer**: Complete implementation of the next-generation Residency Intelligence Controller.
- **Reactive Remapping**: Added a 256-entry hardware-proxy CAM to surgically resolve regional hash collisions and load-balance the mesh.
- **Regret-Aware Admission Control**: Implemented a utility-heuristic based bypass mechanism to protect high-utility resident objects from "residency pollution."
- **Selective Hot-Object Replication**: Integrated automated cloning for ultra-hot tensors, achieving a **26% reduction in regional occupancy skew**.
- **Replication Stress-Test Framework**: A multi-workload evaluation harness (`experiments/replication_eval.py`) supporting Hotspots, Bursts, and Rotation scenarios.
- **X2 Technical Suite**: Added comprehensive buyer-grade documentation including `TECHNICAL_BRIEF.md`, `RESULTS_SUMMARY.md`, and `IP_DIFFERENTIATION.md`.

### Fixed
- **Metric Isolation**: Hardened the evaluation harness to ensure zero metric leakage between X1 baseline and X2 scenarios.
- **Deterministic Simulation**: Replaced Python's randomized hashing with a consistent MD5-based mapping for architectural reproducibility.

### Changed
- **Pressure-Aware Routing**: Refined the `handle_access` logic to dynamically route hits to the coldest resident copy among primary and replica regions.
- **Latency Proxy Hardening**: Enhanced the cycle-proxy model to include regional congestion penalties, accurately reflecting tail-latency gains.

---

## [v2.2.0] - 2026-03-18

### SRMIC-X1: Empirical Scaling Validation (7B Milestone)

This release provides the first empirical evidence of SRMIC-X1 scaling behavior on deployment-relevant 7B class models.

### Added
- **Mistral-7B Validation**: Full autoregressive decode trace for `Mistral-7B-v0.1`, demonstrating a **1.22x speedup** even with sub-optimal coverage.
- **OPT-6.7B Validation**: Tracing results for `OPT-6.7B`, showing a **1.34x speedup** and confirming consistent architectural response across model architectures.
- **Multi-Model Comparison**: Added automated study utility (`studies/runtime/run_study.py`) to generate cross-model speedup tables.
- **Scaling Analysis**: Comprehensive documentation of regional hash collision scaling in `docs/RUNTIME_VALIDATION_REVIEW.md`.

### Changed
- **Plotter Optimization**: Enhanced `srmic_runtime/plotter.py` to support diverse MLP naming conventions (FC1/FC2) used in OPT and other model families.
- **README Elevation**: Integrated empirical performance benchmarks into the main repository documentation.

### Fixed
- **Tracer Accuracy**: Hardened `WeightAccessTracer` to use `model.generate()` with KV-cache awareness, correctly isolating decode-phase weight fetches from prefill.

---

## [v2.1.0] - 2026-03-17

### SRMIC-X1: Runtime Residency Simulation

Introduction of the trace-driven runtime validation suite to bridge the gap between analytical modeling and physical inference patterns.

### Added
- **Runtime Simulator**: Python package `srmic_runtime/` implementing regionalized HRM residency with SRMIC-aware "Pin" eviction policies.
- **Weight Access Tracer**: Hook-based tracer for HuggingFace `transformers` to capture real-world residency requirements.
- **Empirical Baseline**: First-ever measured hit rates and speedups using `Pythia-1.4B` and `OPT-1.3B`.
- **CI Study**: Automated runtime study in GitHub Actions to protect architectural invariants (I1, I2).

---

## [v2.0.0] - 2026-03-17

### SRMIC-X1: Pre-Silicon Hardened Baseline

This release marks a major architectural leap to the **v20 Bounded Working-Set Model**, providing a physically correct analytical latency model and a fully hardened RTL prototype.

### Added
- **Architectural Specification**: Integrated the v20 latency model (`core/decode_core.py`) correcting bandwidth accounting for distributed HRM regions.
- **Formal Verification**: Added SymbiYosys (`.sby`) formal property checks for RIC state transitions and SRMESH flow control.
- **FPGA Synthesis Scaffold**: Added Vivado out-of-context synthesis scripts and constraints for hardware feasibility studies.
- **Performance Sweep**: Automation script (`scripts/perf_sweep.py`) for multi-dimensional RTL parameter exploration.
- **Documentation**: New technical guides including `ARCHITECTURAL_INVARIANTS.md`, `RTL_BRINGUP.md`, and `PATENT_PENDING.md`.

### Fixed
- **RTL Integrity**: Resolved all Verilator lint warnings (timescale, implicit static, dummy wires) and Yosys synthesis errors (dynamic part-selects, 2D unpacked arrays).
- **Scoreboard Synchronization**: Re-architected the testbench as a FIFO-based response-time checker, resolving `SB_MISMATCH` and `SB_UNEXPECTED_HIT` errors.
- **Residency Timing**: Synchronized RTL latency (2-cycle Hit, 6-cycle Miss, 4-cycle Promotion) with cycle-accurate scoreboard prediction.
- **RIC Hardening**: Fixed victim index out-of-bounds, wired real `demote_page_id` from HRM selection, and implemented region-aware promotion tracking.
- **CI/CD Robustness**: Restored GitHub Actions workflow with hardened executable permissions and toolchain dependency fixes.

### Changed
- **SRMESH Router**: Complete rewrite of the router fabric to use flat packed arrays for broad toolchain compatibility (Verilator/Yosys).
- **Unified Response Pipeline**: Optimized HRM region response paths to eliminate false hits via request-qualified validation.

---

## [v1.2-professional] - 2026-03-17

### Professional RTL Bring-up Package

### Added
- Professional Makefile build flow.
- Clean RTL formatting and hardened testbench.
- Comprehensive documentation for initial bring-up.

---

## [v1.1-rtl-bringup] - 2026-03-17

### Initial RTL Bring-up

### Added
- Initial implementation of RIC, HRM Region, and SRMESH Router.
- Basic testbench and simulation flow.
