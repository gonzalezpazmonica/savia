#!/usr/bin/env python3
"""SE-527 AC-S0 — ningún agente retirado sigue citado en una referencia viva.

Uso: se527_retired_refs.py [--root DIR] NOMBRE...
Salida: 0 sin referencias · 1 hay referencias (una línea por hallazgo) · 2 uso.

Referencia viva = fichero del repo fuera de la historia (CHANGELOG, specs y propuestas,
evidencias, arneses congelados) que nombra al agente de forma que lo despacha o lo lista:
fichero de agente, `subagent_type`, `agent: <x>`, `Task(<x>`, fila de tabla `| <x> |`,
lista YAML `- <x>`, cadena entre comillas `"<x>"`, ruta `agents/<x>.md`, o el nombre
literal en `scripts/` y `config/`. La prosa con la palabra común no cuenta.
Patrón alineado con R10 de SE-532 (validate-agent-catalog.py --retired).
"""
import os
import re
import subprocess
import sys

SKIP_DIRS = {".git", "node_modules", "__pycache__", "output", "target", ".venv"}
HISTORY_PREFIX = (
    "CHANGELOG", "docs/specs-archive/", "docs/specs/", "docs/propuestas/", "docs/evidence/",
    "docs/ROADMAP.md", "tests/evals/se511-d4/", "tests/evals/se527-s1/", "tests/se527_retired_refs.py",
    "tests/bats/test-se527-s1-retire-unused.bats", "tests/bats/se527-spec-coherence.bats",
)
HISTORY_RE = re.compile(r"^projects/[^/]+/specs/")
EXT = (".md", ".yaml", ".yml", ".json", ".jsonl", ".txt", ".sh", ".py", ".ts", ".js", ".bats", ".toml")
LITERAL_ROOTS = ("scripts/", "config/")


def patterns(name):
    n = re.escape(name)
    a, b = r"(?<![A-Za-z0-9_-])", r"(?![A-Za-z0-9_-])"
    return [
        re.compile(r"subagent_type[\"']?\s*[:=]\s*[\"']?" + n + b),
        re.compile(a + r"agent[\"']?\s*:\s*[\"']?" + n + b),
        re.compile(r"(?:Task|Agent)\(\s*[\"']?" + n + b),
        re.compile(r"^\s*-\s+[\"']?" + n + r"[\"']?\s*$"),
        re.compile(r"\|\s*`?" + n + r"`?\s*\|"),
        re.compile(r"[\"'`]" + n + r"[\"'`]"),
        re.compile(r"agents/" + n + r"\.md"),
    ], re.compile(a + n + b)


def history(rel):
    return rel.startswith(HISTORY_PREFIX) or bool(HISTORY_RE.match(rel))


def iter_files(root):
    """Ficheros versionados o nuevos no ignorados si hay git; si no, recorrido del árbol."""
    if os.path.isdir(os.path.join(root, ".git")) or os.path.isfile(os.path.join(root, ".git")):
        p = subprocess.run(["git", "-C", root, "ls-files", "-co", "--exclude-standard", "-z"],
                           capture_output=True)
        if p.returncode != 0:
            raise SystemExit("git ls-files falló en %s (fail-closed)" % root)
        for rel in p.stdout.decode("utf-8", "surrogateescape").split("\0"):
            if rel and os.path.isfile(os.path.join(root, rel)):
                yield rel
        return
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            yield os.path.relpath(os.path.join(dp, fn), root).replace(os.sep, "/")


def scan(root, names):
    hits = []
    for name in names:
        for side in (".opencode/agents", ".claude/agents"):
            if os.path.exists(os.path.join(root, side, name + ".md")):
                hits.append("%s/%s.md:0: fichero del agente retirado '%s'" % (side, name, name))
    pats = {n: patterns(n) for n in names}
    for rel in iter_files(root):
        full = os.path.join(root, rel)
        if history(rel) or not rel.endswith(EXT) or os.path.islink(full):
            continue
        try:
            with open(full, encoding="utf-8", errors="strict") as fh:
                lines = fh.readlines()
        except (OSError, UnicodeDecodeError) as e:
            # Fail-closed: un fichero que no se puede leer no se da por limpio.
            hits.append("%s:0: no legible (%s)" % (rel, e.__class__.__name__))
            continue
        literal_file = rel.startswith(LITERAL_ROOTS)
        for i, line in enumerate(lines, 1):
            for name, (ctx, lit) in pats.items():
                if (literal_file and lit.search(line)) or any(p.search(line) for p in ctx):
                    hits.append("%s:%d: '%s'" % (rel, i, name))
    return hits


def main(argv):
    root = os.getcwd()
    if argv[:1] == ["--root"]:
        if len(argv) < 2:
            print("uso: se527_retired_refs.py [--root DIR] NOMBRE...", file=sys.stderr)
            return 2
        root, argv = argv[1], argv[2:]
    names = [a for a in argv if a]
    if not names or not os.path.isdir(os.path.join(root, ".opencode", "agents")):
        print("uso: se527_retired_refs.py [--root DIR] NOMBRE... (raíz con .opencode/agents)", file=sys.stderr)
        return 2
    hits = scan(root, names)
    for h in hits:
        print(h)
    print("%s: %d referencia(s) viva(s) a %s" % ("FAIL" if hits else "PASS", len(hits), ", ".join(names)))
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
