"""Canal de respaldo (E10): solo cuando Soul no está presente.

Una sola voz: con la presencia de Soul vigente, Pulse no emite nada. Con la
presencia ausente, ilegible, vencida o inverosímil (vencimiento más allá del
máximo configurable, o fichero escribible por otros), Pulse entrega por
respaldo —notificación del SO y `pulse inbox`— y lo deja en el ledger para que
Soul, al volver, no lo repita.
"""
import datetime as dt
import re
import shutil
import subprocess

from . import SCHEMA_VERSION, events, store
from .store import PulseError

PRESENCIA = "presencia.json"
ACUSES = "acuses.jsonl"
MARCA = "aviso por canal de respaldo"
MAX_VALIDEZ_DEFECTO = 600
MAX_POR_PASADA = 5
_CTRL = re.compile(r"[\x00-\x1f\x7f]")


def presencia(root, max_validez=MAX_VALIDEZ_DEFECTO, ahora=None):
    """(vigente: bool, motivo: str)."""
    ahora = ahora or store.now()
    estado, data = store.read_json(root + "/" + PRESENCIA, "presencia")
    if estado == store.SIN_CONECTAR:
        return False, "no ha dado nunca señales"
    if estado == store.FALLIDA:
        return False, "su presencia es inutilizable (%s)" % data
    try:
        at, hasta = store.parse_ts(data["at"]), store.parse_ts(data["valid_until"])
    except ValueError:
        return False, "su presencia tiene fechas inválidas"
    if hasta - at > dt.timedelta(seconds=max_validez):
        return False, "su presencia declara una validez mayor que el máximo"
    if at > ahora + dt.timedelta(seconds=60):
        return False, "su presencia está fechada en el futuro"
    if hasta <= ahora:
        return False, "sin señales desde las " + at.astimezone().strftime("%H:%M")
    return True, "presente"


def _limpio(texto, n=200):
    return _CTRL.sub(" ", texto)[:n]


def notificar_so(titulo, texto):
    """Notificación del sistema operativo; sin herramienta devuelve False. Sin shell."""
    titulo, texto = _limpio(titulo, 60), _limpio(texto)
    try:
        if shutil.which("notify-send"):
            cmd = ["notify-send", "--", titulo, texto]
        elif shutil.which("osascript"):
            cmd = ["osascript", "-e", "on run argv", "-e",
                   "display notification (item 1 of argv) with title (item 2 of argv)",
                   "-e", "end run", texto, titulo]
        else:
            return False
        return subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=10).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def pendientes(root, ahora=None, incluir_respaldo=False):
    """Peticiones vigentes sin acuse de Soul; por defecto también sin aviso previo del respaldo."""
    ahora = ahora or store.now()
    estado, snap = store.read_json(root + "/" + events.PETICIONES, "peticiones")
    if estado != store.OK:
        return []
    est_a, acuses, _ = store.read_jsonl(root + "/" + ACUSES, "acuse")
    # acuses ilegibles: no se sabe qué entregó Soul; se informa (mejor repetir que callar)
    acusados = {a["id"] for a in acuses} if est_a == store.OK else set()
    est_e, evs, _ = events.read_ledger(root)
    por_respaldo = set()
    if est_e == store.OK and not incluir_respaldo:
        por_respaldo = {e["ref"] for e in evs if e["tipo"] == "aviso_respaldo"}
    return [p for p in snap["peticiones"]
            if store.parse_ts(p["caduca"]) > ahora and p["id"] not in acusados and p["id"] not in por_respaldo]


def entregar(root, max_validez=MAX_VALIDEZ_DEFECTO, maximo=MAX_POR_PASADA, notificador=notificar_so):
    """Una pasada de respaldo. Devuelve {'soul': bool, 'motivo': str, 'avisados': [ids]}."""
    vigente, motivo = presencia(root, max_validez)
    if vigente:
        return {"soul": True, "motivo": motivo, "avisados": []}
    avisados = []
    with store.lock(root):
        for pet in pendientes(root)[:maximo]:
            texto = "%s: %s" % (MARCA, pet["que"])
            ok = notificador("Savia", texto)
            ev = events._event("aviso_respaldo", pet["nivel"], entrega="respaldo", ref=pet["id"],
                               texto=_limpio(texto, 300), canal_so="ok" if ok else "no_disponible")
            store.append_jsonl(root, events.EVENTS, ev, "evento")
            avisados.append(pet["id"])
    return {"soul": False, "motivo": motivo, "avisados": avisados}


def inbox_text(root):
    """Lo pendiente, en llano, con las cinco cosas de cada petición."""
    pend = pendientes(root, incluir_respaldo=True)
    if not pend:
        estado, _snap = store.read_json(root + "/" + events.PETICIONES, "peticiones")
        if estado == store.FALLIDA:
            return "No puedo leer la lista de pendientes (fichero dañado o inseguro). No asumas que no hay nada."
        if estado == store.SIN_CONECTAR:
            return "Todavía no hay lista de pendientes: Pulse no ha publicado ninguna."
        return "No hay nada pendiente de ti."
    out = ["Pendiente de ti (%d):" % len(pend)]
    for p in pend:
        out += ["- " + p["que"],
                "    Por qué ahora: " + p["por_que_ahora"],
                "    Si no contestas: " + p["si_no_contestas"],
                "    Si aplazas: " + p["si_aplazas"],
                "    Vale hasta: " + store.parse_ts(p["caduca"]).astimezone().strftime("%d/%m %H:%M")]
    return "\n".join(out)
