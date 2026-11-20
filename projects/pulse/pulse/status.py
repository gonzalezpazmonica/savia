"""`pulse status`: el estado de la planta en llano, sin jerga.

Regla: sin datos fiables nunca dice «todo bien». Un latido vencido, ausente o
ilegible es «sin señales».
"""
import datetime as dt

from . import backup, catalogo, events, nocturna, store

LOCAL = "%H:%M"


MODO = "observar"
MODO_TEXTO = ("Modo: observar. Pulse no lanza nada; quien actúa sigue siendo el bucle actual "
              "(todavía no hay configuración de modo, así que el efectivo es siempre observar).")


def _hace(delta):
    s = max(0, int(delta.total_seconds()))
    if s < 90:
        return "%d segundo%s" % (s, "" if s == 1 else "s")
    m = round(s / 60)
    if m < 60:
        return "%d minutos" % m
    h, m = divmod(m, 60)
    return "%d h %d min" % (h, m) if m else "%d h" % h


def _nocturna(evs, ahora, env):
    """Estado de la comprobación nocturna para status. Sin datos fiables nunca es «bien»."""
    try:
        cfg = nocturna.configuracion(env)
    except store.EntradaInvalida:
        return {"estado": "config_invalida"}
    if cfg is None:
        return {"estado": "sin_configurar"}
    u = nocturna.estado(evs)["ultimo"] if evs is not None else None
    if u is None:
        return {"estado": "sin_datos"}
    n = nocturna.estado(evs)["racha"]
    out = {"estado": u["resultado"], "racha": n, "pasada_edad_s": int((ahora - store.parse_ts(u["at"])).total_seconds())}
    cierres = [e for e in evs if e["tipo"] == "nocturna_racha_cerrada" and e["dia"] == u["dia"]]
    if cierres and u["resultado"] == "verde":
        out["cerrada"] = cierres[-1]["longitud"]  # solo el día del cierre: al siguiente ya no reaparece
    if u.get("ejecucion_at"):
        out["ejecucion_edad_s"] = int((ahora - store.parse_ts(u["ejecucion_at"])).total_seconds())
    if out["pasada_edad_s"] > nocturna.MAX_EDAD.total_seconds():
        out["estado"] = "pasada_vieja"
    return out


def collect(root, ahora=None, env=None):
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
    cat, ult = catalogo.estado(evs) if est_l == store.OK else ("sin_datos", None)
    out["catalogo"] = {"estado": cat, "agentes": ult["agentes"] if cat == "con_deriva" else []}
    out["nocturna"] = _nocturna(evs if est_l == store.OK else None, ahora, env)
    out["trabajos"], out["terminados_hoy"] = jobs, fin_hoy
    todas = backup.pendientes(root, ahora, incluir_respaldo=True)
    out["avisos"] = sum(1 for p in todas if backup.es_aviso(p))
    out["pendientes"] = [{"que": p["que"], "critica": p["critica"]} for p in todas if not backup.es_aviso(p)]
    out["modo"] = MODO
    vigente, motivo = backup.presencia(root)
    out["soul"] = {"presente": vigente, "motivo": motivo}
    return out


def _noches(n):
    return "%d noche%s seguida%s" % (n, "" if n == 1 else "s", "" if n == 1 else "s")


def _linea_nocturna(n):
    e = n["estado"]
    if e == "sin_configurar":
        return ("Comprobación nocturna: sin configurar (hacen falta %s y %s); no consulto nada."
                % (nocturna.ENV_REPO, nocturna.ENV_FLUJO))
    if e == "config_invalida":
        return "Comprobación nocturna: la configuración no es válida; no consulto nada."
    if e == "sin_datos":
        return "Comprobación nocturna: todavía no se ha comprobado."
    if e == "pasada_vieja":
        return ("Comprobación nocturna: la última comprobación de Pulse fue hace %s; no sé cómo está ahora."
                % _hace(dt.timedelta(seconds=n["pasada_edad_s"])))
    if e == "verde":
        linea = "Comprobación nocturna: bien (última ejecución hace %s)." % _hace(dt.timedelta(seconds=n["ejecucion_edad_s"]))
        if n.get("cerrada"):
            linea += " La racha en rojo terminó tras %s." % _noches(n["cerrada"]).replace(" seguidas", "").replace(" seguida", "")
        return linea
    sufijo = " Detalle en «Esperan algo de ti»."
    if e == "rojo":
        return "Comprobación nocturna: en rojo, %s.%s" % (_noches(n["racha"]), sufijo)
    if e == "sin_ejecucion":
        return "Comprobación nocturna: no se ha ejecutado en las últimas 26 horas (%s).%s" % (_noches(n["racha"]), sufijo)
    return "Comprobación nocturna: no he podido mirarla, no sé si está bien.%s" % sufijo


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
    L.append(MODO_TEXTO)
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
    if d["avisos"]:
        L.append("Avisos: %d (trabajos terminados bien, no piden nada). Detalle: pulse inbox." % d["avisos"])
    if d["pendientes"]:
        crit = sum(1 for x in d["pendientes"] if x["critica"])
        L.append("Esperan algo de ti: %d%s. Detalle: pulse inbox." % (len(d["pendientes"]), " (%d crítica(s))" % crit if crit else ""))
    else:
        L.append("Esperan algo de ti: nada que conste.")
    c = d["catalogo"]
    if c["estado"] == "con_deriva":
        L.append("Agentes desajustados con el repositorio: %s. Se resolverá al regenerar las copias." % ", ".join(c["agentes"]))
    elif c["estado"] == "sin_deriva":
        L.append("Catálogo de agentes: sin deriva (agentes de nivel superior).")
    else:
        L.append("Catálogo de agentes: sin datos.")
    L.append(_linea_nocturna(d["nocturna"]))
    L.append("Freno: sin información (todavía no está conectado a Pulse).")
    if d["soul"]["presente"]:
        L.append("Soul: presente. Los avisos los da Soul.")
    else:
        L.append("Soul: %s. Los avisos salen por el canal de respaldo." % d["soul"]["motivo"])
    return "\n".join(L)
