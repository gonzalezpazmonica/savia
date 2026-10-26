#!/usr/bin/env python3
"""SE-400 F2 — grafos de dependencias, contrato y fallos (solo lectura).

Complementa el grafo de consumidores literales de F1 con aristas tipadas y
dirigidas que salen de código ejecutable o de frontmatter declarado:

- ``SOURCES``: ``source``/``.`` de bash resuelto a un fichero versionado.
- ``INVOKES``: ``bash|python3 scripts/<x>`` o ``.opencode|.claude/hooks/<x>``.
- ``IMPORTS``: ``import x``/``from x import`` resuelto a ``scripts/x.py``.
- ``DECLARES_SKILL``/``DELEGATES_TO``/``USES_DECISION_TREE``: frontmatter.
- ``REGISTERED_AT``: evento de settings -> hook.

La matriz evento->hook->fallo describe cada registro de settings: tier del
``profile_gate``, perfiles donde corre, si puede bloquear (``exit 2`` o
decisión ``deny``/``block``), comportamiento ante caída o timeout y si el
hook depende de un modelo (``type: prompt``). Hallazgos, nunca veredictos:
una arista ausente no prueba independencia y un hallazgo no autoriza retirar.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from ablation_inventory import (CONTRACT_PATH, DEFAULT_OUT, InventoryError, _git, canonical,
                                sha256, tracked_files, validate_contract)

REPORT_NAME = "f2-graphs"
LIMITATIONS = [
    "STATIC_TRACKED_TREE_ONLY",
    "EDGES_FROM_LITERAL_PATHS_DYNAMIC_DISPATCH_NOT_RESOLVED",
    "HOOK_REGISTRATION_IS_NOT_INVOCATION",
    "BLOCKING_CAPABILITY_IS_STATIC_NOT_OBSERVED",
    "SHARED_INTERCEPTION_POINT_IS_NOT_REDUNDANCY",
]

PROFILES = ("minimal", "standard", "ci", "strict")
TIER_PROFILES = {
    "security": PROFILES,
    "standard": ("standard", "ci", "strict"),
    "strict": ("strict",),
}
TIER_RE = re.compile(r'profile_gate\s+"?([a-z]+)"?')
BLOCK_RE = re.compile(r'\bexit\s+2\b|"(?:permissionDecision|decision)"\s*:\s*"(?:deny|block)"')
SOURCE_RE = re.compile(r'^\s*(?:source|\.)\s+("[^"\n]*(?:"[^"\n]*"[^"\n]*)*"|\S+)', re.M)
SUFFIX_RE = re.compile(r'(?:\$\{?([A-Za-z_]\w*)\}?|[)}])?(/[^$)}"]+)$')
INVOKE_RE = re.compile(r'(?:\.opencode|\.claude)/hooks/([A-Za-z0-9._-]+)|'
                       r'\b(?:bash|sh|python3?)\s+(?:-[A-Za-z]+\s+)*"?[^"\s]*?(scripts/[A-Za-z0-9._/-]+)')
IMPORT_RE = re.compile(r'^\s*(?:from\s+([A-Za-z_][\w]*)[\w.]*\s+import|import\s+([A-Za-z_][\w]*))', re.M)
HOOK_CMD_RE = re.compile(r"hooks/([A-Za-z0-9._-]+\.sh)")
FM_LIST_RE = re.compile(r"^([a-z_]+):\s*(.*)$")
MAX_BYTES = 1_000_000


def _read(root: Path, rel: str) -> str:
    try:
        data = (root / rel).read_bytes()
    except OSError:
        return ""
    if len(data) > MAX_BYTES or b"\0" in data:
        return ""
    return data.decode("utf-8", "ignore")


def frontmatter(text: str) -> dict[str, list[str]]:
    """Frontmatter YAML mínimo: escalares y listas ``- x``; sin dependencias."""
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end < 0:
        return {}
    out: dict[str, list[str]] = {}
    key = None
    for line in text[4:end].splitlines():
        if line.startswith("  - ") and key:
            out[key].append(line[4:].strip().strip("'\""))
            continue
        match = FM_LIST_RE.match(line)
        if match:
            key, value = match.group(1), match.group(2).strip().strip("'\"")
            if value.startswith("[") and value.endswith("]"):
                out[key] = [v.strip().strip("'\"") for v in value[1:-1].split(",") if v.strip()]
            else:
                out[key] = [value] if value and value not in (">", "|", ">-", "|-") else []
        elif not line.startswith(" "):
            key = None
    return out


def _resolve_source(base: str, target: str, files: dict) -> str | None:
    """Resuelve ``$(dirname "${BASH_SOURCE[0]}")/../x.sh``, ``$LIB_DIR/x.sh``…

    Toma el sufijo literal tras la última expansión y prueba, en orden, el
    directorio del fichero, ``lib/`` (``LIB_DIR``) y ``scripts/``
    (``SCRIPTS_DIR``). Una expansión sin sufijo literal no se resuelve.
    """
    target = target.strip().strip('"').replace('"', "")
    if target.endswith(("2>/dev/null", "||")):
        return None
    match = SUFFIX_RE.search(target)
    if not match:
        return None
    var, suffix = match.group(1) or "", match.group(2)
    here = str(Path(base).parent)
    if target.startswith("/") or target.startswith("$HOME"):
        return None
    if match.start() == 0 and not var and not target.startswith((")", "}")):
        candidates = [suffix.lstrip("/")]
    else:
        candidates = [here + suffix]
        if "LIB" in var:
            candidates.insert(0, here + "/lib" + suffix)
        if "SCRIPTS" in var:
            candidates.insert(0, "scripts" + suffix)
    for cand in candidates:
        norm = _normpath(cand)
        if norm in files:
            return norm
    return None


def _normpath(path: str) -> str:
    parts: list[str] = []
    for part in path.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if parts:
                parts.pop()
            continue
        parts.append(part)
    return "/".join(parts)


def dependency_edges(root: Path, files: dict) -> list[dict]:
    """Aristas tipadas desde hooks, scripts, agents y commands versionados."""
    edges: set[tuple[str, str, str]] = set()
    names = {p.rsplit("/", 1)[1][:-3]: p for p in files
             if p.startswith(".claude/agents/") and p.endswith(".md")}
    skills = {p.split("/")[2]: p for p in files
              if p.startswith(".claude/skills/") and p.endswith("/SKILL.md")}
    for path, (mode, _blob) in sorted(files.items()):
        if mode == "120000":
            continue
        is_code = path.startswith(("scripts/", ".claude/hooks/")) and \
            path.endswith((".sh", ".py", ".bash"))
        if is_code:
            text = _read(root, path)
            for target in SOURCE_RE.findall(text):
                dep = _resolve_source(path, target.split(" 2>")[0].split(" &&")[0], files)
                if dep and dep != path:
                    edges.add((path, dep, "SOURCES"))
            for hook, script in INVOKE_RE.findall(text):
                dep = f".claude/hooks/{hook}" if hook else _normpath(script.rstrip(".,;:)"))
                if dep in files and dep != path:
                    edges.add((path, dep, "INVOKES"))
            if path.endswith(".py"):
                for mod_a, mod_b in IMPORT_RE.findall(text):
                    dep = f"{Path(path).parent}/{mod_a or mod_b}.py"
                    if dep in files and dep != path:
                        edges.add((path, dep, "IMPORTS"))
        elif path.startswith((".claude/agents/", ".claude/commands/")) and path.endswith(".md"):
            fm = frontmatter(_read(root, path))
            for skill in fm.get("skills", []):
                edges.add((path, skills.get(skill, f"MISSING:skill/{skill}"), "DECLARES_SKILL"))
            for agent in fm.get("agent", []):
                if agent not in ("task", "none") and "{" not in agent:
                    edges.add((path, names.get(agent, f"MISSING:agent/{agent}"), "DELEGATES_TO"))
            for tree in fm.get("decision_tree", []):
                dep = _normpath(f".claude/agents/{tree}")
                edges.add((path, dep if dep in files else f"MISSING:{dep}", "USES_DECISION_TREE"))
    return [{"source": s, "target": t, "relation": r} for s, t, r in sorted(edges)]


def hook_tier(text: str) -> str | None:
    match = TIER_RE.search(text)
    return match.group(1) if match else None


def hook_matrix(root: Path, files: dict) -> list[dict]:
    """Un registro por (evento, matcher, hook) de ``.claude/settings.json``."""
    settings = json.loads(_read(root, ".claude/settings.json") or "{}")
    rows = []
    for event, groups in (settings.get("hooks") or {}).items():
        for group in groups:
            matcher = group.get("matcher", "*") or "*"
            for hook in group.get("hooks", []):
                rows.append(_hook_row(root, files, event, matcher, hook))
    seen = Counter((r["event"], r["matcher"], r["hook"]) for r in rows if r["hook"])
    for row in rows:
        if row["hook"] and seen[(row["event"], row["matcher"], row["hook"])] > 1:
            row["findings"].append("DUPLICATE_REGISTRATION")
    return rows


def _hook_row(root: Path, files: dict, event: str, matcher: str, hook: dict) -> dict:
    row = {"event": event, "matcher": matcher, "type": hook.get("type", "command"),
           "hook": None, "timeout_s": hook.get("timeout"), "async": bool(hook.get("async")),
           "tier": None, "profiles": list(PROFILES), "blocking_capable": False,
           "on_crash_or_timeout": "FAIL_OPEN", "model_mediated": False, "findings": []}
    if row["type"] == "prompt":
        row.update({"model_mediated": True, "blocking_capable": True,
                    "on_crash_or_timeout": "UNKNOWN"})
        row["findings"].append("MODEL_MEDIATED_NON_DETERMINISTIC")
        return row
    names = HOOK_CMD_RE.findall(str(hook.get("command", "")))
    if not names:
        row["findings"].append("INLINE_COMMAND")
        return row
    path = f".claude/hooks/{names[0]}"
    row["hook"] = path
    if path not in files:
        row["findings"].append("MISSING_HOOK_FILE")
        return row
    text = _read(root, path)
    row["tier"] = hook_tier(text)
    if row["tier"]:
        row["profiles"] = list(TIER_PROFILES.get(row["tier"], ("strict",)))
        if row["tier"] not in TIER_PROFILES:
            row["findings"].append("UNKNOWN_TIER_SKIPPED_IN_DEFAULT_PROFILE")
    row["blocking_capable"] = bool(BLOCK_RE.search(text))
    if row["async"] and row["blocking_capable"]:
        row["findings"].append("ASYNC_CANNOT_BLOCK")
        row["blocking_capable"] = False
    if not row["blocking_capable"]:
        row["on_crash_or_timeout"] = "NO_EFFECT"
    return row


def matcher_matches(matcher: str, tool: str, command: str = "") -> bool:
    """Semántica de matcher de Claude Code: ``A|B``, ``Tool(glob)`` y regex."""
    if matcher in ("*", ""):
        return True
    for token in matcher.split("|"):
        name, _, pattern = token.partition("(")
        if pattern:
            if name == tool and fnmatch.fnmatchcase(command, pattern.rstrip(")")):
                return True
        elif name == tool or (any(c in name for c in ".*[") and re.fullmatch(name, tool)):
            return True
    return False


def defense_groups(rows: list[dict]) -> list[dict]:
    """Hooks bloqueantes que comparten evento y matcher: solape, no redundancia."""
    groups: dict[tuple[str, str], set[str]] = defaultdict(set)
    for row in rows:
        if row["blocking_capable"] and row["hook"]:
            matcher = "|".join(sorted(row["matcher"].split("|")))
            groups[(row["event"], matcher)].add(row["hook"])
    return [{"event": e, "matcher": m, "blocking_hooks": sorted(h)}
            for (e, m), h in sorted(groups.items()) if len(h) > 1]


def contract_links(rows: list[dict]) -> list[dict]:
    """Hook -> dimensión del contrato, solo con autoridad en código.

    Única autoridad hoy: ``profile_gate "security"`` declara que el hook es
    un blocker de seguridad que corre incluso en el perfil ``minimal``.
    """
    hooks = sorted({r["hook"] for r in rows if r["tier"] == "security" and r["hook"]})
    return [{"source": h, "dimension": "security_floors",
             "basis": 'PROFILE_GATE:security'} for h in hooks]


def summarize(edges: list[dict], rows: list[dict]) -> dict:
    missing = [e for e in edges if e["target"].startswith("MISSING:")]
    return {
        "edges_by_relation": dict(sorted(Counter(e["relation"] for e in edges).items())),
        "dangling_declared": len(missing),
        "hook_registrations": len(rows),
        "registrations_by_event": dict(sorted(Counter(r["event"] for r in rows).items())),
        "blocking_capable": sum(r["blocking_capable"] for r in rows),
        "model_mediated": sum(r["model_mediated"] for r in rows),
        "findings": dict(sorted(Counter(f for r in rows for f in r["findings"]).items())),
    }


def build_graphs(root: Path, files: dict) -> dict:
    edges = dependency_edges(root, files)
    rows = hook_matrix(root, files)
    for row in rows:
        if row["hook"]:
            edges.append({"source": f"settings:{row['event']}", "target": row["hook"],
                          "relation": "REGISTERED_AT"})
    edges.sort(key=lambda e: (e["source"], e["target"], e["relation"]))
    return {"dependency_edges": edges, "hook_matrix": rows,
            "defense_groups": defense_groups(rows), "contract_links": contract_links(rows),
            "summary": summarize(edges, rows)}


def build_report(root: Path) -> dict:
    root = root.resolve()
    contract = validate_contract(_load_json(root / CONTRACT_PATH))
    files = tracked_files(root)
    graphs = build_graphs(root, files)
    scope = sorted(p for p in files if p == ".claude/settings.json"
                   or p.startswith(("scripts/", ".claude/hooks/", ".claude/agents/",
                                    ".claude/commands/")))
    report = {
        "schema": 1, "spec": "SE-400", "phase": "F2",
        "provenance": {
            "contract_version": contract["contract_version"],
            "contract_sha256": sha256(canonical(contract)),
            "surface_sha256": sha256(canonical([[p, files[p][1]] for p in scope])),
        },
        "limitations": LIMITATIONS, **graphs,
    }
    report["report_revision"] = sha256(canonical(report))
    report["head"] = _git(root, "rev-parse", "HEAD").strip()
    return report


def render_md(report: dict) -> str:
    s = report["summary"]
    lines = ["# SE-400 F2 — Grafos de dependencias, contrato y fallos", "",
             f"HEAD (informativo): `{report['head']}`  ",
             f"Revisión del informe: `{report['report_revision'][:12]}`", "",
             "| Relación | Aristas |", "|---|---:|"]
    lines += [f"| {k} | {v} |" for k, v in s["edges_by_relation"].items()]
    lines += ["", f"Declaraciones colgantes: {s['dangling_declared']}. Registros de hook: "
              f"{s['hook_registrations']} ({s['blocking_capable']} pueden bloquear, "
              f"{s['model_mediated']} mediados por modelo).", "",
              "| Hallazgo de la matriz evento→hook→fallo | Registros |", "|---|---:|"]
    lines += [f"| {k} | {v} |" for k, v in s["findings"].items()]
    lines += ["", "| Evento | Matcher | Hooks bloqueantes que comparten punto |", "|---|---|---:|"]
    lines += [f"| {g['event']} | `{g['matcher']}` | {len(g['blocking_hooks'])} |"
              for g in report["defense_groups"]]
    lines += ["", "Limitaciones: " + ", ".join(report["limitations"]) + ".", ""]
    return "\n".join(lines)


def _load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise InventoryError("CONTRACT_MISSING", str(path)) from exc


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
        print(f"ABLATION-F2: INVALID {exc}", file=sys.stderr)
        return 2
    target = out / f"{REPORT_NAME}.json"
    if args.command == "summary":
        print(json.dumps(report["summary"], indent=2, sort_keys=True))
        return 0
    if args.command == "generate":
        out.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (out / f"{REPORT_NAME}.md").write_text(render_md(report), encoding="utf-8")
        print(f"ABLATION-F2: WRITTEN {target} ({len(report['dependency_edges'])} edges)")
        return 0
    try:
        stored = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print(f"ABLATION-F2: MISSING {target}")
        return 1
    if stored.get("report_revision") != report["report_revision"]:
        print("ABLATION-F2: STALE (contenido distinto del árbol actual)")
        return 1
    print(f"ABLATION-F2: FRESH ({len(report['dependency_edges'])} edges)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
