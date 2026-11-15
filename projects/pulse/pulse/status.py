"""`pulse status`: el estado de la planta en llano, sin jerga.

Regla: sin datos fiables nunca dice «todo bien». Un latido vencido, ausente o
ilegible es «sin señales».
"""
import datetime as dt

from . import backup, events, store

LOCAL = "%H:%M"


def _hace(delta):
    s = max(0, int(delta.total_seconds()))
    if s < 90:
        return "%d segundos" % s
    if s < 5400:
        return "%d minutos" % round(s / 60)
    return "%.1f horas" % (s / 3600)


def collect(root, ahora=None):
    ahora = ahora or store.now()
    out = {"at": store.fmt(ahora), "problemas": []}
    est, lat = store.read_json(root + "/" + events.LATIDO, "latido")
    if est == store.OK:
        try:
            at, hasta = store.parse_ts(lat["at"]), store.parse_ts(lat["valid_until"])
        except ValueError:
            est, lat = store.FALLIDA, "fechas inválidas"
    if est == store.OK:
        vivo = hasta > ahora and at <= ahora + dt.timedelta(seconds=60)
        out["pulse"] = {"estado": "da_senales" if vivo else "sin_senales", "desde": lat["at"],
                        "edad_s": int((ahora - at).total_seconds()), "pasada": lat["pasada"],
                        "duracion_s": lat.get("duracion_s"), "fuentes_vencidas": lat["fuentes_vencidas"]}
    else:
        out["pulse"] = {"estado": "sin_senales", "desde": None, "motivo": lat if est == store.FALLIDA else "no hay latido"}
    est_l, evs, rechazadas = events.read_ledger(root)
    out["ledger"] = est_l
    jobs, fin_hoy = [], {"ok": 0, "fallo": 0, "interrumpido": 0}
    if est_l == store.OK:
        inicio_dia = ahora.astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
        for jid, j in events._jobs(evs).items():
            st = j["started"]
            if not st:
                continue
            if j["finished"]:
                if store.parse_ts(j["finished"]["at"]) >= inicio_dia:
                    fin_hoy[j["finished"]["resultado"]] += 1
                continue
            started = store.parse_ts(st["at"])
            last = store.parse_ts(j["last_beat"]["at"]) if j["last_beat"] else started
            ttl = st.get("heartbeat_ttl")
            if ttl is None:
                senal = "sin_latido_declarado"
            else:
                senal = "da_senales" if (ahora - last).total_seconds() < ttl else "sin_senales"
            jobs.append({"job_id": jid, "edad_s": int((ahora - started).total_seconds()),
                         "ultima_senal_s": int((ahora - last).total_seconds()),
                         "fase": j["last_beat"]["fase"] if j["last_beat"] else None, "senal": senal})
    elif est_l == store.FALLIDA:
        out["problemas"].append("no puedo leer el registro de eventos")
    if rechazadas:
        out["problemas"].append("%d líneas del registro de eventos son ilegibles" % len(rechazadas))
    out["trabajos"], out["terminados_hoy"] = jobs, fin_hoy
    out["pendientes"] = [{"que": p["que"], "critica": p["critica"]} for p in backup.pendientes(root, incluir_respaldo=True)]
    vigente, motivo = backup.presencia(root)
    out["soul"] = {"presente": vigente, "motivo": motivo}
    return out


def render(d):
    L = []
    p = d["pulse"]
    if p["estado"] == "da_senales":
        dur = "" if p.get("duracion_s") is None else ", duró %d s" % round(p["duracion_s"])
        L.append("Pulse: da señales. Última comprobación hace %s (pasada %d%s)."
                 % (_hace(dt.timedelta(seconds=p["edad_s"])), p["pasada"], dur))
        L.append("Fuentes sin datos: " + (", ".join(p["fuentes_vencidas"]) or "ninguna") + ".")
    elif p.get("desde"):
        desde = store.parse_ts(p["desde"]).astimezone().strftime(LOCAL)
        L.append("Pulse: sin señales desde las %s. No te fíes de lo que sigue." % desde)
    else:
        L.append("Pulse: sin señales (%s). No te fíes de lo que sigue." % p["motivo"])
    for prob in d["problemas"]:
        L.append("Aviso: " + prob + ".")
    jobs = d["trabajos"]
    if d["ledger"] == store.SIN_CONECTAR:
        L.append("Trabajos: todavía no hay registro de trabajos.")
    elif d["ledger"] == store.OK:
        L.append("Trabajos en marcha: %d." % len(jobs))
        for j in sorted(jobs, key=lambda x: -x["edad_s"]):
            if j["senal"] == "da_senales":
                s = "dio señales hace %s" % _hace(dt.timedelta(seconds=j["ultima_senal_s"]))
            elif j["senal"] == "sin_senales":
                s = "SIN SEÑALES desde hace %s" % _hace(dt.timedelta(seconds=j["ultima_senal_s"]))
            else:
                s = "no declara latido, no sé si sigue vivo"
            fase = " (fase: %s)" % j["fase"] if j["fase"] else ""
            L.append("  - %s: lleva %s; %s%s." % (j["job_id"], _hace(dt.timedelta(seconds=j["edad_s"])), s, fase))
        t = d["terminados_hoy"]
        L.append("Terminados hoy: %d bien, %d con fallo, %d interrumpidos." % (t["ok"], t["fallo"], t["interrumpido"]))
    if d["pendientes"]:
        crit = sum(1 for x in d["pendientes"] if x["critica"])
        L.append("Esperan algo de ti: %d%s. Detalle: pulse inbox." % (len(d["pendientes"]), " (%d crítica(s))" % crit if crit else ""))
    else:
        L.append("Esperan algo de ti: nada que conste.")
    L.append("Freno: sin información (todavía no está conectado a Pulse).")
    if d["soul"]["presente"]:
        L.append("Soul: presente. Los avisos los da Soul.")
    else:
        L.append("Soul: %s. Los avisos salen por el canal de respaldo." % d["soul"]["motivo"])
    return "\n".join(L)
