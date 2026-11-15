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
    if hasta <= at:
        return False, "su presencia vence antes de declararse"
    if hasta - at > dt.timedelta(seconds=max_validez):
        return False, "su presencia declara una validez mayor que el máximo"
    if at > ahora + dt.timedelta(seconds=60):
        return False, "su presencia está fechada en el futuro"
    if hasta <= ahora:
        return False, "sin señales desde las " + at.astimezone().strftime("%H:%M")
    return True, "presente"


def _limpio(texto, n=200):
    return _CTRL.sub(" ", texto)[:n]


def _mostrable(texto):
    """Texto ajeno para la terminal: sin caracteres de control (ni secuencias ANSI)."""
    return _CTRL.sub(" ", texto)


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


DELIVER_LOCK = ".deliver.lock"


class PasadaEnCurso(PulseError):
    """Otra pasada de respaldo tiene su cerrojo: no es un fallo, esta pasada no hace nada."""


def entregar(root, max_validez=MAX_VALIDEZ_DEFECTO, maximo=MAX_POR_PASADA, notificador=notificar_so):
    """Una pasada de respaldo. Devuelve {'soul': bool, 'motivo': str, 'avisados': [ids]}.

    El notificador puede tardar (hasta 10 s por aviso): nunca se llama con el
    cerrojo de escritor cogido, para no bloquear el fin de un trabajo. «Una vez»
    lo garantiza el cerrojo propio de la pasada (una sola pasada a la vez) más
    volver a comprobar `pendientes` con el cerrojo de escritor antes de anotar.

    Fail-closed con el ledger: si no se puede leer, no se sabe qué se avisó ya ni
    se podría anotar el aviso, así que no se notifica nada (PulseError, salida 1).
    """
    vigente, motivo = presencia(root, max_validez)
    if vigente:
        return {"soul": True, "motivo": motivo, "avisados": []}
    avisados, sin_so = [], 0
    with store.lock(root, timeout=0, name=DELIVER_LOCK, error=PasadaEnCurso,
                    ocupado="otra pasada de respaldo está en curso; no se avisa dos veces"):
        with store.lock(root):
            events._locked_ledger(root)
            lista = pendientes(root)[:maximo]
        for pet in lista:
            with store.lock(root):
                events._locked_ledger(root)  # ilegible: ni se avisa ni se podría anotar
                if pet["id"] not in {p["id"] for p in pendientes(root)}:
                    continue  # acusada o caducada entretanto
            texto = "%s: %s" % (MARCA, pet["que"])
            ok = notificador("Savia", texto)
            ev = events._event("aviso_respaldo", pet["nivel"], entrega="respaldo", ref=pet["id"],
                               texto=_limpio(texto, 300), canal_so="ok" if ok else "no_disponible")
            with store.lock(root):
                store.append_jsonl(root, events.EVENTS, ev, "evento")
            avisados.append(pet["id"])
            sin_so += 0 if ok else 1
    return {"soul": False, "motivo": motivo, "avisados": avisados, "sin_canal_so": sin_so}


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
        out += ["- " + _mostrable(p["que"]),
                "    Por qué ahora: " + _mostrable(p["por_que_ahora"]),
                "    Si no contestas: " + _mostrable(p["si_no_contestas"]),
                "    Si aplazas: " + _mostrable(p["si_aplazas"]),
                "    Vale hasta: " + store.parse_ts(p["caduca"]).astimezone().strftime("%d/%m %H:%M")]
    return "\n".join(out)
