"""Deriva del catálogo de agentes (SE-532 S3, D7): informa, no aplica nada.

Dos lados, fijados por medición (el conversor va de `.claude/agents/` a
`.opencode/agents/`, no al revés):

- esperado: lo que generaría `scripts/agents-opencode-convert.sh` desde `.claude/agents/`;
- visto: lo presente en `.opencode/agents/`.

La huella es un hash estable de los pares (nombre, hash del fichero) de cada lado.
Solo se comparan los agentes de nivel superior que tienen fichero en `.claude/agents/`
(el emparejamiento y su lista de excepciones son de SE-253, no se recalculan aquí).
El evento lleva solo nombres y huellas, nunca contenido de agentes.
"""
import hashlib
import os
import subprocess
import tempfile

from . import events, store
from .store import EntradaInvalida, PulseError

CONVERSOR = os.path.join("scripts", "agents-opencode-convert.sh")
ORIGEN = os.path.join(".claude", "agents")
DESTINO = os.path.join(".opencode", "agents")
TIMEOUT_S = 120


def _nombres(directorio):
    try:
        return sorted(n[:-3] for n in os.listdir(directorio)
                      if n.endswith(".md") and n != "README.md" and os.path.isfile(os.path.join(directorio, n)))
    except OSError as exc:
        raise PulseError("no se puede leer %s: %s" % (directorio, exc.strerror or exc))


def _hash(path):
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise PulseError("no se puede leer %s: %s" % (path, exc.strerror or exc))


def huella(pares):
    """Hash estable (16 hex) de {nombre: hash_o_None}. Un agente ausente cuenta distinto de uno vacío."""
    h = hashlib.sha256()
    for nombre in sorted(pares):
        h.update(("%s\0%s\n" % (nombre, "AUSENTE" if pares[nombre] is None else pares[nombre])).encode("utf-8"))
    return h.hexdigest()[:16]


def _esperado(repo, nombres):
    """{nombre: hash} de lo que generaría el conversor. Falla cerrado si el conversor falla."""
    script = os.path.join(repo, CONVERSOR)
    if not os.path.isfile(script):
        raise EntradaInvalida("no hay conversor en el repositorio indicado: " + CONVERSOR)
    with tempfile.TemporaryDirectory(prefix="pulse-catalogo-") as tmp:
        env = dict(os.environ, SRC_DIR=os.path.join(repo, ORIGEN), DST_DIR=tmp, PROJECT_ROOT=repo)
        try:
            r = subprocess.run(["bash", script, "--apply"], env=env, capture_output=True, text=True,
                               timeout=TIMEOUT_S, cwd=repo)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise PulseError("el conversor no se pudo ejecutar: %s" % exc)
        if r.returncode != 0:
            raise PulseError("el conversor falló (código %d); no se compara nada" % r.returncode)
        out = {}
        for n in nombres:
            h = _hash(os.path.join(tmp, n + ".md"))
            if h is None:
                raise PulseError("el conversor no generó " + n)
            out[n] = h
        return out


def medir(repo):
    """Devuelve {huella_repo, huella_vista, agentes, motivo|None}. No escribe nada."""
    repo = os.path.abspath(repo)
    nombres = _nombres(os.path.join(repo, ORIGEN))
    if not nombres:
        raise PulseError("catálogo vacío en %s: no hay nada que comparar" % ORIGEN)
    esperado = _esperado(repo, nombres)
    visto = {n: _hash(os.path.join(repo, DESTINO, n + ".md")) for n in nombres}
    distintos = sorted(n for n in nombres if visto[n] is not None and visto[n] != esperado[n])
    ausentes = sorted(n for n in nombres if visto[n] is None)
    motivo = None
    if distintos and ausentes:
        motivo = "ambos"
    elif distintos:
        motivo = "espejo_distinto"
    elif ausentes:
        motivo = "espejo_ausente"
    return {"huella_repo": huella(esperado), "huella_vista": huella(visto),
            "agentes": sorted(distintos + ausentes), "motivo": motivo}


def estado(evs):
    """Estado derivado del último evento de catálogo: (clave, evento|None).

    `sin_datos` si nunca hubo uno (no se inventa «sin deriva»), `con_deriva` o `sin_deriva`.
    """
    ultimo = None
    for ev in evs:
        if ev["tipo"] in ("catalogo_deriva", "catalogo_resuelto"):
            ultimo = ev
    if ultimo is None:
        return "sin_datos", None
    return ("con_deriva" if ultimo["tipo"] == "catalogo_deriva" else "sin_deriva"), ultimo


def comprobar(root, repo, nivel="N1"):
    """Una pasada: mide y emite como mucho un evento por cambio. Devuelve (accion, evento|None).

    accion: `deriva`, `resuelto` o `nada`. Mismo conjunto de agentes desajustados = nada.
    """
    m = medir(repo)  # lento, fuera del cerrojo
    with store.lock(root):
        est, ultimo = estado(events._locked_ledger(root))
        if m["motivo"] is not None:
            if est == "con_deriva" and ultimo["agentes"] == m["agentes"] and ultimo["motivo"] == m["motivo"]:
                return "nada", None
            ev = events._event("catalogo_deriva", nivel, agentes=m["agentes"], huella_repo=m["huella_repo"],
                               huella_vista=m["huella_vista"], motivo=m["motivo"])
            store.append_jsonl(root, events.EVENTS, ev, "evento")
            return "deriva", ev
        if est == "con_deriva":
            ev = events._event("catalogo_resuelto", nivel, huella=m["huella_vista"])
            store.append_jsonl(root, events.EVENTS, ev, "evento")
            return "resuelto", ev
        return "nada", None
