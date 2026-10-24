#!/usr/bin/env python3
"""SE-400 F1 — normalización Resource/Capability de solo lectura.

Superpone una clasificación sobre el SAM (SE-397) sin crear otro grafo:
cada registro apunta, si existe, al nodo CAPABILITY del SAM. Solo asigna una
clase taxonómica cuando hay autoridad verificable (SAM, settings, registry de
packs, generator declarado o symlink); en otro caso queda ``UNKNOWN``.

F1 no tiene receipts de ablación: ningún registro puede salir CORE_*, MERGE,
REDUNDANT_CANDIDATE ni DEAD, y UNKNOWN nunca lleva acción de retirada.
Frescura por contenido (hashes de blobs), no por commit: HEAD es informativo.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

from ablation_consumers import static_consumers

CONTRACT_PATH = "config/ablation-contract.json"
DEFAULT_OUT = "output/ablation"
REPORT_NAME = "f1-inventory"
FRONTENDS = (".claude", ".opencode", ".agents")
MODEL_KEYS = frozenset({"model", "model_id", "provider", "frontend", "baseline_model"})
CONSUMED_KINDS = frozenset({"command", "skill", "agent", "hook", "script", "rule"})
REMOVAL_ACTIONS = frozenset({"delete", "remove", "retire"})
REQUIRED_FLOORS = ("authority_effect_correctness", "security_floors")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
HOOK_RE = re.compile(r"hooks/([A-Za-z0-9._-]+\.sh)")
LIMITATIONS = [
    "NO_ABLATION_RECEIPTS_ESSENTIALITY_UNKNOWN",
    "NO_SEMANTIC_EQUIVALENCE",
    "STATIC_TRACKED_TREE_ONLY",
    "HOOK_REGISTRATION_IS_NOT_INVOCATION",
    "STATIC_CONSUMERS_ARE_LITERAL_REFERENCES_NOT_USAGE",
]


class InventoryError(Exception):
    def __init__(self, code: str, where: str) -> None:
        self.code, self.where = code, where
        super().__init__(f"{code}: {where}")


def canonical(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _walk_keys(value: object):
    if isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from _walk_keys(item)
    elif isinstance(value, list):
        for item in value:
            yield from _walk_keys(item)


def validate_contract(contract: dict) -> dict:
    """Valida el contrato base: versionado y sin modelo como baseline (AC01/AC02)."""
    if contract.get("schema") != 1:
        raise InventoryError("CONTRACT_SCHEMA", "schema")
    if not SEMVER_RE.match(str(contract.get("contract_version", ""))):
        raise InventoryError("CONTRACT_VERSION", "contract_version")
    base = contract.get("baseline") or {}
    bad = sorted(set(_walk_keys(base)) & MODEL_KEYS)
    if bad:
        raise InventoryError("MODEL_AS_BASELINE", ",".join(bad))
    dims = base.get("dimensions") or []
    if not dims or len(dims) != len(set(dims)):
        raise InventoryError("CONTRACT_DIMENSIONS", "baseline.dimensions")
    floors = base.get("non_compensable_floors") or []
    if not set(floors) <= set(dims) or not set(REQUIRED_FLOORS) <= set(floors):
        raise InventoryError("CONTRACT_FLOORS", "baseline.non_compensable_floors")
    if "FALSE_ALLOW" not in (base.get("abort_conditions") or []):
        raise InventoryError("CONTRACT_ABORT", "baseline.abort_conditions")
    tax = contract.get("taxonomy") or {}
    ess = set(tax.get("essentiality") or [])
    receipt = set(tax.get("requires_ablation_receipt") or [])
    removal = set(tax.get("physical_removal_states") or [])
    if "UNKNOWN" not in set(tax.get("classes") or []) or "UNKNOWN" not in ess:
        raise InventoryError("TAXONOMY_UNKNOWN", "taxonomy")
    if not removal or not removal <= receipt <= ess:
        raise InventoryError("TAXONOMY_GATES", "taxonomy.physical_removal_states")
    return contract


def validate_record(rec: dict, contract: dict) -> None:
    """Gates de seguridad por registro (AC09/AC34): F1 no autoriza retiradas."""
    tax = contract["taxonomy"]
    where = rec.get("path", "?")
    if rec.get("class") not in tax["classes"]:
        raise InventoryError("UNKNOWN_CLASS", where)
    ess = rec.get("essentiality")
    if ess not in tax["essentiality"]:
        raise InventoryError("UNKNOWN_ESSENTIALITY", where)
    if rec["class"] != "UNKNOWN" and not rec.get("basis"):
        raise InventoryError("CLASS_WITHOUT_AUTHORITY", where)
    if ess in tax["requires_ablation_receipt"]:
        if not SHA_RE.match(str(rec.get("ablation_receipt", ""))):
            raise InventoryError("ESSENTIALITY_WITHOUT_RECEIPT", where)
        if ess in tax["physical_removal_states"] and not rec.get("human_gate"):
            raise InventoryError("REMOVAL_WITHOUT_HUMAN_GATE", where)
    action = str(rec.get("recommended_action", "")).lower()
    if action in REMOVAL_ACTIONS and ess not in tax["physical_removal_states"]:
        raise InventoryError("REMOVAL_ACTION_NOT_ALLOWED", where)


def _glob_re(pattern: str) -> re.Pattern:
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif pattern.startswith("**", i):
            out, i = out + ".*", i + 2
        elif pattern[i] == "*":
            out, i = out + "[^/]*", i + 1
        else:
            out, i = out + re.escape(pattern[i]), i + 1
    return re.compile(f"^{out}$")


def _git(root: Path, *args: str) -> str:
    proc = subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                          text=True, check=False)
    if proc.returncode != 0:
        raise InventoryError("GIT", " ".join(args))
    return proc.stdout


def tracked_files(root: Path) -> dict[str, tuple[str, str]]:
    """path -> (mode, blob sha) del índice git: superficie reproducible."""
    files = {}
    for line in _git(root, "ls-files", "-s", "-z").split("\0"):
        if line:
            meta, path = line.split("\t", 1)
            mode, blob, _stage = meta.split()
            files[path] = (mode, blob)
    return files


def _read_json(root: Path, rel: str, code: str) -> dict:
    try:
        return json.loads((root / rel).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise InventoryError(code, rel) from exc


def _sam_index(root: Path) -> tuple[dict[str, str], str]:
    sam = _read_json(root, ".scm/sam.json", "SAM_MISSING")
    caps = {e["source"][len("component/"):]: e["target"]
            for e in sam.get("edges", []) if e.get("relation") == "IMPLEMENTS"
            and str(e.get("source", "")).startswith("component/")}
    return caps, str(sam.get("model_revision", "UNKNOWN"))


def _hook_events(root: Path) -> dict[str, list[str]]:
    settings = _read_json(root, ".claude/settings.json", "SETTINGS_MISSING")
    events: dict[str, set[str]] = defaultdict(set)
    for event, groups in (settings.get("hooks") or {}).items():
        for group in groups:
            for hook in group.get("hooks", []):
                for name in HOOK_RE.findall(str(hook.get("command", ""))):
                    events[f".claude/hooks/{name}"].add(event)
    return {path: sorted(evs) for path, evs in events.items()}


def _origin(path: str) -> str:
    head = path.split("/", 1)[0]
    return head if head in FRONTENDS else "neutral"


def classify(path: str, kind: str, mode: str, ctx: dict) -> dict:
    rec = {"path": path, "kind": kind, "origin": _origin(path), "class": "UNKNOWN",
           "essentiality": "UNKNOWN", "sam_capability": ctx["sam"].get(path),
           "basis": [], "hypotheses": [], "unknowns": []}
    views = ctx["views"]
    if mode == "120000":
        rec.update({"class": "Projection", "essentiality": "RUNTIME_PROJECTION"})
        link = ctx["root"] / path
        rec["basis"].append(f"SYMLINK:{link.readlink()}" if link.is_symlink() else "SYMLINK")
    elif path in views:
        if views[path] in ctx["files"]:
            rec.update({"class": "GeneratedView", "essentiality": "GENERATED_VIEW"})
            rec["basis"].append(f"GENERATOR:{views[path]}")
        else:
            rec["unknowns"].append("GENERATOR_MISSING")
    elif kind == "hook":
        if path in ctx["hooks"]:
            rec["class"] = "Control"
            rec["basis"].append("SETTINGS:" + ",".join(ctx["hooks"][path]))
        else:
            rec["unknowns"].append("NOT_REGISTERED_IN_SETTINGS")
    elif kind == "script":
        rec["class"] = "Script"
        rec["basis"].append("PATH:scripts/")
    elif kind == "rule":
        rec["hypotheses"].append("CONTROL_OR_DOCUMENTATION")
    elif rec["sam_capability"]:
        rec["class"] = "Capability"
    elif kind == "agent" and path.startswith(".claude/agents/"):
        twin = ".opencode/agents/" + path.rsplit("/", 1)[1]
        if twin in ctx["files"]:
            rec["basis"].append(f"MIRROR_OF:{twin}")
            rec["hypotheses"].append("PROJECTION_OR_COMPATIBILITY")
    elif kind == "command":
        rec["hypotheses"].append("PACK_OR_ALIAS")
    if rec["sam_capability"]:
        rec["basis"].append(f"SAM:{rec['sam_capability']}")
    elif kind in ("command", "skill", "agent", "script") and rec["class"] != "Projection":
        rec["unknowns"].append("NOT_INDEXED_IN_SAM")
    return rec


def build_report(root: Path) -> dict:
    root = root.resolve()
    contract = validate_contract(_read_json(root, CONTRACT_PATH, "CONTRACT_MISSING"))
    files = tracked_files(root)
    sam, sam_rev = _sam_index(root)
    ctx = {"root": root, "files": files, "sam": sam, "hooks": _hook_events(root),
           "views": {v["path"]: v["generator"] for v in contract["generated_views"]}}
    rules = [(s["kind"], _glob_re(s["pattern"])) for s in contract["surface"]]
    records = []
    for path in sorted(files):
        kind = next((k for k, rx in rules if rx.match(path)), None)
        if path in ctx["views"]:
            kind = "generated_view"
        if kind == "frontend_link" and files[path][0] != "120000":
            kind = None
        if kind:
            records.append(classify(path, kind, files[path][0], ctx))
    packs = _read_json(root, "config/domain-packs.json", "PACKS_MISSING")
    for pack in packs.get("packs", []):
        records.append({"path": f"config/domain-packs.json#{pack['id']}", "kind": "pack",
                        "origin": "neutral", "class": "DomainPack",
                        "essentiality": "DOMAIN_PACK", "sam_capability": None,
                        "basis": ["REGISTRY:config/domain-packs.json"],
                        "hypotheses": [], "unknowns": []})
    consumers = static_consumers(root, files, records, set(ctx["views"]))
    for rec in records:
        edges = consumers.get(rec["path"], {})
        rec["static_consumers"] = {b: len(edges.get(b, [])) for b in ("active", "tests")}
        if rec["kind"] in CONSUMED_KINDS and not any(rec["static_consumers"].values()):
            rec["unknowns"].append("NO_STATIC_CONSUMER")
        validate_record(rec, contract)
    surface = sha256(canonical([[r["path"], files.get(r["path"], ("", ""))[1]]
                                for r in records]))
    report = {
        "schema": 1, "spec": "SE-400", "phases": ["F1", "F2-static-consumers"],
        "provenance": {
            "contract_version": contract["contract_version"],
            "contract_sha256": sha256(canonical(contract)),
            "sam_model_revision": sam_rev,
            "scm_hash": str(_read_json(root, ".scm/resources.json", "SCM_MISSING").get("hash")),
            "surface_sha256": surface,
        },
        "summary": summarize(records),
        "limitations": LIMITATIONS,
        "records": records,
    }
    report["report_revision"] = sha256(canonical(report))
    report["head"] = _git(root, "rev-parse", "HEAD").strip()
    return report


def summarize(records: list[dict]) -> dict:
    by_kind: dict[str, Counter] = defaultdict(Counter)
    by_origin: dict[str, Counter] = defaultdict(Counter)
    for rec in records:
        by_kind[rec["kind"]]["physical"] += 1
        by_kind[rec["kind"]]["indexed_in_sam"] += bool(rec["sam_capability"])
        sc = rec.get("static_consumers", {})
        by_kind[rec["kind"]]["only_test_consumers"] += bool(sc.get("tests") and not sc.get("active"))
        by_origin[rec["origin"]][rec["kind"]] += 1
    unknowns = Counter(u for rec in records for u in rec["unknowns"])
    hypotheses = Counter(h for rec in records for h in rec["hypotheses"])
    return {
        "records": len(records),
        "by_kind": {k: dict(v) for k, v in sorted(by_kind.items())},
        "by_class": dict(sorted(Counter(r["class"] for r in records).items())),
        "by_essentiality": dict(sorted(Counter(r["essentiality"] for r in records).items())),
        "by_origin": {k: dict(sorted(v.items())) for k, v in sorted(by_origin.items())},
        "unknown_reasons": dict(sorted(unknowns.items())),
        "hypotheses": dict(sorted(hypotheses.items())),
    }


def render_md(report: dict) -> str:
    s, p = report["summary"], report["provenance"]
    lines = ["# SE-400 F1 — Inventario Resource/Capability", "",
             f"HEAD (informativo): `{report['head']}`  ",
             f"Revisión del informe: `{report['report_revision'][:12]}`", "",
             "| Procedencia | Valor |", "|---|---|"]
    lines += [f"| {k} | `{v}` |" for k, v in sorted(p.items())]
    lines += ["", "| Kind | Física | Indexada en SAM | Solo consumidores test |",
              "|---|---:|---:|---:|"]
    lines += [f"| {k} | {v.get('physical', 0)} | {v.get('indexed_in_sam', 0)} "
              f"| {v.get('only_test_consumers', 0)} |" for k, v in s["by_kind"].items()]
    for title, key in (("Clase", "by_class"), ("Essentiality", "by_essentiality"),
                       ("Motivo UNKNOWN", "unknown_reasons"),
                       ("Hipótesis (no autoritativas)", "hypotheses")):
        lines += ["", f"| {title} | Registros |", "|---|---:|"]
        lines += [f"| {k} | {v} |" for k, v in s[key].items()]
    lines += ["", "Limitaciones: " + ", ".join(report["limitations"]) + ".", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("command", choices=("generate", "check", "summary"))
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--out", default=None, help=f"directorio (por defecto {DEFAULT_OUT})")
    args = ap.parse_args(argv)
    root = Path(args.root)
    out = Path(args.out) if args.out else root / DEFAULT_OUT
    try:
        report = build_report(root)
    except InventoryError as exc:
        print(f"ABLATION-F1: INVALID {exc}", file=sys.stderr)
        return 2
    target = out / f"{REPORT_NAME}.json"
    if args.command == "summary":
        print(json.dumps(report["summary"], indent=2, sort_keys=True))
        return 0
    if args.command == "generate":
        out.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (out / f"{REPORT_NAME}.md").write_text(render_md(report), encoding="utf-8")
        print(f"ABLATION-F1: WRITTEN {target} ({report['summary']['records']} records)")
        return 0
    try:
        committed = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print(f"ABLATION-F1: MISSING {target}")
        return 1
    if committed.get("report_revision") != report["report_revision"]:
        print("ABLATION-F1: STALE (contenido distinto del árbol actual)")
        return 1
    print(f"ABLATION-F1: FRESH ({report['summary']['records']} records)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
