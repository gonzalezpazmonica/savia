#!/usr/bin/env python3
"""pr_summary_root.py — árbol cuyo .pr-summary.md vale para un `gh pr create` (SE-510 F3).

El gate de resumen leía `$CLAUDE_PROJECT_DIR/.pr-summary.md`: desde un worktree se
evaluaba el resumen de otra carpeta (caso real F3, 97 h). Aquí se resuelve el
directorio donde corre `gh` y se devuelve la raíz git de ese árbol.

Uso: python3 pr_summary_root.py <raíz-de-respaldo>   (entrada del hook en stdin)

Entrada: el JSON del hook (`tool_input.command`, `cwd`) o la orden en texto plano.
Orden de resolución del directorio base:
  1. `cwd` de la entrada; sin él, la raíz de respaldo (el comportamiento anterior).
  2. Un `cd <ruta>` anterior a `gh pr create` en la misma línea (`cd X && gh …`,
     `(cd X; gh …)`), relativo a la base.
  3. `git -C <dir> rev-parse --show-toplevel`; si no es un repo, el directorio mismo.

Salida: la raíz en stdout, exit 0. Fallo cerrado (exit 2 con motivo en stderr):
JSON malformado, `cd` cuyo destino no se puede saber sin ejecutar nada (`$VAR`,
`$(…)`, `` ` ``, `~usuario`, `cd -`, `cd` a secas) o un directorio que no existe.
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

GH_RE = re.compile(r"(?:^|[;&|(`\s])(?:[^\s;&|()]*/)?gh\s+pr\s+create(?:\s|$)")
# `cd <arg>` al inicio de una orden (principio o tras separador / subshell).
CD_RE = re.compile(r"(?:^|[;&|(]|\$\()\s*cd(?:\s+(\"[^\"]*\"|'[^']*'|[^\s;&|()]+))?\s*(?=$|[;&|)])")
# Cualquier `cd` en posición de orden (también `cd $(…)`, `cd "$x"y`): si hay más de los que
# CD_RE entiende, alguno no se sabe adónde va → fallo cerrado.
CD_ANY = re.compile(r"(?:^|[;&|(]|\$\()\s*cd(?=\s|$|[;&|)])")
UNSAFE = re.compile(r"[$`]|^~[^/]|^-$")


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
    """Destino del último `cd` antes de `gh pr create`. None si no hay `cd`."""
    gh = GH_RE.search(command)
    if not gh:
        return None
    head = command[: gh.start() + 1]
    parsed = list(CD_RE.finditer(head))
    if len(parsed) != len(CD_ANY.findall(head)):
        raise Unresolved("`cd` con un destino que no se entiende antes de gh pr create")
    last = parsed[-1] if parsed else None
    if last is None:
        return None
    arg = last.group(1)
    if arg is None:
        raise Unresolved("`cd` sin destino antes de gh pr create (iría a HOME)")
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
