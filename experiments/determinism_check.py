import json
import os
import subprocess
import sys


def run_inline(script: str, hash_seed: str) -> dict:
    env = os.environ.copy()
    env["PYTHONHASHSEED"] = hash_seed
    result = subprocess.run(
        [sys.executable, "-c", script],
        check=True,
        capture_output=True,
        text=True,
        cwd=os.getcwd(),
        env=env,
    )
    return json.loads(result.stdout)


def compare_runs(label: str, script: str):
    run_a = run_inline(script, "1")
    run_b = run_inline(script, "2")
    if run_a != run_b:
        print(f"Determinism check failed for {label}.")
        print("seed=1:", json.dumps(run_a, indent=2, sort_keys=True))
        print("seed=2:", json.dumps(run_b, indent=2, sort_keys=True))
        sys.exit(1)
    print(f"{label}: stable across PYTHONHASHSEED")


def main():
    variable_size_script = r"""
import json
from ric_x2.types import TraceEvent
from ric_x2.controller import RICX2
from sim_x2.config import X2SimConfig
from sim_x2.trace_runner import TraceRunner
from telemetry.metrics import X2Metrics

cfg = X2SimConfig(NUM_REGIONS=2, REGION_CAPACITY_MB=1, REPLICATION_ENABLED=False, MAX_CAM_ENTRIES=8)
trace = []
for step in range(12):
    trace.append(TraceEvent(step, "big_hot", 700_000))
    trace.append(TraceEvent(step, "small_a", 120_000))
    trace.append(TraceEvent(step, "small_b", 80_000))
    trace.append(TraceEvent(step, "small_c", 90_000))

controller = RICX2(cfg, x2_mode=True)
results = TraceRunner(controller).run(trace)
summary = X2Metrics.summarize(controller, results, "variable_size", cfg, "variable_size")
print(json.dumps(summary, sort_keys=True))
"""

    full_trace_script = r"""
import json
from experiments.run_x1_vs_x2 import generate_hot_trace
from ric_x2.controller import RICX2
from sim_x2.config import X2SimConfig
from sim_x2.trace_runner import TraceRunner
from telemetry.metrics import X2Metrics

cfg = X2SimConfig(REGION_CAPACITY_MB=64)
trace = generate_hot_trace()
controller = RICX2(cfg, x2_mode=True)
results = TraceRunner(controller).run(trace)
summary = X2Metrics.summarize(controller, results, "X2_Remap_Admission", cfg)
print(json.dumps(summary, sort_keys=True))
"""

    compare_runs("variable_size", variable_size_script)
    compare_runs("full_trace", full_trace_script)
    print("All determinism checks passed.")


if __name__ == "__main__":
    main()
