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
  - el nombre del fichero escrito no aparece después en la orden (`bash f`),
    y lo que sigue no tiene glob ni variable (`bash ./*.sh`, `. "$F"`) que
    pueda nombrarlo sin escribirlo;
  - el fichero no se ejecuta fuera de la orden: nada bajo `.git/` (hooks,
    config) ni ficheros de arranque del shell (`.bashrc`, `.profile`…).
Todo lo demás se devuelve intacto: `bash <<EOF`, `sh -c`, `cat <<EOF | bash`,
`python3 - <<EOF`, `cat <<EOF` a stdout, heredocs sin cerrar. La línea del
heredoc y el delimitador se conservan; las órdenes posteriores, también.

Sin dependencias externas; sin red.
"""
import re
import sys

HEREDOC = re.compile(r"(?<!<)<<(?!<)(-?)[ \t]*(['\"]?)([A-Za-z_][\w.-]*)\2(?=[ \t<>]|$)")
UNSAFE_LINE = re.compile(r"[|;&()`]|\$\(|\\$")
# Lo que sigue al heredoc puede nombrar el fichero sin escribirlo.
INDIRECT = re.compile(r"[*?\[{$`]")
# Ficheros que se ejecutan solos, fuera de la orden.
AUTORUN = re.compile(r"(^|/)\.git(/|$)|(^|/)\.(bashrc|bash_profile|bash_login|bash_logout|"
                     r"profile|zshrc|zprofile|zshenv|zlogin|envrc)$")
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


def strip(command):
    lines = command.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        found = HEREDOC.findall(line)
        lead = LEAD.match(line)
        if len(found) != 1 or not lead or UNSAFE_LINE.search(line) \
                or (i > 0 and lines[i - 1].endswith("\\")):
            out.append(line)
            i += 1
            continue
        dash, quote, delim = found[0]
        target = _target(line, lead.group(1))
        end = next((j for j in range(i + 1, len(lines))
                    if (lines[j].lstrip("\t") if dash else lines[j]) == delim), None)
        if not target or end is None or AUTORUN.search(target):
            out.append(line)
            i += 1
            continue
        body = "\n".join(lines[i + 1:end])
        later = "\n".join(lines[end + 1:])
        if (not quote and ("$(" in body or "`" in body)) or target in later \
                or target.rsplit("/", 1)[-1] in later or INDIRECT.search(later):
            out.append(line)
            i += 1
            continue
        out.extend([line, lines[end]])
        i = end + 1
    return "\n".join(out)


def main():
    sys.stdout.write(strip(sys.stdin.read()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
