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
    installed: dict = field(default_factory=dict)  # component id -> version ("unknown" when only presence is known)
    disk_free_bytes: "int | None" = None  # None = not measured (unknown fails safe)
    is_root: bool = False
    is_wsl: bool = False
    proxy_configured: bool = False  # presence only: proxy URLs may embed credentials and are never read
    shell: str = ""  # basename only


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
            disk_free_bytes=r.get("disk_free_bytes"), is_root=bool(r.get("is_root", False)),
            is_wsl=bool(r.get("is_wsl", False)), proxy_configured=bool(r.get("proxy_configured", False)),
            shell=str(r.get("shell", "")),
        )
