#!/usr/bin/env python3
"""SE-397 F1: deterministic, read-only Savia Architecture Model core."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Iterable

SCHEMA_VERSION = 1
MODEL_ID = "savia-architecture-model"
NODE_TYPES = frozenset({
    "SYSTEM", "SUBSYSTEM", "COMPONENT", "CAPABILITY", "POLICY",
    "ADAPTER", "FRONTEND", "STORE", "EVIDENCE",
})
RELATIONS = frozenset({
    "CONTAINS", "IMPLEMENTS", "USES", "DEPENDS_ON", "ENFORCES",
    "PRODUCES", "REQUIRES_AUTHORITY",
})
SOURCE_KINDS = frozenset({"DECLARED", "DISCOVERED"})
KNOWN_UNKNOWNS = [
    "CAPABILITY_DEPENDENCIES_INCOMPLETE",
    "CAPABILITY_TEST_LINKS_INCOMPLETE",
    "OPERATIONAL_EVIDENCE_NOT_MODELLED",
    "RUNTIME_ARCHITECTURE_NOT_MODELLED",
]
ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9._:/-]{2,255}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


class SamValidationError(ValueError):
    """Closed, machine-readable SAM validation failure."""

    def __init__(self, code: str, path: str) -> None:
        self.code = code
        self.path = path
        super().__init__(f"{code}: {path}")


def canonical_json(value: object) -> bytes:
    """Return stable UTF-8 JSON bytes without a trailing newline."""
    try:
        text = json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
            allow_nan=False,
        )
    except (TypeError, ValueError) as exc:
        raise SamValidationError("INVALID_MODEL", "$") from exc
    return text.encode("utf-8")


def _read_json(path: Path, code: str) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise SamValidationError(code, path.as_posix()) from exc


def _closed(record: object, fields: set[str], path: str,
            code: str = "UNKNOWN_FIELD") -> dict:
    if not isinstance(record, dict):
        raise SamValidationError("INVALID_TOP_LEVEL", path)
    unknown = set(record) - fields
    missing = fields - set(record)
    if unknown:
        raise SamValidationError(code, f"{path}/{sorted(unknown)[0]}")
    if missing:
        raise SamValidationError("INVALID_TOP_LEVEL", f"{path}/{sorted(missing)[0]}")
    return record


def _safe_source(root: Path, value: object, path: str) -> tuple[str, Path]:
    if not isinstance(value, str) or not value:
        raise SamValidationError("MISSING_INPUT", path)
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts or value != pure.as_posix():
        raise SamValidationError("PATH_OUTSIDE_ROOT", path)
    root_resolved = root.resolve()
    candidate = root / pure
    try:
        resolved = candidate.resolve(strict=True)
    except OSError as exc:
        raise SamValidationError("MISSING_INPUT", value) from exc
    if not resolved.is_relative_to(root_resolved):
        raise SamValidationError("PATH_OUTSIDE_ROOT", value)
    if not resolved.is_file():
        raise SamValidationError("MISSING_INPUT", value)
    return pure.as_posix(), resolved


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise SamValidationError("MISSING_INPUT", path.as_posix()) from exc
    return digest.hexdigest()


def _git_commits(root: Path, paths: Iterable[str]) -> dict[str, str]:
    wanted = set(paths)
    commits = {path: "NOT_AVAILABLE" for path in wanted}
    try:
        result = subprocess.run(
            ["git", "log", "--format=SAM-COMMIT:%H", "--name-only", "--no-renames", "--"],
            cwd=root, check=False, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return commits
    if result.returncode != 0:
        return commits
    current = "NOT_AVAILABLE"
    remaining = set(wanted)
    for line in result.stdout.splitlines():
        if line.startswith("SAM-COMMIT:"):
            candidate = line.removeprefix("SAM-COMMIT:")
            current = candidate if COMMIT_RE.fullmatch(candidate) else "NOT_AVAILABLE"
        elif line in remaining:
            commits[line] = current
            remaining.remove(line)
            if not remaining:
                break
    return commits


def _ensure_capability_map_fresh(root: Path) -> None:
    checker = root / "scripts/generate-capability-map.py"
    if not checker.is_file():
        raise SamValidationError("MISSING_INPUT", "scripts/generate-capability-map.py")
    try:
        result = subprocess.run(
            [sys.executable, str(checker), "--check"],
            cwd=root, check=False, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise SamValidationError("STALE_CAPABILITY_MAP", ".scm/registry.json") from exc
    if result.returncode != 0 or "SCM: FRESH" not in result.stdout:
        raise SamValidationError("STALE_CAPABILITY_MAP", ".scm/registry.json")


def _validate_source_paths(root: Path, values: object, path: str) -> list[str]:
    if not isinstance(values, list) or not values or values != sorted(values):
        raise SamValidationError("INVALID_TOP_LEVEL", path)
    if len(values) != len(set(values)):
        raise SamValidationError("INVALID_TOP_LEVEL", path)
    return [_safe_source(root, value, f"{path}/{index}")[0]
            for index, value in enumerate(values)]


def _load_declarations(root: Path) -> tuple[list[dict], list[dict]]:
    path = root / ".scm/sam-declarations.json"
    document = _closed(
        _read_json(path, "MISSING_INPUT"),
        {"schema_version", "nodes", "edges"}, "$",
    )
    if document["schema_version"] != SCHEMA_VERSION:
        raise SamValidationError("INVALID_TOP_LEVEL", "$/schema_version")
    if not isinstance(document["nodes"], list) or not isinstance(document["edges"], list):
        raise SamValidationError("INVALID_TOP_LEVEL", "$/nodes")
    nodes: list[dict] = []
    for index, raw in enumerate(document["nodes"]):
        item_path = f"$/nodes/{index}"
        node = _closed(raw, {"id", "type", "label", "source_paths"}, item_path)
        if not isinstance(node["id"], str) or not ID_RE.fullmatch(node["id"]):
            raise SamValidationError("INVALID_ID", f"{item_path}/id")
        if not isinstance(node["type"], str) or node["type"] not in NODE_TYPES:
            raise SamValidationError("UNKNOWN_NODE_TYPE", f"{item_path}/type")
        if not isinstance(node["label"], str) or not node["label"].strip():
            raise SamValidationError("INVALID_TOP_LEVEL", f"{item_path}/label")
        nodes.append({**node, "source_paths": _validate_source_paths(
            root, node["source_paths"], f"{item_path}/source_paths"
        )})
    ids = [node["id"] for node in nodes]
    if len(ids) != len(set(ids)):
        raise SamValidationError("DUPLICATE_ID", "$/nodes")
    missing_types = NODE_TYPES - {node["type"] for node in nodes}
    if missing_types:
        raise SamValidationError("UNKNOWN_NODE_TYPE", f"$/nodes/{sorted(missing_types)[0]}")
    edges: list[dict] = []
    keys: set[tuple[str, str, str]] = set()
    for index, raw in enumerate(document["edges"]):
        item_path = f"$/edges/{index}"
        edge = _closed(raw, {"source", "relation", "target", "source_paths"}, item_path)
        for field in ("source", "target"):
            if not isinstance(edge[field], str) or not ID_RE.fullmatch(edge[field]):
                raise SamValidationError("INVALID_ID", f"{item_path}/{field}")
        if not isinstance(edge["relation"], str) or edge["relation"] not in RELATIONS:
            raise SamValidationError("UNKNOWN_RELATION", f"{item_path}/relation")
        if edge["source"] not in ids or edge["target"] not in ids:
            raise SamValidationError("DANGLING_EDGE", item_path)
        key = (edge["source"], edge["relation"], edge["target"])
        if key in keys:
            raise SamValidationError("DUPLICATE_EDGE", item_path)
        keys.add(key)
        edges.append({**edge, "source_paths": _validate_source_paths(
            root, edge["source_paths"], f"{item_path}/source_paths"
        )})
    return nodes, edges


def _load_registry(root: Path) -> list[dict]:
    _ensure_capability_map_fresh(root)
    path = root / ".scm/registry.json"
    registry = _read_json(path, "INVALID_REGISTRY")
    if not isinstance(registry, dict) or not isinstance(registry.get("capabilities"), list):
        raise SamValidationError("INVALID_REGISTRY", ".scm/registry.json")
    result = []
    seen = set()
    for index, raw in enumerate(registry["capabilities"]):
        if not isinstance(raw, dict):
            raise SamValidationError("INVALID_REGISTRY", f"capabilities/{index}")
        capability_id = raw.get("id")
        source = raw.get("source")
        if (not isinstance(capability_id, str) or not capability_id
                or not isinstance(source, str) or not source):
            raise SamValidationError("INVALID_REGISTRY", f"capabilities/{index}")
        generated_id = f"capability/{capability_id}"
        component_id = f"component/{source}"
        if not ID_RE.fullmatch(generated_id) or not ID_RE.fullmatch(component_id):
            raise SamValidationError("INVALID_ID", f"capabilities/{index}")
        if capability_id in seen:
            raise SamValidationError("INVALID_REGISTRY", f"capabilities/{index}/id")
        seen.add(capability_id)
        safe_source = _safe_source(root, source, f"capabilities/{index}/source")[0]
        result.append({"id": capability_id, "source": safe_source})
    return result


def _input_records(root: Path, source_paths: Iterable[str],
                   commits: dict[str, str]) -> list[dict]:
    records = []
    for source in sorted(set(source_paths)):
        relative, resolved = _safe_source(root, source, source)
        records.append({
            "path": relative,
            "sha256": _sha256(resolved),
            "source_commit": commits.get(relative, "NOT_AVAILABLE"),
            "status": "PRESENT",
        })
    return records


def _provenance(inputs: dict[str, dict], kind: str, source_paths: Iterable[str]) -> list[dict]:
    return sorted(({
        "source_kind": kind,
        "source_path": path,
        "sha256": inputs[path]["sha256"],
        "source_commit": inputs[path]["source_commit"],
    } for path in set(source_paths)), key=lambda item: (item["source_path"], item["source_kind"]))


def build_model(root: Path) -> dict:
    """Build the F1 projection from declarations and the existing SCM registry."""
    root = Path(root).resolve()
    declared_nodes, declared_edges = _load_declarations(root)
    capabilities = _load_registry(root)
    all_sources = {".scm/sam-declarations.json", ".scm/registry.json"}
    for node in declared_nodes:
        all_sources.update(node["source_paths"])
    for edge in declared_edges:
        all_sources.update(edge["source_paths"])
    for capability in capabilities:
        all_sources.add(capability["source"])
    commits = _git_commits(root, all_sources)
    inputs_list = _input_records(root, all_sources, commits)
    inputs = {item["path"]: item for item in inputs_list}

    nodes: dict[str, dict] = {}
    for declared in declared_nodes:
        nodes[declared["id"]] = {
            "id": declared["id"], "type": declared["type"],
            "label": declared["label"],
            "provenance": _provenance(inputs, "DECLARED", declared["source_paths"]),
        }
    edges: dict[tuple[str, str, str], dict] = {}
    for declared in declared_edges:
        key = (declared["source"], declared["relation"], declared["target"])
        edges[key] = {
            "source": key[0], "relation": key[1], "target": key[2],
            "provenance": _provenance(inputs, "DECLARED", declared["source_paths"]),
        }
    for capability in capabilities:
        capability_id = f"capability/{capability['id']}"
        component_id = f"component/{capability['source']}"
        discovered_sources = [".scm/registry.json", capability["source"]]
        if capability_id in nodes:
            raise SamValidationError("DUPLICATE_ID", capability_id)
        nodes[capability_id] = {
            "id": capability_id, "type": "CAPABILITY", "label": capability["id"],
            "provenance": _provenance(inputs, "DISCOVERED", discovered_sources),
        }
        if component_id not in nodes:
            nodes[component_id] = {
                "id": component_id, "type": "COMPONENT", "label": capability["source"],
                "provenance": _provenance(inputs, "DISCOVERED", discovered_sources),
            }
        key = (component_id, "IMPLEMENTS", capability_id)
        if key in edges:
            raise SamValidationError("DUPLICATE_EDGE", "|".join(key))
        edges[key] = {
            "source": key[0], "relation": key[1], "target": key[2],
            "provenance": _provenance(inputs, "DISCOVERED", discovered_sources),
        }
    model = {
        "schema_version": SCHEMA_VERSION,
        "model_id": MODEL_ID,
        "model_revision": "",
        "inputs": inputs_list,
        "nodes": sorted(nodes.values(), key=lambda item: item["id"]),
        "edges": sorted(edges.values(), key=lambda item: (
            item["source"], item["relation"], item["target"]
        )),
        "known_unknowns": sorted(KNOWN_UNKNOWNS),
    }
    revision_payload = {key: model[key] for key in ("inputs", "nodes", "edges", "known_unknowns")}
    model["model_revision"] = hashlib.sha256(canonical_json(revision_payload)).hexdigest()
    return validate_model(model, root)


def _validate_model(model: object, root: Path, verify_sources: bool) -> dict:
    original = copy.deepcopy(model)
    document = _closed(model, {
        "schema_version", "model_id", "model_revision", "inputs", "nodes",
        "edges", "known_unknowns",
    }, "$", "UNKNOWN_FIELD")
    if document["schema_version"] != SCHEMA_VERSION or document["model_id"] != MODEL_ID:
        raise SamValidationError("INVALID_MODEL", "$")
    if not isinstance(document["model_revision"], str) or not SHA_RE.fullmatch(document["model_revision"]):
        raise SamValidationError("INVALID_MODEL", "$/model_revision")
    if not isinstance(document["inputs"], list) or not isinstance(document["nodes"], list) \
            or not isinstance(document["edges"], list) or not isinstance(document["known_unknowns"], list):
        raise SamValidationError("INVALID_MODEL", "$")
    if any(not isinstance(item, str) or not item for item in document["known_unknowns"]):
        raise SamValidationError("INVALID_MODEL", "$/known_unknowns")
    if document["known_unknowns"] != sorted(set(document["known_unknowns"])):
        raise SamValidationError("INVALID_MODEL", "$/known_unknowns")

    inputs: dict[str, dict] = {}
    last_input = ""
    for index, raw in enumerate(document["inputs"]):
        path = f"$/inputs/{index}"
        item = _closed(raw, {"path", "sha256", "source_commit", "status"}, path)
        relative, resolved = _safe_source(root, item["path"], f"{path}/path")
        if relative <= last_input or item["status"] != "PRESENT" or not SHA_RE.fullmatch(str(item["sha256"])):
            raise SamValidationError("INVALID_MODEL", path)
        if not isinstance(item["source_commit"], str) or (
                item["source_commit"] != "NOT_AVAILABLE"
                and not COMMIT_RE.fullmatch(item["source_commit"])):
            raise SamValidationError("INVALID_MODEL", f"{path}/source_commit")
        if verify_sources and _sha256(resolved) != item["sha256"]:
            raise SamValidationError("INVALID_MODEL", f"{path}/sha256")
        inputs[relative] = item
        last_input = relative

    def validate_provenance(value: object, path: str) -> None:
        if not isinstance(value, list) or not value:
            raise SamValidationError("INVALID_MODEL", path)
        keys = []
        for index, raw in enumerate(value):
            item = _closed(raw, {"source_kind", "source_path", "sha256", "source_commit"}, f"{path}/{index}")
            if not isinstance(item["source_kind"], str) or item["source_kind"] not in SOURCE_KINDS:
                raise SamValidationError("UNSUPPORTED_SOURCE_KIND", f"{path}/{index}/source_kind")
            if not isinstance(item["source_path"], str):
                raise SamValidationError("INVALID_MODEL", f"{path}/{index}/source_path")
            source = inputs.get(item["source_path"])
            if source is None or item["sha256"] != source["sha256"] \
                    or item["source_commit"] != source["source_commit"]:
                raise SamValidationError("INVALID_MODEL", f"{path}/{index}")
            keys.append((item["source_path"], item["source_kind"]))
        if keys != sorted(set(keys)):
            raise SamValidationError("INVALID_MODEL", path)

    ids = []
    last_id = ""
    for index, raw in enumerate(document["nodes"]):
        path = f"$/nodes/{index}"
        node = _closed(raw, {"id", "type", "label", "provenance"}, path)
        if not isinstance(node["id"], str) or not ID_RE.fullmatch(node["id"]):
            raise SamValidationError("INVALID_ID", f"{path}/id")
        if node["id"] <= last_id:
            raise SamValidationError("DUPLICATE_ID", path)
        if not isinstance(node["type"], str) or node["type"] not in NODE_TYPES:
            raise SamValidationError("UNKNOWN_NODE_TYPE", f"{path}/type")
        if not isinstance(node["label"], str) or not node["label"].strip():
            raise SamValidationError("INVALID_MODEL", f"{path}/label")
        validate_provenance(node["provenance"], f"{path}/provenance")
        ids.append(node["id"])
        last_id = node["id"]
    id_set = set(ids)
    last_edge: tuple[str, str, str] | None = None
    for index, raw in enumerate(document["edges"]):
        path = f"$/edges/{index}"
        edge = _closed(raw, {"source", "relation", "target", "provenance"}, path)
        if not all(isinstance(edge[field], str) for field in ("source", "relation", "target")):
            raise SamValidationError("INVALID_MODEL", path)
        key = (edge["source"], edge["relation"], edge["target"])
        if edge["relation"] not in RELATIONS:
            raise SamValidationError("UNKNOWN_RELATION", f"{path}/relation")
        if edge["source"] not in id_set or edge["target"] not in id_set:
            raise SamValidationError("DANGLING_EDGE", path)
        if last_edge is not None and key <= last_edge:
            raise SamValidationError("DUPLICATE_EDGE", path)
        validate_provenance(edge["provenance"], f"{path}/provenance")
        last_edge = key
    payload = {key: document[key] for key in ("inputs", "nodes", "edges", "known_unknowns")}
    if hashlib.sha256(canonical_json(payload)).hexdigest() != document["model_revision"]:
        raise SamValidationError("INVALID_MODEL", "$/model_revision")
    if document != original:
        raise SamValidationError("INVALID_MODEL", "$")
    return document


def validate_model(model: object, root: Path) -> dict:
    """Validate the closed model and its current repository sources."""
    return _validate_model(model, Path(root).resolve(), verify_sources=True)


def build_views(model: dict) -> dict[str, dict]:
    """Build deterministic report-only F1 views referencing model IDs."""
    definitions = {
        "foundation": {"SYSTEM", "POLICY", "EVIDENCE"},
        "capabilities": {"CAPABILITY", "COMPONENT"},
        "structural": {"SYSTEM", "SUBSYSTEM", "COMPONENT", "ADAPTER", "FRONTEND", "STORE"},
    }
    views = {}
    for name, types in definitions.items():
        node_ids = sorted(node["id"] for node in model["nodes"] if node["type"] in types)
        selected = set(node_ids)
        edge_ids = sorted(
            f"{edge['source']}|{edge['relation']}|{edge['target']}"
            for edge in model["edges"]
            if edge["source"] in selected and edge["target"] in selected
        )
        views[name] = {
            "schema_version": SCHEMA_VERSION,
            "view": name,
            "model_revision": model["model_revision"],
            "node_ids": node_ids,
            "edge_ids": edge_ids,
            "limitations": ["GENERATED_FROM_SAM", "REPORT_ONLY"],
        }
    return views


def query_node(model: dict, node_id: str) -> dict:
    """Return one node and incident edges, or explicit UNKNOWN."""
    node = next((item for item in model["nodes"] if item["id"] == node_id), None)
    if node is None:
        return {"status": "UNKNOWN", "node": None, "edges": []}
    edges = [edge for edge in model["edges"]
             if edge["source"] == node_id or edge["target"] == node_id]
    return {"status": "FOUND", "node": node, "edges": edges}


def serialized_outputs(model: dict) -> dict[str, bytes]:
    """Return every generated F1 artifact as stable newline-terminated bytes."""
    outputs = {".scm/sam.json": canonical_json(model) + b"\n"}
    for name, view in build_views(model).items():
        outputs[f".scm/views/{name}.json"] = canonical_json(view) + b"\n"
    return outputs
