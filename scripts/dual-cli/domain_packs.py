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
    visiting = set()
    resolved = []
    def add(pack_id):
        if pack_id in visiting:
            raise ProtocolError("CONFIG_CONFLICT")
        if pack_id not in packs:
            raise ProtocolError("CONFIG_CONFLICT")
        if any(pack["id"] == pack_id for pack in resolved):
            return
        visiting.add(pack_id)
        for dependency in packs[pack_id]["dependencies"]:
            if "@" not in dependency:
                raise ProtocolError("CONFIG_CONFLICT")
            dependency_id, version = dependency.rsplit("@", 1)
            if dependency_id not in packs or packs[dependency_id]["version"] != version:
                raise ProtocolError("CONFIG_CONFLICT")
            add(dependency_id)
        visiting.remove(pack_id)
        resolved.append(packs[pack_id])
    for pack_id in ids:
        add(pack_id)
    for pack in resolved:
        if pack["memory_namespace"] in namespaces:
            raise ProtocolError("CONFIG_CONFLICT")
        namespaces.add(pack["memory_namespace"])
    return resolved
