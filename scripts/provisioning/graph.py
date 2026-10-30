"""Dependency graph over component manifests (SE-399 F2). Pure, read-only."""
from __future__ import annotations


def build_graph(manifests: dict, steps: list) -> dict:
    """Nodes are the planned components; an edge A -> B reads 'A DEPENDS_ON B'."""
    ids = {s["component"] for s in steps}
    nodes = [{"id": s["component"], "disposition": s["disposition"]} for s in steps]
    edges = sorted(
        ({"from": c, "to": d, "kind": "DEPENDS_ON"} for c in ids for d in manifests[c].get("depends_on", []) if d in ids),
        key=lambda e: (e["from"], e["to"]),
    )
    return {"nodes": sorted(nodes, key=lambda n: n["id"]), "edges": edges}


def dependents(manifests: dict, present, cid: str) -> list:
    """Present components that depend on cid, directly or transitively (what a removal would break)."""
    found, todo = set(), [cid]
    while todo:
        cur = todo.pop()
        for o in sorted(present):
            if o not in found and o != cid and cur in manifests.get(o, {}).get("depends_on", []):
                found.add(o)
                todo.append(o)
    return sorted(found)


def retirement(manifests: dict, present, cid: str, undetectable=()) -> dict:
    """Answer 'can cid be retired without breaking dependencies?' (SE-399 section 12).

    undetectable: components whose presence cannot be determined on this host (no detection
    declared). Presence of those is unknown, so the answer is only safe when none of them could be
    affected; otherwise it fails closed with `undetermined` listing what could not be checked.
    """
    present = set(present)
    deps = dependents(manifests, present, cid)
    blind = set(undetectable) - present
    undetermined = [o for o in dependents(manifests, set(manifests), cid) if o in blind]
    cid_present = True if cid in present else ("unknown" if cid in blind else False)
    return {"component": cid, "present": cid_present, "dependents": deps, "undetermined": undetermined,
            "safe": not deps and not undetermined and cid_present != "unknown"}
