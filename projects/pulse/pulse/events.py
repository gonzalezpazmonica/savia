"""Eventos de planta, peticiones y latido: lo que Pulse publica (S1).

El lanzador emite inicio, latido y fin con código y clase. La clase sale del
código de salida o de una señal tipada que aporta el lanzador; nunca se lee de
texto libre (F1). Ante un código no clasificable, `desconocida` (fail-closed).
"""
import datetime as dt
import math
import re
import secrets

from . import SCHEMA_VERSION, schema, store
from .store import EntradaInvalida, PulseError

EVENTS = "eventos.jsonl"
PETICIONES = "peticiones.json"
LATIDO = "latido.json"

CLASES = ("transitoria", "cuota", "ci_ajena", "ci_atascada", "logica", "entorno", "politica", "desconocida")
NIVELES = ("N1", "N2", "N3", "N4", "N4b")
ENTORNO_RC = (143, 137)  # interrumpido por SIGTERM/SIGKILL: relanzar gratis (S3 lo aplica)
JOB_ID = re.compile(r"[A-Za-z0-9_-]{1,64}")
FASE = re.compile(r"[A-Za-z0-9 ._:/-]{1,200}")
VENTANA_PETICION_H = 24
CAUSA = {"transitoria": "fallo pasajero (red o servicio)", "cuota": "se agotó la cuota del proveedor",
         "ci_ajena": "las pruebas fallan también en la rama principal", "ci_atascada": "las pruebas no arrancan",
         "logica": "el trabajo o sus pruebas están mal", "entorno": "el equipo lo interrumpió",
         "politica": "tocó algo fuera de su alcance", "desconocida": "no sé clasificar la causa"}


def classify(rc, clase=None):
    """(clase, resultado). `clase` es la señal tipada del lanzador, opcional."""
    if isinstance(rc, bool) or not isinstance(rc, int) or not 0 <= rc <= 255:
        raise EntradaInvalida("rc debe ser un entero entre 0 y 255")
    if clase is not None and clase != "ninguna" and clase not in CLASES:
        raise EntradaInvalida("clase fuera del conjunto cerrado")
    if rc == 0:
        if clase not in (None, "ninguna"):
            raise EntradaInvalida("rc 0 no admite una clase de fallo")
        return "ninguna", "ok"
    if clase == "ninguna":
        raise EntradaInvalida("rc distinto de 0 no puede tener clase «ninguna»")
    if clase is None:
        clase = "entorno" if rc in ENTORNO_RC else "desconocida"
    return clase, ("interrumpido" if clase == "entorno" else "fallo")


def _check_job_id(job_id):
    if not isinstance(job_id, str) or not JOB_ID.fullmatch(job_id):
        raise EntradaInvalida("job_id inválido")


def _event(tipo, nivel, clase="ninguna", entrega="ninguna", **fields):
    ev = {"schema_version": SCHEMA_VERSION, "id": "ev-" + secrets.token_hex(8),
          "tipo": tipo, "at": store.fmt(store.now()), "clase": clase,
          "entrega": entrega, "nivel": nivel}
    ev.update(fields)
    return ev


def read_ledger(root):
    """(estado, eventos válidos, motivos de líneas rechazadas)."""
    return store.read_jsonl(root + "/" + EVENTS, "evento")


def _jobs(events):
    """Estado por trabajo derivado solo del ledger: {job_id: {...}}."""
    jobs = {}
    for ev in events:
        jid = ev.get("job_id")
        if jid is None:
            continue
        if ev["tipo"] == "job_started":  # un intento nuevo reinicia el estado del trabajo
            jobs[jid] = {"started": ev, "beats": 0, "last_beat": None, "finished": None}
            continue
        j = jobs.setdefault(jid, {"started": None, "beats": 0, "last_beat": None, "finished": None})
        if ev["tipo"] == "job_beat":
            j["beats"] = max(j["beats"], ev["seq"])
            j["last_beat"] = ev
        elif ev["tipo"] == "job_finished":
            j["finished"] = j["finished"] or ev
    return jobs


def _locked_ledger(root):
    estado, events, rejected = read_ledger(root)
    if estado == store.FALLIDA:
        raise PulseError("el ledger de eventos no se puede leer; no se escribe nada")
    return events


def job_start(root, job_id, nivel="N4", intento=1, heartbeat_ttl=None, propuesta=None, modelo=None):
    _check_job_id(job_id)
    with store.lock(root):
        jobs = _jobs(_locked_ledger(root))
        j = jobs.get(job_id)
        if j and j["started"] and not j["finished"]:
            raise PulseError("el intento anterior del trabajo sigue en marcha")
        if j and j["started"] and intento <= j["started"]["intento"]:
            raise PulseError("el intento debe ser mayor que el anterior")
        extra = {"job_id": job_id, "intento": intento}
        for key, val in (("heartbeat_ttl", heartbeat_ttl), ("propuesta", propuesta), ("modelo", modelo)):
            if val is not None:
                extra[key] = val
        ev = _event("job_started", nivel, **extra)
        store.append_jsonl(root, EVENTS, ev, "evento")
        return ev


def job_beat(root, job_id, fase, nivel="N4"):
    """Latido mínimo de un trabajo (parte mínima de SE-507, que está PROPOSED)."""
    _check_job_id(job_id)
    if not FASE.fullmatch(fase or ""):
        raise EntradaInvalida("fase inválida")
    with store.lock(root):
        j = _jobs(_locked_ledger(root)).get(job_id)
        if not j or not j["started"] or j["finished"]:
            raise PulseError("latido rechazado: el trabajo no está en marcha")
        ev = _event("job_beat", nivel, job_id=job_id, seq=j["beats"] + 1, fase=fase[:80])
        store.append_jsonl(root, EVENTS, ev, "evento")
        return ev


def _resumen_fin(job_id, resultado, clase):
    if resultado == "ok":
        return ("El trabajo %s terminó bien." % job_id,
                "No necesitas hacer nada hasta la revisión.")
    if resultado == "interrumpido":
        return ("El trabajo %s se interrumpió (el equipo se durmió o lo pararon)." % job_id,
                "Se puede relanzar una vez sin coste para el límite de intentos.")
    return ("El trabajo %s falló: %s." % (job_id, CAUSA[clase]),
            "Revisa el motivo antes de relanzarlo.")


def _peticion_fin(ev):
    """La petición de aviso de un fin; se deriva solo del evento (determinista, regenerable)."""
    que, nada = _resumen_fin(ev["job_id"], ev["resultado"], ev["clase"])
    return {
        "id": ev["peticion_id"], "fuente": "AVISO_RUN", "nivel": ev["nivel"],
        "critica": ev["clase"] == "politica", "desde": ev["at"],
        "que": que, "por_que_ahora": "El trabajo acaba de terminar (código %d)." % ev["rc"],
        "si_no_contestas": nada, "si_aplazas": "No pasa nada: el aviso sigue en la cola.",
        "caduca": store.fmt(store.parse_ts(ev["at"]) + dt.timedelta(hours=VENTANA_PETICION_H)),
    }


def job_finish(root, job_id, rc, clase=None, nivel="N4"):
    """Registra el fin (código y clase) y la petición de aviso. Devuelve (evento, creado).

    Fin y petición van juntos: la instantánea de peticiones se lee y la petición se
    valida ANTES de anotar el fin, así que si no se puede publicar la petición no se
    anota nada. Si el fin ya constaba pero su petición falta (vigente), el reintento
    la regenera.
    """
    _check_job_id(job_id)
    clase, resultado = classify(rc, clase)
    with store.lock(root):
        j = _jobs(_locked_ledger(root)).get(job_id)
        if not j or not j["started"]:
            raise PulseError("fin sin inicio: el trabajo no consta como lanzado")
        current = _peticiones_vigentes(root)
        if j["finished"]:
            if j["finished"]["rc"] != rc:
                raise PulseError("el trabajo ya terminó con otro código; el primer resultado manda")
            pet = _peticion_fin(j["finished"])
            if store.parse_ts(pet["caduca"]) > store.now() and pet["id"] not in {p["id"] for p in current}:
                _write_peticiones(root, current, pet)
            return j["finished"], False
        intento = j["started"]["intento"]
        ev = _event("job_finished", nivel, clase=clase, entrega="pendiente", job_id=job_id,
                    intento=intento, rc=rc, resultado=resultado,
                    peticion_id="aviso-run-%s-%d" % (job_id, intento))
        pet = _peticion_fin(ev)
        _check_peticiones(current + [pet])
        store.append_jsonl(root, EVENTS, ev, "evento")
        _write_peticiones(root, current, pet)
        return ev, True


def pr_event(root, tipo, propuesta, nivel="N4"):
    if tipo not in ("pr_created", "pr_merged"):
        raise EntradaInvalida("tipo de evento de propuesta inválido")
    with store.lock(root):
        _locked_ledger(root)
        ev = _event(tipo, nivel, propuesta=propuesta)
        store.append_jsonl(root, EVENTS, ev, "evento")
        return ev


def _peticiones_vigentes(root):
    """Peticiones de la instantánea sin las caducadas. Ilegible o insegura: PulseError. Con el cerrojo."""
    estado, snap = store.read_json(root + "/" + PETICIONES, "peticiones")
    if estado == store.FALLIDA:
        raise PulseError("peticiones.json ilegible; no se sobrescribe ni se anota el fin (" + snap + ")")
    current = snap["peticiones"] if estado == store.OK else []
    t = store.now()
    return [p for p in current if store.parse_ts(p["caduca"]) > t]


def _snapshot(peticiones):
    return {"schema_version": SCHEMA_VERSION, "at": store.fmt(store.now()), "peticiones": peticiones}


def _check_peticiones(peticiones):
    errors = schema.validate(_snapshot(peticiones), schema.load_schema("peticiones"))
    if errors:
        raise EntradaInvalida("petición fuera de contrato, no se anota nada: " + errors[0])


def _write_peticiones(root, current, pet):
    """Instantánea de nivel: sustitución atómica, sin duplicar el id. Llamar con el cerrojo."""
    keep = [p for p in current if p["id"] != pet["id"]] + [pet]
    store.write_json_atomic(root, PETICIONES, _snapshot(keep), "peticiones")


def write_latido(root, pasada, ttl=180, duracion_s=None, fuentes_vencidas=()):
    if not isinstance(ttl, int) or isinstance(ttl, bool) or not 10 <= ttl <= 86400:
        raise EntradaInvalida("ttl fuera de rango (10–86400 s)")
    if duracion_s is not None and not (isinstance(duracion_s, (int, float)) and math.isfinite(duracion_s)):
        raise EntradaInvalida("duración no es un número finito")
    t = store.now()
    data = {"schema_version": SCHEMA_VERSION, "at": store.fmt(t),
            "valid_until": store.fmt(t + dt.timedelta(seconds=ttl)),
            "pasada": pasada, "fuentes_vencidas": list(fuentes_vencidas)}
    if duracion_s is not None:
        data["duracion_s"] = duracion_s
    with store.lock(root):
        store.write_json_atomic(root, LATIDO, data, "latido")
    return data
