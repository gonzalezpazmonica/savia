#!/usr/bin/env python3
"""SE-531 S1 (D4) — aviso de versión de las fichas de runtime.

Los datos de una ficha envejecen: cada uno lleva `version_cli`. Este módulo
ejecuta `<orden> --version` (lista de argumentos, sin shell, 10 s de plazo) y
devuelve AVISOS si la versión instalada difiere de la medida o no se puede
leer. Nunca falla la validación. Vive aparte de `harness_ficha.py` para que
este siga sin importar `subprocess`: el validador no ejecuta nada, ni siquiera
`rc_deteccion`, que este módulo tampoco lee.
"""
import re
import subprocess

DEFAULT_BIN = {"claude-code": "claude"}
VERSION_RE = re.compile(r"\d+\.\d+\.\d+")


def measured_versions(doc):
    """Versiones (conjunto) con las que se midió algún dato de la ficha; vacío = nada medido."""
    rt = doc.get("runtime")
    if not isinstance(rt, dict) or not isinstance(rt.get("version_cli"), dict):
        return set()
    return {str(v).strip() for v in rt["version_cli"].values()}


def installed_version(cmd):
    """Versión que informa `cmd --version` (sin shell) o None si no se puede leer."""
    try:
        p = subprocess.run([cmd, "--version"], capture_output=True, text=True, timeout=10,
                           stdin=subprocess.DEVNULL, shell=False)
    except (OSError, subprocess.SubprocessError):
        return None
    m = VERSION_RE.search(p.stdout or "")
    return m.group(0) if p.returncode == 0 and m else None


def version_warnings(fichas, binarios=None):
    """Lista de avisos (str). Nunca decide el éxito: la validación es otra cosa."""
    binarios = binarios or {}
    out = []
    for fid, doc in fichas.items():
        medidas = measured_versions(doc)
        if not medidas:
            continue
        cmd = binarios.get(fid, DEFAULT_BIN.get(fid, fid))
        actual = installed_version(cmd)
        if actual is None:
            out.append(f"AVISO {fid}: no se pudo leer la versión instalada ({cmd} --version); datos medidos con {sorted(medidas)}")
        elif medidas != {actual}:
            out.append(f"AVISO {fid}: versión instalada {actual} difiere de la medida {sorted(medidas)}; revisa los datos de la ficha")
    return out
