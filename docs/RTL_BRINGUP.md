# SRMIC-X1 RTL Bring-up Guide

## 1. Module List
| Module | File | Description |
|---|---|---|
| `ric` | `rtl/ric.sv` | Residency Intelligence Controller (Promotion/Demotion Engine) |
| `hrm_region` | `rtl/hrm_region.sv` | Hot Residency Memory (Tag RAM, LRU, Bank Model) |
| `srmesh_router` | `rtl/srmesh_router.sv` | 4-Port Mesh Router (Dual VC, WRR, Starvation Prevention) |
| `srmic_top` | `rtl/srmic_top.sv` | Top-level integration & synthetic traffic generator |
| `tb_top` | `tb/tb_top.sv` | Simulation testbench with scoreboard & perf metrics |

## 2. Compile & Run Commands
### Verilator
```bash
./scripts/run_verilator.sh
```
### Icarus Verilog
```bash
./scripts/run_iverilog.sh
```

## 3. Waveform Analysis (Signals to Inspect)
Inspect `srmic_bringup.vcd` for the following key signals:
* `dut.dbg_ric_state`: Verify FSM transitions for promotion/demotion.
* `dut.gen_regions[0].i_hrm.bank_conflict_count`: Monitor memory bank contention.
* `dut.i_router.dbg_grant_port`: Observe router arbitration (VC0/VC1).
* `dut.i_router.dbg_stall_cycles`: Track fabric backpressure.

## 4. Performance Counters
* **Bank Conflicts:** Occurs when a compute access hits the same bank as an active promotion/demotion.
* **Router Stalls:** Total cycles a flit was buffered in the router due to credit unavailability or arbitration loss.
* **Avg Latency:** Weighted average of hit (2c) and miss (6c) access times.

## 5. Known Prototype Limitations
* **Mesh Interconnect:** The top-level currently instantiates a single router; full 2x2 mesh topology is modeled but not fully interconnected in this bring-up version.
* **Scoreboard:** Uses a simple wrap-around reference model (256 entries); not exhaustive for the full address space.
* **Memory Macros:** Uses synthesizable `reg` arrays; must be replaced by SRAM macros for real ASIC synthesis.
