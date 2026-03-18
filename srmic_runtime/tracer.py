import torch
import torch.nn as nn
from collections import defaultdict
import time

class WeightAccessTracer:
    """
    Hooks into HuggingFace transformers to capture weight access patterns.
    """
    def __init__(self):
        self.access_trace = []
        self.current_token_idx = 0
        self.hooks = []
        self.tensor_info = {} # data_ptr -> (name, size_bytes)

    def hook_fn(self, name):
        def hook(module, input, output):
            if hasattr(module, 'weight') and module.weight is not None:
                w = module.weight
                ptr = w.data_ptr()
                size = w.numel() * w.element_size()
                
                # Deduplicate and store info
                if ptr not in self.tensor_info:
                    self.tensor_info[ptr] = (name, size)
                
                self.access_trace.append({
                    'token_idx': self.current_token_idx,
                    'tensor_name': name,
                    'ptr': ptr,
                    'size_bytes': size,
                    'timestamp': time.time()
                })
        return hook

    def attach(self, model):
        """
        Attaches forward hooks to all Linear and Embedding layers.
        """
        for name, module in model.named_modules():
            if isinstance(module, (nn.Linear, nn.Embedding)):
                handle = module.register_forward_hook(self.hook_fn(name))
                self.hooks.append(handle)
        return self

    def detach(self):
        for handle in self.hooks:
            handle.remove()
        self.hooks = []

    def step(self):
        self.current_token_idx += 1

    def get_trace(self):
        return self.access_trace
