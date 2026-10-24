"""LocalAdapter: sanitized, read-only detection of the real host (SE-399 F2).

Never executes anything, never reads secrets: only presence of executables (PATH lookup), the
basename of the shell, the *presence* of proxy variables (their values may carry credentials) and
free disk space. Component versions are therefore reported as "unknown": running a
manifest-declared command during discovery would be code execution, which stays behind F3.
"""
from __future__ import annotations

import os
import platform
import shutil

from .adapter import HostFacts, PlatformAdapter

KNOWN_PACKAGE_MANAGERS = ("apt", "dnf", "winget", "npm")
PROXY_VARS = ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")
ARCH = {"x86_64": "x64", "amd64": "x64", "aarch64": "arm64", "arm64": "arm64"}


def _distro(read) -> str:
    try:
        for line in read("/etc/os-release").splitlines():
            if line.startswith("ID="):
                return line[3:].strip().strip('"').lower()
    except OSError:
        pass
    return ""


def _read(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


class LocalAdapter(PlatformAdapter):
    """All system access is injectable so tests never depend on the machine they run on."""

    def __init__(self, manifests: "dict | None" = None, *, env=None, which=shutil.which, system=None,
                 machine=None, disk_usage=shutil.disk_usage, read=_read, geteuid=None, home=None):
        self._manifests = manifests or {}
        self._env = dict(os.environ if env is None else env)
        self._which, self._disk, self._read = which, disk_usage, read
        self._system = (system or platform.system()).lower()
        self._machine = (machine or platform.machine()).lower()
        self._geteuid = geteuid if geteuid is not None else getattr(os, "geteuid", lambda: -1)
        self._home = home or os.path.expanduser("~")

    def _is_wsl(self) -> bool:
        if self._system != "linux":
            return False
        if self._env.get("WSL_DISTRO_NAME"):
            return True
        try:
            return "microsoft" in self._read("/proc/version").lower()
        except OSError:
            return False

    def discover(self) -> HostFacts:
        osname = {"linux": "linux", "windows": "windows"}.get(self._system)
        arch = ARCH.get(self._machine)
        if not osname or not arch:  # outside the MVP matrix: refuse to guess
            raise ValueError(f"unsupported host {self._system}/{self._machine}")
        is_root = self._geteuid() == 0
        pms = tuple(sorted(pm for pm in KNOWN_PACKAGE_MANAGERS if self._which(pm)))
        try:
            free = int(self._disk(self._home).free)
        except OSError:
            free = None
        installed = {}
        for cid, m in sorted(self._manifests.items()):
            exe = (m.get("detection") or {}).get("executable")
            if exe and self._which(exe):
                installed[cid] = "unknown"
        return HostFacts(
            os=osname, arch=arch, distro=_distro(self._read) if osname == "linux" else "",
            elevation_available=is_root or (osname == "linux" and bool(self._which("sudo"))),
            package_managers=pms, installed=installed, disk_free_bytes=free, is_root=is_root,
            is_wsl=self._is_wsl(), shell=os.path.basename(self._env.get("SHELL", "")),
            proxy_configured=any(self._env.get(v) for v in PROXY_VARS),
        )
