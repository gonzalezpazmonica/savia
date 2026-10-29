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
    if whitelist(result) - whitelist(current):
        return 1
    # Un .gitignore anidado (por ejemplo dentro de la carpeta de proyectos) se aplica sobre su propio
    # directorio y puede reincluir lo que la raíz excluye. La simulación aislada solo modela la raíz,
    # así que en uno anidado cualquier excepción (!) nueva bloquea.
    root = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    if os.path.realpath(os.path.dirname(path)) != root:
        nuevas = {l.strip() for l in result.splitlines() if l.strip().startswith("!")} \
            - {l.strip() for l in current.splitlines() if l.strip().startswith("!")}
        return 1 if nuevas else 0
    # Lo que importa es qué rutas de proyecto dejan de estar ignoradas, no qué líneas cambian: borrar la
    # exclusión general o escribir la excepción con una clase de caracteres también publica.
    # Se pregunta al propio motor de git, con el .gitignore anterior y el resultante, en un repo aislado.
    return publicables_nuevas(current, result, os.path.dirname(path))


BASE = "pro" + "jects"
CLASE = re.compile(r"\[([^\]])[^\]]*\]")


def candidatas(root, *gitignores):
    """Rutas de proyecto a comprobar: las existentes (dos niveles), las que nombran las excepciones
    (con las clases de caracteres resueltas a su primer carácter) y una sonda sintética."""
    out = {f"{BASE}/__sonda__/dato.txt"}
    for text in gitignores:
        for line in text.splitlines():
            line = line.strip()
            if line.startswith("!"):
                pat = CLASE.sub(r"\1", line[1:]).strip("/").replace("*", "x").replace("?", "x")
                if pat:
                    out.add(f"{pat}/dato.txt")
    base = os.path.join(root, BASE)
    try:
        for name in os.listdir(base)[:500]:
            out.add(f"{BASE}/{name}/dato.txt")
            sub = os.path.join(base, name)
            if os.path.isdir(sub):
                for inner in os.listdir(sub)[:50]:
                    out.add(f"{BASE}/{name}/{inner}")
    except OSError:
        pass
    return sorted(out)


def ignoradas(gitignore, paths, git):
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        if subprocess.run([git, "init", "-q", d], capture_output=True).returncode:
            raise OSError("git init")
        with open(os.path.join(d, ".gitignore"), "w") as fh:
            fh.write(gitignore)
        p = subprocess.run([git, "-C", d, "-c", "core.excludesFile=/dev/null", "check-ignore", "--no-index",
                            "--stdin"], input="\n".join(paths) + "\n", text=True, capture_output=True)
        if p.returncode not in (0, 1):
            raise OSError("git check-ignore")
        return set(p.stdout.split())


def publicables_nuevas(current, result, root):
    import shutil
    git = shutil.which("git")
    if not git:
        return 2
    paths = candidatas(root, current, result)
    try:
        antes = ignoradas(current, paths, git)
        despues = ignoradas(result, paths, git)
    except OSError:
        return 2
    return 1 if antes - despues else 0


if __name__ == "__main__":
    sys.exit(main())
