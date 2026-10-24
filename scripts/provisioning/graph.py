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


def retirement(manifests: dict, present, cid: str) -> dict:
    """Answer 'can cid be retired without breaking dependencies?' (SE-399 section 12)."""
    deps = dependents(manifests, present, cid)
    return {"component": cid, "present": cid in set(present), "dependents": deps, "safe": not deps}
