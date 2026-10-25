"""PlatformAdapter contract (SE-399 F1). Fake fixtures only; real adapters land in F3."""
from __future__ import annotations

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass(frozen=True)
class HostFacts:
    os: str
    arch: str
    distro: str = ""
    elevation_available: bool = False
    package_managers: tuple = ()
    installed: dict = field(default_factory=dict)  # component id -> version


class PlatformAdapter(ABC):
    """Boundary between the Provisioning Core and one operating system."""

    @abstractmethod
    def discover(self) -> HostFacts:
        """Sanitized, read-only detection. Must never read secrets."""

    def invoke(self, action: dict) -> None:
        """Structured invocation (executable, args[], env allowlist, cwd). Not in F1."""
        raise NotImplementedError("execution is out of scope until F3 (human gate)")


class FixtureAdapter(PlatformAdapter):
    """Deterministic fake host loaded from a JSON fixture."""

    def __init__(self, path: str):
        with open(path, encoding="utf-8") as fh:
            self._raw = json.load(fh)

    def discover(self) -> HostFacts:
        r = self._raw
        return HostFacts(
            os=r["os"], arch=r["arch"], distro=r.get("distro", ""),
            elevation_available=bool(r.get("elevation_available", False)),
            package_managers=tuple(sorted(r.get("package_managers", []))),
            installed=dict(r.get("installed", {})),
        )
