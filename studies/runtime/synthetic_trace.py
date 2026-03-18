from typing import List, Dict, Any

def generate_synthetic_trace(num_tokens: int = 100, model_type: str = "llama-3-8b") -> List[Dict[str, Any]]:
    """
    Generates a synthetic weight access trace for testing.
    Models the repetitive access pattern of a decoder-only transformer.
    """
    if model_type == "llama-3-8b":
        # 8B model: ~32 layers, active set per layer ~125MB (total 4GB)
        num_layers = 32
        layer_size_mb = 125
        tensors_per_layer = 7 # q, k, v, o, up, gate, down
    else:
        # Default small model
        num_layers = 12
        layer_size_mb = 20
        tensors_per_layer = 4

    trace: List[Dict[str, Any]] = []
    for token_idx in range(num_tokens):
        # Every token decode step accesses all layers in sequence
        for layer_idx in range(num_layers):
            for t_idx in range(tensors_per_layer):
                trace.append({
                    'token_idx': token_idx,
                    'tensor_name': f"layer_{layer_idx}_tensor_{t_idx}",
                    'size_bytes': (layer_size_mb * 1024**2) // tensors_per_layer,
                })
                
    return trace
