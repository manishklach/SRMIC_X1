# Changelog

All notable changes to this project will be documented in this file.

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
