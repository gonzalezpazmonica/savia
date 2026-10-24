"""Read-only resolver + deterministic preview (SE-399 F1). Executes nothing."""
from __future__ import annotations

import hashlib
import json
import os
import re

from . import schema_lite
from .adapter import HostFacts

SCHEMA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "schemas", "installer")
SECRET_KEY = re.compile(r"(token|passw(or)?d|secret|api[_-]?key|credential|private[_-]?key)", re.I)
SECRET_VALUE = re.compile(r"(gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|://[^/@\s]+:[^/@\s]+@)")
SHELL_INTERPRETERS = {"sh", "bash", "zsh", "dash", "ksh", "fish", "cmd", "cmd.exe", "powershell", "powershell.exe", "pwsh", "pwsh.exe"}
PRIV_RANK = {"USER": 0, "ELEVATED": 1, "ROOT-ADMIN": 2}


def load_schema(name: str) -> dict:
    with open(os.path.join(SCHEMA_DIR, f"{name}.schema.json"), encoding="utf-8") as fh:
        return json.load(fh)


def validate(doc: dict, schema_name: str) -> list:
    """Return sorted schema error messages (empty = valid)."""
    return schema_lite.validate(doc, load_schema(schema_name))


def find_secrets(obj, path="$") -> list:
    """Paths of secret-looking keys/values. Plans, states and receipts must yield none."""
    hits = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if SECRET_KEY.search(str(k)):
                hits.append(f"{path}.{k}")
            hits += find_secrets(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            hits += find_secrets(v, f"{path}[{i}]")
    elif isinstance(obj, str) and SECRET_VALUE.search(obj):
        hits.append(path)
    return hits


def load_manifests(directory: str) -> dict:
    out = {}
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(directory, name), encoding="utf-8") as fh:
            m = json.load(fh)
        errs = validate(m, "component-manifest")
        if errs:
            raise ValueError(f"{name}: invalid manifest: {errs[0]}")
        if m["id"] in out:
            raise ValueError(f"duplicate component id {m['id']}")
        out[m["id"]] = m
    return out


def _pick_target(m: dict, host: HostFacts):
    for t in m["targets"]:
        if t["os"] == host.os and host.arch in t["arch"] and (not t.get("distros") or host.distro in t["distros"]):
            return t
    return None


def _integrity_problem(t: dict):
    s = t["source"]
    if s["kind"] != "package_manager" and not s["locator"].strip().lower().startswith("https://") or s["locator"] != s["locator"].strip():
        return "insecure transport; HTTPS required"
    if s["kind"] in ("signed_installer", "official_release") and not s.get("integrity", {}).get("sha256"):
        return f"{s['kind']} source without sha256"
    return None


def _closure(manifests: dict, selection: list, blockers: list, installed=()) -> list:
    """Dependency closure in deterministic topological order; cycles/missing deps block."""
    order, state = [], {}
    missing_ok = set(installed) - set(manifests)  # installed dependency without manifest: nothing to plan

    def visit(cid, chain):
        if cid in missing_ok or state.get(cid) == "missing":
            return
        if cid not in manifests:
            state[cid] = "missing"
            blockers.append({"code": "missing_dependency", "component": cid, "message": f"no manifest for {cid} (needed by {chain[-1] if chain else 'selection'})"})
            return
        if state.get(cid) == "done":
            return
        if state.get(cid) == "active":
            blockers.append({"code": "dependency_cycle", "component": cid, "message": " -> ".join(chain + [cid])})
            return
        state[cid] = "active"
        for d in sorted(manifests[cid].get("depends_on", [])):
            visit(d, chain + [cid])
        state[cid] = "done"
        order.append(cid)

    for cid in sorted(set(selection)):
        visit(cid, [])
    return order


def build_plan(manifests: dict, host: HostFacts, selection: list) -> dict:
    blockers, warnings, steps = [], [], []
    order = _closure(manifests, selection, blockers, host.installed)
    selected = set(selection)
    present = (set(host.installed) | set(order))
    for cid in order:
        m = manifests[cid]
        # conflicts in both directions: this manifest vs present, and present manifests vs this component
        found = {c for c in m.get("conflicts", []) if c in present and c != cid}
        found |= {o for o in present if o != cid and o in manifests and cid in manifests[o].get("conflicts", [])
                  and (o in selected or o in order or o in host.installed)}
        for c in sorted(found):
            blockers.append({"code": "conflict", "component": cid, "message": f"conflicts with {c}"})
        t = _pick_target(m, host)
        installed = cid in host.installed
        if installed:
            # Nothing will run for this component: skip platform/integrity/privilege blockers.
            if host.installed[cid] != m["version"]:
                warnings.append({"code": "version_mismatch", "component": cid, "message": f"installed {host.installed[cid]} differs from manifest {m['version']}; F1 never upgrades"})
            act = t["actions"]["install"] if t else None
            steps.append({
                "order": len(steps) + 1, "component": cid, "version": m["version"], "disposition": "already_installed",
                "source": {"kind": t["source"]["kind"], "locator": t["source"]["locator"]} if t else {"kind": "installed"},
                "privilege": act["privilege"] if act else "USER", "reversibility": act["reversibility"] if act else "reversible",
                "changes": [], "_t": t or {}, "_m": m,
            })
            continue
        if t is None:
            blockers.append({"code": "unsupported_platform", "component": cid, "message": f"no target for {host.os}/{host.arch}{'/' + host.distro if host.distro else ''}"})
            continue
        for aname, a in sorted(t["actions"].items()):
            exe = a.get("invocation", {}).get("executable", "")
            if exe.replace("\\", "/").rsplit("/", 1)[-1].lower() in SHELL_INTERPRETERS:
                warnings.append({"code": "shell_interpreter", "component": cid, "message": f"{aname} runs a shell interpreter ({exe}); needs human review"})
        problem = _integrity_problem(t)
        if problem:
            blockers.append({"code": "integrity", "component": cid, "message": problem})
            continue
        if t["source"]["kind"] == "manual":
            warnings.append({"code": "manual_source", "component": cid, "message": "manual download requires explicit authorization"})
        act = t["actions"]["install"]
        if PRIV_RANK[act["privilege"]] > 0 and not host.elevation_available:
            blockers.append({"code": "no_elevation", "component": cid, "message": f"requires {act['privilege']} but the host offers no elevation"})
            continue
        for aname in ("uninstall", "rollback"):
            a = t["actions"].get(aname)
            if a and PRIV_RANK[a["privilege"]] > 0 and not host.elevation_available:
                warnings.append({"code": "recovery_needs_elevation", "component": cid, "message": f"{aname} requires {a['privilege']} but the host offers no elevation; recovery would not be possible"})
        if act["reversibility"] == "irreversible" and not act.get("compensation", "none") == "none":
            warnings.append({"code": "compensation_on_irreversible", "component": cid, "message": "irreversible action declares compensation; verify it is real"})
        steps.append({
            "order": len(steps) + 1, "component": cid, "version": m["version"], "disposition": "install",
            "source": {"kind": t["source"]["kind"], "locator": t["source"]["locator"], **({"sha256": t["source"]["integrity"]["sha256"]} if t["source"].get("integrity", {}).get("sha256") else {})},
            "privilege": act["privilege"], "reversibility": act["reversibility"],
            "changes": sorted(act.get("changes", []), key=lambda c: (c["kind"], c["target"])),
            "_t": t, "_m": m,
        })
    todo = [s for s in steps if s["disposition"] == "install"]
    preview = {
        "download_bytes": sum(s["_t"].get("download_bytes", 0) for s in todo),
        "disk_bytes": sum(s["_t"].get("disk_bytes", 0) for s in todo),
        "privileges": sorted({s["privilege"] for s in todo}, key=PRIV_RANK.get),
        "irreversible": sorted(s["component"] for s in todo if s["reversibility"] == "irreversible"),
        "restarts": sorted(s["component"] for s in todo if s["_m"].get("requires_restart")),
        "changes": sorted((dict(c, component=s["component"]) for s in todo for c in s["changes"]), key=lambda c: (c["component"], c["kind"], c["target"])),
    }
    for s in steps:
        s.pop("_t"), s.pop("_m")
    plat = {"os": host.os, "arch": host.arch, **({"distro": host.distro} if host.distro else {})}
    blockers.sort(key=lambda f: (f["component"], f["code"]))
    warnings.sort(key=lambda f: (f["component"], f["code"]))
    plan = {
        "schema_version": 1, "platform": plat, "selection": sorted(set(selection)),
        "status": "blocked" if blockers else ("ready_with_warnings" if warnings else "ready"),
        "steps": steps, "blockers": blockers, "warnings": warnings, "preview": preview,
    }
    plan["plan_id"] = hashlib.sha256(json.dumps(plan, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return plan
