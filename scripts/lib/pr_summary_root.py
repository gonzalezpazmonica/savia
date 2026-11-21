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
  3. `git -C <dir> rev-parse --show-toplevel`; si no es un repo, fallo cerrado.
Antes de nada se borran las continuaciones de línea (`\\` + salto), como hace bash, y la
búsqueda de otros `cd` mira el texto sin comillas ni barras (`c\\d`, `c''d`).

Salida: la raíz en stdout, exit 0. Fallo cerrado (exit 2 con motivo en stderr):
JSON malformado, directorio que no es un repo git, `&` entre el `cd` y gh (el `cd`
queda en segundo plano), `cd` cuyo destino no se puede saber sin ejecutar nada (`$VAR`,
`$(…)`, `` ` ``, `~usuario`, `cd -`, `cd` a secas), más de un `cd` (habría que
encadenarlos), un `cd` dentro de un subshell que se cierra antes de gh (`(cd X); gh …`),
`pushd`/`popd` en cualquier posición (`builtin pushd`), `source` o `.` (ejecutan otro
fichero en este shell; `.` también tras salto de línea, `then`, `command`…), un `cd` a una
ruta relativa sin `./` (bash la busca antes en CDPATH, que el hook no ve), `env -C` en cualquier grafía (`-C<ruta>`, `-iC`, `--chdir`,
`--chdir=`) o `env -S`/`--split-string`, cualquier expansión antes de gh (`$x`, `${x}d`,
`$(…)`, `` `…` ``, `$'…'`, `$"…"`: puede formar un `cd` y `$'…'` no se analiza), un
`gh pr create` disfrazado (`\\gh`, `"gh"`) que no se puede situar en la orden, o un
directorio que no existe. Es deliberadamente amplio: `env -uCI` o un `popd` dentro de un
texto previo también bloquean.
Un `&` o un `cd` dentro de una cadena: `&` entre comillas es texto y no se toma por
segundo plano; `cd` entre comillas sí bloquea (`"cd" X` es un `cd` real y sin un
analizador de shell no se distingue de `printf 'cd'`): bloqueo falso, nunca permiso falso.
No hay `-C` en gh: el `-C` de la spec es el de `git -C` y el de `cd`.
Límite conocido: `gh -R <repo> --head <rama>` abre la PR en otro remoto u otra rama;
el resumen que se evalúa sigue siendo el del árbol donde corre gh, no el de esa rama.
Límite conocido: un gh que no se nombra (`$(which gh) pr create`) no lo ve GH_RE y se
resuelve el cwd; tampoco lo ve el grep del gate, que no llega a llamar a este resolvedor
(hueco previo a SE-510, igual en main).
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
# Se busca en el texto sin comillas ni barras y en cualquier posición (`builtin pushd`,
# `env -C/ruta`, `env -iC ruta`): ante la duda, se bloquea.
# `source`/`.` ejecutan otro fichero en ESTE shell (puede hacer `cd`); `env -S`/`--split-string`
# parte un texto en argumentos (`env -S'-C /B gh pr create'`), y `--chdir=` no lleva espacio.
OTHER_CHDIR = re.compile(r"(?<![\w./-])(?:pushd|popd|source)(?![\w./-])"
                         # `.` como orden: al inicio, tras un separador o salto de línea, o tras una
                         # palabra que da paso a una orden (`then . x`, `command . x`) (correctness
                         # 2021f79 P1-1, Codex 2021f79).
                         r"|(?:^|[;&|({!\n]|\b(?:then|do|else|elif|command|builtin|exec|time|eval)\b)\s*\.\s"
                         r"|\benv\b[^;&|()]*[\s=](?:-[A-Za-z]*[CS]|--chdir|--split-string)")
# Una expansión (`$x`, `$(…)`, `` `…` ``, `$'…'`, `$"…"`) antes de gh puede ser el propio `cd`
# (`c$'d' /B`, `x=cd; $x /B`) y el texto entre `$'…'` no se analiza: fallo cerrado.
EXPANSION = re.compile(r"[$`]")
# `&` suelto (no `&&`, `>&`, `&>`, `<&`, `|&`): la lista anterior va a un subshell de fondo y su
# `cd` no llega a gh (`cd X && true & gh pr create`).
BACKGROUND = re.compile(r"(?<![&>|<])&(?![&>])")
CONTINUATION = re.compile(r"\\\r?\n")
# Destino relativo que no empieza por `/`, `.` ni `~`: bash lo busca primero en CDPATH, que
# puede venir del perfil de la shell y que el hook no ve → fallo cerrado (Codex 2021f79).
BARE_RELATIVE = re.compile(r"^[^/.~]")
# Palabra que precede a `pr create`: si es `gh` escrito con barras o comillas cerradas
# (`\\gh`, `"gh"`, `g''h`), es gh para bash pero GH_RE no la ve.
GH_WORD = re.compile(r"(?:^|(?<=[;&|(`\s]))([^\s;&|()]+)(?=\s+pr\s+create(?:[\s;&|)]|$))")


def disguised_gh(word: str) -> bool:
    """`\\gh`, `"gh"`, `/usr/bin/"gh"`; no `'gh` (comilla abierta: es texto de un argumento)."""
    if word == plain(word) or word.count("'") % 2 or word.count('"') % 2:
        return False
    return re.fullmatch(r"(?:\S*/)?gh", plain(word)) is not None


def outside_quotes(text: str) -> str:
    """El texto que bash ve fuera de comillas; lo escapado (`\\&`) es literal y se quita.
    Una comilla sin cerrar deja el resto tal cual (conservador)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c in "'\"":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if (c == '"' and text[j] == "\\") else 1
            if j >= n:
                out.append(text[i:])
                break
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def plain(text: str) -> str:
    """Texto sin comillas ni barras: `c\\d`, `c''d` y `"cd"` son `cd` para bash."""
    return re.sub(r"[\"'\\]", "", text)


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


def rest_after_prefix(head: str) -> str:
    """Lo que hay antes de gh sin el `cd` inicial (su destino ya lo valida UNSAFE)."""
    pre = CD_PREFIX.match(head)
    return head[pre.end():] if pre else head


def cd_target(command: str) -> str | None:
    """Destino del `cd` que precede a `gh pr create`. None si no hay ningún `cd`.

    Solo se sigue un `cd <literal>` al principio de la orden. Cualquier otra palabra `cd`
    (o pushd/popd/env -C) antes de la ÚLTIMA mención de `gh pr create` bloquea: la última,
    porque `echo gh pr create; cd X && gh pr create` menciona gh dos veces."""
    command = CONTINUATION.sub("", command)  # bash borra `\\` + salto antes de partir palabras
    gh = None
    for gh in GH_RE.finditer(command):
        pass
    if any(disguised_gh(m.group(1)) for m in GH_WORD.finditer(command)):
        raise Unresolved("`gh pr create` con comillas o barras (`\\gh`, `\"gh\"`): no se sabe dónde corre")
    if gh is None:
        return None
    head = command[: gh.start() + 1]
    if OTHER_CHDIR.search(plain(head)):
        raise Unresolved("pushd/popd o env -C antes de gh pr create: no se siguen")
    if EXPANSION.search(plain(rest_after_prefix(head))):
        raise Unresolved("expansión (`$…`, `` `…` ``, `$'…'`) antes de gh pr create: puede ser un `cd` "
                         "que no se ve sin ejecutarla")
    pre = CD_PREFIX.match(head)
    rest = head[pre.end():] if pre else head
    if CD_WORD.search(plain(rest)):
        raise Unresolved("un `cd` que no es el primero de la orden (o está en otra posición: "
                         "`||`, pipe, comillas, `bash -c`, subshell…) antes de gh pr create")
    if pre is None:
        return None
    if BACKGROUND.search(outside_quotes(rest)):
        raise Unresolved("`&` entre el `cd` y gh pr create: el `cd` queda en segundo plano")
    if pre.group(1) and ")" in rest:
        raise Unresolved("`cd` dentro de un subshell que se cierra antes de gh pr create")
    arg = pre.group(2)
    try:
        parts = shlex.split(arg)
    except ValueError as exc:
        raise Unresolved(f"destino de `cd` ilegible: {arg}") from exc
    if len(parts) != 1 or UNSAFE.search(parts[0]):
        raise Unresolved(f"destino de `cd` no resoluble sin ejecutar nada: {arg}")
    if BARE_RELATIVE.match(parts[0]):
        raise Unresolved(f"`cd {parts[0]}` relativo sin `./`: bash lo busca antes en CDPATH, que el "
                         "hook no ve; usa `cd ./{0}` o la ruta absoluta".replace("{0}", parts[0]))
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
    raise Unresolved(f"{base} no es un repositorio git: no hay resumen de PR que valga")


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
