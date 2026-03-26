# ============================================================================
# Performance Sweep Methodology
# ============================================================================

The repository includes a Python-based automation script (`scripts/perf_sweep.py`) 
to evaluate the microarchitectural behavior across different physical parameter 
configurations.

### 1. Knobs That Matter
*   `REGION_DEPTH`: The physical capacity of the tag array per region. Larger 
    depths improve hit rate but increase SRAM area and macro leakage.
*   `NUM_REGIONS`: The horizontal scaling factor of the mesh. More regions 
    reduce contention but widen the fabric bisection requirement.
*   `Traffic Seed`: Varies the pseudo-random access pattern to test corner 
    cases in the arbitration and starvation logic.

### 2. Running the Sweep
```bash
make perf-sweep
```

### 3. Interpreting Results
The sweep outputs two artifacts in `build/`:
*   `perf_results.csv`: Raw metric dump (Hit Rate, Latency, Bank Conflicts, etc.).
*   `perf_plot.png`: Graphical visualization showing the inflection point 
    where increasing `REGION_DEPTH` yields diminishing returns on `Hit Rate`.
