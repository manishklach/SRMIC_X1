from typing import List, Dict, Any
from ric_x2.controller import RICX2
from ric_x2.types import TensorMetadata, AccessResult
from sim_x2.config import X2SimConfig

class TraceRunner:
    """Executes a trace through a given RIC controller."""
    def __init__(self, controller: RICX2):
        self.controller = controller

    def run(self, trace: List[Dict[str, Any]], remap_threshold: float = 0.9) -> List[AccessResult]:
        results = []
        for event in trace:
            tensor = TensorMetadata(
                tensor_id=event['tensor_id'],
                size_bytes=event['size_bytes'],
                layer_idx=event.get('layer_idx'),
                phase_tag=event.get('phase_tag')
            )
            res = self.controller.handle_access(
                tensor, 
                event['token_idx'], 
                remap_threshold=remap_threshold
            )
            results.append(res)
        return results
