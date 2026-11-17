#!/usr/bin/env python3
"""SE-512 S1 — grant de política del sprint nocturno: plan, petición y verificación.

  plan     construye la política canónica de R1 desde un borrador JSON y la guarda
           (no la guarda si algún límite de R1 falla: exit 2).
  request  genera el artefacto `aprobacion/1` de tipo `savia-politica` (SE-488), el
           título y la descripción de la PR de aprobación; con --abrir, la abre.
  verify   comprueba el recibo de SE-488 de la política, su digest y la ventana
           efectiva. Nunca aprueba, nunca consume, nunca fusiona.

Un solo formato de autorización: la aprobación es la fusión de una PR en el repo de
aprobaciones, verificada con scripts/approval-receipt.py. El tipo `savia-politica`
no está en el enum de SE-488; aquí se habilita en memoria, solo para este consumidor
(habilitar_tipo_politica), sin tocar el verificador compartido.

Salida de verify: 0 grant · 7 recibo válido, antes de la ventana efectiva · 3 sin
grant (sin recibo, recibo no válido, caducado, herramienta ausente, error) · 4 libro
de consumidos manipulado · 5 anomalía (digest distinto o configuración de aprobación
cambiada). Ante cualquier duda: sin grant (fail-closed).
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TIPO = "savia-politica"
CAMPOS = {"kind", "id", "not_before", "not_after", "repos", "tiers", "max_merges",
          "max_parks_in_row", "universe", "frozen_prs", "reviewers", "max_reviews_per_pr",
          "runner_blob", "classifier_blob", "f5_blob", "resolver_blob", "main_pending_timeout"}
CAMPOS_REPO = {"repo", "base", "include", "exclude", "required_checks"}
CLAVES_REPO_BORRADOR = {"repo", "base", "include", "exclude"}
MAX_VENTANA = dt.timedelta(hours=12)
MAX_LATENCIA = dt.timedelta(hours=1)        # «sin políticas latentes»
TECHO_MERGES, TECHO_PARKS, TECHO_REVIEWS = 40, 3, 4
HORA_FIN_LOCAL = 8
RE_ID = re.compile(r"^[0-9a-f]{16}$")
RE_BLOB = re.compile(r"^[0-9a-f]{40}$")
RE_REPO = re.compile(r"^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}$")
GRANT, ANTES, SIN_GRANT, MANIPULADO, ANOMALIA, RECHAZADA = 0, 7, 3, 4, 5, 2


def cargar_verificador():
    spec = importlib.util.spec_from_file_location("approval_receipt_se512",
                                                  os.path.join(HERE, "approval-receipt.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ar = cargar_verificador()


class Rechazada(Exception):
    pass


ORQUESTADORES = {"savia-orchestrator", "savia-orquestadora"}


def orquestadores():
    """Ids que nunca pueden ser reviewers: los de siempre más los de MERGE_SPRINT_ORCHESTRATOR.

    La variable amplía la lista, no la sustituye (no puede «desprohibir» a nadie)."""
    return ORQUESTADORES | set(os.environ.get("MERGE_SPRINT_ORCHESTRATOR", "").split())


# ---------------------------------------------------------------- R1: forma canónica

def canonico(pol):
    """JSON canónico de R1: claves ordenadas, sin espacios. `approval` no entra."""
    cuerpo = {k: v for k, v in pol.items() if k != "approval"}
    return json.dumps(cuerpo, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def digest(pol):
    return hashlib.sha256(canonico(pol).encode()).hexdigest()


def _fecha(s, campo):
    try:
        return ar.parse_fecha(s)
    except ar.Rechazo:
        raise Rechazada(f"{campo} no es un instante UTC AAAA-MM-DDTHH:MM:SSZ: {s!r}")


def _entero(v, campo, lo, hi):
    if type(v) is not int or not lo <= v <= hi:
        raise Rechazada(f"{campo} debe ser un entero entre {lo} y {hi}: {v!r}")


RE_GLOB_RUTA = re.compile(r"^[A-Za-z0-9._/*-]+$")          # lista blanca: nada de marcado Markdown/HTML
RE_REVIEWER = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})(?:\[bot\])?$")
RE_CHECK = re.compile(r"^[^\x00-\x1f\x7f<>`]{1,200}$")


def _globs(v, campo, vacia_ok):
    if not isinstance(v, list) or (not v and not vacia_ok) or not all(
            isinstance(g, str) and RE_GLOB_RUTA.fullmatch(g) and not g.startswith("/")
            and ".." not in g.split("/") for g in v):
        raise Rechazada(f"{campo}: lista de globs de rutas relativas" + ("" if vacia_ok else " no vacía"))


def validar(pol):
    """Límites de R1 que se comprueban sin red. Lanza Rechazada."""
    if not isinstance(pol, dict) or set(pol) != CAMPOS:
        faltan = sorted(CAMPOS - set(pol)) if isinstance(pol, dict) else []
        sobran = sorted(set(pol) - CAMPOS) if isinstance(pol, dict) else []
        raise Rechazada(f"campos de la política: faltan {faltan}, sobran {sobran}")
    if pol["kind"] != "policy":
        raise Rechazada("kind debe ser \"policy\"")
    if not isinstance(pol["id"], str) or not RE_ID.fullmatch(pol["id"]):
        raise Rechazada("id debe ser 16 hex")
    nb, na = _fecha(pol["not_before"], "not_before"), _fecha(pol["not_after"], "not_after")
    if not dt.timedelta(0) < na - nb <= MAX_VENTANA:
        raise Rechazada(f"ventana fuera de (0, 12 h]: {na - nb}")
    t = pol["tiers"]
    if not isinstance(t, list) or not t or any(type(x) is not int or x not in (1, 2) for x in t) \
            or len(set(t)) != len(t):
        raise Rechazada(f"tiers debe ser un subconjunto no vacío de {{1,2}}: {t!r}")
    _entero(pol["max_merges"], "max_merges", 1, TECHO_MERGES)
    _entero(pol["max_parks_in_row"], "max_parks_in_row", 1, TECHO_PARKS)
    _entero(pol["max_reviews_per_pr"], "max_reviews_per_pr", 1, TECHO_REVIEWS)
    _entero(pol["main_pending_timeout"], "main_pending_timeout", 5, 60)
    u, fz = pol["universe"], pol["frozen_prs"]
    if u not in ("open", "frozen"):
        raise Rechazada("universe debe ser \"open\" o \"frozen\"")
    if not isinstance(fz, list) or any(type(n) is not int or n <= 0 for n in fz) or len(set(fz)) != len(fz):
        raise Rechazada("frozen_prs debe ser una lista de números de PR distintos")
    if u == "frozen" and not fz:
        raise Rechazada("universe frozen sin lista de PR")
    if u == "open" and fz:
        raise Rechazada("universe open no lleva lista de PR")
    rv = pol["reviewers"]
    if not isinstance(rv, list) or not all(isinstance(r, str) and RE_REVIEWER.fullmatch(r) for r in rv) \
            or len({r.casefold() for r in rv}) != len(rv):
        raise Rechazada("reviewers debe ser una lista de ids distintos (logins de GitHub, sin distinguir mayúsculas)")
    if len(rv) < 2:
        raise Rechazada("hacen falta al menos dos reviewers distintos")
    if {r.casefold() for r in rv} & {o.casefold() for o in orquestadores()}:
        raise Rechazada("el id del orquestador no puede ser reviewer")
    for k in ("runner_blob", "classifier_blob", "f5_blob", "resolver_blob"):
        if not isinstance(pol[k], str) or not RE_BLOB.fullmatch(pol[k]):
            raise Rechazada(f"{k} no es un blob de 40 hex")
    repos = pol["repos"]
    if not isinstance(repos, list) or not repos:
        raise Rechazada("repos debe ser una lista no vacía")
    vistos = set()
    for r in repos:
        if not isinstance(r, dict) or set(r) != CAMPOS_REPO:
            raise Rechazada(f"cada repo lleva exactamente {sorted(CAMPOS_REPO)}")
        if not isinstance(r["repo"], str) or not RE_REPO.fullmatch(r["repo"]) or ".." in r["repo"]:
            raise Rechazada(f"repo fuera de la lista blanca: {r['repo']!r}")
        if not isinstance(r["base"], str) or not ar.RE_RAMA.fullmatch(r["base"]) or ".." in r["base"]:
            raise Rechazada(f"base no válida: {r['base']!r}")
        if (r["repo"], r["base"]) in vistos:
            raise Rechazada(f"repo repetido: {r['repo']}")
        vistos.add((r["repo"], r["base"]))
        _globs(r["include"], "include", vacia_ok=False)
        _globs(r["exclude"], "exclude", vacia_ok=True)
        rc = r["required_checks"]
        if not isinstance(rc, list) or not rc or not all(isinstance(c, str) and RE_CHECK.fullmatch(c) for c in rc):
            raise Rechazada(f"required_checks vacío en {r['repo']}")


# ---------------------------------------------------------------- plan

def fin_por_defecto(nb):
    """Primer instante entre las 08:00 locales siguientes y nb + 12 h."""
    local = nb.astimezone()
    dia = local.date() if local.hour < HORA_FIN_LOCAL else local.date() + dt.timedelta(days=1)
    # Hora ingenua → astimezone() la interpreta en la zona local con su DST de ese día.
    ocho = dt.datetime(dia.year, dia.month, dia.day, HORA_FIN_LOCAL).astimezone()
    return min(ocho.astimezone(dt.timezone.utc), nb + MAX_VENTANA)


def ventana(borrador, ahora):
    nb = _fecha(borrador["not_before"], "not_before") if "not_before" in borrador else ahora
    if nb - ahora > MAX_LATENCIA:
        raise Rechazada(f"not_before {ar.fmt_fecha(nb)} es posterior a la emisión en más de 1 h")
    if "not_after" in borrador:
        na = _fecha(borrador["not_after"], "not_after")
        if na - nb > MAX_VENTANA:
            raise Rechazada(f"not_after explícito da una ventana de {na - nb} (> 12 h)")
    else:
        na = fin_por_defecto(nb)
    if na <= ahora:
        raise Rechazada("not_after ya ha pasado")
    return nb, na


def _git(d, *args):
    p = subprocess.run(["git", "-C", d, *args], capture_output=True)
    if p.returncode != 0:
        raise Rechazada(f"git {args[0]} falló en {d}: {p.stderr.decode(errors='replace').strip()[:160]}")
    return p.stdout.decode("utf-8", errors="replace")


def blob_en(d, base, ruta):
    p = subprocess.run(["git", "-C", d, "rev-parse", "-q", "--verify", f"origin/{base}:{ruta}"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise Rechazada(f"sin {ruta} en origin/{base}")
    return p.stdout.strip()


RE_GLOB_SIMPLE = re.compile(r"^[A-Za-z0-9._/*-]+$")


def _glob_gh(patron):
    """Regex de un filtro de ramas de GitHub con solo `*` (no cruza `/`) y `**` (cruza `/`).

    None si el patrón usa sintaxis que aquí no se interpreta (`?`, `+`, `[]`…): el llamador
    lo trata como desconocido, nunca como coincidencia ni como no coincidencia."""
    if not isinstance(patron, str) or not RE_GLOB_SIMPLE.fullmatch(patron):
        return None
    trozos = re.split(r"(\*\*|\*)", patron)
    return re.compile("".join(".*" if t == "**" else "[^/]*" if t == "*" else re.escape(t)
                              for t in trozos))


def _rama_casa(patrones, base, negacion_ok):
    """True/False según los filtros de GitHub (gana el último que casa; `!` niega).
    None si algún patrón no se sabe interpretar."""
    if not isinstance(patrones, list):
        patrones = [patrones]
    casa = False
    for p in patrones:
        neg = isinstance(p, str) and p.startswith("!")
        if neg and not negacion_ok:
            return None
        rx = _glob_gh(p[1:] if neg else p)
        if rx is None:
            return None
        if rx.fullmatch(base):
            casa = not neg
    return casa


def push_sin_filtro(on, base):
    """¿Este `on:` dispara en cada push a `base` sin filtro de rutas?"""
    if on == "push":
        return True
    if isinstance(on, list):
        return "push" in on
    if not isinstance(on, dict) or "push" not in on:
        return False
    p = on["push"]
    if p is None or p == {}:
        return True
    if not isinstance(p, dict) or "paths" in p or "paths-ignore" in p:
        return False
    if "branches" in p:
        return _rama_casa(p["branches"] or [], base, negacion_ok=True) is True
    if "branches-ignore" in p:
        return _rama_casa(p["branches-ignore"] or [], base, negacion_ok=False) is False
    return "tags" not in p and "tags-ignore" not in p


def workflow_sin_filtro(d, base):
    """Workflows de origin/<base> que corren en cada push a <base> sin filtro de rutas."""
    import yaml
    salida = []
    lista = _git(d, "ls-tree", "-r", "--name-only", f"origin/{base}", "--", ".github/workflows/")
    for ruta in lista.splitlines():
        if not re.fullmatch(r"\.github/workflows/[^/]+\.ya?ml", ruta):   # GitHub ignora subcarpetas
            continue
        try:
            doc = yaml.safe_load(_git(d, "show", f"origin/{base}:{ruta}"))
        except Exception:
            continue                                  # ilegible: no cuenta (fail-closed)
        if isinstance(doc, dict):
            on = doc.get("on", doc.get(True))         # YAML 1.1 lee `on` como True
            if push_sin_filtro(on, base):
                salida.append(ruta)
    return salida


def repo_de_origin(d):
    """`owner/repo` del remoto origin del clon `d` (URL tal cual, sin insteadOf), o None."""
    p = subprocess.run(["git", "-C", d, "config", "--get", "remote.origin.url"],
                       capture_output=True, text=True)
    m = re.fullmatch(r"(?:https://github\.com/|ssh://git@github\.com/|git@github\.com:)"
                     r"([^/\s]+/[^/\s]+?)(?:\.git)?/?", p.stdout.strip()) if p.returncode == 0 else None
    return m.group(1) if m else None


def checks_obligatorios(repo, base):
    gh = os.environ.get("GH", "gh")
    p = subprocess.run([gh, "api", f"repos/{repo}/branches/{base}/protection/required_status_checks",
                        "--jq", ".contexts[]"], capture_output=True, text=True)
    if p.returncode != 0:
        raise Rechazada(f"no se pudo leer la protección de {repo}:{base}")
    return sorted({c for c in p.stdout.splitlines() if c.strip()})


def plan(borrador, ahora, raiz):
    if not isinstance(borrador, dict):
        raise Rechazada("el borrador debe ser un objeto JSON")
    permitidos = {"repos", "tiers", "max_merges", "max_parks_in_row", "universe", "frozen_prs",
                  "reviewers", "max_reviews_per_pr", "main_pending_timeout", "not_before", "not_after"}
    if set(borrador) - permitidos:
        raise Rechazada(f"claves desconocidas en el borrador: {sorted(set(borrador) - permitidos)}")
    if "max_merges" not in borrador:
        raise Rechazada("max_merges es obligatorio")
    nb, na = ventana(borrador, ahora)
    repos = []
    if not isinstance(borrador.get("repos") or [], list):
        raise Rechazada("repos del borrador debe ser una lista")
    for r in borrador.get("repos") or []:
        if not isinstance(r, dict):
            raise Rechazada("cada repo del borrador es un objeto")
        if set(r) - CLAVES_REPO_BORRADOR:
            raise Rechazada(f"claves desconocidas en un repo del borrador: {sorted(set(r) - CLAVES_REPO_BORRADOR)}")
        repo, base = r.get("repo"), r.get("base", "main")
        # Antes de cualquier llamada a git o a la API: repo y base dentro de la lista blanca.
        if not isinstance(repo, str) or not RE_REPO.fullmatch(repo) or ".." in repo:
            raise Rechazada(f"repo fuera de la lista blanca: {repo!r}")
        if not isinstance(base, str) or not ar.RE_RAMA.fullmatch(base) or ".." in base:
            raise Rechazada(f"base no válida: {base!r}")
        # El workflow sin filtro y los blobs congelados se leen del clon `raiz`: ha de ser el
        # clon de ese repo y estar al día con su remoto.
        origen = repo_de_origin(raiz)
        if origen != repo:
            raise Rechazada(f"{repo}: el clon {raiz} no es de ese repo (origin = {origen})")
        _git(raiz, "fetch", "-q", "origin", f"+refs/heads/{base}:refs/remotes/origin/{base}")
        if not workflow_sin_filtro(raiz, base):
            raise Rechazada(f"{repo}: origin/{base} no tiene ningún workflow sin filtro de rutas en push a {base}")
        repos.append({"repo": repo, "base": base, "include": r.get("include"),
                      "exclude": r.get("exclude", []),
                      "required_checks": checks_obligatorios(repo, base)})
    base0 = (borrador.get("repos") or [{}])[0].get("base", "main") if borrador.get("repos") else "main"
    pol = {"kind": "policy", "id": os.urandom(8).hex(),
           "not_before": ar.fmt_fecha(nb), "not_after": ar.fmt_fecha(na), "repos": repos,
           "tiers": borrador.get("tiers"), "max_merges": borrador["max_merges"],
           "max_parks_in_row": borrador.get("max_parks_in_row", TECHO_PARKS),
           "universe": borrador.get("universe", "open"), "frozen_prs": borrador.get("frozen_prs", []),
           "reviewers": borrador.get("reviewers"),
           "max_reviews_per_pr": borrador.get("max_reviews_per_pr", TECHO_REVIEWS),
           "main_pending_timeout": borrador.get("main_pending_timeout", 20)}
    validar({**pol, **{k: "0" * 40 for k in ("runner_blob", "classifier_blob", "f5_blob", "resolver_blob")}})
    pol.update(runner_blob=blob_en(raiz, base0, "scripts/merge-sprint.sh"),
               classifier_blob=blob_en(raiz, base0, "scripts/risk-tier.py"),
               f5_blob=blob_en(raiz, base0, "scripts/f5-state.sh"),
               resolver_blob=blob_en(raiz, base0, "scripts/merge-registry-resolve.py"))
    validar(pol)
    return pol


# ---------------------------------------------------------------- resumen, título, cuerpo

def _md(s):
    """Texto de usuario sin efecto de marcado: &, <, > como entidades y el resto escapado."""
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return re.sub(r"([\\`*_\[\]()!|~#])", r"\\\1", s)


def generar_resumen(pol):
    """Lenguaje llano, determinista: solo depende del objeto (byte a byte)."""
    tiers = " y ".join(str(t) for t in sorted(pol["tiers"]))
    l = [f"Permiso de fusión nocturna, política {pol['id']}.",
         f"Ventana: desde {pol['not_before']} hasta {pol['not_after']} (hora UTC).",
         f"Tope: {pol['max_merges']} fusiones. Se para tras {pol['max_parks_in_row']} PR aparcadas seguidas.",
         "Repos y rutas:"]
    for r in pol["repos"]:
        fuera = ", ".join(f"`{g}`" for g in r["exclude"]) if r["exclude"] else "nada más"
        dentro = ", ".join(f"`{g}`" for g in r["include"])
        l.append(f"- {r['repo']} hacia {r['base']}: entran {dentro}; "
                 f"quedan fuera {fuera}. Checks obligatorios: {', '.join(_md(c) for c in r['required_checks'])}.")
    l.append("Universo: " + ("cualquier PR abierta de esas ramas, también las que se abran de noche."
                             if pol["universe"] == "open" else
                             "solo las PR " + ", ".join(f"#{n}" for n in sorted(pol["frozen_prs"])) + "."))
    l.append(f"Solo PR de tier {tiers}, con dos APPROVE sobre su cabeza exacta de revisoras distintas "
             f"entre {', '.join(pol['reviewers'])}; como mucho {pol['max_reviews_per_pr']} revisiones por PR.")
    l.append("Siempre quedan fuera, diga lo que diga la política: gobernanza, código de los gates, "
             "manifiestos de dependencias, tests de los gates, el guard nocturno y el código que "
             "ejecutan los workflows.")
    l.append(f"main ha de estar en verde antes y después de cada fusión; espera máxima "
             f"{pol['main_pending_timeout']} min.")
    l.append(f"Código congelado: ejecutor {pol['runner_blob'][:12]}, clasificador "
             f"{pol['classifier_blob'][:12]}, f5 {pol['f5_blob'][:12]}, resolutor {pol['resolver_blob'][:12]}.")
    l.append("Para pararla: merge-sprint.sh stop o revoke. Para ampliarla hace falta otra PR de aprobación.")
    return "\n".join(l)


def generar_titulo(pol):
    repos = ", ".join(r["repo"] for r in pol["repos"])
    return (f"Permiso para el sprint nocturno: {repos} hasta {pol['not_after']}, "
            f"máximo {pol['max_merges']} fusiones")


def generar_cuerpo(pol, resumen):
    return (resumen + "\n\nDigest de la política (sha256 del JSON canónico): " + digest(pol)
            + "\n\nFusionar esta PR aprueba exactamente esta política. Cerrarla sin fusionar la rechaza.\n")


# ---------------------------------------------------------------- tipo savia-politica en SE-488

def habilitar_tipo_politica(mod):
    """Da de alta `savia-politica` en una copia en memoria del verificador de SE-488.

    No cambia el fichero compartido ni a otros consumidores. Pendiente declarado (SE-488
    R2.9): darlo de alta en su enum cerrado en su propia PR."""
    if TIPO in mod.TIPOS:
        return mod
    o_validar, o_id, o_resumen = mod.validar_objeto, mod.id_de, mod.generar_resumen
    o_unidad, o_artefacto = mod.unidad_y_coincidencia, mod.validar_artefacto
    mod.TIPOS = tuple(mod.TIPOS) + (TIPO,)
    mod.RE_RUTA = re.compile(r"^aprobaciones/(yema-contrato|savia-merge|savia-settings|savia-politica)/"
                             r"([0-9]{8})-([a-z0-9-]{1,64})-([0-9a-f]{8})\.json$")

    def validar_objeto(tipo, obj):
        if tipo != TIPO:
            return o_validar(tipo, obj)
        try:
            validar(obj)
        except Rechazada as e:
            raise mod.invalido("R1", f"política no válida: {e}")

    def unidad_y_coincidencia(tipo, obj, esperado, contenidos):
        if tipo != TIPO:
            return o_unidad(tipo, obj, esperado, contenidos)
        if not isinstance(esperado, dict) or digest(esperado) != digest(obj):
            raise Anomalia("digest", "el fichero de política no es el aprobado (digest distinto)")
        return f"politica@{digest(obj)}"

    def validar_artefacto(art, ruta, max_horas=mod.MAX_HORAS):
        emitida, caduca = o_artefacto(art, ruta, max_horas)
        if art["tipo"] == TIPO:
            obj = art["objeto"]
            if art["caduca"] != obj["not_after"]:
                raise mod.invalido("SE-512", "caduca distinto de not_after del objeto")
            if emitida < ar.parse_fecha(obj["not_before"]) - MAX_LATENCIA:
                raise mod.invalido("SE-512", "emitida anterior a not_before − 1 h")
        return emitida, caduca

    mod.validar_objeto, mod.unidad_y_coincidencia, mod.validar_artefacto = \
        validar_objeto, unidad_y_coincidencia, validar_artefacto
    mod.id_de = lambda tipo, obj: obj["id"] if tipo == TIPO else o_id(tipo, obj)
    mod.generar_resumen = lambda tipo, obj: generar_resumen(obj) if tipo == TIPO else o_resumen(tipo, obj)
    return mod


habilitar_tipo_politica(ar)


class Anomalia(ar.Rechazo):
    def __init__(self, condicion, motivo):
        super().__init__(ANOMALIA, condicion, motivo)


def nuevo_artefacto(pol, emitida):
    validar(pol)
    nb, na = ar.parse_fecha(pol["not_before"]), ar.parse_fecha(pol["not_after"])
    if emitida < nb - MAX_LATENCIA:
        raise Rechazada("la petición es anterior a not_before − 1 h")
    if emitida >= na:
        raise Rechazada("la política ya caducó (emitida ≥ not_after)")
    nonce = os.urandom(8).hex()
    art = {"esquema": ar.ESQUEMA, "tipo": TIPO, "nonce": nonce, "emitida": ar.fmt_fecha(emitida),
           "caduca": pol["not_after"], "objeto": json.loads(canonico(pol)),
           "resumen": generar_resumen(pol)}
    ruta = f"aprobaciones/{TIPO}/{emitida.strftime('%Y%m%d')}-{pol['id']}-{nonce[:8]}.json"
    ar.validar_artefacto(art, ruta)
    return ruta, art


def huella_config(cfg):
    """Huella de la configuración de aprobación de SE-488 que fija la verificación."""
    if not isinstance(cfg, dict):
        raise Rechazada("la configuración de aprobación no es un objeto JSON")
    try:
        with open(cfg["clave_webflow"], "rb") as f:
            clave = hashlib.sha256(f.read()).hexdigest()
    except (OSError, KeyError, TypeError):
        clave = None
    fija = {"genesis": cfg.get("genesis"), "autor": cfg.get("autor"), "rama": cfg.get("rama", "main"),
            "huella_webflow": str(cfg.get("huella_webflow", "")).upper(), "clave": clave,
            # También mandan: el libro (límite de uso único, R2.8), de dónde se leen el título y
            # el cuerpo de la PR, y los tipos habilitados. El espejo y su remoto no: moverlos no
            # amplía nada, porque la cadena hasta el génesis y la clave fijados se verifican igual.
            "libro": cfg.get("libro"), "repo_aprobaciones": cfg.get("repo_aprobaciones"),
            "tipos": cfg.get("tipos")}
    return hashlib.sha256(json.dumps(fija, sort_keys=True).encode()).hexdigest()


# ---------------------------------------------------------------- verify

class LibroPolitica(ar.Libro):
    """Libro de SE-488 con la lectura de uso único de SE-512: la unidad es la activación.

    La misma unidad ya anotada no es reutilización (pasadas siguientes); el mismo nonce
    anotado para otra unidad solo ocurre con el libro manipulado."""
    activada = False

    def usado(self, nonce, unidad):
        try:
            with open(self.consumidos) as f:
                for linea in f:
                    try:
                        r = json.loads(linea)
                    except ValueError:
                        raise ar.Rechazo(MANIPULADO, "R2.8", "línea corrupta en el libro de consumidos")
                    if r.get("nonce") == nonce and r.get("unidad") != unidad:
                        raise ar.Rechazo(MANIPULADO, "R2.8", "nonce anotado para otro digest: libro manipulado")
                    if r.get("nonce") == nonce:
                        self.activada = True
        except FileNotFoundError:
            pass
        return False


def ruta_de_peticion(peticion, pol_id):
    """Ruta del artefacto que registró policy-request, comprobada contra el id de la política."""
    ruta = peticion.get("ruta")
    if not isinstance(ruta, str) or not re.fullmatch(
            rf"aprobaciones/{TIPO}/[0-9]{{8}}-{re.escape(pol_id)}-[0-9a-f]{{8}}\.json", ruta):
        raise ar.invalido("SE-512", "la ruta de la petición no es de esta política")
    return ruta


def buscar_merge(esp, rama, ruta):
    """Último merge first-parent de `rama` que añade exactamente el artefacto `ruta` de la petición."""
    out = esp.out("log", "--first-parent", "--diff-filter=A", "--name-only", "--format=%x00%H",
                  f"refs/heads/{rama}", "--", f"aprobaciones/{TIPO}/")
    for bloque in out.split("\0"):
        lineas = [x for x in bloque.splitlines() if x]
        if len(lineas) >= 2 and ruta in lineas[1:]:
            return lineas[0]
    return None


def _texto_pr(s):
    """Normalización documentada del texto que devuelve GitHub: CRLF → LF y sin blancos finales.

    Nada más: cualquier otro cambio (palabras, cifras, líneas) es «distinto». Un cuerpo
    `null` o que no es texto nunca coincide."""
    if not isinstance(s, str):
        return None
    return s.replace("\r\n", "\n").rstrip()


def pr_de_merge(cfg, m):
    gh = os.environ.get("GH", "gh")
    p = subprocess.run([gh, "api", f"repos/{cfg['repo_aprobaciones']}/commits/{m}/pulls",
                        "--jq", "[.[] | {title, body, merge_commit_sha}]"], capture_output=True, text=True)
    if p.returncode != 0:
        raise ar.invalido("SE-512", "no se pudo leer la PR de aprobación")
    prs = [x for x in json.loads(p.stdout) if x.get("merge_commit_sha") == m]
    if len(prs) != 1:
        raise ar.invalido("SE-512", "el merge no corresponde a exactamente una PR")
    return prs[0]


def verificar(pol, cfg, peticion, ahora, activar=False):
    """Nunca lanza. Devuelve un dict con `codigo` (GRANT, ANTES, SIN_GRANT, MANIPULADO, ANOMALIA).

    Con activar=True (solo para `run --policy`, S2) y veredicto GRANT, anota la activación
    `politica@digest` en el libro de consumidos una sola vez, dentro del mismo cerrojo que
    la verificación: dos pasadas o dos procesos concurrentes no activan dos veces."""
    base = {"politica": pol.get("id") if isinstance(pol, dict) else None}
    try:
        if not isinstance(peticion, dict):
            raise ar.invalido("SE-512", "sin registro de policy-request para esta política")
        if peticion.get("digest") != digest(pol):
            raise Anomalia("digest", "el fichero de política no es el de la petición (digest distinto)")
        if peticion.get("aprobacion_cfg") != huella_config(cfg):
            raise Anomalia("configuracion", "la configuración de aprobación de SE-488 cambió desde la petición")
        validar(pol)
        if not isinstance(cfg.get("espejo"), str) or not isinstance(cfg.get("repo_aprobaciones"), str):
            raise ar.invalido("SE-512", "configuración sin espejo o sin repo de aprobaciones")
        if TIPO not in (cfg.get("tipos") or []):
            raise ar.invalido("R2.9", "tipo savia-politica no habilitado en la configuración")
        if not isinstance(cfg.get("libro"), str) or not cfg["libro"]:
            raise ar.invalido("R2.8", "libro de consumidos no configurado")
        esp = ar.Espejo(cfg["espejo"])
        ruta = ruta_de_peticion(peticion, pol["id"])
        m = buscar_merge(esp, cfg.get("rama", "main"), ruta)
        if not m:
            raise ar.no_vigente("SE-512", "sin PR de aprobación fusionada para esta política")
        ar.validar_politica(cfg)
        with LibroPolitica(cfg["libro"]) as libro:
            r = ar._verificar(cfg, cfg["espejo"], m, TIPO, pol, ahora, None, libro, False)
            fechas = esp.out("log", "--format=%ct", "--diff-filter=A", f"{m}^1..{m}^2", "--", ruta).split()
            if len(fechas) != 1:
                raise ar.invalido("SE-512", "el artefacto no lo añade exactamente un commit de la PR")
            art = json.loads(esp.out("show", f"{m}:{ruta}"))
            if art.get("nonce") != r["nonce"]:
                raise ar.invalido("SE-512", "el artefacto de la petición no es el del merge")
            if ar.fmt_fecha(dt.datetime.fromtimestamp(int(fechas[0]), dt.timezone.utc)) != art["emitida"]:
                raise ar.invalido("SE-512", "emitida distinta de la fecha del commit que añade el artefacto")
            resumen = generar_resumen(pol)
            pr = pr_de_merge(cfg, m)
            # Lo que se compara es el texto actual de la PR; el que manda es el objeto firmado.
            if _texto_pr(pr.get("title")) != _texto_pr(generar_titulo(pol)) \
                    or _texto_pr(pr.get("body")) != _texto_pr(generar_cuerpo(pol, resumen)):
                raise ar.invalido("SE-512", "título o descripción de la PR distintos de los generados")
            f_m = dt.datetime.fromtimestamp(int(esp.out("log", "-1", "--format=%ct", m).strip()), dt.timezone.utc)
            inicio = max(ar.parse_fecha(pol["not_before"]), f_m)
            fin = ar.parse_fecha(pol["not_after"])
            res = {**base, "digest": digest(pol), "commit": m, "nonce": r["nonce"], "unidad": r["unidad"],
                   "ventana_efectiva": [ar.fmt_fecha(inicio), ar.fmt_fecha(fin)], "activada": libro.activada}
            if ahora < inicio:
                return {**res, "veredicto": "ANTES_DE_VENTANA", "codigo": ANTES}
            if ahora >= fin:
                return {**res, "veredicto": "SIN_GRANT", "codigo": SIN_GRANT, "motivo": "fuera de ventana"}
            if activar and not libro.activada:
                libro.anotar({"nonce": r["nonce"], "unidad": r["unidad"], "commit": m, "tipo": TIPO,
                              "estado": "activada", "ahora": ar.fmt_fecha(ahora)})
                res["activada"] = True
            return {**res, "veredicto": "GRANT", "codigo": GRANT}
    except ar.Rechazo as e:
        cod = e.codigo if e.codigo in (ANOMALIA, MANIPULADO) else SIN_GRANT
        ver = {ANOMALIA: "ANOMALIA", MANIPULADO: "MANIPULADO"}.get(cod, "SIN_GRANT")
        return {**base, "veredicto": ver, "codigo": cod, "condicion": e.condicion, "motivo": e.motivo}
    except Exception as e:      # fail-closed ante cualquier sorpresa
        return {**base, "veredicto": "SIN_GRANT", "codigo": SIN_GRANT, "condicion": "error",
                "motivo": f"{type(e).__name__}: {e}"}


def activar(pol, cfg, peticion, ahora):
    """Activación de `run --policy` (S2). No la expone ningún subcomando de S1."""
    return verificar(pol, cfg, peticion, ahora, activar=True)


# ---------------------------------------------------------------- request --abrir

def abrir_pr(peticion, clon, repo_aprob, base="main"):
    """Rama + commit con fecha `emitida` en un clon del repo de aprobaciones + PR hacia `base`.

    Lanza subprocess.CalledProcessError u OSError si algún paso falla."""
    rama = "politica-" + os.path.basename(peticion["ruta"])[:-5]
    t = peticion["artefacto"]["emitida"].replace("Z", "+0000")
    env = {**os.environ, "GIT_AUTHOR_DATE": t, "GIT_COMMITTER_DATE": t}
    def g(*a):
        subprocess.run(["git", "-C", clon, *a], check=True, capture_output=True, env=env)
    g("fetch", "-q", "origin", f"+refs/heads/{base}:refs/remotes/origin/{base}")
    g("checkout", "-q", "-b", rama, f"origin/{base}")     # -b: nunca pisa una rama del clon
    destino = os.path.join(clon, peticion["ruta"])
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with open(destino, "w", encoding="utf-8") as f:
        f.write(json.dumps(peticion["artefacto"], ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    g("add", "--", peticion["ruta"])
    # --only: solo el artefacto, aunque el índice del clon traiga otras altas preparadas.
    g("commit", "-q", "--only", "-m", peticion["titulo"], "--", peticion["ruta"])
    g("push", "-q", "-u", "origin", rama)
    gh = os.environ.get("GH", "gh")
    with tempfile.TemporaryDirectory() as td:       # fuera de .git (en un worktree .git es un fichero)
        cuerpo = os.path.join(td, "cuerpo.md")
        with open(cuerpo, "w", encoding="utf-8") as f:
            f.write(peticion["cuerpo"])
        subprocess.run([gh, "pr", "create", "-R", repo_aprob, "--base", base, "--head", rama,
                        "--title", peticion["titulo"], "--body-file", cuerpo], check=True)


# ---------------------------------------------------------------- CLI

def _leer(ruta):
    with open(ruta, "rb") as f:
        return json.loads(f.read().decode("utf-8"))


def _guardar(ruta, contenido):
    os.makedirs(os.path.dirname(ruta), mode=0o700, exist_ok=True)
    tmp = ruta + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(contenido)
    os.replace(tmp, ruta)


def _ahora(s):
    return ar.parse_fecha(s) if s else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def _request(a, pol, cfg, preq):
    """policy-request. Todas las validaciones van antes de cualquier efecto; el registro de la
    petición se escribe solo si todo lo anterior (también --abrir) ha ido bien. Una política
    tiene una sola petición: repetirla exige otra política (policy-plan, otro id)."""
    def rechazo(motivo):
        print(f"policy-request: rechazada: {motivo}", file=sys.stderr)
        return RECHAZADA
    if not isinstance(cfg, dict):
        return rechazo("la configuración de aprobación no es un objeto JSON")
    if a.abrir and (not a.clon or not isinstance(cfg.get("repo_aprobaciones"), str)):
        return rechazo("--abrir exige --clon y repo_aprobaciones")
    try:
        # La configuración se valida como la validará verify: una que nunca podría verificarse
        # no registra petición (registrarla bloquearía la política: solo hay una petición).
        ar.validar_politica(cfg)
        if TIPO not in cfg["tipos"] or not isinstance(cfg.get("espejo"), str) \
                or not isinstance(cfg.get("repo_aprobaciones"), str):
            raise Rechazada("la configuración no habilita savia-politica o le falta espejo o repo_aprobaciones")
        ruta, art = nuevo_artefacto(pol, _ahora(a.ahora))
        pet = {"ruta": ruta, "artefacto": art, "digest": digest(pol), "aprobacion_cfg": huella_config(cfg),
               "titulo": generar_titulo(pol), "cuerpo": generar_cuerpo(pol, art["resumen"])}
    except (Rechazada, ar.Rechazo) as e:
        return rechazo(getattr(e, "motivo", e))
    # Reserva atómica (O_EXCL) antes de abrir la PR: dos peticiones simultáneas no abren dos PR.
    os.makedirs(os.path.dirname(preq), mode=0o700, exist_ok=True)
    try:
        os.close(os.open(preq, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
    except FileExistsError:
        return rechazo(f"ya hay una petición para esta política ({preq}); para otra, policy-plan")
    try:
        if a.abrir:
            try:
                abrir_pr(pet, a.clon, cfg["repo_aprobaciones"], cfg.get("rama", "main"))
            except (subprocess.CalledProcessError, OSError) as e:
                os.unlink(preq)
                return rechazo(f"no se pudo abrir la PR de aprobación: {e}")
        _guardar(preq, json.dumps(pet, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    except BaseException:
        if os.path.exists(preq) and os.path.getsize(preq) == 0:
            os.unlink(preq)
        raise
    print(json.dumps({"peticion": preq, "ruta": ruta, "titulo": pet["titulo"]}, ensure_ascii=False))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--home", default=os.environ.get("MERGE_SPRINT_HOME",
                                                     os.path.expanduser("~/.savia/merge-sprint")))
    sub = ap.add_subparsers(dest="orden", required=True)
    s = sub.add_parser("plan"); s.add_argument("--borrador", required=True); s.add_argument("--ahora")
    s.add_argument("--raiz", default=os.environ.get("MERGE_SPRINT_GIT_ROOT", os.path.dirname(HERE)))
    s = sub.add_parser("request"); s.add_argument("--politica", required=True)
    s.add_argument("--aprobacion", required=True); s.add_argument("--ahora")
    s.add_argument("--abrir", action="store_true"); s.add_argument("--clon")
    s = sub.add_parser("verify"); s.add_argument("--politica", required=True)
    s.add_argument("--aprobacion", required=True); s.add_argument("--ahora")
    s.add_argument("--sincronizar", action="store_true")
    a = ap.parse_args(argv)
    pdir = os.path.join(a.home, "policy")
    if a.orden == "plan":
        try:
            pol = plan(_leer(a.borrador), _ahora(a.ahora), a.raiz)
        except (Rechazada, ar.Rechazo, OSError, ValueError, ImportError) as e:
            print(f"policy-plan: rechazada: {getattr(e, 'motivo', e)}", file=sys.stderr)
            return RECHAZADA
        ruta = os.path.join(pdir, f"{pol['id']}.json")
        _guardar(ruta, canonico(pol) + "\n")
        print(json.dumps({"politica": ruta, "id": pol["id"], "digest": digest(pol),
                          "ventana": [pol["not_before"], pol["not_after"]]}))
        return 0
    try:
        pol = _leer(a.politica)
        cfg = _leer(a.aprobacion)
    except (OSError, ValueError) as e:
        print(json.dumps({"veredicto": "SIN_GRANT", "codigo": SIN_GRANT, "motivo": str(e)}))
        return SIN_GRANT if a.orden == "verify" else RECHAZADA
    pid = pol.get("id") if isinstance(pol, dict) else None
    preq = os.path.join(pdir, f"{pid}.request.json")
    if a.orden == "request":
        return _request(a, pol, cfg, preq)
    try:
        pet = _leer(preq)
    except (OSError, ValueError):
        pet = None
    if a.sincronizar:
        try:
            ar.sincronizar(cfg["espejo"], cfg["remoto"], cfg.get("rama", "main"))
        except Exception as e:
            print(json.dumps({"veredicto": "SIN_GRANT", "codigo": SIN_GRANT, "motivo": f"sincronización: {e}"}))
            return SIN_GRANT
    r = verificar(pol, cfg, pet, _ahora(a.ahora))
    print(json.dumps(r, ensure_ascii=False))
    return r["codigo"]


if __name__ == "__main__":
    sys.exit(main())
