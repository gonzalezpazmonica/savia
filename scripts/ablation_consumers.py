"""SE-400 F2 (parcial) — grafo de consumidores estáticos por referencia literal.

Un consumidor es un fichero versionado que nombra un recurso del inventario F1
por su ruta, por ``hooks/<nombre>.sh`` o ``scripts/<nombre>`` con cualquier
prefijo (symlinks ``.opencode/``, ``$CLAUDE_PROJECT_DIR``), por el directorio
de una skill o por la invocación ``/<comando>``. No se excluyen tests: un test
es un consumidor real, y se cuenta aparte.

Vistas generadas, ``.scm/`` y el changelog no cuentan como consumidores
activos: repiten el inventario o la historia. Cero consumidores estáticos
significa solo eso; nunca autoriza DEAD (UNKNOWN != DELETE).
"""
from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path

MAX_BYTES = 1_000_000
TOKEN_RE = re.compile(r"[A-Za-z0-9_$./{}-]+")
PASSIVE_PREFIXES = (".scm/", "CHANGELOG.d/")
PASSIVE_FILES = frozenset({"CHANGELOG.md"})
TEST_PREFIXES = ("tests/",)


def _is_passive(path: str, views: set[str]) -> bool:
    return path in views or path in PASSIVE_FILES or path.startswith(PASSIVE_PREFIXES)


def build_keys(records: list[dict]) -> dict[str, str]:
    """Token normalizado -> ruta del recurso. Claves ambiguas se descartan."""
    keys: dict[str, set[str]] = defaultdict(set)
    for rec in records:
        path, kind = rec["path"], rec["kind"]
        if "#" in path:
            continue
        keys[path].add(path)
        if kind == "hook":
            keys["hooks/" + path.rsplit("/", 1)[1]].add(path)
        elif kind == "script":
            keys[path].add(path)
        elif kind == "skill":
            skill_dir = path.rsplit("/", 1)[0]
            keys[skill_dir].add(path)
            keys["skills/" + skill_dir.rsplit("/", 1)[1]].add(path)
        elif kind == "command":
            stem = path[len(".claude/commands/"):-len(".md")]
            keys["/" + stem].add(path)
            keys["commands/" + stem + ".md"].add(path)
        elif kind == "agent":
            keys["agents/" + path.rsplit("/", 1)[1]].add(path)
    return {key: next(iter(paths)) for key, paths in keys.items() if len(paths) == 1}


def _candidates(token: str):
    token = token.strip("{}`'\"").rstrip(".:,")
    if token.startswith("./"):
        token = token[2:]
    if token.endswith("/SKILL.md"):
        token = token[:-len("/SKILL.md")]
    yield token
    for marker in ("scripts/", "hooks/", "skills/", "agents/", "commands/"):
        idx = token.find(marker)
        if idx > 0:
            yield token[idx:]


def static_consumers(root: Path, files: dict, records: list[dict],
                     views: set[str]) -> dict[str, dict[str, list[str]]]:
    """Devuelve ruta -> {"active": [...], "tests": [...]} ordenados."""
    keys = build_keys(records)
    edges: dict[str, dict[str, set[str]]] = defaultdict(lambda: {"active": set(), "tests": set()})
    for consumer, (mode, _blob) in files.items():
        if mode == "120000" or _is_passive(consumer, views):
            continue
        try:
            data = (root / consumer).read_bytes()
        except OSError:
            continue
        if len(data) > MAX_BYTES or b"\0" in data:
            continue
        bucket = "tests" if consumer.startswith(TEST_PREFIXES) else "active"
        for token in set(TOKEN_RE.findall(data.decode("utf-8", "ignore"))):
            if "/" not in token:
                continue
            for cand in _candidates(token):
                target = keys.get(cand)
                if target and target != consumer:
                    edges[target][bucket].add(consumer)
    return {path: {b: sorted(v) for b, v in e.items()} for path, e in edges.items()}
