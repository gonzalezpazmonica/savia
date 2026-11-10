#!/usr/bin/env python3
"""SE-488 S1 — artefacto de aprobación (R1) y recibo de merge verificable sin red (R2).

Una aprobación que amplía la autoridad de un agente es una PR en un repo privado
de aprobaciones que la operadora fusiona desde la app de GitHub. Este CLI:

  resumen   regenera el `resumen` determinista de un `objeto` (R1).
  nuevo     construye un artefacto `aprobacion/1` y su ruta (R1).
  artefacto valida un artefacto suelto contra R1 (ruta + esquema).
  verificar comprueba un commit de merge del espejo local (R2.1–R2.9) sin consumir.
  consumir  comprueba y anota el uso en el libro de consumidos bajo flock (R2.8);
            la acción se ejecuta DESPUÉS, fuera de este CLI.
  sincronizar avanza el espejo solo por fast-forward.

Códigos de salida (AC-3): 0 aprobado · 1 no vigente (cabeza/huella distinta,
caducado, por debajo del suelo, ya consumido) · 2 inválido (cualquier fallo
estructural R2.1–R2.6/R2.9, herramienta ausente, clave o génesis sin fijar,
espejo sin rama). Ante cualquier duda: no aprobado (fail-closed).

Política (JSON, la pasa el consumidor; nunca la decide el artefacto):
  {"genesis": "<sha40>", "rama": "main",
   "autor": {"email": "...", "nombre": "..."},       # nombre opcional
   "clave_webflow": "<ruta .asc>", "huella_webflow": "<fpr40 de la clave primaria>",
   "tipos": ["savia-merge"], "libro": "<directorio del libro de consumidos>",
   "caducidad_max_horas": 24}                         # el verificador impone ≤ 24
"""
import argparse
import datetime as dt
import difflib
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ESQUEMA = "aprobacion/1"
TIPOS = ("yema-contrato", "savia-merge", "savia-settings")
MAX_HORAS = 24
CAMPOS = {"esquema", "tipo", "nonce", "emitida", "caduca", "objeto", "resumen"}
RE_RUTA = re.compile(
    r"^aprobaciones/(yema-contrato|savia-merge|savia-settings)/"
    r"([0-9]{8})-([a-z0-9-]{1,64})-([0-9a-f]{8})\.json$")
RE_ID = re.compile(r"^[a-z0-9-]{1,64}$")
RE_HEX64 = re.compile(r"^[0-9a-f]{64}$")
RE_HEX40 = re.compile(r"^[0-9a-f]{40}$")
RE_NONCE = re.compile(r"^[0-9a-f]{16}$")
RE_REPO = re.compile(r"^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}$")
RE_FECHA = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
RE_RAMA = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,99}")
MAX_PRS = 50

APROBADO, NO_VIGENTE, INVALIDO = 0, 1, 2


class Rechazo(Exception):
    def __init__(self, codigo, condicion, motivo):
        super().__init__(motivo)
        self.codigo, self.condicion, self.motivo = codigo, condicion, motivo


def invalido(cond, motivo):
    return Rechazo(INVALIDO, cond, motivo)


def no_vigente(cond, motivo):
    return Rechazo(NO_VIGENTE, cond, motivo)


# ---------------------------------------------------------------- R1: artefacto

def parse_fecha(s, cond="R1"):
    if not isinstance(s, str) or not RE_FECHA.fullmatch(s):
        raise invalido(cond, f"fecha no ISO-8601 UTC (AAAA-MM-DDTHH:MM:SSZ): {s!r}")
    try:
        return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        raise invalido(cond, f"fecha imposible: {s!r}")


def fmt_fecha(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _claves(obj, esperadas, cond, que):
    if not isinstance(obj, dict) or set(obj) != set(esperadas):
        raise invalido(cond, f"{que}: claves esperadas {sorted(esperadas)}")


def validar_objeto(tipo, obj):
    """Valida el objeto según su tipo (R1). Lanza Rechazo(INVALIDO)."""
    c = "R1"
    if tipo == "yema-contrato":
        _claves(obj, {"id", "huella"}, c, "objeto yema-contrato")
        if not isinstance(obj["id"], str) or not RE_ID.fullmatch(obj["id"]):
            raise invalido(c, "id de contrato fuera de la lista blanca")
        if not isinstance(obj["huella"], str) or not RE_HEX64.fullmatch(obj["huella"]):
            raise invalido(c, "huella sha256 incompleta o no hex")
    elif tipo == "savia-merge":
        _claves(obj, {"repo", "prs"}, c, "objeto savia-merge")
        if not isinstance(obj["repo"], str) or not RE_REPO.fullmatch(obj["repo"]) or ".." in obj["repo"]:
            raise invalido(c, "repo fuera de la lista blanca (propietario/nombre)")
        prs = obj["prs"]
        if not isinstance(prs, list) or not 1 <= len(prs) <= MAX_PRS:
            raise invalido(c, f"prs debe ser una lista de 1 a {MAX_PRS}")
        vistos = set()
        for pr in prs:
            _claves(pr, {"numero", "head_sha"}, c, "pr")
            n = pr["numero"]
            if type(n) is not int or n <= 0 or n in vistos:
                raise invalido(c, "numero de PR no entero positivo o repetido")
            vistos.add(n)
            if not isinstance(pr["head_sha"], str) or not RE_HEX40.fullmatch(pr["head_sha"]):
                raise invalido(c, "head_sha no es un sha1 completo")
    elif tipo == "savia-settings":
        _claves(obj, {"fichero", "sha256_antes", "sha256_despues", "diff"}, c, "objeto savia-settings")
        f = obj["fichero"]
        if (not isinstance(f, str) or not f or len(f) > 200 or not f.isascii()
                or f.startswith("/") or ".." in f.split("/") or "\\" in f
                or not re.fullmatch(r"[A-Za-z0-9_./-]+", f)):
            raise invalido(c, "fichero de settings fuera de la lista blanca (ruta relativa ASCII)")
        for k in ("sha256_antes", "sha256_despues"):
            if not isinstance(obj[k], str) or not RE_HEX64.fullmatch(obj[k]):
                raise invalido(c, f"{k} no es un sha256 completo")
        if not isinstance(obj["diff"], str):
            raise invalido(c, "diff debe ser texto")
    else:
        raise invalido(c, f"tipo fuera del enum: {tipo!r}")


def id_de(tipo, obj):
    """<id> de la ruta, derivado de forma determinista del objeto."""
    if tipo == "yema-contrato":
        return obj["id"]
    if tipo == "savia-merge":
        return "pr-" + "-".join(str(p["numero"]) for p in obj["prs"])
    return "settings-" + obj["sha256_despues"][:12]


def generar_resumen(tipo, obj):
    """Resumen en lenguaje llano, determinista (R1). Byte a byte reproducible."""
    if tipo == "yema-contrato":
        return (f"Aprobar el contrato de Yema «{obj['id']}» con huella "
                f"{obj['huella']}. Si el contrato cambia, esta aprobación deja de valer.")
    if tipo == "savia-merge":
        lineas = [f"Fusionar en {obj['repo']} {len(obj['prs'])} PR, cada una solo con esta cabeza exacta:"]
        lineas += [f"- PR #{p['numero']} con cabeza {p['head_sha']}" for p in obj["prs"]]
        return "\n".join(lineas)
    return (f"Cambiar el fichero de settings {obj['fichero']} del contenido con sha256 "
            f"{obj['sha256_antes']} al contenido con sha256 {obj['sha256_despues']}, "
            f"según el diff incluido.")


def diff_canonico(antes, despues, fichero):
    return "".join(difflib.unified_diff(
        antes.decode("utf-8").splitlines(keepends=True),
        despues.decode("utf-8").splitlines(keepends=True),
        fromfile=f"a/{fichero}", tofile=f"b/{fichero}"))


def validar_artefacto(art, ruta, max_horas=MAX_HORAS):
    """R1 + R2.5 (ruta ↔ campos) + R2.6 (esquema, nonce, ventana ≤ 24 h)."""
    m = RE_RUTA.fullmatch(ruta) if isinstance(ruta, str) and ruta.isascii() else None
    if not m:
        raise invalido("R2.5", f"ruta fuera de la lista blanca: {ruta!r}")
    r_tipo, r_fecha, r_id, r_nonce8 = m.groups()
    if not isinstance(art, dict) or set(art) != CAMPOS:
        raise invalido("R2.6", f"esquema {ESQUEMA}: claves exactas {sorted(CAMPOS)}")
    if art["esquema"] != ESQUEMA:
        raise invalido("R2.6", "esquema distinto de aprobacion/1")
    tipo = art["tipo"]
    if tipo not in TIPOS:
        raise invalido("R2.6", f"tipo fuera del enum: {tipo!r}")
    if not isinstance(art["nonce"], str) or not RE_NONCE.fullmatch(art["nonce"]):
        raise invalido("R2.6", "nonce no son 16 hex")
    emitida = parse_fecha(art["emitida"], "R2.6")
    caduca = parse_fecha(art["caduca"], "R2.6")
    tope = dt.timedelta(hours=min(MAX_HORAS, max_horas))
    if not dt.timedelta(0) < caduca - emitida <= tope:
        raise invalido("R2.6", f"caduca − emitida debe estar en (0, {tope}]")
    validar_objeto(tipo, art["objeto"])
    if not isinstance(art["resumen"], str) or art["resumen"] != generar_resumen(tipo, art["objeto"]):
        raise invalido("R1", "el resumen no coincide byte a byte con el regenerado")
    if (r_tipo, r_id, r_nonce8) != (tipo, id_de(tipo, art["objeto"]), art["nonce"][:8]):
        raise invalido("R2.5", "la ruta no casa con el tipo, el id o el nonce del fichero")
    if r_fecha != emitida.strftime("%Y%m%d"):
        raise invalido("R2.5", "la fecha de la ruta no es la de emisión")
    return emitida, caduca


def nuevo_artefacto(tipo, obj, emitida, horas):
    validar_objeto(tipo, obj)
    nonce = os.urandom(8).hex()
    art = {"esquema": ESQUEMA, "tipo": tipo, "nonce": nonce,
           "emitida": fmt_fecha(emitida),
           "caduca": fmt_fecha(emitida + dt.timedelta(hours=horas)),
           "objeto": obj, "resumen": generar_resumen(tipo, obj)}
    ruta = f"aprobaciones/{tipo}/{emitida.strftime('%Y%m%d')}-{id_de(tipo, obj)}-{nonce[:8]}.json"
    validar_artefacto(art, ruta, horas)
    return ruta, art


# ---------------------------------------------------------------- git sin red

def _which(prog):
    p = shutil.which(prog)
    if not p:
        raise invalido("entorno", f"herramienta ausente: {prog}")
    return p


class Espejo:
    """Acceso de solo lectura al espejo, aislado de la configuración del usuario."""

    def __init__(self, ruta, gnupghome=None, gpg=None):
        self.ruta, self.git = ruta, _which("git")
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        # Ni objetos de reemplazo (refs/replace) ni grafts: git leería otro contenido
        # u otros padres que los firmados.
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        LC_ALL="C", GIT_TERMINAL_PROMPT="0",
                        GIT_NO_REPLACE_OBJECTS="1", GIT_GRAFT_FILE=os.devnull)
        if gnupghome:
            self.env["GNUPGHOME"] = gnupghome
        falso = shutil.which("false") or "/bin/false"
        # Precedencia de línea de órdenes: la config del espejo no puede redirigir gpg.
        self.cfg = ["-c", "core.fsmonitor=false", "-c", "core.useReplaceRefs=false",
                    "-c", "protocol.ext.allow=never",
                    "-c", f"gpg.program={gpg or falso}",
                    "-c", f"gpg.openpgp.program={gpg or falso}",
                    "-c", f"gpg.x509.program={falso}", "-c", f"gpg.ssh.program={falso}"]

    def integridad(self):
        """El espejo no es de fiar: sin reemplazos, grafts ni shallow, y cada objeto
        con el hash que dice tener (fsck recalcula los hashes, también los sueltos)."""
        if self.out("for-each-ref", "--format=%(refname)", "refs/replace/").strip():
            raise invalido("espejo", "el espejo tiene refs/replace: rechazado")
        comun = self.out("rev-parse", "--path-format=absolute", "--git-common-dir").strip()
        if os.path.lexists(os.path.join(comun, "info", "grafts")):
            raise invalido("espejo", "el espejo tiene info/grafts: rechazado")
        if self.out("rev-parse", "--is-shallow-repository").strip() != "false":
            raise invalido("espejo", "el espejo es shallow: rechazado")
        p = self.run("fsck", "--no-dangling", "--no-progress", "--no-reflogs", check=False)
        if p.returncode != 0:
            raise invalido("espejo", "git fsck falló (objetos alterados o ausentes): "
                           + p.stderr.decode(errors="replace").strip()[:200])

    def run(self, *args, check=True):
        p = subprocess.run([self.git, *self.cfg, "-C", self.ruta, *args], env=self.env,
                           capture_output=True)
        if check and p.returncode != 0:
            raise invalido("espejo", f"git {args[0]} falló: {p.stderr.decode(errors='replace').strip()[:200]}")
        return p

    def out(self, *args):
        return self.run(*args).stdout.decode("utf-8", errors="strict")


def _importar_clave(gnupghome, gpg, clave):
    p = subprocess.run([gpg, "--batch", "--homedir", gnupghome, "--import", clave],
                       capture_output=True)
    if p.returncode != 0:
        raise invalido("R2.3", "no se pudo importar la clave web-flow fijada")


def _matar_gpg(gnupghome):
    gc = shutil.which("gpgconf")
    if gc:
        subprocess.run([gc, "--homedir", gnupghome, "--kill", "all"], capture_output=True)


def firma_valida(esp, sha, huella):
    """R2.3: GOODSIG + VALIDSIG cuya clave primaria es la fijada."""
    p = esp.run("verify-commit", "--raw", sha, check=False)
    estado = p.stderr.decode("utf-8", errors="replace").splitlines()
    if p.returncode != 0:
        return False
    good = any(l.startswith("[GNUPG:] GOODSIG ") for l in estado)
    bad = any(re.match(r"^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG) ", l) for l in estado)
    fprs = set()
    for l in estado:
        if l.startswith("[GNUPG:] VALIDSIG "):
            campos = l.split()
            fprs.add(campos[-1].upper())  # huella de la clave primaria
            fprs.add(campos[2].upper())
    return good and not bad and huella.upper() in fprs


def entrada_unica(esp, m):
    """R2.5: exactamente un alta (A) de fichero normal 100644; devuelve (ruta, blob)."""
    raw = esp.run("diff-tree", "-r", "-z", "--raw", "--no-renames", "--no-commit-id",
                  f"{m}^1", m).stdout
    partes = [x for x in raw.split(b"\0") if x != b""]
    if len(partes) != 2:
        raise invalido("R2.5", "el merge no cambia exactamente un fichero")
    meta, ruta = partes[0].decode("ascii", errors="strict"), partes[1]
    campos = meta.lstrip(":").split()
    if len(campos) != 5 or campos[4] != "A":
        raise invalido("R2.5", f"la entrada no es un alta (A): {campos[-1] if campos else '?'}")
    if campos[1] != "100644":
        raise invalido("R2.5", f"modo no permitido para el fichero nuevo: {campos[1]}")
    try:
        ruta = ruta.decode("ascii")
    except UnicodeDecodeError:
        raise invalido("R2.5", "ruta con caracteres fuera de ASCII")
    return ruta, campos[3]


def commit_aprobado(esp, sha, pol):
    """R2.2–R2.5 para un commit de la cadena. Devuelve (ruta, blob)."""
    padres = esp.out("rev-list", "--parents", "-n", "1", sha).split()[1:]
    if len(padres) != 2:
        raise invalido("R2.2", f"{sha[:12]} tiene {len(padres)} padre(s); se exigen 2")
    if not firma_valida(esp, sha, pol["huella_webflow"]):
        raise invalido("R2.3", f"{sha[:12]} sin firma válida de la clave web-flow fijada")
    email, nombre = esp.out("log", "-1", "--format=%ae%x00%an", sha).rstrip("\n").split("\0")
    autor = pol["autor"]
    if email != autor["email"] or ("nombre" in autor and nombre != autor["nombre"]):
        raise invalido("R2.4", f"{sha[:12]} no tiene como autora a la operadora")
    return entrada_unica(esp, sha)


# ---------------------------------------------------------------- libro (R2.7/R2.8)

class Libro:
    def __init__(self, directorio):
        self.dir = directorio
        os.makedirs(directorio, mode=0o700, exist_ok=True)
        self.consumidos = os.path.join(directorio, "consumidos.jsonl")
        self.estado_f = os.path.join(directorio, "estado.json")
        self._fd = None

    def __enter__(self):
        self._fd = open(os.path.join(self.dir, ".cerrojo"), "a")
        fcntl.flock(self._fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        fcntl.flock(self._fd, fcntl.LOCK_UN)
        self._fd.close()

    def estado(self):
        try:
            with open(self.estado_f) as f:
                e = json.load(f)
            return e if isinstance(e, dict) else {}
        except FileNotFoundError:
            return {}
        except (OSError, ValueError):
            raise invalido("R2.8", "libro de consumidos ilegible")

    def guardar(self, e):
        tmp = self.estado_f + ".tmp"
        with open(tmp, "w") as f:
            json.dump(e, f, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.estado_f)

    def usado(self, nonce, unidad):
        try:
            with open(self.consumidos) as f:
                for linea in f:
                    try:
                        r = json.loads(linea)
                    except ValueError:
                        raise invalido("R2.8", "línea corrupta en el libro de consumidos")
                    if r.get("nonce") == nonce and r.get("unidad") == unidad:
                        return True
        except FileNotFoundError:
            pass
        return False

    def anotar(self, registro):
        with open(self.consumidos, "a") as f:
            f.write(json.dumps(registro, sort_keys=True) + "\n")
            f.flush()
            os.fsync(f.fileno())


# ---------------------------------------------------------------- R2: recibo

def unidad_y_coincidencia(tipo, obj, esperado, contenidos):
    """R2.6 (objeto ↔ esperado). Devuelve la unidad de consumo (R2.8)."""
    if not isinstance(esperado, dict):
        raise invalido("R2.6", "objeto esperado ausente")
    if tipo == "yema-contrato":
        if esperado.get("id") != obj["id"]:
            raise invalido("R2.6", "el recibo es de otro contrato")
        if esperado.get("huella") != obj["huella"]:
            raise no_vigente("R2.6", "huella distinta: el contrato cambió tras aprobar")
        return f"{obj['id']}@{obj['huella']}"
    if tipo == "savia-merge":
        if esperado.get("repo") != obj["repo"]:
            raise invalido("R2.6", "el recibo es de otro repo")
        pr = next((p for p in obj["prs"] if p["numero"] == esperado.get("numero")), None)
        if pr is None:
            raise invalido("R2.6", "la PR no figura en el lote aprobado")
        if esperado.get("head_sha") != pr["head_sha"]:
            raise no_vigente("R2.6", "la cabeza de la PR difiere de la aprobada")
        return f"{obj['repo']}#{pr['numero']}"
    # savia-settings: el verificador comprueba el diff con los contenidos reales.
    if esperado.get("fichero") != obj["fichero"]:
        raise invalido("R2.6", "el recibo es de otro fichero de settings")
    antes, despues = contenidos or (None, None)
    if antes is None or despues is None:
        raise invalido("R2.6", "faltan los contenidos antes/después para comprobar el diff")
    if hashlib.sha256(antes).hexdigest() != obj["sha256_antes"]:
        raise no_vigente("R2.6", "el fichero actual no es el aprobado (sha256_antes)")
    if hashlib.sha256(despues).hexdigest() != obj["sha256_despues"]:
        raise no_vigente("R2.6", "el resultado propuesto no es el aprobado (sha256_despues)")
    try:
        canon = diff_canonico(antes, despues, obj["fichero"])
    except UnicodeDecodeError:
        raise invalido("R2.6", "settings no UTF-8")
    if obj["diff"] != canon:
        raise invalido("R2.6", "el diff no lleva de sha256_antes a sha256_despues")
    return f"{obj['fichero']}@{obj['sha256_antes']}"


def validar_politica(pol):
    req = ("genesis", "autor", "clave_webflow", "huella_webflow", "tipos", "libro")
    if not isinstance(pol, dict) or any(k not in pol for k in req):
        raise invalido("política", f"política incompleta: se exigen {list(req)}")
    if not isinstance(pol["genesis"], str) or not RE_HEX40.fullmatch(pol["genesis"]):
        raise invalido("R2.1", "commit génesis no fijado")
    if not isinstance(pol["huella_webflow"], str) or not re.fullmatch(r"[0-9A-Fa-f]{40}", pol["huella_webflow"]):
        raise invalido("R2.3", "huella de la clave web-flow no fijada")
    if not isinstance(pol["clave_webflow"], str) or not os.path.isfile(pol["clave_webflow"]):
        raise invalido("R2.3", "clave web-flow fijada ausente")
    if not isinstance(pol["autor"], dict) or not pol["autor"].get("email"):
        raise invalido("R2.4", "identidad de la operadora no configurada")
    if not isinstance(pol["tipos"], list):
        raise invalido("R2.9", "tipos habilitados mal formados")
    validar_rama(pol.get("rama", "main"))


def validar_rama(rama):
    if not isinstance(rama, str) or not RE_RAMA.fullmatch(rama) or ".." in rama:
        raise invalido("R2.1", f"rama fuera de la lista blanca: {rama!r}")


def _verificar(pol, espejo, commit, tipo, esperado, ahora, contenidos, libro, consumir):
    validar_politica(pol)
    if tipo not in TIPOS or tipo not in pol["tipos"]:
        raise invalido("R2.9", f"tipo no habilitado en la política: {tipo!r}")
    if not isinstance(commit, str) or not RE_HEX40.fullmatch(commit):
        raise invalido("R2.1", "el commit debe ser un sha1 completo (40 hex en minúscula)")
    gpg = _which("gpg")
    gh = tempfile.mkdtemp(prefix="se488-")
    try:
        os.chmod(gh, 0o700)
        _importar_clave(gh, gpg, pol["clave_webflow"])
        esp = Espejo(espejo, gh, gpg)
        rama = pol.get("rama", "main")
        esp.integridad()
        p = esp.run("rev-parse", "--verify", "--quiet", "--end-of-options",
                    f"refs/heads/{rama}^{{commit}}", check=False)
        if p.returncode != 0:
            raise invalido("R2.1", f"el espejo no tiene la rama {rama}")
        punta = p.stdout.decode().strip()
        p = esp.run("rev-parse", "--verify", "--quiet", "--end-of-options",
                    f"{commit}^{{commit}}", check=False)
        if p.returncode != 0:
            raise invalido("R2.1", "el commit no existe en el espejo")
        m = p.stdout.decode().strip()

        estado = libro.estado()
        visto = estado.get("punta")
        if visto and visto != punta:
            ok = esp.run("merge-base", "--is-ancestor", visto, punta, check=False).returncode == 0
            if not ok:
                raise invalido("R2.1", "main del espejo se reescribió (no fast-forward)")

        cadena = esp.out("rev-list", "--first-parent", punta).split()
        if not cadena or cadena[-1] != pol["genesis"].lower():
            raise invalido("R2.1", "la cadena first-parent de main no llega al génesis fijado")
        if esp.out("rev-list", "--parents", "-n", "1", cadena[-1]).split()[1:]:
            raise invalido("R2.1", "el génesis fijado no es un commit raíz")
        if m not in cadena[:-1]:
            raise invalido("R2.1", "M no está en la cadena first-parent de main")
        ruta_m = blob_m = None
        for sha in cadena[:-1]:
            ruta, blob = commit_aprobado(esp, sha, pol)
            if sha == m:
                ruta_m, blob_m = ruta, blob

        crudo = esp.run("cat-file", "blob", blob_m).stdout
        if hashlib.sha1(b"blob %d\0" % len(crudo) + crudo).hexdigest() != blob_m:
            raise invalido("espejo", "el contenido leído no tiene el hash del blob firmado")
        try:
            art = json.loads(crudo.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            raise invalido("R2.6", "el fichero no es JSON UTF-8")
        emitida, caduca = validar_artefacto(art, ruta_m, pol.get("caducidad_max_horas", MAX_HORAS))
        if art["tipo"] != tipo:
            raise invalido("R2.6", "el recibo es de otro tipo")
        unidad = unidad_y_coincidencia(tipo, art["objeto"], esperado, contenidos)

        # R2.7: ventana y suelo monótono.
        f_m = dt.datetime.fromtimestamp(int(esp.out("log", "-1", "--format=%ct", m).strip()), dt.timezone.utc)
        f_punta = dt.datetime.fromtimestamp(int(esp.out("log", "-1", "--format=%ct", punta).strip()), dt.timezone.utc)
        suelo = max([f_punta, f_m] + ([parse_fecha(estado["suelo"], "R2.7")] if estado.get("suelo") else []))
        if ahora < suelo:
            raise no_vigente("R2.7", f"ahora ({fmt_fecha(ahora)}) es anterior al suelo monótono ({fmt_fecha(suelo)})")
        if not emitida <= f_m <= caduca:
            raise no_vigente("R2.7", "la fecha del merge está fuera de [emitida, caduca]")
        if not ahora < caduca:
            raise no_vigente("R2.7", "recibo caducado")

        # R2.8: libro de consumidos (comprobar → anotar; la acción va después).
        if libro.usado(art["nonce"], unidad):
            raise no_vigente("R2.8", f"unidad ya consumida: {unidad}")
        if consumir:
            libro.anotar({"nonce": art["nonce"], "unidad": unidad, "commit": m,
                          "tipo": tipo, "ahora": fmt_fecha(ahora)})
        libro.guardar({"punta": punta, "suelo": fmt_fecha(max(suelo, ahora) if consumir else suelo)})
        return {"veredicto": "APROBADO", "codigo": APROBADO, "commit": m, "unidad": unidad,
                "nonce": art["nonce"], "via": f"github:{m[:12]}", "consumido": consumir}
    finally:
        _matar_gpg(gh)
        shutil.rmtree(gh, ignore_errors=True)


def verificar(pol, espejo, commit, tipo, esperado, ahora=None, contenidos=None, consumir=False):
    """Punto de enganche para consumidores (R4). Siempre devuelve un dict; nunca lanza."""
    ahora = ahora or dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    try:
        libro_dir = pol.get("libro") if isinstance(pol, dict) else None
        if not isinstance(libro_dir, str) or not libro_dir:
            raise invalido("R2.8", "libro de consumidos no configurado")
        with Libro(libro_dir) as libro:
            return _verificar(pol, espejo, commit, tipo, esperado, ahora, contenidos, libro, consumir)
    except Rechazo as r:
        v = "NO_VIGENTE" if r.codigo == NO_VIGENTE else "INVALIDO"
        return {"veredicto": v, "codigo": r.codigo, "condicion": r.condicion, "motivo": r.motivo}
    except Exception as e:  # fail-closed ante cualquier sorpresa
        return {"veredicto": "INVALIDO", "codigo": INVALIDO, "condicion": "error",
                "motivo": f"{type(e).__name__}: {e}"}


def sincronizar(espejo, remoto, rama="main"):
    """Avanza refs/heads/<rama> del espejo SOLO por fast-forward (sin '+')."""
    validar_rama(rama)
    if not isinstance(remoto, str) or not remoto or remoto.startswith("-"):
        raise invalido("R2.1", f"remoto no válido: {remoto!r}")
    esp = Espejo(espejo)
    p = esp.run("fetch", "--no-tags", "--end-of-options", remoto,
                f"refs/heads/{rama}:refs/heads/{rama}", check=False)
    if p.returncode != 0:
        raise invalido("R2.1", "sincronización rechazada (¿main reescrito?): "
                       + p.stderr.decode(errors="replace").strip()[:200])


# ---------------------------------------------------------------- CLI

def _leer_json(ruta):
    with open(ruta, "rb") as f:
        return json.loads(f.read().decode("utf-8"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="orden", required=True)
    s = sub.add_parser("resumen"); s.add_argument("--tipo", required=True); s.add_argument("--objeto", required=True)
    s = sub.add_parser("nuevo"); s.add_argument("--tipo", required=True); s.add_argument("--objeto", required=True)
    s.add_argument("--horas", type=int, default=MAX_HORAS); s.add_argument("--emitida")
    s = sub.add_parser("artefacto"); s.add_argument("fichero"); s.add_argument("--ruta", required=True)
    for nombre in ("verificar", "consumir"):
        s = sub.add_parser(nombre)
        s.add_argument("--politica", required=True); s.add_argument("--espejo", required=True)
        s.add_argument("--commit", required=True); s.add_argument("--tipo", required=True)
        s.add_argument("--esperado", required=True, help="JSON con la unidad esperada")
        s.add_argument("--ahora", help="fecha UTC; con red, la del servidor (R2.7)")
        s.add_argument("--antes"); s.add_argument("--despues")
    s = sub.add_parser("sincronizar"); s.add_argument("--espejo", required=True)
    s.add_argument("--remoto", required=True); s.add_argument("--rama", default="main")
    a = ap.parse_args(argv)
    try:
        if a.orden == "resumen":
            obj = json.loads(a.objeto); validar_objeto(a.tipo, obj)
            sys.stdout.write(generar_resumen(a.tipo, obj) + "\n"); return 0
        if a.orden == "nuevo":
            if not 1 <= a.horas <= MAX_HORAS:
                raise invalido("R1", f"--horas debe estar entre 1 y {MAX_HORAS}")
            em = parse_fecha(a.emitida) if a.emitida else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
            ruta, art = nuevo_artefacto(a.tipo, json.loads(a.objeto), em, a.horas)
            print(json.dumps({"ruta": ruta, "artefacto": art}, ensure_ascii=False, indent=2)); return 0
        if a.orden == "artefacto":
            validar_artefacto(_leer_json(a.fichero), a.ruta)
            print(json.dumps({"veredicto": "VALIDO"})); return 0
        if a.orden == "sincronizar":
            sincronizar(a.espejo, a.remoto, a.rama); print(json.dumps({"veredicto": "SINCRONIZADO"})); return 0
        pol = _leer_json(a.politica)
        contenidos = None
        if a.antes or a.despues:
            if not (a.antes and a.despues):
                raise invalido("R2.6", "--antes y --despues van juntos")
            with open(a.antes, "rb") as f1, open(a.despues, "rb") as f2:
                contenidos = (f1.read(), f2.read())
        ahora = parse_fecha(a.ahora, "R2.7") if a.ahora else None
        r = verificar(pol, a.espejo, a.commit, a.tipo, json.loads(a.esperado), ahora,
                      contenidos, consumir=(a.orden == "consumir"))
    except Rechazo as e:
        r = {"veredicto": "INVALIDO", "codigo": INVALIDO, "condicion": e.condicion, "motivo": e.motivo}
    except (OSError, ValueError) as e:
        r = {"veredicto": "INVALIDO", "codigo": INVALIDO, "condicion": "entrada", "motivo": str(e)}
    print(json.dumps(r, ensure_ascii=False))
    return r["codigo"]


if __name__ == "__main__":
    sys.exit(main())
