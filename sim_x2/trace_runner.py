from typing import List, Dict
from ric_x2.types import TraceEvent, AccessResult
from ric_x2.controller import RICX2

class TraceRunner:
    """Executes a list of events through a controller."""
    def __init__(self, controller: RICX2):
        self.controller = controller
        self.results: List[AccessResult] = []

    def run(self, trace: List[TraceEvent]):
        for event in trace:
            res = self.controller.handle_access(event)
            self.results.append(res)
        return self.results
