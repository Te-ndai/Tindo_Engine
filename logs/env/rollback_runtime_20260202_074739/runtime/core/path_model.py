from __future__ import annotations
from dataclasses import dataclass
from typing import Literal


@dataclass(frozen=True)
class HostPath:
    raw: str


@dataclass(frozen=True)
class LogicalPath:
    namespace: str
    key: str


@dataclass(frozen=True)
class MemoryPath:
    logical: LogicalPath
    sha256: str
    loaded_at_utc: str


TransitionName = Literal["adapt", "resolve"]


def adapt(host: HostPath) -> LogicalPath:
    return LogicalPath(namespace="host", key=host.raw)


def resolve(logical: LogicalPath, sha256: str, loaded_at_utc: str) -> MemoryPath:
    return MemoryPath(logical=logical, sha256=sha256, loaded_at_utc=loaded_at_utc)


def forbid_host_to_memory(_host: HostPath) -> None:
    raise RuntimeError("Forbidden transition: HostPath -> MemoryPath")
