from __future__ import annotations
from dataclasses import dataclass
from typing import Dict


@dataclass(frozen=True)
class CapabilityLattice:
    """Simple meet-semilattice implementation (pure, no IO)."""
    meet_table: Dict[str, Dict[str, str]]
    bottom: str = "BOTTOM"

    def meet(self, a: str, b: str) -> str:
        return self.meet_table.get(a, {}).get(b, self.bottom)


def meet_all(lattice: CapabilityLattice, *caps: str) -> str:
    """Meet of many elements; returns BOTTOM if any pair is undefined."""
    if not caps:
        return lattice.bottom
    acc = caps[0]
    for c in caps[1:]:
        acc = lattice.meet(acc, c)
    return acc


def execution_allowed(lattice: CapabilityLattice, *caps: str) -> bool:
    return meet_all(lattice, *caps) != lattice.bottom
