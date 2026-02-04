from __future__ import annotations
from dataclasses import dataclass
from typing import Dict, Any

from .capability import CapabilityLattice, execution_allowed


@dataclass(frozen=True)
class ExecutionContext:
    host: str
    context: str
    runtime: str
    command: str
    financial: str


class RegistryError(Exception):
    pass


def validate_command_request(registry: Dict[str, Any], name: str, args: Dict[str, Any]) -> None:
    if name not in registry.get("commands", {}):
        raise RegistryError(f"Unknown command: {name}")
    # Args schema validation is deferred (no jsonschema dependency in Phase 0).
    if not isinstance(args, dict):
        raise RegistryError("args must be an object")


def capabilities_for_command(registry: Dict[str, Any], name: str) -> Dict[str, str]:
    cmd = registry["commands"][name]
    return cmd["required_capabilities"]


def can_execute(lattice: CapabilityLattice, ctx: ExecutionContext, req: Dict[str, str]) -> bool:
    return execution_allowed(lattice, ctx.host, ctx.context, ctx.runtime, ctx.command, ctx.financial) and \
           execution_allowed(lattice, req["host"], req["context"], req["runtime"], req["command"], req["financial"])
