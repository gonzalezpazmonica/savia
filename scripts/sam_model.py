#!/usr/bin/env python3
"""SE-397 F1/F2: deterministic, read-only Savia Architecture Model core."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Iterable

SCHEMA_VERSION = 2
DECLARATION_SCHEMA_VERSION = 1
MODEL_ID = "savia-architecture-model"
NODE_TYPES = frozenset({
    "SYSTEM", "SUBSYSTEM", "COMPONENT", "CAPABILITY", "POLICY",
    "ADAPTER", "FRONTEND", "STORE", "EVIDENCE",
    "FLOW", "EFFECT", "RISK", "AUTHORITY", "HUMAN_GATE", "FAILURE_STATE",
})
RELATIONS = frozenset({
    "CONTAINS", "IMPLEMENTS", "USES", "DEPENDS_ON", "ENFORCES",
    "PRODUCES", "REQUIRES_AUTHORITY",
    "HAS_EFFECT", "HAS_RISK", "HAS_EXECUTION_AUTHORITY", "REQUIRES_HUMAN",
    "GATES", "DEGRADES_TO",
})
F1_NODE_TYPES = frozenset({
    "SYSTEM", "SUBSYSTEM", "COMPONENT", "CAPABILITY", "POLICY",
    "ADAPTER", "FRONTEND", "STORE", "EVIDENCE",
})
F1_RELATIONS = frozenset({
    "CONTAINS", "IMPLEMENTS", "USES", "DEPENDS_ON", "ENFORCES",
    "PRODUCES", "REQUIRES_AUTHORITY",
})
RUNTIME_RELATIONS = frozenset({
    "HAS_EFFECT", "HAS_RISK", "HAS_EXECUTION_AUTHORITY", "REQUIRES_HUMAN",
    "GATES", "DEGRADES_TO",
})
SOURCE_KINDS = frozenset({"DECLARED", "DISCOVERED"})
KNOWN_UNKNOWNS = [
    "AUTHORITY_PATHS_DECLARED_NOT_ENFORCED",
    "CAPABILITY_DEPENDENCIES_INCOMPLETE",
    "CAPABILITY_TEST_LINKS_INCOMPLETE",
    "FAILURE_PATHS_INCOMPLETE",
    "OPERATIONAL_EVIDENCE_NOT_MODELLED",
    "RUNTIME_ARCHITECTURE_DECLARED_NOT_OBSERVED",
]
ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9._:/-]{2,255}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")

GOLDEN_FLOWS = [
    "flow:bash", "flow:edit", "flow:external-effect",
    "flow:mcp", "flow:read", "flow:write",
]
RUNTIME_MATRIX = {
    "flow:bash": (
        "effect:context-dependent", "risk:context-dependent",
        "human-gate:policy-dependent", "failure:unknown-effect",
    ),
    "flow:edit": (
        "effect:workspace-mutation", "risk:L1",
        "human-gate:not-required-within-approved-scope", "failure:needs-human",
    ),
    "flow:external-effect": (
        "effect:external", "risk:human-review-required",
        "human-gate:required", "failure:unknown-effect",
    ),
    "flow:mcp": (
        "effect:context-dependent", "risk:context-dependent",
        "human-gate:policy-dependent", "failure:unavailable",
    ),
    "flow:read": (
        "effect:local-read", "risk:L0",
        "human-gate:not-required-within-approved-scope", "failure:blocked",
    ),
    "flow:write": (
        "effect:workspace-mutation", "risk:context-dependent",
        "human-gate:policy-dependent", "failure:needs-human",
    ),
}
_AUTONOMY = "scripts/dual-cli/autonomy.py"
_CONTRACTS = "scripts/dual-cli/contracts.py"
_RUNTIME = "scripts/dual-cli/runtime.py"
_SAFETY = "docs/rules/domain/autonomous-safety.md"
_PARENT_SPEC = "docs/specs/SE-397-savia-architectural-self-knowledge.spec.md"
_HUMAN_CONTROL = "laws/human-control.md"
RUNTIME_NODE_CONTRACT = {
    "authority:delegated-execution-only": (
        "AUTHORITY", "Delegated execution only", [_SAFETY, _AUTONOMY]),
    "authority:human-decision": (
        "AUTHORITY", "Human decision authority", [_HUMAN_CONTROL, _AUTONOMY]),
    "effect:context-dependent": (
        "EFFECT", "Context-dependent effect", [_SAFETY, _PARENT_SPEC]),
    "effect:external": (
        "EFFECT", "External effect", [_HUMAN_CONTROL, _AUTONOMY]),
    "effect:local-read": ("EFFECT", "Local read", [_AUTONOMY]),
    "effect:workspace-mutation": (
        "EFFECT", "Workspace mutation", [_SAFETY, _AUTONOMY]),
    "failure:blocked": (
        "FAILURE_STATE", "Blocked", [_CONTRACTS, _RUNTIME]),
    "failure:needs-human": (
        "FAILURE_STATE", "Needs human", [_AUTONOMY, _CONTRACTS]),
    "failure:unavailable": ("FAILURE_STATE", "Unavailable", [_RUNTIME]),
    "failure:unknown-effect": (
        "FAILURE_STATE", "Unknown effect", [_SAFETY, _CONTRACTS]),
    "flow:bash": ("FLOW", "BASH", [_SAFETY, _PARENT_SPEC, _AUTONOMY]),
    "flow:edit": ("FLOW", "EDIT", [_PARENT_SPEC, _AUTONOMY]),
    "flow:external-effect": (
        "FLOW", "EXTERNAL_EFFECT", [_PARENT_SPEC, _HUMAN_CONTROL, _AUTONOMY]),
    "flow:mcp": ("FLOW", "MCP", [_SAFETY, _PARENT_SPEC, _CONTRACTS]),
    "flow:read": ("FLOW", "READ", [_PARENT_SPEC, _AUTONOMY]),
    "flow:write": ("FLOW", "WRITE", [_SAFETY, _PARENT_SPEC, _AUTONOMY]),
    "human-gate:not-required-within-approved-scope": (
        "HUMAN_GATE", "Not required within approved L0-L2 scope", [_SAFETY, _AUTONOMY]),
    "human-gate:policy-dependent": (
        "HUMAN_GATE", "Policy dependent", [_SAFETY, _AUTONOMY]),
    "human-gate:required": (
        "HUMAN_GATE", "Human gate required", [_HUMAN_CONTROL, _AUTONOMY]),
    "risk:L0": ("RISK", "L0", [_AUTONOMY]),
    "risk:L1": ("RISK", "L1", [_AUTONOMY]),
    "risk:context-dependent": (
        "RISK", "Context-dependent risk", [_SAFETY, _AUTONOMY]),
    "risk:human-review-required": (
        "RISK", "Human review required", [_HUMAN_CONTROL, _AUTONOMY]),
}
VERIFICATION_SCHEMA_VERSION = 1
VERIFICATION_BASIS = "SAME_REPOSITORY_PATH"
DRIFT_LIMITATIONS = ["NO_SEMANTIC_INFERENCE", "REPORT_ONLY", "STATIC_REPOSITORY_EVIDENCE"]
CLAIM_LIMITATIONS = ["NO_RUNTIME_EVIDENCE", "REPORT_ONLY", "STATIC_GRAPH_PATHS_ONLY"]
IMPACT_LIMITATIONS = ["GRAPH_REACHABILITY_ONLY", "REPORT_ONLY"]
CLAIM_TYPES = frozenset({"CAPABILITY", "POLICY", "FLOW"})


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
    if document["schema_version"] != DECLARATION_SCHEMA_VERSION:
        raise SamValidationError("INVALID_TOP_LEVEL", "$/schema_version")
    if not isinstance(document["nodes"], list) or not isinstance(document["edges"], list):
        raise SamValidationError("INVALID_TOP_LEVEL", "$/nodes")
    nodes: list[dict] = []
    for index, raw in enumerate(document["nodes"]):
        item_path = f"$/nodes/{index}"
        node = _closed(raw, {"id", "type", "label", "source_paths"}, item_path)
        if not isinstance(node["id"], str) or not ID_RE.fullmatch(node["id"]):
            raise SamValidationError("INVALID_ID", f"{item_path}/id")
        if not isinstance(node["type"], str) or node["type"] not in F1_NODE_TYPES:
            raise SamValidationError("UNKNOWN_NODE_TYPE", f"{item_path}/type")
        if not isinstance(node["label"], str) or not node["label"].strip():
            raise SamValidationError("INVALID_TOP_LEVEL", f"{item_path}/label")
        nodes.append({**node, "source_paths": _validate_source_paths(
            root, node["source_paths"], f"{item_path}/source_paths"
        )})
    ids = [node["id"] for node in nodes]
    if len(ids) != len(set(ids)):
        raise SamValidationError("DUPLICATE_ID", "$/nodes")
    missing_types = F1_NODE_TYPES - {node["type"] for node in nodes}
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
        if not isinstance(edge["relation"], str) or edge["relation"] not in F1_RELATIONS:
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


def _expected_runtime_edges() -> set[tuple[str, str, str]]:
    expected: set[tuple[str, str, str]] = set()
    for flow, (effect, risk, gate, failure) in RUNTIME_MATRIX.items():
        expected.update({
            (flow, "HAS_EFFECT", effect),
            (flow, "HAS_RISK", risk),
            (flow, "HAS_EXECUTION_AUTHORITY", "authority:delegated-execution-only"),
            (gate, "GATES", flow),
            (flow, "DEGRADES_TO", failure),
        })
    expected.add((
        "flow:external-effect", "REQUIRES_HUMAN", "authority:human-decision",
    ))
    return expected


def _load_runtime_declarations(
        root: Path, reserved_ids: set[str]) -> tuple[list[dict], list[dict]]:
    path = root / ".scm/sam-runtime-declarations.json"
    document = _closed(
        _read_json(path, "MISSING_INPUT"),
        {"schema_version", "golden_flows", "nodes", "edges"}, "$",
    )
    if document["schema_version"] != DECLARATION_SCHEMA_VERSION:
        raise SamValidationError("INVALID_RUNTIME_DECLARATION", "$/schema_version")
    if document["golden_flows"] != GOLDEN_FLOWS:
        raise SamValidationError("INVALID_RUNTIME_DECLARATION", "$/golden_flows")
    if not isinstance(document["nodes"], list) or not isinstance(document["edges"], list):
        raise SamValidationError("INVALID_RUNTIME_DECLARATION", "$/nodes")

    nodes: list[dict] = []
    ids: set[str] = set()
    for index, raw in enumerate(document["nodes"]):
        item_path = f"$/nodes/{index}"
        node = _closed(raw, {"id", "type", "label", "source_paths"}, item_path)
        if not isinstance(node["id"], str) or not ID_RE.fullmatch(node["id"]):
            raise SamValidationError("INVALID_ID", f"{item_path}/id")
        if node["id"] in ids or node["id"] in reserved_ids:
            raise SamValidationError("DUPLICATE_ID", f"{item_path}/id")
        ids.add(node["id"])
        if not isinstance(node["type"], str) or node["type"] not in NODE_TYPES:
            raise SamValidationError("UNKNOWN_NODE_TYPE", f"{item_path}/type")
        if not isinstance(node["label"], str) or not node["label"].strip():
            raise SamValidationError("INVALID_TOP_LEVEL", f"{item_path}/label")
        nodes.append({**node, "source_paths": _validate_source_paths(
            root, node["source_paths"], f"{item_path}/source_paths"
        )})

    if ids != set(RUNTIME_NODE_CONTRACT):
        raise SamValidationError("INVALID_RUNTIME_DECLARATION", "$/nodes")
    for node in nodes:
        expected_type, expected_label, expected_sources = RUNTIME_NODE_CONTRACT[node["id"]]
        if (node["type"], node["label"], node["source_paths"]) != (
                expected_type, expected_label, expected_sources):
            raise SamValidationError("INVALID_RUNTIME_DECLARATION", f"$/nodes/{node['id']}")

    edges: list[dict] = []
    keys: set[tuple[str, str, str]] = set()
    nodes_by_id = {node["id"]: node for node in nodes}
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
        source_paths = _validate_source_paths(
            root, edge["source_paths"], f"{item_path}/source_paths"
        )
        expected_sources = sorted(set(
            nodes_by_id[edge["source"]]["source_paths"]
            + nodes_by_id[edge["target"]]["source_paths"]
        ))
        if source_paths != expected_sources:
            raise SamValidationError("INVALID_RUNTIME_DECLARATION", f"{item_path}/source_paths")
        edges.append({**edge, "source_paths": source_paths})

    expected_keys = _expected_runtime_edges()
    if keys != expected_keys:
        differences = keys.symmetric_difference(expected_keys)
        touches_flow = any(
            source in GOLDEN_FLOWS or target in GOLDEN_FLOWS
            for source, _relation, target in differences
        )
        code = "INCOMPLETE_FLOW" if touches_flow else "INVALID_RUNTIME_DECLARATION"
        raise SamValidationError(code, "$/edges")
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
    previous: dict[str, dict[str, str]] = {}
    previous_path = root / ".scm/sam.json"
    try:
        previous_document = json.loads(previous_path.read_text(encoding="utf-8"))
        previous_inputs = previous_document.get("inputs", [])
        if isinstance(previous_inputs, list):
            for item in previous_inputs:
                if isinstance(item, dict) and {
                    "path", "sha256", "source_commit"
                } <= set(item):
                    previous[item["path"]] = item
    except (OSError, UnicodeError, json.JSONDecodeError, AttributeError):
        # A missing or malformed committed model is validated by the caller;
        # generation must still be able to rebuild it from repository state.
        previous = {}

    records = []
    for source in sorted(set(source_paths)):
        relative, resolved = _safe_source(root, source, source)
        digest = _sha256(resolved)
        prior = previous.get(relative)
        source_commit = commits.get(relative, "NOT_AVAILABLE")
        if prior is not None and prior.get("sha256") == digest:
            # Commit IDs are not stable across squash/rebase. Preserve the
            # provenance already attached to identical content so a rewrite
            # of history cannot make an unchanged projection stale.
            source_commit = prior["source_commit"]
        records.append({
            "path": relative,
            "sha256": digest,
            "source_commit": source_commit,
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
    """Build the F1/F2 projection from declarations and the SCM registry."""
    root = Path(root).resolve()
    declared_nodes, declared_edges = _load_declarations(root)
    capabilities = _load_registry(root)
    reserved_ids = {node["id"] for node in declared_nodes}
    for capability in capabilities:
        reserved_ids.update({
            f"capability/{capability['id']}",
            f"component/{capability['source']}",
        })
    runtime_nodes, runtime_edges = _load_runtime_declarations(root, reserved_ids)
    all_sources = {
        ".scm/sam-declarations.json", ".scm/sam-runtime-declarations.json",
        ".scm/registry.json",
    }
    for node in [*declared_nodes, *runtime_nodes]:
        all_sources.update(node["source_paths"])
    for edge in [*declared_edges, *runtime_edges]:
        all_sources.update(edge["source_paths"])
    for capability in capabilities:
        all_sources.add(capability["source"])
    commits = _git_commits(root, all_sources)
    inputs_list = _input_records(root, all_sources, commits)
    inputs = {item["path"]: item for item in inputs_list}

    nodes: dict[str, dict] = {}
    for declared in [*declared_nodes, *runtime_nodes]:
        nodes[declared["id"]] = {
            "id": declared["id"], "type": declared["type"],
            "label": declared["label"],
            "provenance": _provenance(inputs, "DECLARED", declared["source_paths"]),
        }
    edges: dict[tuple[str, str, str], dict] = {}
    for declared in [*declared_edges, *runtime_edges]:
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


def _validate_runtime_projection(nodes: list[dict], edges: list[dict]) -> None:
    runtime_ids = set(RUNTIME_NODE_CONTRACT)
    projected = {node["id"]: node for node in nodes if node["id"] in runtime_ids}
    f2_types = NODE_TYPES - F1_NODE_TYPES
    if set(projected) != runtime_ids or any(
            node["type"] in f2_types and node["id"] not in runtime_ids for node in nodes):
        raise SamValidationError("INVALID_MODEL", "$/nodes")
    for node_id, node in projected.items():
        expected_type, expected_label, expected_sources = RUNTIME_NODE_CONTRACT[node_id]
        actual_sources = [item["source_path"] for item in node["provenance"]]
        if (node["type"], node["label"], actual_sources) != (
                expected_type, expected_label, expected_sources):
            raise SamValidationError("INVALID_MODEL", f"$/nodes/{node_id}")
        if any(item["source_kind"] != "DECLARED" for item in node["provenance"]):
            raise SamValidationError("INVALID_MODEL", f"$/nodes/{node_id}/provenance")
    incident = {
        (edge["source"], edge["relation"], edge["target"])
        for edge in edges
        if edge["source"] in runtime_ids or edge["target"] in runtime_ids
    }
    if incident != _expected_runtime_edges():
        raise SamValidationError("INVALID_MODEL", "$/edges")


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
    if document["known_unknowns"] != sorted(KNOWN_UNKNOWNS):
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
    _validate_runtime_projection(document["nodes"], document["edges"])
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
    """Build deterministic report-only F1/F2 views referencing model IDs."""
    definitions = {
        "foundation": {"SYSTEM", "POLICY", "EVIDENCE"},
        "capabilities": {"CAPABILITY", "COMPONENT"},
        "structural": {"SYSTEM", "SUBSYSTEM", "COMPONENT", "ADAPTER", "FRONTEND", "STORE"},
        "runtime": {"FLOW", "EFFECT", "RISK", "AUTHORITY", "HUMAN_GATE", "FAILURE_STATE"},
        "authority": {"FLOW", "AUTHORITY", "HUMAN_GATE", "POLICY"},
        "failure": {"FLOW", "FAILURE_STATE"},
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
        limitations = ["GENERATED_FROM_SAM", "REPORT_ONLY"]
        if name in {"runtime", "authority", "failure"}:
            limitations = ["DECLARED_NOT_OBSERVED", *limitations]
        views[name] = {
            "schema_version": SCHEMA_VERSION,
            "view": name,
            "model_revision": model["model_revision"],
            "node_ids": node_ids,
            "edge_ids": edge_ids,
            "limitations": limitations,
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


def _provenance_kinds(node: dict) -> set[str]:
    return {item["source_kind"] for item in node["provenance"]}


def _node_source_paths(node: dict) -> set[str]:
    return {item["source_path"] for item in node["provenance"]}


def load_verification_declarations(root: Path, model: dict) -> dict:
    path = Path(root).resolve() / ".scm/sam-verification-declarations.json"
    document = _closed(_read_json(path, "MISSING_INPUT"),
                       {"schema_version", "bindings", "impact_roots"}, "$")
    if document["schema_version"] != VERIFICATION_SCHEMA_VERSION:
        raise SamValidationError("INVALID_VERIFICATION_DECLARATION", "$/schema_version")
    bindings, roots = document["bindings"], document["impact_roots"]
    if not isinstance(bindings, list) or not isinstance(roots, list):
        raise SamValidationError("INVALID_VERIFICATION_DECLARATION", "$")
    if roots != sorted(set(roots)) or not roots:
        raise SamValidationError("INVALID_VERIFICATION_DECLARATION", "$/impact_roots")
    node_by_id = {node["id"]: node for node in model["nodes"]}
    if any(not isinstance(item, str) or item not in node_by_id for item in roots):
        raise SamValidationError("INVALID_VERIFICATION_DECLARATION", "$/impact_roots")
    seen_ids: set[str] = set()
    seen_nodes: set[str] = set()
    previous_id = ""
    validated = []
    for index, raw in enumerate(bindings):
        item_path = f"$/bindings/{index}"
        item = _closed(raw, {"id", "declared_node_id", "discovered_node_id", "basis"}, item_path)
        binding_id = item["id"]
        if (not isinstance(binding_id, str) or not ID_RE.fullmatch(binding_id)
                or binding_id <= previous_id or binding_id in seen_ids):
            raise SamValidationError("INVALID_VERIFICATION_DECLARATION", f"{item_path}/id")
        previous_id = binding_id
        seen_ids.add(binding_id)
        declared_id, discovered_id = item["declared_node_id"], item["discovered_node_id"]
        declared, discovered = node_by_id.get(declared_id), node_by_id.get(discovered_id)
        valid = (
            isinstance(declared_id, str) and isinstance(discovered_id, str)
            and declared_id != discovered_id and declared is not None and discovered is not None
            and declared_id not in seen_nodes and discovered_id not in seen_nodes
            and declared["type"] == discovered["type"] == "COMPONENT"
            and _provenance_kinds(declared) == {"DECLARED"}
            and _provenance_kinds(discovered) == {"DISCOVERED"}
            and len(_node_source_paths(declared)) == 1
            and next(iter(_node_source_paths(declared))) == discovered["label"]
            and discovered["label"] in _node_source_paths(discovered)
            and item["basis"] == VERIFICATION_BASIS
        )
        if not valid:
            raise SamValidationError("INVALID_VERIFICATION_DECLARATION", item_path)
        seen_nodes.update({declared_id, discovered_id})
        validated.append({"id": binding_id, "declared_node_id": declared_id,
                          "discovered_node_id": discovered_id, "basis": VERIFICATION_BASIS})
    return {"bindings": validated, "impact_roots": roots}


def build_drift_report(model: dict, verification: dict) -> dict:
    node_by_id = {node["id"]: node for node in model["nodes"]}
    bound = {endpoint for binding in verification["bindings"]
             for endpoint in (binding["declared_node_id"], binding["discovered_node_id"])}
    items = []
    for binding in verification["bindings"]:
        declared = node_by_id[binding["declared_node_id"]]
        discovered = node_by_id[binding["discovered_node_id"]]
        items.append({"node_id": binding["declared_node_id"], "status": "CORROBORATED",
                      "counterpart_id": binding["discovered_node_id"],
                      "source_paths": sorted(_node_source_paths(declared) | _node_source_paths(discovered))})
    for node in model["nodes"]:
        if node["id"] in bound:
            continue
        kinds = _provenance_kinds(node)
        status = ("MIXED_UNBOUND" if kinds == {"DECLARED", "DISCOVERED"}
                  else "DECLARED_ONLY" if kinds == {"DECLARED"}
                  else "DISCOVERED_ONLY" if kinds == {"DISCOVERED"}
                  else "MIXED_UNBOUND")
        items.append({"node_id": node["id"], "status": status, "counterpart_id": None,
                      "source_paths": sorted(_node_source_paths(node))})
    items.sort(key=lambda item: item["node_id"])
    summary = {key: 0 for key in ("corroborated", "declared_only", "discovered_only", "mixed_unbound")}
    for item in items:
        summary[item["status"].lower()] += 1
    return {"schema_version": 1, "report": "architecture-drift",
            "model_revision": model["model_revision"], "summary": summary,
            "items": items, "limitations": DRIFT_LIMITATIONS}


def build_claim_evidence_report(model: dict) -> dict:
    node_by_id = {node["id"]: node for node in model["nodes"]}
    incoming: dict[str, list[dict]] = {}
    for edge in model["edges"]:
        incoming.setdefault(edge["target"], []).append(edge)
    items = []
    for claim in model["nodes"]:
        if claim["type"] not in CLAIM_TYPES:
            continue
        paths = []
        if claim["type"] == "CAPABILITY":
            for component_edge in incoming.get(claim["id"], []):
                if component_edge["relation"] != "IMPLEMENTS":
                    continue
                component = node_by_id.get(component_edge["source"])
                if component is None or component["type"] != "COMPONENT":
                    continue
                for evidence_edge in incoming.get(component["id"], []):
                    if evidence_edge["relation"] != "DEPENDS_ON":
                        continue
                    evidence = node_by_id.get(evidence_edge["source"])
                    if evidence is not None and evidence["type"] == "EVIDENCE":
                        paths.append((evidence["id"], component["id"], claim["id"]))
        paths = sorted(set(paths))
        items.append({"claim_id": claim["id"],
                      "status": "STATIC_PATH_PRESENT" if paths else "NO_STATIC_EVIDENCE_PATH",
                      "evidence_paths": [list(path) for path in paths]})
    items.sort(key=lambda item: item["claim_id"])
    return {"schema_version": 1, "report": "claim-evidence",
            "model_revision": model["model_revision"],
            "summary": {"claims": len(items),
                        "static_path_present": sum(item["status"] == "STATIC_PATH_PRESENT" for item in items),
                        "no_static_evidence_path": sum(item["status"] == "NO_STATIC_EVIDENCE_PATH" for item in items)},
            "items": items, "limitations": CLAIM_LIMITATIONS}


def impact_node(model: dict, node_id: str, depth: int = 2) -> dict:
    node = next((item for item in model["nodes"] if item["id"] == node_id), None)
    if node is None:
        return {"status": "UNKNOWN", "node": None, "edges": []}
    if depth not in {1, 2}:
        raise SamValidationError("INVALID_MODEL", "$/impact/depth")
    outgoing: dict[str, set[str]] = {}
    incoming: dict[str, set[str]] = {}
    for edge in model["edges"]:
        outgoing.setdefault(edge["source"], set()).add(edge["target"])
        incoming.setdefault(edge["target"], set()).add(edge["source"])

    def reachable(graph: dict[str, set[str]]) -> list[str]:
        found: set[str] = set()
        frontier = {node_id}
        for _ in range(depth):
            next_frontier = {target for source in frontier for target in graph.get(source, set())} - found - {node_id}
            found.update(next_frontier)
            frontier = next_frontier
        return sorted(found)

    return {"root_id": node_id, "depth": depth, "upstream": reachable(incoming),
            "downstream": reachable(outgoing), "limitations": IMPACT_LIMITATIONS}


def build_impact_report(model: dict, verification: dict) -> dict:
    return {"schema_version": 1, "report": "impact", "model_revision": model["model_revision"],
            "items": [impact_node(model, root, 2) for root in verification["impact_roots"]],
            "limitations": IMPACT_LIMITATIONS}


def serialized_outputs(model: dict, root: Path) -> dict[str, bytes]:
    """Return every generated SAM artifact as stable newline-terminated bytes."""
    outputs = {".scm/sam.json": canonical_json(model) + b"\n"}
    for name, view in build_views(model).items():
        outputs[f".scm/views/{name}.json"] = canonical_json(view) + b"\n"
    verification = load_verification_declarations(root, model)
    reports = {
        "drift": build_drift_report(model, verification),
        "claim-evidence": build_claim_evidence_report(model),
        "impact": build_impact_report(model, verification),
    }
    for name, report in reports.items():
        outputs[f".scm/reports/{name}.json"] = canonical_json(report) + b"\n"
    return outputs
