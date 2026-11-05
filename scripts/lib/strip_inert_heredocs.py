#!/usr/bin/env python3
"""strip_inert_heredocs.py — quita de una orden de shell el TEXTO de los
heredocs que solo escriben un fichero, para que los guards no confundan
instrucciones escritas en un fichero con órdenes que se ejecutan.

Uso:    strip_inert_heredocs.py   (orden por stdin, orden filtrada por stdout)

Se quita el cuerpo SOLO si todo esto se cumple (lista blanca, fail-closed):
  - la línea del heredoc es `cat … > fichero <<DELIM` o `tee [-a] fichero <<DELIM`
    (redirección `>`/`>>` en cat; en ambos, un único heredoc en la línea);
  - esa línea no tiene `|`, `;`, `&`, `(`, `)`, `$(` ni comillas invertidas:
    nada encadenado que pueda leer o ejecutar lo escrito; ni ella ni la
    anterior acaban en `\` (bash uniría la línea siguiente a la orden);
  - el delimitador es una palabra entera (`<<EOF'X'` o `<<EOF\X` delimitan
    con `EOFX`: no se reconoce y no se quita nada);
  - el heredoc termina (línea DELIM; con `<<-`, tabuladores iniciales);
  - si el delimitador no va entre comillas, el cuerpo no tiene `$(` ni
    comillas invertidas (bash las ejecutaría al expandir el cuerpo);
  - el destino es una ruta literal (`[A-Za-z0-9_./-]`): sin `$`, `~`, comillas
    ni glob; y no se ejecuta solo fuera de la orden: nada bajo `.git/` (hooks,
    config), `.claude/`, `.opencode/` o `.github/`, ni ficheros de arranque
    del shell (`.bashrc`, `.profile`, `profile.d/`…). El resto de la orden
    tampoco nombra uno de esos ficheros ni una ruta con `~` (no copia allí
    el fichero escrito);
  - TODO lo que queda de la orden fuera de esos cuerpos son órdenes de una
    lista cerrada que solo leen o escriben datos (cat, tee, echo, grep…), sin
    `$`, comillas invertidas ni `#`. Nunca se infiere que algo es inerte por
    buscar el nombre del fichero: `export BASH_ENV=…` antes, `bash /tmp/x-*`
    o `npm test` después, o cualquier orden desconocida, conservan TODO.
  - si algún heredoc de la orden no cumple lo anterior, no se quita ninguno.
Todo lo demás se devuelve intacto: `bash <<EOF`, `sh -c`, `cat <<EOF | bash`,
`python3 - <<EOF`, `cat <<EOF` a stdout, heredocs sin cerrar. La línea del
heredoc y el delimitador se conservan; las órdenes posteriores, también.

Sin dependencias externas; sin red.
"""
import re
import shlex
import sys

HEREDOC = re.compile(r"(?<!<)<<(?!<)(-?)[ \t]*(['\"]?)([A-Za-z_][\w.-]*)\2(?=[ \t<>]|$)")
UNSAFE_LINE = re.compile(r"[|;&()`]|\$\(|\\$")
LITERAL_TARGET = re.compile(r"[A-Za-z0-9_./-]+")
# Órdenes que no ejecutan sus argumentos, su stdin ni ficheros (lista cerrada).
INERT = {"cat", "tee", "echo", "printf", "grep", "wc", "head", "tail", "cut", "tr",
         "ls", "mkdir", "true", "false", ":"}
SEPARATORS = set(";&|\n()")
# Ficheros que se ejecutan solos, fuera de la orden: config de git, arranque de
# shells, hooks y plugins de los frontends, workflows de CI.
AUTORUN = re.compile(r"(^|/)\.git(/|$)|(^|/)\.(bashrc|bash_profile|bash_login|bash_logout|"
                     r"bash_aliases|profile|zshrc|zprofile|zshenv|zlogin|zlogout|envrc)$"
                     r"|(^|/)profile\.d(/|$)|(^|/)\.config/fish(/|$)"
                     r"|(^|/)\.(claude|opencode|github)(/|$)")
LEAD = re.compile(r"^[ \t]*(?:[A-Za-z_][A-Za-z0-9_]*=\S*[ \t]+)*(cat|tee)(?=[ \t])")


def _target(line, prog):
    """Fichero que escribe la línea, o None si no escribe uno con certeza."""
    rest = HEREDOC.sub(" ", line[LEAD.match(line).end():])
    if prog == "cat":
        m = re.search(r"(?<![0-9&])>>?[ \t]*([^\s<>]+)", rest)
        return m.group(1).strip("'\"") if m else None
    words = [w for w in re.sub(r"[0-9]*>>?[ \t]*\S+", " ", rest).split()]
    files = [w.strip("'\"") for w in words if not w.startswith("-")]
    return files[0] if len(files) == 1 else None


def rest_is_inert(text):
    """True si cada orden de `text` empieza por una palabra de INERT."""
    if "$" in text or "`" in text or "#" in text:
        return False
    try:
        # Cada línea cierra sus comillas: si no, una cadena de varias líneas
        # podría envolver la línea del heredoc y el «cuerpo» sería orden.
        for line in text.split("\n"):
            shlex.split(line, comments=False, posix=True)
        lex = shlex.shlex(text, posix=True, punctuation_chars=";&|\n()<>")
        lex.whitespace = " \t\r"
        lex.whitespace_split = True
        lex.commenters = ""
        start = True
        for token in lex:
            if token and all(c in SEPARATORS for c in token):
                start = True
            elif token.startswith("~") or AUTORUN.search(token):
                # `cat n.md >> ~/.bashrc`, `tee -a .git/hooks/x`: copia el texto
                # «inerte» a un fichero que se ejecuta solo (revisión #1483 P2-1).
                return False
            elif start:
                if token not in INERT:
                    return False
                start = False
    except ValueError:  # comillas sin cerrar: no se sabe dónde acaba nada
        return False
    return True


def _span(lines, i):
    """Índice de la línea DELIM si `lines[i]` abre un heredoc que solo escribe
    un fichero literal; None si la línea no tiene heredoc; False si lo tiene
    pero no se puede probar inerte."""
    line = lines[i]
    found = HEREDOC.findall(line)
    if not found and "<<" not in line.replace("<<<", ""):
        return None
    lead = LEAD.match(line)
    if len(found) != 1 or not lead or UNSAFE_LINE.search(line) \
            or (i > 0 and lines[i - 1].endswith("\\")):
        return False
    dash, quote, delim = found[0]
    target = _target(line, lead.group(1))
    end = next((j for j in range(i + 1, len(lines))
                if (lines[j].lstrip("\t") if dash else lines[j]) == delim), None)
    if not target or end is None or not LITERAL_TARGET.fullmatch(target) \
            or AUTORUN.search(target):
        return False
    body = "\n".join(lines[i + 1:end])
    if not quote and ("$(" in body or "`" in body):
        return False
    return end


def strip(command):
    lines = command.split("\n")
    out, rest, i = [], [], 0
    while i < len(lines):
        end = _span(lines, i)
        if end is False:
            return command  # un heredoc dudoso: no se quita ninguno
        if end is None:
            out.append(lines[i])
            rest.append(lines[i])
            i += 1
            continue
        out.extend([lines[i], lines[end]])
        rest.append(lines[i])  # la línea del heredoc cuenta; el DELIM no es orden
        i = end + 1
    if len(out) == len(lines) or not rest_is_inert("\n".join(rest)):
        return command
    return "\n".join(out)


def main():
    sys.stdout.write(strip(sys.stdin.read()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
