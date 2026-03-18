import torch
import torch.nn as nn
from typing import Dict, List, Any, Optional, Tuple
import time

class WeightAccessTracer:
    """
    Hooks into HuggingFace transformers to capture weight access patterns.
    Handles tied weights (shared tensors) by deduplicating via data_ptr.
    """
    def __init__(self):
        self.access_trace: List[Dict[str, Any]] = []
        self.current_token_idx: int = 0
        self.hooks: List[torch.utils.hooks.RemovableHandle] = []
        # data_ptr -> (name, size_bytes, shape)
        self.tensor_info: Dict[int, Tuple[str, int, torch.Size]] = {}

    def hook_fn(self, name: str):
        def hook(module: nn.Module, input: Any, output: Any):
            if hasattr(module, 'weight') and module.weight is not None:
                w = module.weight
                ptr = w.data_ptr()
                size = w.numel() * w.element_size()
                
                # Capture unique tensor info (handles tied embeddings)
                if ptr not in self.tensor_info:
                    self.tensor_info[ptr] = (name, size, w.shape)
                
                self.access_trace.append({
                    'token_idx': self.current_token_idx,
                    'tensor_name': name,
                    'ptr': ptr,
                    'size_bytes': size,
                    'timestamp': time.time()
                })
        return hook

    def attach(self, model: nn.Module) -> 'WeightAccessTracer':
        """
        Attaches forward hooks to all Linear and Embedding layers.
        """
        for name, module in model.named_modules():
            if isinstance(module, (nn.Linear, nn.Embedding)):
                handle = module.register_forward_hook(self.hook_fn(name))
                self.hooks.append(handle)
        return self

    def detach(self) -> None:
        """
        Removes all active hooks.
        """
        for handle in self.hooks:
            handle.remove()
        self.hooks = []

    def step(self) -> None:
        """
        Advances the token index.
        """
        self.current_token_idx += 1

    def get_trace(self) -> List[Dict[str, Any]]:
        """
        Returns the captured access trace.
        """
        return self.access_trace
