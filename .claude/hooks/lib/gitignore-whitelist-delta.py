#!/usr/bin/env python3
"""Decide si una llamada Edit/MultiEdit/Write sobre .gitignore AÑADE alguna línea de whitelist de proyecto.

Lee el JSON del hook por stdin y evalúa el contenido RESULTANTE del fichero, no solo el texto nuevo:
editar únicamente el nombre dentro de una whitelist existente también publica otro proyecto.

Salida: 0 = no añade whitelist (o no es .gitignore) · 1 = añade whitelist · 2 = no se puede evaluar.
"""
import json
import os
import re
import sys

WL = re.compile(r"^\s*!\s*/?projects/")


def whitelist(text):
    return {line.strip() for line in text.splitlines() if WL.match(line)}


def main():
    try:
        data = json.loads(sys.stdin.read())
    except (ValueError, UnicodeDecodeError):
        return 2
    ti = data.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("filePath") or ""
    if os.path.basename(path) != ".gitignore":
        return 0
    if not os.path.isabs(path):
        path = os.path.join(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), path)
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            current = fh.read()
    except FileNotFoundError:
        current = ""
    except OSError:
        return 2

    if "content" in ti:
        result = ti.get("content") or ""
    else:
        edits = ti.get("edits")
        if not isinstance(edits, list):
            edits = [ti]
        result = current
        for e in edits:
            old = e.get("old_string", e.get("oldString"))
            new = e.get("new_string", e.get("newString"))
            if not isinstance(old, str) or not isinstance(new, str):
                return 2
            if old not in result:
                # La edición fallará en la herramienta; por prudencia se evalúa el texto nuevo tal cual.
                result = result + "\n" + new
                continue
            result = result.replace(old, new) if e.get("replace_all") else result.replace(old, new, 1)
    return 1 if whitelist(result) - whitelist(current) else 0


if __name__ == "__main__":
    sys.exit(main())
