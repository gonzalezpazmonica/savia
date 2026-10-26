#!/usr/bin/env python3
"""Read-only native-tool -> canonical-effect mapping for SE-398 F2.

TOOL != EFFECT: each runtime maps native tool names to the worst-case set of
canonical effects. An unmapped tool is UNKNOWN_EFFECT, never a weaker class.
Dispositions never contain an allow: a surface without proven pre-effect
interception degrades safe or reroutes to a human.
"""
from __future__ import annotations

from pathlib import Path

from sam_surface import (EFFECTS, STATE_RANK, RUNTIME_IDS, MANIFEST_DIR, _fail, _load,
                         _reject_forbidden, _check_provenance, _check_verification,
                         load_manifests, resolve_surface)

CRITICAL_EFFECTS = frozenset(EFFECTS) - {"READ_WORKSPACE", "SEARCH_WORKSPACE",
                                         "REQUEST_HUMAN_DECISION"}
UNKNOWN_EFFECT = "UNKNOWN_EFFECT"
DISPOSITIONS = ("CANDIDATE_GATED", "DEGRADED_SAFE", "REROUTE_HUMAN", "UNSUPPORTED_FOR_EFFECT")
# Semantic floor fixed in code, not taken from the map under validation: every
# shell tool and every delegating tool (subagents inherit the shell) must carry
# the full worst case of an arbitrary command.
SHELL_FLOOR = frozenset({"EXECUTE_LOCAL", "CREATE_PROCESS", "WRITE_WORKSPACE", "ACCESS_SECRET",
                         "ACCESS_NETWORK", "MODIFY_CONFIG", "EXTERNAL_EFFECT", "CHANGE_SHARED_STATE"})
SHELL_TOOLS = {"claude-code": ("Bash",), "opencode": ("bash",), "codex": ("shell", "exec_command")}
# Codex has no documented subagent tool (SE-398 F0); any spawn tool it exposes is
# unmapped, so it classifies as UNKNOWN_EFFECT and fails closed.
DELEGATING_TOOLS = {"claude-code": ("Agent", "Task"), "opencode": ("task",), "codex": ()}
_KEYS = {"schema_version", "kind", "runtime", "tools", "patterns", "provenance",
         "verification", "notes"}


def _effects_ok(value: object) -> bool:
    return isinstance(value, list) and bool(value) and len(set(map(str, value))) == len(value) \
        and all(isinstance(e, str) and e in EFFECTS for e in value)


def _check_semantics(doc: dict, rel: str) -> None:
    runtime, tools = doc["runtime"], doc["tools"]
    for name in SHELL_TOOLS[runtime] + DELEGATING_TOOLS[runtime]:
        if not SHELL_FLOOR <= set(tools.get(name, ())):
            raise _fail(f"{rel}/tools/{name}")
    # A workspace write can land on a config file: it never omits MODIFY_CONFIG.
    for name, effects in tools.items():
        if "WRITE_WORKSPACE" in effects and "MODIFY_CONFIG" not in effects:
            raise _fail(f"{rel}/tools/{name}")


def load_effect_maps(root: Path) -> dict:
    directory = root / MANIFEST_DIR / "effects"
    if (root / MANIFEST_DIR).is_symlink() or directory.is_symlink() or not directory.is_dir():
        raise _fail(f"{MANIFEST_DIR}/effects")
    maps: dict[str, dict] = {}
    for path in sorted(directory.glob("*.json")):
        rel = f"{MANIFEST_DIR}/effects/{path.name}"
        if path.is_symlink():
            raise _fail(rel)
        doc = _load(path, rel)
        _reject_forbidden(doc, rel)
        if set(doc) - _KEYS or doc.get("schema_version") != 1 or doc.get("kind") != "effect-map" \
                or doc.get("runtime") not in RUNTIME_IDS or path.stem != doc["runtime"]:
            raise _fail(rel)
        tools = doc.get("tools")
        if not isinstance(tools, dict) or not tools \
                or not all(isinstance(k, str) and k and _effects_ok(v) for k, v in tools.items()):
            raise _fail(f"{rel}/tools")
        patterns = doc.get("patterns")
        if not isinstance(patterns, list) or not all(
                isinstance(p, dict) and set(p) == {"prefix", "effects"}
                and isinstance(p["prefix"], str) and p["prefix"] and _effects_ok(p["effects"])
                for p in patterns):
            raise _fail(f"{rel}/patterns")
        _check_provenance(doc.get("provenance"), rel)
        _check_verification(doc.get("verification"), rel)
        _check_semantics(doc, rel)
        maps[doc["runtime"]] = doc
    if set(maps) != set(RUNTIME_IDS):
        raise _fail(f"{MANIFEST_DIR}/effects")
    return maps


def classify_tool(maps: dict, runtime: str, tool: str) -> list[str]:
    """Worst-case canonical effects of a native tool; unmapped fails closed.

    The result is the union of the exact entry and every matching prefix, so
    adding a pattern can only widen a tool, never pick a weaker first match.
    """
    doc = maps.get(runtime)
    if doc is None:
        raise _fail(f"runtime/{runtime}")
    effects = set(doc["tools"].get(tool, ()))
    for pattern in doc["patterns"]:
        if tool.startswith(pattern["prefix"]):
            effects.update(pattern["effects"])
    return sorted(effects) if effects else [UNKNOWN_EFFECT]


def effect_disposition(state: str | None) -> str:
    """Disposition of one effect from the surface capability state.

    No branch allows: even NATIVE/ADAPTED is only a gated candidate until
    operational evidence exists (AVAILABLE != VERIFIED != SUPPORTED).
    CANDIDATE_GATED is an extension of the three outcomes in spec SE-398 s5
    (UNSUPPORTED_FOR_EFFECT, DEGRADED_SAFE, human reroute): it claims no support
    and is the weakest value, never an allow. A state outside the F1 vocabulary
    (typo, missing) is the strictest outcome, not a degradation.
    """
    if state not in STATE_RANK or state == "UNSUPPORTED":
        return "UNSUPPORTED_FOR_EFFECT"
    if state == "EMULATED":
        return "REROUTE_HUMAN"
    if state in ("NATIVE", "ADAPTED"):
        return "CANDIDATE_GATED"
    return "DEGRADED_SAFE"


def surface_dispositions(manifests: dict, surface_id: str) -> dict:
    caps = resolve_surface(manifests, surface_id)["capabilities"]
    return {e: (effect_disposition(caps.get(e)) if e in CRITICAL_EFFECTS else "NOT_CRITICAL")
            for e in EFFECTS}


def tool_disposition(manifests: dict, maps: dict, surface_id: str, tool: str) -> dict:
    """Strictest disposition over all effects the tool may have on a surface."""
    surface = manifests["surfaces"].get(surface_id)
    if surface is None:
        raise _fail(f"surface/{surface_id}")
    effects = classify_tool(maps, surface["runtime"], tool)
    by_effect = surface_dispositions(manifests, surface_id)
    order = {"UNSUPPORTED_FOR_EFFECT": 0, "REROUTE_HUMAN": 1, "DEGRADED_SAFE": 2,
             "CANDIDATE_GATED": 3, "NOT_CRITICAL": 4}
    parts = {e: ("UNSUPPORTED_FOR_EFFECT" if e == UNKNOWN_EFFECT else by_effect[e])
             for e in effects}
    strictest = min(parts.values(), key=order.__getitem__)
    return {"surface": surface_id, "tool": tool, "effects": effects,
            "per_effect": parts, "disposition": strictest, "claims": "NONE_REPORT_ONLY"}
