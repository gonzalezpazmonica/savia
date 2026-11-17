"""Revisión diaria de la comprobación nocturna (SE-518 A1, slice S1n, escena E11).

Una vez al día mira el resultado de la última ejecución de un flujo del forge y,
si no es verde, deja una petición que pide algo a la persona. Solo lectura:
la única orden que se ejecuta es `gh run list`. Repositorio y flujo salen de
configuración (`PULSE_NOCTURNA_REPO`, `PULSE_NOCTURNA_FLUJO`), nunca del código.
Solo cuentan las ejecuciones de la rama vigilada (`PULSE_NOCTURNA_RAMA`, por
defecto `main`): una ejecución manual en otra rama no puede tapar un rojo.

Fail-closed: sin configuración no se consulta; si no se puede consultar, es una
petición («no he podido mirar»), nunca «bien». Al ledger solo van contadores y
conjuntos cerrados, nunca salida de la consulta; la URL de la ejecución solo
entra en la petición, y solo si es https sin caracteres de control.
"""
import datetime as dt
import json
import os
import re
import subprocess

from . import events, store
from .store import EntradaInvalida, PulseError

ENV_REPO = "PULSE_NOCTURNA_REPO"
ENV_FLUJO = "PULSE_NOCTURNA_FLUJO"
ENV_RAMA = "PULSE_NOCTURNA_RAMA"
RAMA_POR_DEFECTO = "main"
TIMEOUT_S = 60
MAX_EDAD = dt.timedelta(hours=26)
CADUCIDAD = dt.timedelta(hours=30)  # algo más de un día: la pasada siguiente la sustituye
PREFIJO = "nocturna-"
REPO = re.compile(r"^(?:[A-Za-z0-9][A-Za-z0-9.-]*/)?[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$")
FLUJO = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,99}$")
RAMA = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_./-]{0,99}$")
URL_OK = re.compile(r"^https://[^\s\x00-\x1f\x7f]{1,200}$")
CONCLUSIONES = ("failure", "cancelled", "timed_out", "startup_failure", "action_required", "stale", "neutral", "skipped")
ROJOS = ("rojo", "sin_ejecucion")
_PERMITIDO = (("run", "list"),)


class Consulta(Exception):
    def __init__(self, motivo):
        super().__init__(motivo)
        self.motivo = motivo


def _ejecutar(argv, timeout):
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)


def _gh(args, runner=None):
    """Única puerta a `gh`: solo `run list` (lectura). Cualquier otra orden se rechaza sin ejecutarla."""
    if tuple(args[:2]) not in _PERMITIDO:
        raise PulseError("orden de gh no permitida: Pulse solo lee (run list)")
    return (runner or _ejecutar)(["gh"] + list(args), TIMEOUT_S)


def configuracion(env=None):
    """(repo, flujo, rama) o None si falta repo o flujo. Valores con forma no válida: EntradaInvalida."""
    env = os.environ if env is None else env
    repo, flujo = (env.get(ENV_REPO) or "").strip(), (env.get(ENV_FLUJO) or "").strip()
    rama = (env.get(ENV_RAMA) or "").strip() or RAMA_POR_DEFECTO
    if not repo or not flujo:
        return None
    if not REPO.match(repo):
        raise EntradaInvalida("%s no tiene la forma [HOST/]PROPIETARIO/REPOSITORIO" % ENV_REPO)
    if not FLUJO.match(flujo):
        raise EntradaInvalida("%s no es un nombre de flujo válido" % ENV_FLUJO)
    if not RAMA.match(rama):
        raise EntradaInvalida("%s no es un nombre de rama válido" % ENV_RAMA)
    return repo, flujo, rama


def _motivo_fallo(stderr):
    s = (stderr or "").lower()
    if any(k in s for k in ("gh auth login", "authentication", "401", "bad credentials", "not logged in")):
        return "sin_sesion"
    return "consulta_fallida"


def consultar(repo, flujo, ahora, runner=None, rama=RAMA_POR_DEFECTO):
    """Última ejecución terminada en `rama`: dict conclusion/at/url, o None si no hay. Imposible: Consulta(motivo)."""
    try:
        r = _gh(["run", "list", "--repo", repo, "--workflow", flujo, "--branch", rama, "--limit", "10",
                 "--json", "status,conclusion,createdAt,url,headBranch"], runner)
    except subprocess.TimeoutExpired:
        raise Consulta("tiempo_agotado")
    except OSError:
        raise Consulta("herramienta_ausente")
    if r.returncode != 0:
        raise Consulta(_motivo_fallo(r.stderr))
    try:
        datos = json.loads(r.stdout)
        if not isinstance(datos, list):
            raise ValueError
        terminadas = []
        for c in datos:
            if not isinstance(c, dict) or not isinstance(c.get("status"), str) \
                    or not isinstance(c.get("headBranch"), str):
                raise ValueError
            if c["headBranch"] != rama:
                continue  # otra rama: aunque `--branch` ya filtra, no se fía de que lo haga
            if c["status"] != "completed":
                continue  # en curso: no cuenta todavía; si se atasca, la edad de la terminada vencerá
            if not isinstance(c.get("conclusion"), str) or not isinstance(c.get("createdAt"), str):
                raise ValueError
            terminadas.append({"conclusion": c["conclusion"], "at": store.parse_ts(c["createdAt"]),
                               "url": c.get("url") if isinstance(c.get("url"), str) else ""})
    except (ValueError, RecursionError):
        raise Consulta("respuesta_ilegible")
    if not terminadas:
        return None
    ult = max(terminadas, key=lambda x: x["at"])
    if ult["at"] > ahora + dt.timedelta(minutes=5):
        raise Consulta("respuesta_ilegible")  # fecha del futuro: no se fía
    return ult


def evaluar(ult, ahora):
    """(resultado, conclusion|None) para una ejecución (o None)."""
    if ult is None or ahora - ult["at"] > MAX_EDAD:
        return "sin_ejecucion", None
    if ult["conclusion"] == "success":
        return "verde", "success"
    return "rojo", ult["conclusion"] if ult["conclusion"] in CONCLUSIONES else "otra"


def estado(evs):
    """Estado derivado solo del ledger: racha abierta, último evento y último día en rojo."""
    racha, ultimo, rojo_dia = 0, None, None
    for ev in evs:
        if ev["tipo"] != "nocturna_comprobada":
            continue
        ultimo, racha = ev, ev["racha"]
        if ev["resultado"] in ROJOS:
            rojo_dia = ev["dia"]
    return {"racha": racha, "ultimo": ultimo, "rojo_dia": rojo_dia}


def _peticion(ahora, dia, resultado, racha, conclusion, motivo, url):
    enlace = " Lo que falla está en: %s." % url if URL_OK.match(url or "") else ""
    sig = "mañana te lo vuelvo a decir con la noche %d" % (racha + 1)
    if resultado == "no_consultable":
        porque = {"herramienta_ausente": "no encuentro la herramienta del forge (gh)",
                  "sin_sesion": "no hay sesión abierta en el forge",
                  "tiempo_agotado": "la consulta tardó demasiado",
                  "respuesta_ilegible": "el forge contestó algo que no entiendo",
                  "consulta_fallida": "la consulta falló (sin red o servicio caído)"}[motivo]
        que = "No he podido mirar la comprobación nocturna: %s. No sé si está bien." % porque
        if racha:
            que += " Antes llevaba %d noches seguidas en rojo." % racha
        no_contestas = "Sigo sin saber cómo está; mañana lo intento otra vez."
        accion = "Restablece el acceso (por ejemplo, abre sesión con gh) y vuelve a lanzar «pulse nocturna»."
    elif resultado == "sin_ejecucion":
        que = "La comprobación nocturna no se ha ejecutado en las últimas 26 horas."
        if racha > 1:
            que += " Lleva %d noches seguidas sin pasar en verde." % racha
        que += enlace
        no_contestas = "Sigue sin ejecutarse y %s." % sig
        accion = "Mira por qué el forge no la lanza."
    else:
        verbo = {"failure": "falló", "cancelled": "se canceló y no probó nada",
                 "timed_out": "se quedó sin tiempo"}.get(conclusion, "no terminó bien")
        if racha == 1:
            que = "La comprobación nocturna %s anoche." % verbo
        else:
            que = "La comprobación nocturna %s y lleva %d noches seguidas en rojo." % (verbo, racha)
        que += enlace
        no_contestas = "Sigue en rojo y %s." % sig
        accion = "Abre la ejecución, mira qué prueba falla y decide si se arregla o se aparta con motivo."
    return {"id": PREFIJO + dia.replace("-", ""), "fuente": "AVISO_RUN", "nivel": "N4", "critica": False,
            "desde": store.fmt(ahora), "que": que[:300],
            "por_que_ahora": ("Pasada diaria de hoy. " + accion)[:300],
            "si_no_contestas": no_contestas[:300],
            "si_aplazas": "Puedes aplazarlo: mañana vuelve a aparecer con el contador al día.",
            "caduca": store.fmt(ahora + CADUCIDAD)}


def comprobar(root, ahora=None, env=None, runner=None):
    """Una pasada diaria. Devuelve (accion, evento|None); accion: resultado o `nada` si es repetida.

    Sin configuración: PulseError y no se consulta nada. La consulta va fuera del cerrojo.
    """
    ahora = ahora or store.now()
    cfg = configuracion(env)
    if cfg is None:
        raise PulseError("sin configuración: define %s y %s; no consulto nada" % (ENV_REPO, ENV_FLUJO))
    dia = ahora.astimezone(dt.timezone.utc).date().isoformat()  # jornada UTC: determinista
    try:
        ult = consultar(cfg[0], cfg[1], ahora, runner, rama=cfg[2])
        resultado, conclusion = evaluar(ult, ahora)
        motivo = None
    except Consulta as exc:
        ult, resultado, conclusion, motivo = None, "no_consultable", None, exc.motivo
    with store.lock(root):
        prev = estado(events._locked_ledger(root))
        if resultado == "verde":
            racha = 0
        elif resultado == "no_consultable":
            racha = prev["racha"]  # no se sabe: ni suma ni reinicia
        elif prev["racha"] > 0 and prev["rojo_dia"] == dia:
            racha = prev["racha"]  # misma jornada: no es otra noche
        else:
            racha = prev["racha"] + 1
        campos = {"resultado": resultado, "dia": dia, "racha": racha}
        if conclusion:
            campos["conclusion"] = conclusion
        if motivo:
            campos["motivo"] = motivo
        if ult is not None and resultado in ("verde", "rojo"):
            campos["ejecucion_at"] = store.fmt(ult["at"])
        u = prev["ultimo"]
        repetida = (u is not None and all(u.get(k) == v for k, v in campos.items())
                    and not (resultado == "verde" and prev["racha"] > 0))
        actuales = [p for p in events._peticiones_vigentes(root) if not p["id"].startswith(PREFIJO)]
        nuevas = [] if resultado == "verde" else [_peticion(
            ahora, dia, resultado, racha, conclusion, motivo, (ult or {}).get("url"))]
        events._check_peticiones(actuales + nuevas)
        ev = None
        if not repetida:
            ev = events._event("nocturna_comprobada", "N4", at=store.fmt(ahora), **campos)
            store.append_jsonl(root, events.EVENTS, ev, "evento")
            if resultado == "verde" and prev["racha"] > 0:
                cierre = events._event("nocturna_racha_cerrada", "N4", at=store.fmt(ahora), longitud=prev["racha"], dia=dia)
                store.append_jsonl(root, events.EVENTS, cierre, "evento")
        store.write_json_atomic(root, events.PETICIONES, events._snapshot(actuales + nuevas), "peticiones")
    return (resultado if ev else "nada"), ev


def resumen(accion, ev):
    """Línea llana para la orden `pulse nocturna`."""
    if ev is None:
        return "Sin cambios respecto a la pasada de hoy."
    r = ev["resultado"]
    if r == "verde":
        return "Comprobación nocturna: bien." + (" La racha en rojo terminó." if ev["racha"] == 0 else "")
    if r == "no_consultable":
        return "No he podido mirar la comprobación nocturna (%s). No sé si está bien; queda una petición." % ev["motivo"]
    if r == "sin_ejecucion":
        return "La comprobación nocturna no se ha ejecutado en las últimas 26 horas; queda una petición."
    return ("La comprobación nocturna falló anoche; queda una petición." if ev["racha"] == 1 else
            "La comprobación nocturna lleva %d noches seguidas en rojo; queda una petición." % ev["racha"])
