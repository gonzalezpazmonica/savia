#!/usr/bin/env python3
"""dispatch-table.py — SE-510 D3: la tabla de despacho PreToolUse se GENERA desde settings.json.

  dispatch-table.py generate   imprime la tabla (stdout)
  dispatch-table.py write      escribe hooks/routing-pretooluse.tsv
  dispatch-table.py check      exit 0 si el fichero coincide con settings.json; exit 1 si no;
                               exit 2 ante cualquier error (fail-closed: nunca PASS por defecto)

Solo se despachan hooks `command` con la forma `[bash ]"$CLAUDE_PROJECT_DIR"/ruta.sh [args]`.
Los hooks de otro tipo (p. ej. `prompt`) no se pueden despachar por shell: salen como
comentario `# EXCLUIDO(tipo)` para que la ausencia sea visible, no silenciosa.
Cualquier otra forma de `command` aborta la generación (exit 2).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETTINGS = ROOT / ".claude" / "settings.json"
TABLE = ROOT / "hooks" / "routing-pretooluse.tsv"
# Args: solo tokens literales; `&&`, `;`, `|`, `$(...)`, `>` o globs abortan (el despachador no los ejecutaría).
CMD_RE = re.compile(r'^(?:bash\s+)?"?\$CLAUDE_PROJECT_DIR"?/([\w./-]+\.sh)((?:\s+[\w./=:,+-]+)*)\s*$')
# Matcher: subconjunto en el que la regex de Claude Code (JS) y la ERE de bash coinciden.
MATCHER_RE = re.compile(r'^[A-Za-z0-9_|.*]+$')
# Tiempo máximo por hook en el despachador; debe cubrir el mayor `timeout` de settings.json.
DISPATCH_TIMEOUT = 100


class TableError(Exception):
    pass


def _matcher(raw):
    m = ".*" if raw in ("", "*", ".*") else raw
    if not isinstance(m, str) or not MATCHER_RE.match(m):
        raise TableError(f"matcher no despachable (solo [A-Za-z0-9_|.*]): {raw!r}")
    try:
        re.compile(f"^({m})$")
    except re.error as exc:
        raise TableError(f"matcher no es una regex válida: {raw!r}: {exc}")
    return m


def build():
    try:
        settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
        groups = settings["hooks"]["PreToolUse"]
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise TableError(f"settings.json ilegible o sin PreToolUse: {exc}")
    rows, excluded, max_timeout = [], [], 0
    if not isinstance(groups, list):
        raise TableError("PreToolUse no es una lista")
    for g in groups:
        if not isinstance(g, dict) or not isinstance(g.get("hooks", []), list) \
                or not all(isinstance(h, dict) for h in g.get("hooks", [])):
            raise TableError(f"grupo PreToolUse con forma inesperada: {g!r}")
        raw = g.get("matcher", "")
        hooks = g.get("hooks", [])
        if all(h.get("type") != "command" for h in hooks):
            excluded += [(raw, h.get("type", "?")) for h in hooks]
            continue
        matcher = _matcher(raw)
        for h in hooks:
            if h.get("type") != "command":
                excluded.append((matcher, h.get("type", "?")))
                continue
            m = CMD_RE.match(h.get("command", ""))
            if not m:
                raise TableError(f"command no despachable: {h.get('command')!r}")
            if ".." in m.group(1).split("/"):
                raise TableError(f"ruta de hook con '..' (fuera del repo): {h.get('command')!r}")
            script = m.group(1) + m.group(2).rstrip()
            desc = (h.get("statusMessage") or m.group(1)).replace("\t", " ").replace("\n", " ")
            # `async: true` en Claude Code no puede bloquear: aquí es bloqueante=no.
            blocking = "no" if h.get("async") is True else "yes"
            rows.append((matcher, script, "spawn", blocking, desc))
            t = h.get("timeout", 0)
            if isinstance(t, bool) or not isinstance(t, (int, float)) or t < 0:
                raise TableError(f"timeout no numérico en {h.get('command')!r}: {t!r}")
            max_timeout = max(max_timeout, t)
    if max_timeout > DISPATCH_TIMEOUT:
        raise TableError(f"timeout de settings ({max_timeout}s) > despachador ({DISPATCH_TIMEOUT}s)")
    if not rows:
        raise TableError("settings.json no deja ningún hook PreToolUse despachable")
    return rows, excluded


def render():
    rows, excluded = build()
    out = [
        "# routing-pretooluse.tsv — GENERADO por scripts/dispatch-table.py desde .claude/settings.json (SE-510 D3)",
        "# No editar a mano: `python3 scripts/dispatch-table.py write`. Un test exige que coincida con settings.json.",
        "# Columnas: matcher<TAB>hook_script [args]<TAB>mode<TAB>bloqueante<TAB>descripcion",
        "# bloqueante=yes: exit 2, exit distinto de 0, tiempo agotado o hook ausente => el despachador sale 2.",
        "# bloqueante=no (async:true en settings.json): corre tras los bloqueantes; su fallo solo avisa.",
        "# Orden = orden de settings.json (el primer exit 2 corta). Un comando repetido corre una vez.",
    ]
    out += [f"# EXCLUIDO({t}) matcher={m}: no se despacha por shell" for m, t in excluded]
    out += ["\t".join(r) for r in rows]
    return "\n".join(out) + "\n"


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    try:
        text = render()
        if cmd == "generate":
            sys.stdout.write(text)
        elif cmd == "write":
            TABLE.write_text(text, encoding="utf-8")
        elif cmd == "check":
            current = TABLE.read_text(encoding="utf-8")
            if current != text:
                print("DRIFT: hooks/routing-pretooluse.tsv no coincide con .claude/settings.json", file=sys.stderr)
                return 1
            print("OK: tabla de despacho = settings.json")
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (TableError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # fail-closed: un error inesperado nunca sale 1 (DRIFT) ni 0
        print(f"ERROR inesperado: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
