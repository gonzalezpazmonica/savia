"""Preflight checks (SE-399 section 7). Read-only: derives verdicts from facts and the plan preview."""
from __future__ import annotations

from .adapter import HostFacts

# A check is "ok", "warning", "blocker" or "not_probed" (F2 never touches the network or certificate stores).
ORDER = {"ok": 0, "not_probed": 0, "warning": 1, "blocker": 2}


def run(host: HostFacts, steps: list, preview: dict) -> dict:
    todo = [s for s in steps if s["disposition"] == "install"]
    checks = []

    def add(cid, status, message, component=""):
        checks.append({"id": cid, "status": status, "component": component, "message": message})

    need = preview["download_bytes"] + preview["disk_bytes"]
    if not todo:
        add("disk", "ok", "nothing to install")
    elif host.disk_free_bytes is None:
        add("disk", "warning", "free disk space could not be measured; unknown state is not assumed safe")
    elif need > host.disk_free_bytes:
        add("disk", "blocker", f"needs {need} bytes (download + installed) but only {host.disk_free_bytes} are free")
    else:
        add("disk", "ok", f"needs {need} bytes, {host.disk_free_bytes} free")

    for s in todo:
        src = s["source"]
        if src["kind"] == "package_manager":
            pm = src["locator"].split(":", 1)[0]
            if pm not in host.package_managers:
                add("package_manager", "blocker", f"{pm} is not available on this host", s["component"])
    if not any(c["id"] == "package_manager" for c in checks):
        add("package_manager", "ok", "every package-manager source has its manager")

    if any(s["source"]["kind"] != "installed" and s["source"]["kind"] != "package_manager" for s in todo) or preview["download_bytes"]:
        add("network", "not_probed", "connectivity is not probed in read-only mode; downloads may still fail")
        add("certificates", "not_probed", "TLS trust is not probed; TLS validation stays enabled during install")
    if host.proxy_configured and todo:
        add("proxy", "warning", "a proxy is configured; downloads will go through it (value not read)")
    if host.is_wsl:
        add("wsl", "warning", "running inside WSL: host path and guest path differ; plan targets the guest")
    checks.sort(key=lambda c: (c["id"], c["component"]))
    worst = max((ORDER[c["status"]] for c in checks), default=0)
    return {"status": ["ready", "warnings", "blockers"][worst], "checks": checks}
