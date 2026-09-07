"""Validated domain-pack descriptors; packs can restrict, never relax, policy."""
import json
from pathlib import Path
from protocol import ProtocolError, identifier

def load(path):
    try:
        payload = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        raise ProtocolError("CONFIG_CONFLICT") from None
    if payload.get("schema") != 2 or not isinstance(payload.get("packs"), list):
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    out = {}
    for pack in payload["packs"]:
        required = {"id", "version", "capability_ids", "rule_refs", "context_refs", "test_refs", "memory_namespace", "dependencies", "compatibility_schema"}
        if not isinstance(pack, dict) or set(pack) != required or pack["compatibility_schema"] != 2:
            raise ProtocolError("UNSUPPORTED_SCHEMA")
        for name in ("id", "version", "memory_namespace"):
            identifier(pack[name])
        for name in ("capability_ids", "rule_refs", "context_refs", "test_refs", "dependencies"):
            if not isinstance(pack[name], list): raise ProtocolError("UNSUPPORTED_SCHEMA")
            for item in pack[name]: identifier(item)
        if pack["id"] in out: raise ProtocolError("CONFIG_CONFLICT")
        out[pack["id"]] = pack
    return out

def activate(packs, ids):
    selected = []
    namespaces = set()
    for pack_id in ids:
        if pack_id not in packs: raise ProtocolError("CONFIG_CONFLICT")
        pack = packs[pack_id]
        if pack["memory_namespace"] in namespaces: raise ProtocolError("CONFIG_CONFLICT")
        namespaces.add(pack["memory_namespace"]); selected.append(pack)
    return selected
