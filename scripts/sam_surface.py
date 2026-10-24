#!/usr/bin/env python3
"""Read-only runtime/surface manifests for SE-398 F1.

Declares what each runtime and surface is believed to support. It never
executes a runtime, enforces anything or claims support: a manifest is a
documented hypothesis with provenance, and surfaces only carry deltas.
"""
from __future__ import annotations

import json
from pathlib import Path
import re

from sam_model import SamValidationError

MANIFEST_DIR = ".scm/runtime-surface"
CODE = "INVALID_SURFACE_MANIFEST"

EFFECTS = (
    "READ_WORKSPACE", "SEARCH_WORKSPACE", "WRITE_WORKSPACE", "EXECUTE_LOCAL",
    "ACCESS_SECRET", "ACCESS_NETWORK", "CALL_MCP", "MODIFY_CONFIG",
    "CREATE_PROCESS", "EXTERNAL_EFFECT", "CHANGE_SHARED_STATE",
    "REQUEST_HUMAN_DECISION",
)
# Fail-safe order: UNKNOWN is never stronger than a state that was assessed.
STATE_RANK = {"UNSUPPORTED": 0, "UNKNOWN": 1, "EMULATED": 2, "ADAPTED": 3, "NATIVE": 4}
EVIDENCE_CLASSES = ("STATIC", "DOCUMENTAL", "OPERATIONAL")
# F1 makes no support claim: SUPPORTED/functional/resilient states are rejected.
SURFACE_STATES = ("unassessed", "discovered", "experimental", "degraded-safe",
                  "blocked", "unsupported")
VERIFICATION_STATES = ("NOT_VERIFIED", "NOT_AVAILABLE", "NOT_SUPPORTED", "NOT_AUTHORIZED")
EQUIVALENCE_LEVELS = ("E0", "E1")
EXECUTION_MODES = ("LOCAL", "REMOTE", "CLOUD", "SANDBOXED_LOCAL", "SANDBOXED_REMOTE")
DELTA_DOMAINS = ("process", "filesystem", "shell", "environment", "plugins", "lifecycle",
                 "permissions", "sandbox", "context", "mcp", "approval")
FORBIDDEN_KEYS = frozenset({
    "policy_owner", "policy", "authority", "authority_grant", "ceiling_override",
    "allow", "allow_with_warning", "bypass", "disable_shield",
})
RUNTIME_IDS = ("opencode", "codex", "claude-code")
SURFACE_IDS = ("opencode-tui", "opencode-desktop", "codex-cli", "codex-desktop",
               "claude-code-cli", "claude-code-desktop")
_ID = re.compile(r"^[a-z][a-z0-9-]{1,40}$")
_RUNTIME_KEYS = {"schema_version", "kind", "id", "capabilities", "provenance",
                 "verification", "notes"}
_SURFACE_KEYS = {"schema_version", "kind", "id", "runtime", "execution_modes",
                 "state", "equivalence", "verification", "deltas",
                 "capability_overrides", "provenance", "notes"}


def _fail(path: str) -> SamValidationError:
    return SamValidationError(CODE, path)


def _reject_forbidden(value: object, path: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).lower() in FORBIDDEN_KEYS:
                raise _fail(f"{path}/{key}")
            _reject_forbidden(child, f"{path}/{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _reject_forbidden(child, f"{path}/{index}")


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(key)
        result[key] = value
    return result


def _load(path: Path, rel: str) -> dict:
    try:
        document = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_pairs)
    except (OSError, ValueError) as exc:
        raise _fail(rel) from exc
    if not isinstance(document, dict):
        raise _fail(rel)
    return document


def _check_provenance(value: object, path: str) -> None:
    if not isinstance(value, dict) or set(value) != {"evidence_class", "sources"} \
            or value["evidence_class"] not in EVIDENCE_CLASSES \
            or not isinstance(value["sources"], list) or not value["sources"] \
            or not all(isinstance(s, str) and s for s in value["sources"]):
        raise _fail(f"{path}/provenance")
    if value["evidence_class"] == "OPERATIONAL":
        # F1 has no operational evidence by definition.
        raise _fail(f"{path}/provenance/evidence_class")


def _check_verification(value: object, path: str) -> None:
    if value not in VERIFICATION_STATES:
        raise _fail(f"{path}/verification")


def _check_runtime(doc: dict, rel: str) -> None:
    if set(doc) - _RUNTIME_KEYS or doc.get("schema_version") != 1 \
            or doc.get("kind") != "runtime" or doc.get("id") not in RUNTIME_IDS:
        raise _fail(rel)
    caps = doc.get("capabilities")
    if not isinstance(caps, dict) or set(caps) != set(EFFECTS) \
            or any(state not in STATE_RANK for state in caps.values()):
        raise _fail(f"{rel}/capabilities")
    _check_provenance(doc.get("provenance"), rel)
    _check_verification(doc.get("verification"), rel)


def _check_surface(doc: dict, rel: str) -> None:
    if set(doc) - _SURFACE_KEYS or doc.get("schema_version") != 1 \
            or doc.get("kind") != "surface" or doc.get("id") not in SURFACE_IDS \
            or not _ID.fullmatch(str(doc.get("runtime", ""))):
        raise _fail(rel)
    modes = doc.get("execution_modes")
    if not isinstance(modes, list) or not modes or len(set(modes)) != len(modes) \
            or any(m not in EXECUTION_MODES for m in modes):
        raise _fail(f"{rel}/execution_modes")
    if doc.get("state") not in SURFACE_STATES:
        raise _fail(f"{rel}/state")
    if doc.get("equivalence") not in EQUIVALENCE_LEVELS:
        raise _fail(f"{rel}/equivalence")
    _check_verification(doc.get("verification"), rel)
    deltas = doc.get("deltas")
    if not isinstance(deltas, dict) or set(deltas) - set(DELTA_DOMAINS) \
            or any(not isinstance(v, str) or not v for v in deltas.values()):
        raise _fail(f"{rel}/deltas")
    overrides = doc.get("capability_overrides", {})
    if not isinstance(overrides, dict) or set(overrides) - set(EFFECTS) \
            or any(state not in STATE_RANK for state in overrides.values()):
        raise _fail(f"{rel}/capability_overrides")
    _check_provenance(doc.get("provenance"), rel)


def load_manifests(root: Path) -> dict:
    """Validate and return {'runtimes': {...}, 'surfaces': {...}}."""
    base = root / MANIFEST_DIR
    runtimes: dict[str, dict] = {}
    surfaces: dict[str, dict] = {}
    for folder, store, check, expected in (
            ("runtimes", runtimes, _check_runtime, RUNTIME_IDS),
            ("surfaces", surfaces, _check_surface, SURFACE_IDS)):
        directory = base / folder
        if not directory.is_dir():
            raise _fail(f"{MANIFEST_DIR}/{folder}")
        for path in sorted(directory.glob("*.json")):
            rel = f"{MANIFEST_DIR}/{folder}/{path.name}"
            doc = _load(path, rel)
            _reject_forbidden(doc, rel)
            check(doc, rel)
            if path.stem != doc["id"] or doc["id"] in store:
                raise _fail(rel)
            store[doc["id"]] = doc
        if set(store) != set(expected):
            raise _fail(f"{MANIFEST_DIR}/{folder}")
    for sid, surface in surfaces.items():
        runtime = runtimes.get(surface["runtime"])
        if runtime is None or not sid.startswith(surface["runtime"] + "-"):
            raise _fail(f"{MANIFEST_DIR}/surfaces/{sid}.json/runtime")
        for effect, state in surface.get("capability_overrides", {}).items():
            # Inheritance may only reduce: a surface never widens its runtime.
            if STATE_RANK[state] > STATE_RANK[runtime["capabilities"][effect]]:
                raise _fail(f"{MANIFEST_DIR}/surfaces/{sid}.json/capability_overrides/{effect}")
    return {"runtimes": runtimes, "surfaces": surfaces}


def resolve_surface(manifests: dict, surface_id: str) -> dict:
    """Effective read-only view of a surface: runtime capabilities + deltas."""
    surface = manifests["surfaces"].get(surface_id)
    if surface is None:
        raise _fail(f"surface/{surface_id}")
    runtime = manifests["runtimes"][surface["runtime"]]
    capabilities = {**runtime["capabilities"], **surface.get("capability_overrides", {})}
    return {
        "surface": surface_id,
        "runtime": surface["runtime"],
        "state": surface["state"],
        "equivalence": surface["equivalence"],
        "verification": surface["verification"],
        "execution_modes": list(surface["execution_modes"]),
        "capabilities": capabilities,
        "deltas": dict(surface["deltas"]),
        "claims": "NONE_REPORT_ONLY",
    }
