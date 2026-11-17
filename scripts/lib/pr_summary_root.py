#!/usr/bin/env python3
"""pr_summary_root.py — árbol cuyo .pr-summary.md vale para un `gh pr create` (SE-510 F3).

El gate de resumen leía `$CLAUDE_PROJECT_DIR/.pr-summary.md`: desde un worktree se
evaluaba el resumen de otra carpeta (caso real F3, 97 h). Aquí se resuelve el
directorio donde corre `gh` y se devuelve la raíz git de ese árbol.

Uso: python3 pr_summary_root.py <raíz-de-respaldo>   (entrada del hook en stdin)

Entrada: el JSON del hook (`tool_input.command`, `cwd`) o la orden en texto plano.
Orden de resolución del directorio base:
  1. `cwd` de la entrada; sin él, la raíz de respaldo (el comportamiento anterior).
  2. Un único `cd <ruta>` que sea lo primero de la orden (`cd X && gh …`, `(cd X; gh …)`),
     relativo a la base. Cualquier otro `cd` antes del último `gh pr create` bloquea.
  3. `git -C <dir> rev-parse --show-toplevel`; si no es un repo, el directorio mismo.

Salida: la raíz en stdout, exit 0. Fallo cerrado (exit 2 con motivo en stderr):
JSON malformado, `cd` cuyo destino no se puede saber sin ejecutar nada (`$VAR`,
`$(…)`, `` ` ``, `~usuario`, `cd -`, `cd` a secas), más de un `cd` (habría que
encadenarlos), un `cd` dentro de un subshell que se cierra antes de gh (`(cd X); gh …`),
`pushd`/`popd` o `env -C`/`--chdir`, o un directorio que no existe.
No hay `-C` en gh: el `-C` de la spec es el de `git -C` y el de `cd`; `gh -R`
apunta al remoto, no al árbol, y no cambia nada aquí.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys

GH_RE = re.compile(r"(?:^|[;&|(`\s])(?:[^\s;&|()]*/)?gh\s+pr\s+create(?=[\s;&|)'\"}]|$)")
# Única forma de `cd` que se sigue: es lo PRIMERO de la orden (`cd X && …`, `cd X; …`,
# `(cd X; …`), con un destino de una sola palabra.
CD_PREFIX = re.compile(r"^\s*(\(\s*)?cd\s+(\"[^\"]*\"|'[^']*'|[^\s;&|()]+)\s*(?:&&|;)\s*")
# Cualquier otra aparición de `cd` como palabra (tras `builtin`, `command`, `||`, `|`, un
# salto de línea, comillas, `{`, `then`, `bash -c '…'`…): no se sabe si se ejecuta ni en qué
# orden → fallo cerrado. Es deliberadamente amplio: ante la duda, se bloquea.
CD_WORD = re.compile(r"(?<![\w./-])(?:cd|chdir)(?![\w./-])")
UNSAFE = re.compile(r"[$`]|^~[^/]|^-$")
# Otras formas de cambiar de directorio que no se siguen: fallo cerrado.
OTHER_CHDIR = re.compile(r"(?:(?:^|[;&|(]|\$\()\s*(?:pushd|popd)(?=\s|$|[;&|)]))"
                         r"|(?:\benv\b[^;&|()]*\s(?:-C|--chdir)(?:=|\s|$))")


class Unresolved(Exception):
    pass


def parse_input(raw: str) -> tuple[str, str | None]:
    """(orden, cwd) de la entrada del hook. Texto plano → (texto, None)."""
    text = raw.strip()
    if not text.startswith("{"):
        return raw, None
    try:
        doc = json.loads(text)
    except json.JSONDecodeError as exc:
        raise Unresolved(f"entrada del hook malformada ({exc.msg})") from exc
    if not isinstance(doc, dict):
        raise Unresolved("entrada del hook no es un objeto")
    ti = doc.get("tool_input") or {}
    cmd = ti.get("command", "") if isinstance(ti, dict) else ""
    cwd = doc.get("cwd")
    return (cmd if isinstance(cmd, str) else ""), (cwd if isinstance(cwd, str) and cwd else None)


def cd_target(command: str) -> str | None:
    """Destino del `cd` que precede a `gh pr create`. None si no hay ningún `cd`.

    Solo se sigue un `cd <literal>` al principio de la orden. Cualquier otra palabra `cd`
    (o pushd/popd/env -C) antes de la ÚLTIMA mención de `gh pr create` bloquea: la última,
    porque `echo gh pr create; cd X && gh pr create` menciona gh dos veces."""
    gh = None
    for gh in GH_RE.finditer(command):
        pass
    if gh is None:
        return None
    head = command[: gh.start() + 1]
    if OTHER_CHDIR.search(head):
        raise Unresolved("pushd/popd o env -C antes de gh pr create: no se siguen")
    pre = CD_PREFIX.match(head)
    rest = head[pre.end():] if pre else head
    if CD_WORD.search(rest):
        raise Unresolved("un `cd` que no es el primero de la orden (o está en otra posición: "
                         "`||`, pipe, comillas, `bash -c`, subshell…) antes de gh pr create")
    if pre is None:
        return None
    if pre.group(1) and ")" in rest:
        raise Unresolved("`cd` dentro de un subshell que se cierra antes de gh pr create")
    arg = pre.group(2)
    try:
        parts = shlex.split(arg)
    except ValueError as exc:
        raise Unresolved(f"destino de `cd` ilegible: {arg}") from exc
    if len(parts) != 1 or UNSAFE.search(parts[0]):
        raise Unresolved(f"destino de `cd` no resoluble sin ejecutar nada: {arg}")
    return os.path.expanduser(parts[0])


def resolve(raw: str, fallback: str) -> str:
    command, cwd = parse_input(raw)
    base = cwd or fallback
    target = cd_target(command)
    if target is not None:
        base = os.path.normpath(os.path.join(base, target))
    if not os.path.isdir(base):
        raise Unresolved(f"el directorio donde corre gh no existe: {base}")
    res = subprocess.run(["git", "-C", base, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, timeout=5)
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip()
    return base


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("uso: pr_summary_root.py <raíz-de-respaldo>  (entrada en stdin)", file=sys.stderr)
        return 2
    try:
        print(resolve(sys.stdin.read(), argv[1]))
    except (Unresolved, subprocess.TimeoutExpired, OSError) as exc:
        print(f"BLOQUEADO [pr-summary-gate]: no se sabe en qué árbol corre gh: {exc}. "
              "Ejecuta gh desde el worktree o con `cd <ruta literal> && gh pr create …`.",
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
