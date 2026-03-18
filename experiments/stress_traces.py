import random
from ric_x2.types import TraceEvent

def generate_hotspot_fanout(num_regions=64, steps=100, model_mb=2048):
    """Scenario: 2 ultra-hot tensors hash to same region, accessed 10x per step."""
    trace = []
    # Force collision by picking specific names that hash to same value (mocked)
    hot_ids = ["HOT_A", "HOT_B"]
    tensor_size = (model_mb * 1024 * 1024) // (32 * 8)
    
    for s in range(steps):
        # Background noise
        for l in range(32):
            trace.append(TraceEvent(s, f"Noise_L{l}", tensor_size, l))
        # Concentrated hotspot demand
        for h_id in hot_ids:
            for _ in range(10):
                trace.append(TraceEvent(s, h_id, tensor_size, 0))
    return trace

def generate_burst_contention(steps=200, model_mb=2048):
    """Scenario: Random noise punctuated by 10x bursts of 5 hot tensors."""
    trace = []
    tensor_size = (model_mb * 1024 * 1024) // (32 * 8)
    hot_set = [f"BurstHot_{i}" for i in range(5)]
    
    for s in range(steps):
        # 90% background, 10% burst
        if s % 20 < 2:
            for h_id in hot_set:
                for _ in range(15):
                    trace.append(TraceEvent(s, h_id, tensor_size, 0))
        else:
            for i in range(10):
                trace.append(TraceEvent(s, f"Steady_{i}", tensor_size, 0))
    return trace

def generate_hotset_rotation(steps=200, model_mb=2048):
    """Scenario: Identity of hot weights shifts every 50 steps."""
    trace = []
    tensor_size = (model_mb * 1024 * 1024) // (32 * 8)
    
    for s in range(steps):
        phase = s // 50
        for i in range(5):
            h_id = f"Phase_{phase}_Hot_{i}"
            for _ in range(10):
                trace.append(TraceEvent(s, h_id, tensor_size, 0))
        # Cold background
        for j in range(20):
            trace.append(TraceEvent(s, f"Cold_{j}", tensor_size, 0))
    return trace
