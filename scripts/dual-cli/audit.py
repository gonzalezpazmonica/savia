"""Read-only S1 inventory. Discovery is never evidence of CLI equivalence."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


DERIVED_MISSING = "DERIVED_MISSING: bash scripts/derived.sh ensure"


class DerivedMissing(ValueError):
    pass


def inventory(root):
    root = Path(root)
    sources = {}
    # SE-501 AC-11: .scm es D (no versionado). Este inventario es de solo lectura: no lo genera, falla
    # con un error que nombra la orden.
    if not (root / ".scm/resources.json").exists():
        raise DerivedMissing(DERIVED_MISSING)
    for name in (".claude/settings.json", ".scm/resources.json"):
        sources[name] = (root / name).read_bytes()
    digest = hashlib.sha256()
    for name, data in sorted(sources.items()):
        digest.update(name.encode() + b"\0" + hashlib.sha256(data).digest())
    settings = json.loads(sources[".claude/settings.json"])
    registry = json.loads(sources[".scm/resources.json"])
    if not isinstance(settings, dict) or not isinstance(settings.get("hooks"), dict):
        raise ValueError("invalid hooks structure")
    if not isinstance(registry, dict) or not isinstance(registry.get("resources"), list):
        raise ValueError("invalid resource structure")
    resources = registry["resources"]
    if any(not isinstance(r, dict) or not isinstance(r.get("kind"), str) for r in resources):
        raise ValueError("invalid resource entry")
    handlers = []
    gaps = ["CLI_REPLAY_UNTESTED", "NATIVE_E2E_UNTESTED", "MCP_CONTRACTS_UNTESTED",
            "TS_GUARDS_UNCLASSIFIED", "SANDBOX_UNVERIFIED", "CONCURRENCY_UNTESTED",
            "TRUST_UNTESTED", "RESOURCE_MAPPING_UNTESTED"]
    for event, entries in settings["hooks"].items():
        if not isinstance(entries, list):
            raise ValueError("invalid event entries")
        for i, entry in enumerate(entries):
            if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
                raise ValueError("invalid hook group")
            for j, hook in enumerate(entry["hooks"]):
                if not isinstance(hook, dict) or not isinstance(hook.get("type"), str):
                    raise ValueError("invalid handler")
                kind = hook["type"]
                if kind not in ("command", "http", "prompt"):
                    gaps.append("UNSUPPORTED_HANDLER_TYPE")
                handlers.append({"id": f"{event}/{i}/{j}", "event": event,
                                 "type": kind,
                                 "frontends": {"codex": "untested", "opencode": "untested"}})
    return {"version": 1, "revision": digest.hexdigest(),
            "revision_scope": sorted(sources), "certified": False,
            "handler_counts": dict(Counter(h["type"] for h in handlers)),
            "resource_counts": dict(Counter(r["kind"] for r in resources)),
            "handlers": handlers, "gaps": sorted(set(gaps))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    try:
        result = inventory(args.root)
    except DerivedMissing:
        print(json.dumps({"certified": False, "error": DERIVED_MISSING}))
        return 2
    except (OSError, ValueError, TypeError):
        # Do not echo source content, credentials, or private paths in errors.
        print(json.dumps({"certified": False, "error": "INVALID_INVENTORY_SOURCE"}))
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1  # An inventory alone must not pass a certification gate.


if __name__ == "__main__":
    raise SystemExit(main())
