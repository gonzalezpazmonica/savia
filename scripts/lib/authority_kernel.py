#!/usr/bin/env python3
"""Kernel de autoridad determinista (SE-496 F0). Solo stdlib.

Uso (siempre `python3 -I`):
  authority_kernel.py evaluate                  < peticion.json
  authority_kernel.py recheck --prior RECIBO    < peticion.json
  authority_kernel.py check-ontology [FICHERO]
  authority_kernel.py check-contract FICHERO
  authority_kernel.py verify-audit

Salida: JSON por stdout. Exit: 0 ALLOW, 1 DENY, 4 REQUIRES_APPROVAL, 2 sin decision
(peticion mal formada o fallo interno). Deny por defecto; sin cache de decisiones;
`evaluate` nunca consume usos; los hechos `inferred` solo se devuelven como sugerencias.
La autoridad la fija el contrato firmado contra el fichero de firmantes de origin/main;
niveles de agente y ontologia tambien se leen de origin/main. Sin overrides por entorno.

Limites conocidos de F0 (sin hook que lo invoque todavia; se cierran al cablearlo en F1/F2):
- el ledger de usos y el audit viven en ~/.savia: quien pueda editar ese directorio puede
  borrar usos o reescribir la cadena entera (verify-audit no tiene ancla externa de la cabeza);
- risk-tier.py, el perfil activo y el propio kernel se leen del arbol de trabajo (misma clase de
  amenaza: codigo que decide y que el agente puede editar; se cierra al cablear, no a trozos);
- entre varios contratos del mismo delegado y capacidad se evalua el primero (fail-closed:
  puede dar un DENY donde otro contrato vigente daria ALLOW);
- un fichero renombrado se clasifica por su ruta de destino (ni `gh pr view` ni `.filename` de la
  API REST dan la de origen);
- el recibo --prior no esta autenticado: recheck repite los pasos 1-16 y solo lo usa para plazo,
  action_sha256 y state_digest (recalculables); no prueba por si solo que evaluate se ejecutara;
- Branch.* se lee primero de refs/heads locales (la rama que la accion publica); `ci_not_red` de pr.create-draft acepta `none`
  (sin ejecuciones): no es garantia de CI, solo de que no hay una ejecucion roja o pendiente;
- las rutas de vault.note-write son identificadores de recurso: solo ASCII (como ramas y proyectos);
- `ci_green` de pr.merge = al menos un SUCCESS y nada rojo ni pendiente; no comprueba que estén los
  checks requeridos por la protección de rama (para tier >= 3 sigue mandando REVIEW_REQUIRED).
Invariantes del contrato que se aplican tambien al evaluar (no solo en check-contract): vida <= 7 dias
(paso 6) y max_uses 1 si la capacidad no declara `reversibility: reversible` (paso 7).
Los parametros de la accion que nombran un recurso (PARAM_DIMS) tienen que coincidir con el
objetivo, y el objetivo es lo que el ambito firmado cubre.
"""
import datetime
import hashlib
import json
import os
import re
try:
    import pwd
except ImportError:  # sin base de usuarios POSIX: home() falla cerrado fuera de test_mode
    pwd = None
import shutil
import subprocess
import sys
import tempfile
import unicodedata

try:
    import fcntl
except ImportError:  # Windows: sin bloqueo de fichero (el audit sigue encadenado)
    fcntl = None

SELF = os.path.abspath(__file__)
SELF_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(SELF)))
SAFE_PATH = "/usr/bin:/bin:/usr/local/bin"
NAMESPACE = "savia-delegation"
BASE_REF = "refs/remotes/origin/main"
SIGNERS_REL = "config/" + "operator-grant-" + "signers"
REVOKED_REL = "config/delegations/REVOKED"
ONTOLOGY_REL = "contracts/ontology/savia-operational.yaml"
LEVELS_REL = "docs/rules/domain/agent-permission-levels.md"
PRIOR_MAX_AGE = datetime.timedelta(minutes=10)
MAX_LIFE = datetime.timedelta(days=7)
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
LEVELS = {"L0": 0, "L1": 1, "L2": 2, "L3": 3, "L4": 4}
AGENT_PRINCIPALS = {"", "self", "savia", "claude", "yema", "codex"}
# delegados con instancias `<familia>:<id>` que heredan el nivel de la familia (spec SE-496, campo delegate);
# cualquier otro `x:<algo>` necesita su propia fila en agent-permission-levels.md
INSTANCE_FAMILIES = ("savia-worker",)
OWNERS = ("source-backed", "contract-owned", "derived", "inferred")
REQUIRED_FIELDS = ("schema", "id", "nonce", "principal", "delegate", "capability", "authority",
                   "scope", "preconditions", "declared_effects", "not_before", "expires_at",
                   "installation")


class Deny(Exception):
    def __init__(self, code, detail=""):
        super().__init__(code)
        self.code, self.detail = code, detail


class Unknown(Deny):
    def __init__(self, detail=""):
        super().__init__("UNKNOWN_STATE", detail)


class Approval(Exception):
    def __init__(self, code, detail=""):
        super().__init__(code)
        self.code, self.detail = code, detail


class BadRequest(Exception):
    pass


# --------------------------------------------------------------------------- util
# Inyeccion de dependencias SOLO en proceso: la rellena tests/helpers/se496_kernel_entry.py (o la
# bateria en modo inproc) antes de llamar a main(). El kernel no lee ninguna variable de entorno
# para redirigirse: quien lo invoca como programa no puede cambiar raiz, reloj, perfil ni herramientas.
OVERRIDES = {}


def test_mode():
    return bool(OVERRIDES)


def tenv(name, default=None):
    """Valor inyectado en proceso (nunca del entorno del llamante)."""
    return OVERRIDES.get(name, default)


def sha(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def nfc(obj):
    if isinstance(obj, str):
        return unicodedata.normalize("NFC", obj)
    if isinstance(obj, list):
        return [nfc(x) for x in obj]
    if isinstance(obj, dict):
        return {nfc(k): nfc(v) for k, v in obj.items()}
    return obj


def canon(obj):
    return json.dumps(nfc(obj), sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def now():
    fixed = tenv("SAVIA_AUTHORITY_NOW")
    if fixed:
        return datetime.datetime.strptime(fixed, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_ts(s):
    if not isinstance(s, str) or not TS_RE.match(s):
        raise ValueError(s)
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)


def tool(name):
    """Herramienta de sistema por PATH fijo. Ausente => None (el paso que la necesite da UNKNOWN_STATE)."""
    over = tenv("SAVIA_AUTHORITY_TOOL_" + name.upper().replace("-", "_"))
    if over is not None:
        return over if os.access(over, os.X_OK) else None
    return shutil.which(name, path=SAFE_PATH)


def run(argv, stdin=None, timeout=20):
    env = dict(os.environ) if test_mode() else {"PATH": SAFE_PATH, "HOME": home(), "LC_ALL": "C"}
    env["GIT_TERMINAL_PROMPT"] = "0"
    return subprocess.run(argv, input=stdin, capture_output=True, timeout=timeout, env=env)


def home():
    """Home del usuario efectivo segun la base de usuarios, nunca $HOME: un HOME del llamante vaciaria el
    ledger de usos, ocultaria la revocacion local, desviaria el audit y daria a git/gh otra config.
    Solo el mundo hermetico de los tests (test_mode) usa el HOME temporal que fija el arnes."""
    if test_mode():
        return os.path.expanduser("~")
    if pwd is None:
        raise RuntimeError("sin base de usuarios para resolver el home real")
    return pwd.getpwuid(os.getuid()).pw_dir


def root_dir():
    return tenv("SAVIA_AUTHORITY_ROOT", SELF_ROOT)


# --------------------------------------------------------------------------- YAML minimo
def _split_top(s):
    out, depth, q, cur = [], 0, None, ""
    for ch in s:
        if q:
            cur += ch
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
            cur += ch
        elif ch in "[{":
            depth += 1
            cur += ch
        elif ch in "]}":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def _scalar(s):
    s = s.strip()
    if s == "":
        return None
    if s[0] == '"' and s[-1] == '"' and len(s) >= 2:
        return json.loads(s)
    if s[0] == "'" and s[-1] == "'" and len(s) >= 2:
        return s[1:-1]
    if s[0] == "[" and s[-1] == "]":
        return [_scalar(x) for x in _split_top(s[1:-1])]
    if s[0] == "{" and s[-1] == "}":
        d = {}
        for part in _split_top(s[1:-1]):
            k, _, v = part.partition(":")
            d[k.strip().strip("\"'")] = _scalar(v)
        return d
    if s in ("true", "false"):
        return s == "true"
    if s in ("null", "~"):
        return None
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    return s


def _strip_comment(line):
    q = None
    for i, ch in enumerate(line):
        if q:
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i]
    return line


KEY_RE = re.compile(r"""^("[^"]*"|'[^']*'|[^\s:#'"\[\]{}-][^:]*?|-[^\s:][^:]*?):(?:\s+(.*))?$""")


def yaml_load(text):
    lines = []
    for raw in text.splitlines():
        line = _strip_comment(raw).rstrip()
        if line.strip() and line.strip() != "---":
            lines.append((len(line) - len(line.lstrip(" ")), line.strip()))

    def block(i, indent):
        if i >= len(lines):
            return None, i
        if lines[i][1].startswith("- ") or lines[i][1] == "-":
            return seq(i, lines[i][0])
        return mapping(i, lines[i][0])

    def seq(i, indent):
        out = []
        while i < len(lines) and lines[i][0] == indent and (lines[i][1].startswith("- ") or lines[i][1] == "-"):
            body = lines[i][1][1:].strip()
            if body and KEY_RE.match(body) and not body.startswith(("[", "{", '"', "'")):
                lines[i] = (indent + 2, body)
                v, i = mapping(i, indent + 2)
                out.append(v)
            elif body:
                out.append(_scalar(body))
                i += 1
            else:
                i += 1
                if i < len(lines) and lines[i][0] > indent:
                    v, i = block(i, lines[i][0])
                    out.append(v)
                else:
                    out.append(None)
        return out, i

    def mapping(i, indent):
        out = {}
        while i < len(lines) and lines[i][0] == indent and not lines[i][1].startswith("- "):
            m = KEY_RE.match(lines[i][1])
            if not m:
                raise ValueError("yaml: linea no entendida: " + lines[i][1])
            key, rest = m.group(1).strip("\"'"), m.group(2)
            i += 1
            if rest is not None and rest.strip() != "":
                out[key] = _scalar(rest)
            elif i < len(lines) and (lines[i][0] > indent or (lines[i][0] == indent and lines[i][1].startswith("- "))):
                out[key], i = block(i, lines[i][0])
            else:
                out[key] = None
        return out, i

    v, i = block(0, 0)
    if i != len(lines):
        raise ValueError("yaml: contenido sin consumir")
    return v


def load_yaml_file(path):
    with open(path, encoding="utf-8") as f:
        return yaml_load(f.read())


# --------------------------------------------------------------------------- git / gh
def git(root, *args, stdin=None):
    g = tool("git")
    if g is None:
        raise Unknown("git ausente")
    try:
        return run([g, "-C", root, *args], stdin=stdin)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Unknown("git no responde: %s" % e)


def base_ref_ok(root):
    r = git(root, "rev-parse", "--verify", "-q", BASE_REF + "^{commit}")
    if r.returncode != 0:
        raise Unknown("origin/main ilegible (git fetch origin main)")


def base_blob(root, rel):
    """(blob_id, bytes) de rel en origin/main; (None, None) si el fichero no existe alli."""
    base_ref_ok(root)
    r = git(root, "rev-parse", "--verify", "-q", "%s:%s" % (BASE_REF, rel))
    if r.returncode != 0:
        return None, None
    bid = r.stdout.decode().strip()
    c = git(root, "cat-file", "blob", bid)
    if c.returncode != 0:
        raise Unknown("blob ilegible: " + rel)
    return bid, c.stdout


def normalize_remote(url):
    url = url.strip()
    m = re.match(r"^(?:[a-z+]+://)?(?:[^@/]+@)?([^/:]+)[:/](?:\d+/)?([^/]+)/([^/]+?)(?:\.git)?/?$", url)
    if not m:
        raise Unknown("remoto origin no reconocible")
    return "%s/%s/%s" % (m.group(1).lower(), m.group(2), m.group(3))


def local_installation(root):
    r = git(root, "remote", "get-url", "origin")
    if r.returncode != 0:
        raise Unknown("git remote origin ilegible")
    return normalize_remote(r.stdout.decode())


def gh_json(args):
    g = tool("gh")
    if g is None:
        raise Unknown("gh ausente")
    try:
        r = run([g, *args], timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Unknown("gh no responde: %s" % e)
    if r.returncode != 0:
        raise Unknown("gh fallo: " + r.stderr.decode(errors="replace")[:120])
    try:
        return json.loads(r.stdout.decode())
    except ValueError:
        raise Unknown("gh devolvio una respuesta no JSON")


def ci_state(entries):
    """Resumen de checks: success, failure, pending o none. Que valores cumplen lo dice cada descriptor.
    none = sin ejecuciones o solo saltadas/neutras: success exige al menos un SUCCESS real."""
    if not entries:
        return "none"
    pending = failed = succeeded = False
    for e in entries:
        status = str(e.get("status") or "COMPLETED").upper()
        concl = str(e.get("conclusion") or e.get("state") or "").upper()
        if status != "COMPLETED" or concl in ("", "PENDING", "EXPECTED", "IN_PROGRESS", "QUEUED"):
            pending = True
        elif concl == "SUCCESS":
            succeeded = True
        elif concl not in ("NEUTRAL", "SKIPPED"):
            failed = True
    return "failure" if failed else "pending" if pending else "success" if succeeded else "none"


# --------------------------------------------------------------------------- selectores
CTRL_RE = re.compile("[\x00-\x1f\x7f-\x9f​-‏ - ⁠-⁯﻿]")


def check_resource_string(s):
    """AMBIGUOUS si cambia al normalizar, lleva control/confusables o no es ASCII (TR39 simplificado:
    sin tabla de confusables en stdlib, todo no-ASCII en un identificador de recurso es ambiguo)."""
    if unicodedata.normalize("NFC", s) != s:
        raise Deny("AMBIGUOUS", "el recurso cambia al normalizar a NFC")
    if CTRL_RE.search(s):
        raise Deny("AMBIGUOUS", "el recurso contiene caracteres de control")
    if any(ord(c) > 127 for c in s):
        raise Deny("AMBIGUOUS", "el recurso contiene caracteres no ASCII (posible homoglifo)")


def bad_segments(s):
    if s.startswith("/"):
        return True
    return any(seg in ("", ".", "..") for seg in s.split("/"))


def glob_match(pattern, value):
    ps, vs = pattern.split("/"), value.split("/")
    if len(ps) != len(vs):
        return False
    for p, v in zip(ps, vs):
        if "*" in p:
            if not re.fullmatch(".+".join(re.escape(x) for x in p.split("*")), v):
                return False
        elif p != v:
            return False
    return True


def project_match(selector, value):
    return value == selector or value.startswith(selector.rstrip("/") + "/")


# dimension del ambito -> clave del objetivo
SCOPE_DIMS = {"branches": "branch", "prs": "pr", "projects": "project", "paths": "path"}
# parametro de la accion -> clave del objetivo que lo autoriza (el ambito se comprueba sobre el objetivo,
# asi que todo parametro que nombre un recurso tiene que coincidir con el objetivo)
PARAM_DIMS = {"branch": "branch", "pr_number": "pr", "project": "project", "path": "path"}
TARGET_KEYS = ("repo", "branch", "pr", "project", "path")
# tipo JSON-schema del descriptor -> tipo Python exacto (bool no cuenta como integer)
PARAM_TYPES = {"string": str, "integer": int, "boolean": bool}


def path_match(selector, value):
    return glob_match(selector, value) if "*" in selector else project_match(selector, value)


def covered(scope, target, repo):
    """(ok, motivo). Cada dimension presente en el objetivo tiene que estar cubierta por una lista cerrada,
    y cada dimension que el ambito restringe tiene que estar presente en el objetivo."""
    if repo not in (scope.get("repo") or []):
        return False, "repo fuera de ambito"
    for dim, key in SCOPE_DIMS.items():
        if dim in scope and target.get(key) is None:
            return False, "el ambito restringe %s y el objetivo no lo indica" % dim
    if target.get("branch") is not None:
        if not any(glob_match(p, target["branch"]) for p in scope.get("branches") or []):
            return False, "rama fuera de ambito"
    if target.get("pr") is not None:
        if target["pr"] not in (scope.get("prs") or []):
            return False, "PR fuera de ambito"
    if target.get("project") is not None:
        if not any(project_match(p, target["project"]) for p in scope.get("projects") or []):
            return False, "proyecto fuera de ambito"
    if target.get("path") is not None:
        if not any(path_match(p, target["path"]) for p in scope.get("paths") or []):
            return False, "ruta fuera de ambito"
    return True, ""


# --------------------------------------------------------------------------- validadores
def reversible(descriptor):
    """Solo `reversibility: reversible` explicito es reversible; ausente o desconocido cuenta como irreversible."""
    return isinstance(descriptor, dict) and (descriptor.get("safety") or {}).get("reversibility") == "reversible"


def contract_errors(c, root=None, raw=None):
    errs = []
    if not isinstance(c, dict):
        return ["NOT_AN_OBJECT"]
    for f in REQUIRED_FIELDS:
        if f not in c:
            errs.append("MISSING_FIELD:" + f)
    if c.get("schema", "delegation-contract/1") != "delegation-contract/1":
        errs.append("BAD_SCHEMA")
    if "id" in c and not (isinstance(c["id"], str) and ID_RE.match(c["id"])):
        errs.append("BAD_ID")
    if "nonce" in c and not (isinstance(c["nonce"], str) and re.fullmatch(r"[0-9a-f]{16}", c["nonce"])):
        errs.append("BAD_NONCE")
    try:
        nb, ex = parse_ts(c["not_before"]), parse_ts(c["expires_at"])
        if ex <= nb:
            errs.append("BAD_VALIDITY_WINDOW")
        elif ex - nb > MAX_LIFE:
            errs.append("LIFETIME_EXCEEDS_7D")
    except KeyError:
        pass
    except ValueError:
        errs.append("BAD_TIMESTAMP")
    scope = c.get("scope")
    if "scope" in c:
        if not isinstance(scope, dict) or not scope:
            errs.append("BAD_SCOPE")
        else:
            for dim, items in scope.items():
                if dim not in ("repo",) + tuple(SCOPE_DIMS) or not isinstance(items, list) or not items:
                    errs.append("BAD_SCOPE:" + str(dim))
                    continue
                for it in items:
                    if dim == "prs":
                        if not isinstance(it, int) or isinstance(it, bool):
                            errs.append("BAD_SCOPE:prs")
                    elif not isinstance(it, str) or not it or "?" in it or "[" in it or "**" in it \
                            or it.strip("*/") == "" or bad_segments(it):
                        errs.append("BAD_SCOPE:%s" % dim)
                    elif dim not in ("branches", "paths") and "*" in it:
                        errs.append("BAD_SCOPE:%s" % dim)
    if "declared_effects" in c and not (isinstance(c["declared_effects"], list)
                                        and all(isinstance(x, str) for x in c["declared_effects"])):
        errs.append("BAD_EFFECTS")
    mu = c.get("max_uses")
    if "max_uses" in c and (not isinstance(mu, int) or isinstance(mu, bool) or mu < 1):
        errs.append("BAD_MAX_USES")
    auth = c.get("authority")
    if "authority" in c and not (isinstance(auth, dict) and auth.get("level") in LEVELS
                                 and isinstance(auth.get("tier"), int) and 1 <= auth["tier"] <= 4):
        errs.append("BAD_AUTHORITY")
    if raw is not None:
        try:
            if raw.decode("utf-8") != canon(c):
                errs.append("NOT_CANONICAL")
        except UnicodeDecodeError:
            errs.append("NOT_CANONICAL")
    cap = c.get("capability")
    if "capability" in c and not (isinstance(cap, dict) and all(k in cap for k in ("id", "version", "sha256"))):
        errs.append("BAD_CAPABILITY")
    elif root is not None and isinstance(cap, dict) and isinstance(cap.get("id"), str) and ID_RE.match(cap["id"]):
        dpath = os.path.join(root, "contracts", "capabilities", cap["id"] + ".yaml")
        try:
            d = load_yaml_file(dpath)
            if not reversible(d) and c.get("max_uses") != 1:
                errs.append("IRREVERSIBLE_NEEDS_MAX_USES_1")
        except (OSError, ValueError, AttributeError):
            errs.append("CAPABILITY_UNKNOWN")
    return errs


STRUCTURAL = ("MISSING_FIELD", "BAD_", "NOT_AN_OBJECT")


def ontology_errors(onto, root):
    errs = []
    if not isinstance(onto, dict):
        return ["ONTOLOGY_NOT_A_MAP"]
    attrs = {}
    types = onto.get("types")
    if not isinstance(types, dict) or not types:
        errs.append("NO_TYPES")
        types = {}
    for tname, t in types.items():
        for aname, a in ((t or {}).get("attributes") or {}).items():
            owner = (a or {}).get("owner")
            if owner not in OWNERS:
                errs.append("NO_OWNER:%s.%s" % (tname, aname))
            attrs["%s.%s" % (tname, aname)] = owner
    actions = onto.get("actions")
    if not isinstance(actions, dict) or not actions:
        errs.append("NO_ACTIONS")
        actions = {}
    for aid, a in actions.items():
        dpath = os.path.join(root, (a or {}).get("descriptor") or "")
        try:
            d = load_yaml_file(dpath)
            d.get("id")
        except (OSError, ValueError, AttributeError, TypeError):
            errs.append("NO_DESCRIPTOR:" + aid)
            continue
        if not isinstance(d.get("declared_effects"), list) or not d["declared_effects"]:
            errs.append("NO_EFFECTS:" + aid)
        for p in d.get("preconditions") or []:
            fact = (p or {}).get("fact")
            if fact not in attrs:
                errs.append("UNKNOWN_FACT:%s:%s" % (aid, fact))
            elif attrs[fact] not in ("source-backed", "contract-owned"):
                errs.append("INFERRED_IN_RULE:%s:%s" % (aid, fact))
    return errs


# --------------------------------------------------------------------------- evaluacion
class Ctx:
    def __init__(self, req, prior=None):
        self.req = req
        self.prior = prior
        self.root = root_dir()
        self.home = home()
        self.now = now()
        self.contract = self.raw = self.path = None
        self.contract_sha = None
        self.descriptor = self.cap_sha = None
        self.target = {}
        self.repo = self.inst = None
        self.facts = {}
        self.pr = None
        self.tier = 0
        self.signers_blob = None
        self.revoked = {}
        self.suggestions = []
        self.action_effects = []


def read_dir_files(path):
    try:
        return sorted(os.listdir(path))
    except FileNotFoundError:
        return []
    except OSError as e:
        raise Unknown("directorio ilegible: %s" % e)


def load_contracts(ctx):
    found = []
    for base in (os.path.join(ctx.root, "config", "delegations"), os.path.join(ctx.home, ".savia", "delegations")):
        for name in read_dir_files(base):
            if not name.endswith(".json"):
                continue
            p = os.path.join(base, name)
            try:
                with open(p, "rb") as f:
                    raw = f.read()
                c = json.loads(raw.decode("utf-8"))
            except (OSError, ValueError):
                continue
            if any(e.startswith(STRUCTURAL) for e in contract_errors(c)):
                continue  # un contrato estructuralmente roto no es autoridad
            if c.get("delegate") == ctx.req["delegate"] and c["capability"]["id"] == ctx.req["capability"]:
                found.append((p, raw, c))
    return found


def step1_contract(ctx):
    cands = load_contracts(ctx)
    if not cands:
        raise Deny("NO_CONTRACT", "ningun contrato para %s / %s" % (ctx.req["delegate"], ctx.req["capability"]))
    ctx.path, ctx.raw, ctx.contract = cands[0]
    ctx.contract_sha = sha(ctx.raw)


def step2_self_issued(ctx):
    c = ctx.contract
    if c is None or ctx.path is None:  # defensa en profundidad: sin contrato cargado no hay decision
        raise Unknown("ningun contrato cargado")
    p = str(c.get("principal", ""))
    if not os.path.isfile(ctx.path + ".sig"):
        raise Deny("SELF_ISSUED", "contrato sin firma")
    low = p.lower()
    if low in AGENT_PRINCIPALS or p == c.get("delegate") or low.split(":")[0] in ("savia-worker", "agent"):
        raise Deny("SELF_ISSUED", "el principal no puede ser un agente ni self")


def step3_signature(ctx):
    bid, blob = base_blob(ctx.root, SIGNERS_REL)
    if blob is None:
        raise Unknown("sin fichero de firmantes en origin/main")
    ctx.signers_blob = bid
    kg = tool("ssh-keygen")
    if kg is None:
        raise Unknown("ssh-keygen ausente")
    if ctx.raw.decode("utf-8") != canon(ctx.contract):
        raise Deny("BAD_SIGNATURE", "el contrato no esta en forma canonica")
    with tempfile.TemporaryDirectory() as d:
        sp = os.path.join(d, "signers")
        with open(sp, "wb") as f:
            f.write(blob)
        try:
            r = run([kg, "-Y", "verify", "-f", sp, "-I", ctx.contract["principal"], "-n", NAMESPACE,
                     "-s", ctx.path + ".sig"], stdin=ctx.raw)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise Unknown("ssh-keygen no responde: %s" % e)
    if r.returncode != 0:
        raise Deny("BAD_SIGNATURE", "firma no valida contra los firmantes de origin/main")


def active_slug(ctx):
    p = tenv("SAVIA_AUTHORITY_PROFILE") or os.path.join(ctx.root, ".claude", "profiles", "active-user.md")
    try:
        with open(p, encoding="utf-8") as f:
            m = re.search(r'active_slug:\s*"([^"]+)"', f.read())
    except OSError:
        raise Unknown("perfil activo ilegible")
    if not m:
        raise Unknown("perfil activo sin active_slug")
    return m.group(1)


def step4_principal(ctx):
    if active_slug(ctx) != ctx.contract["principal"]:
        raise Deny("PRINCIPAL_MISMATCH", "el contrato lo firma otra persona que la del perfil activo")


def read_revoked(path):
    try:
        with open(path, encoding="utf-8") as f:
            return {l.split("#")[0].strip() for l in f if l.split("#")[0].strip()}
    except FileNotFoundError:
        return set()
    except OSError as e:
        raise Unknown("lista REVOKED ilegible: %s" % e)


def step5_revoked(ctx):
    nonce = ctx.contract["nonce"]
    _, blob = base_blob(ctx.root, REVOKED_REL)
    main = {l.split("#")[0].strip() for l in blob.decode("utf-8", "replace").splitlines()} if blob else set()
    work = read_revoked(os.path.join(ctx.root, REVOKED_REL))
    local = read_revoked(os.path.join(ctx.home, ".savia", "delegations", "REVOKED"))
    ctx.revoked = {"main": nonce in main, "work": nonce in work, "local": nonce in local}
    if any(ctx.revoked.values()):
        raise Deny("REVOKED", "contrato revocado (%s)" % ",".join(k for k, v in ctx.revoked.items() if v))


def check_lifetime(ctx, nb, ex):
    """La vida maxima de 7 dias la exige el camino de decision, no solo check-contract."""
    if ex - nb > MAX_LIFE:
        raise Deny("LIFETIME_EXCEEDS_7D", "el contrato vale mas de 7 dias (%s -> %s)"
                   % (ctx.contract["not_before"], ctx.contract["expires_at"]))


def check_single_use(ctx):
    """Con el descriptor ya atado por sha: un efecto no reversible solo se concede con max_uses: 1."""
    if not reversible(ctx.descriptor) and ctx.contract.get("max_uses") != 1:
        raise Deny("IRREVERSIBLE_NEEDS_MAX_USES_1",
                   "la capacidad no es reversible y el contrato no limita a un solo uso (max_uses: 1)")


def step6_time(ctx):
    try:
        nb, ex = parse_ts(ctx.contract["not_before"]), parse_ts(ctx.contract["expires_at"])
    except ValueError:
        raise Deny("EXPIRED", "fechas del contrato no validas")
    check_lifetime(ctx, nb, ex)
    if ctx.now < nb:
        raise Deny("NOT_YET_VALID", "el contrato empieza el " + ctx.contract["not_before"])
    if ctx.now >= ex:
        raise Deny("EXPIRED", "el contrato caduco el " + ctx.contract["expires_at"])


def step7_capability(ctx):
    cap, cid = ctx.contract["capability"], ctx.req["capability"]
    if not ID_RE.match(cid):
        raise Deny("CAPABILITY_MISMATCH", "id de capacidad no valido")
    p = os.path.join(ctx.root, "contracts", "capabilities", cid + ".yaml")
    try:
        with open(p, "rb") as f:
            data = f.read()
        d = yaml_load(data.decode("utf-8"))
    except FileNotFoundError:
        raise Deny("CAPABILITY_MISMATCH", "descriptor inexistente")
    except (OSError, ValueError):
        raise Unknown("descriptor ilegible")
    ctx.cap_sha, ctx.descriptor = sha(data), d
    if ctx.req["action"]["name"] != cid:
        raise Deny("CAPABILITY_MISMATCH", "action.name (%s) no es la capacidad pedida" % ctx.req["action"]["name"])
    if cap.get("id") != cid or d.get("id") != cid or cap.get("version") != d.get("version") or cap.get("sha256") != ctx.cap_sha:
        raise Deny("CAPABILITY_MISMATCH", "el descriptor cambio desde que se firmo el contrato")
    check_single_use(ctx)


def step8_ambiguous(ctx):
    t = ctx.req["target"]
    if t.get("alias") is not None:
        raise Deny("AMBIGUOUS", "alias sin dueño declarado")
    if isinstance(t.get("candidates"), list) and len(t["candidates"]) > 1:
        raise Deny("AMBIGUOUS", "el selector resuelve a %d recursos" % len(t["candidates"]))
    for k in ("repo", "branch", "project", "path"):
        if t.get(k) is not None:
            if not isinstance(t[k], str):
                raise BadRequest("target.%s debe ser texto" % k)
            check_resource_string(t[k])
    if t.get("pr") is not None and (not isinstance(t["pr"], int) or isinstance(t["pr"], bool)):
        raise BadRequest("target.pr debe ser entero")
    if t.get("branch"):
        r = git(ctx.root, "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes/origin")
        if r.returncode != 0:
            raise Unknown("git for-each-ref fallo")
        want = t["branch"]
        names = {x[len("refs/remotes/origin/"):] if x.startswith("refs/remotes/origin/") else x[len("refs/heads/"):]
                 for x in r.stdout.decode().splitlines() if x}
        if any(n != want and n.lower() == want.lower() for n in names):
            raise Deny("AMBIGUOUS", "existen ramas que solo difieren en mayusculas")
    if t.get("project"):
        pdir = os.path.join(ctx.root, "projects")
        want = t["project"].split("/")[-1] if t["project"].count("/") <= 1 else t["project"].split("/")[1]
        if any(n != want and n.lower() == want.lower() for n in read_dir_files(pdir)):
            raise Deny("AMBIGUOUS", "existen proyectos que solo difieren en mayusculas")
    ctx.target = {k: t[k] for k in TARGET_KEYS if t.get(k) is not None}


def step9_inferred(ctx):
    inferred = [f for f in ctx.req.get("facts") or [] if isinstance(f, dict) and f.get("provenance") == "inferred"]
    for f in inferred:
        ctx.suggestions.append({
            "fact": f.get("fact"), "provenance": "inferred",
            "needed_action": f.get("suggest") or "pedir un contrato firmado que cubra este recurso"})
    if not any(f.get("kind") in ("membership", "permission") for f in inferred):
        return
    scope = ctx.contract["scope"]
    ok, _ = covered(scope, ctx.target, ctx.target.get("repo") or (scope.get("repo") or [""])[0])
    if not ok:
        raise Deny("INFERRED_NOT_AUTHORITY",
                   "la pertenencia solo la sugiere el grafo o el modelo; hace falta un contrato firmado")


def bind_params(ctx):
    """Los parametros de la accion son lo que se ejecuta; el ambito se comprueba sobre el objetivo.
    Todo parametro ha de estar declarado en el descriptor, los obligatorios presentes, y los que nombran
    un recurso iguales (valor y tipo) a su dimension del objetivo. Si no, el ALLOW no cubriria el efecto."""
    if ctx.descriptor is None:  # defensa en profundidad: sin descriptor verificado no hay decision
        raise Unknown("ningun descriptor de capacidad cargado")
    params = ctx.req["action"].get("params") or {}
    inp = ctx.descriptor.get("input") or {}
    declared = set((inp.get("properties") or {}).keys())
    extra = sorted(k for k in params if k not in declared)
    if extra:
        raise Deny("OUT_OF_SCOPE", "parametros no declarados en el descriptor: " + ", ".join(extra))
    missing = [k for k in inp.get("required") or [] if k not in params]
    if missing:
        raise Deny("OUT_OF_SCOPE", "faltan parametros obligatorios: " + ", ".join(missing))
    props = inp.get("properties") or {}
    for k, v in params.items():
        decl = props.get(k)
        want = PARAM_TYPES.get(decl.get("type")) if isinstance(decl, dict) else None
        if want is None:  # tipo no declarado o desconocido: no hay forma de validar el parametro
            raise Deny("OUT_OF_SCOPE", "action.params.%s sin tipo declarado reconocible en el descriptor" % k)
        if type(v) is not want:
            raise Deny("OUT_OF_SCOPE", "action.params.%s no es de tipo %s" % (k, props[k]["type"]))
    for p, key in PARAM_DIMS.items():
        if p not in params:
            continue
        v, t = params[p], ctx.req["target"].get(key)
        if t is None:
            raise Deny("OUT_OF_SCOPE", "action.params.%s sin target.%s: el ambito no lo cubriria" % (p, key))
        if type(v) is not type(t) or v != t:
            raise Deny("OUT_OF_SCOPE", "action.params.%s no coincide con target.%s" % (p, key))


def step10_scope(ctx):
    t = ctx.target
    for k in ("branch", "project", "path"):
        if t.get(k) is not None and bad_segments(t[k]):
            raise Deny("OUT_OF_SCOPE", "segmentos no permitidos en " + k)
    inst = ctx.inst = local_installation(ctx.root)
    ctx.repo = t.get("repo") or inst
    ctx.target["repo"] = ctx.repo
    if inst != ctx.contract["installation"]:
        raise Deny("OUT_OF_SCOPE", "el contrato es de otra instalacion (%s)" % ctx.contract["installation"])
    bind_params(ctx)
    ok, why = covered(ctx.contract["scope"], ctx.target, ctx.repo)
    if not ok:
        raise Deny("OUT_OF_SCOPE", why)


def step11_uses(ctx):
    mu = ctx.contract.get("max_uses")
    if mu is None:
        return
    d = os.path.join(ctx.home, ".savia", "authority", "uses", ctx.contract["id"])
    try:
        n = len([x for x in os.listdir(d) if x.isdigit()])
    except FileNotFoundError:
        n = 0
    except OSError as e:
        raise Unknown("ledger de usos ilegible: %s" % e)
    if n >= mu:
        raise Deny("MAX_USES_EXHAUSTED", "contrato consumido (%d de %d usos)" % (n, mu))


RUN_LIMIT = 200
PR_FIELDS = "isDraft,headRefName,headRefOid,reviewDecision,state,statusCheckRollup,files,changedFiles"


def gh_lines(args):
    """Salida de `gh ... --jq '... | @json'`: una cadena JSON por linea."""
    g = tool("gh")
    if g is None:
        raise Unknown("gh ausente")
    try:
        r = run([g, *args], timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Unknown("gh no responde: %s" % e)
    if r.returncode != 0:
        raise Unknown("gh fallo: " + r.stderr.decode(errors="replace")[:120])
    out = []
    for line in r.stdout.decode().splitlines():
        if not line.strip():
            continue
        try:
            v = json.loads(line)
        except ValueError:
            raise Unknown("gh devolvio una linea no JSON")
        if not isinstance(v, str):
            raise Unknown("gh devolvio un nombre de fichero no textual")
        out.append(v)
    return out


def pr_files(ctx, j):
    """Lista COMPLETA de ficheros del PR. `gh pr view --json files` corta en 100: si no cuadra con
    changedFiles se pide paginada a la API REST; si aun asi no cuadra, UNKNOWN_STATE (fail-closed)."""
    files = [f.get("path") for f in j.get("files") or [] if isinstance(f, dict)]
    want = j.get("changedFiles")
    if not isinstance(want, int) or isinstance(want, bool):
        raise Unknown("gh no informa changedFiles: no se puede comprobar que la lista de ficheros este completa")
    if len(files) != want:
        host, _, slug = ctx.repo.partition("/")
        files = gh_lines(["api", "--hostname", host, "--paginate",
                          "repos/%s/pulls/%d/files" % (slug, ctx.target["pr"]), "--jq", ".[].filename | @json"])
    if len(files) != want or not all(isinstance(f, str) and f for f in files):
        raise Unknown("lista de ficheros del PR incompleta (%d de %d)" % (len(files), want))
    return files


def read_pr(ctx):
    if ctx.target.get("pr") is None:
        return
    j = gh_json(["pr", "view", str(ctx.target["pr"]), "--repo", ctx.repo, "--json", PR_FIELDS])
    head_ref = j.get("headRefName")
    if not isinstance(head_ref, str) or not head_ref:
        raise Unknown("gh no informa headRefName del PR")
    b = ctx.target.get("branch")
    if b is not None and head_ref != b:
        # el ambito se comprobo sobre target.branch, que declara quien pide: tiene que ser la rama real del PR
        raise Deny("OUT_OF_SCOPE", "el PR %d es de la rama %s, no de %s" % (ctx.target["pr"], head_ref, b))
    ctx.pr = {"is_draft": j.get("isDraft"), "head_ref": j.get("headRefName"), "head_sha": j.get("headRefOid"),
              "review_decision": j.get("reviewDecision"), "state": j.get("state"),
              "ci_status": ci_state(j.get("statusCheckRollup")), "files": pr_files(ctx, j)}


def branch_sha(ctx):
    b = ctx.target.get("branch")
    for ref in ("refs/heads/" + b, "refs/remotes/origin/" + b):
        r = git(ctx.root, "rev-parse", "--verify", "-q", ref)
        if r.returncode == 0:
            return r.stdout.decode().strip()
    return None


def read_fact(ctx, fact):
    ent, _, attr = fact.partition(".")
    if ent == "PullRequest":
        if ctx.pr is None:
            raise Unknown("la precondicion %s necesita un PR en el objetivo" % fact)
        if attr not in ctx.pr or attr == "files":
            raise Unknown("lector sin soporte para " + fact)
        if ctx.pr[attr] is None:  # hecho ausente: nunca cumple una precondicion (tampoco una negativa)
            raise Unknown("gh no informa " + fact)
        return ctx.pr[attr]
    if ent == "Branch":
        if ctx.repo != ctx.inst:
            raise Unknown("la rama se lee del git local y el objetivo es otro repo (%s)" % ctx.repo)
        b = ctx.target.get("branch")
        sha_ = branch_sha(ctx) if b else None
        if not b or sha_ is None:
            raise Unknown("la rama del objetivo no existe: " + fact)
        if attr == "name":
            return b
        if attr == "head_sha":
            return sha_
        if attr == "ci_status":
            # todas las ejecuciones del head exacto, no la ultima de cualquier workflow ni de otro commit
            j = gh_json(["run", "list", "--repo", ctx.repo, "--branch", b, "--commit", sha_,
                         "--limit", str(RUN_LIMIT), "--json", "status,conclusion"])
            if not isinstance(j, list):
                raise Unknown("gh run list no devolvio una lista")
            if len(j) >= RUN_LIMIT:  # lista posiblemente truncada: un fallo podria quedar fuera
                raise Unknown("gh run list llego al limite de %d ejecuciones del head" % RUN_LIMIT)
            return ci_state(j)
    raise Unknown("lector sin soporte para " + fact)


def all_preconditions(ctx):
    return list((ctx.descriptor or {}).get("preconditions") or []) + list(ctx.contract.get("preconditions") or [])


def step12_readers(ctx):
    read_pr(ctx)
    pre = all_preconditions(ctx)
    if pre:
        # la ontologia que decide la propiedad de los hechos es la de origin/main, no la del arbol de trabajo
        _, blob = base_blob(ctx.root, ONTOLOGY_REL)
        if blob is None:
            raise Unknown("sin ontologia en origin/main")
        try:
            onto = yaml_load(blob.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            raise Unknown("ontologia ilegible")
        owners = {}
        for tn, t in (onto.get("types") or {}).items():
            for an, a in ((t or {}).get("attributes") or {}).items():
                owners["%s.%s" % (tn, an)] = (a or {}).get("owner")
        for p in pre:
            fact = p.get("fact") if isinstance(p, dict) else None
            if owners.get(fact) not in ("source-backed", "contract-owned"):
                raise Unknown("hecho sin dueño fiable en la precondicion: %s" % fact)
            ctx.facts[fact] = read_fact(ctx, fact)
    if ctx.pr:
        ctx.target["head_sha"] = ctx.pr["head_sha"]
        if "branch" in (ctx.req["action"].get("params") or {}):
            # la accion opera sobre la rama local (p. ej. publicarla): su commit tambien entra en el digest,
            # o avanzar la rama entre evaluate y recheck no se notaria
            ctx.target["branch_sha"] = branch_sha(ctx)
    elif ctx.target.get("branch") is not None:
        ctx.target["head_sha"] = branch_sha(ctx)


def holds(p, value):
    """Comparacion con tipo exacto: 0 no es false ni 1.0 es 1. Tipos distintos no cumplen (fail-closed)."""
    op, want = p.get("op"), p.get("value")
    if op == "==":
        return type(value) is type(want) and value == want
    if op == "!=":
        return type(value) is type(want) and value != want
    if op == "in":
        return isinstance(want, list) and any(type(value) is type(w) and value == w for w in want)
    if op == "startswith":
        return isinstance(value, str) and isinstance(want, str) and value.startswith(want)
    return False  # operador desconocido: no cumple (fail-closed)


def step13_preconditions(ctx):
    for p in all_preconditions(ctx):
        if not isinstance(p, dict) or p.get("fact") not in ctx.facts:
            raise Unknown("precondicion sin hecho leido: %s" % (p.get("fact") if isinstance(p, dict) else p))
        if not holds(p, ctx.facts[p["fact"]]):
            raise Deny("PRECONDITION_FAILED:%s" % p.get("id"), p.get("message") or "no se cumple %s" % p.get("id"))


def step14_effects(ctx):
    if ctx.descriptor is None:  # defensa en profundidad: sin descriptor verificado no hay decision
        raise Unknown("ningun descriptor de capacidad cargado")
    eff = set(ctx.descriptor.get("declared_effects") or [])
    extra = ctx.req["action"].get("effects") or []
    ctx.action_effects = sorted(eff | set(extra))
    missing = [e for e in ctx.action_effects if e not in set(ctx.contract.get("declared_effects") or [])]
    if missing:
        raise Deny("UNDECLARED_EFFECT", "efecto no declarado en el contrato: " + ", ".join(missing))


def agent_level(ctx):
    # de origin/main: el agente no puede subirse de nivel editando su arbol de trabajo
    _, blob = base_blob(ctx.root, LEVELS_REL)
    if blob is None:
        raise Unknown("agent-permission-levels.md ausente en origin/main")
    try:
        txt = blob.decode("utf-8")
    except UnicodeDecodeError:
        raise Unknown("agent-permission-levels.md ilegible")
    name = ctx.req["delegate"]
    cands = [name]
    fam, sep, inst = name.partition(":")
    if sep and fam in INSTANCE_FAMILIES and ID_RE.match(inst):
        cands.append(fam)  # solo las familias con instancias (spec: savia-worker:<id>) heredan el nivel
    for cand in cands:
        m = re.search(r"^\|\s*%s\s*\|\s*(L[0-4])\s*\|" % re.escape(cand), txt, re.M)
        if m:
            return m.group(1)
    raise Unknown("delegado sin nivel asignado: " + name)


def tier_of(ctx):
    if ctx.pr is None:
        raise Unknown("la puerta de tier necesita un PR en el objetivo")
    if any(re.search(r"\s", f) for f in ctx.pr["files"]):
        # risk-tier.py trocea --diff por espacios: una ruta con espacios se clasificaria mal
        raise Unknown("ruta con espacios en el PR: risk-tier.py no la clasifica de forma fiable")
    try:
        r = run([sys.executable, "-I", os.path.join(SELF_ROOT, "scripts", "risk-tier.py"),
                 "--diff", " ".join(ctx.pr["files"]), "--json"])
        if r.returncode != 0:
            raise ValueError("rc")
        return int(json.loads(r.stdout.decode())["tier"])
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        raise Unknown("risk-tier.py no responde")


def step15_level(ctx):
    auth = ctx.descriptor.get("authority") or {}
    need = auth.get("required_level", "L4")
    if need not in LEVELS:
        raise Unknown("required_level no valido en el descriptor")
    eff = min(LEVELS[ctx.contract["authority"]["level"]], LEVELS[agent_level(ctx)])
    if LEVELS[need] > eff:
        raise Deny("LEVEL_EXCEEDED", "la capacidad exige %s y la autoridad efectiva es L%d" % (need, eff))
    if auth.get("tier_gate"):
        ctx.tier = tier_of(ctx)
        if ctx.tier > ctx.contract["authority"]["tier"]:
            raise Deny("LEVEL_EXCEEDED", "el PR es tier %d y el contrato llega a tier %d"
                       % (ctx.tier, ctx.contract["authority"]["tier"]))


def step16_tier(ctx):
    if (ctx.descriptor.get("authority") or {}).get("tier_gate") and ctx.tier >= 3 \
            and ctx.pr.get("review_decision") != "APPROVED":
        raise Approval("REVIEW_REQUIRED", "PR de tier %d sin revision humana" % ctx.tier)


def state_digest(ctx):
    return sha(canon({
        "contract_sha256": ctx.contract_sha, "capability_sha256": ctx.cap_sha,
        "signers_blob": ctx.signers_blob, "revoked": ctx.revoked,
        "target": ctx.target, "facts": ctx.facts}))


def action_hash(req):
    return sha(canon({"delegate": req["delegate"], "capability": req["capability"],
                      "action": req["action"], "target": req["target"]}))


def step17_action(ctx):
    if ctx.prior.get("action_sha256") != action_hash(ctx.req):
        raise Deny("ACTION_MISMATCH", "la orden no es la que se evaluo")


def step18_state(ctx):
    try:
        age = ctx.now - parse_ts(ctx.prior.get("evaluated_at"))
    except ValueError:
        raise Deny("STATE_CHANGED", "recibo previo sin evaluated_at valido")
    if age < datetime.timedelta(0) or age > PRIOR_MAX_AGE:
        raise Deny("STATE_CHANGED", "recibo previo fuera de plazo (%s)" % ctx.prior.get("evaluated_at"))
    if ctx.prior.get("state_digest") != state_digest(ctx):
        raise Deny("STATE_CHANGED", "el estado cambio entre evaluar y ejecutar")


STEPS = [
    (1, "contract", step1_contract), (2, "self_issued", step2_self_issued),
    (3, "signature", step3_signature), (4, "principal", step4_principal),
    (5, "revoked", step5_revoked), (6, "time", step6_time), (7, "capability", step7_capability),
    (8, "ambiguous", step8_ambiguous), (9, "inferred", step9_inferred), (10, "scope", step10_scope),
    (11, "uses", step11_uses), (12, "readers", step12_readers), (13, "preconditions", step13_preconditions),
    (14, "effects", step14_effects), (15, "level", step15_level), (16, "tier", step16_tier),
    (17, "action_match", step17_action), (18, "state_match", step18_state),
]


def validate_request(req):
    if not isinstance(req, dict):
        raise BadRequest("la peticion debe ser un objeto JSON")
    for k, ty in (("delegate", str), ("capability", str), ("action", dict), ("target", dict)):
        if not isinstance(req.get(k), ty):
            raise BadRequest("campo obligatorio ausente o de tipo erroneo: " + k)
    if not isinstance(req["action"].get("name"), str):
        raise BadRequest("action.name obligatorio")
    if "params" in req["action"] and not isinstance(req["action"]["params"], dict):
        raise BadRequest("action.params debe ser objeto")
    eff = req["action"].get("effects")
    if eff is not None and not (isinstance(eff, list) and all(isinstance(x, str) for x in eff)):
        raise BadRequest("action.effects debe ser lista de textos")
    if "facts" in req and not isinstance(req["facts"], list):
        raise BadRequest("facts debe ser lista")


def consume_use(ctx):
    mu = ctx.contract.get("max_uses")
    if mu is None:
        return None
    key = "a-" + action_hash(ctx.req)[:40]
    d = os.path.join(ctx.home, ".savia", "authority", "uses", ctx.contract["id"])
    try:
        os.makedirs(d, exist_ok=True)
    except OSError as e:
        raise Unknown("ledger de usos no escribible: %s" % e)
    for n in range(1, mu + 1):
        try:
            fd = os.open(os.path.join(d, str(n)), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            continue
        except OSError as e:
            raise Unknown("ledger de usos no escribible: %s" % e)
        with os.fdopen(fd, "w") as f:
            f.write(key + "\n")
        return key
    raise Deny("MAX_USES_EXHAUSTED", "contrato consumido")


def audit_append(ctx, result, mode):
    d = os.path.join(ctx.home, ".savia", "authority")
    os.makedirs(d, exist_ok=True)
    plain = set((ctx.descriptor or {}).get("audit_plain") or [])
    params = {k: (v if k in plain else sha(canon(v))) for k, v in (ctx.req["action"].get("params") or {}).items()}
    entry = {"ts": result["evaluated_at"], "mode": mode, "delegate": ctx.req["delegate"],
             "capability": ctx.req["capability"], "action": ctx.req["action"]["name"], "params": params,
             "decision": result["decision"], "reason": result["reason"], "contract_id": result["contract_id"],
             "action_sha256": result["action_sha256"], "state_digest": result["state_digest"]}
    path = os.path.join(d, "audit.jsonl")
    with open(path, "a+b") as f:
        if fcntl:
            fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        lines = [l for l in f.read().split(b"\n") if l]
        entry["prev_sha256"] = sha(lines[-1]) if lines else "0" * 64
        f.seek(0, 2)
        f.write(canon(entry).encode("utf-8") + b"\n")
        f.flush()
        os.fsync(f.fileno())


def policy_sha(ctx):
    h = hashlib.sha256()
    for p in (SELF, os.path.join(ctx.root, "contracts", "ontology", "savia-operational.yaml")):
        try:
            with open(p, "rb") as f:
                h.update(f.read())
        except OSError:
            h.update(b"absent")
    return h.hexdigest()


def evaluate(req, prior=None):
    validate_request(req)
    ctx = Ctx(req, prior)
    decision, reason, detail, key = "ALLOW", "OK", "", None
    try:
        for n, _name, fn in STEPS:
            if n >= 17 and prior is None:
                break
            fn(ctx)
        if prior is not None:
            key = consume_use(ctx)
    except Deny as d:
        decision, reason, detail = "DENY", d.code, d.detail
    except Approval as a:
        decision, reason, detail = "REQUIRES_APPROVAL", a.code, a.detail
    except Exception as e:  # p. ej. contrato firmado mal formado: sin decision (exit 2), pero el intento queda en audit
        try:
            cid = ctx.contract.get("id") if isinstance(ctx.contract, dict) else None
            audit_append(ctx, {"evaluated_at": iso(ctx.now), "decision": "ERROR", "reason": type(e).__name__,
                               "contract_id": cid, "action_sha256": action_hash(req), "state_digest": None},
                         "recheck" if prior is not None else "evaluate")
        except Exception:
            pass
        raise
    result = {
        "decision": decision, "reason": reason, "detail": detail,
        "contract_id": (ctx.contract or {}).get("id"), "contract_sha256": ctx.contract_sha,
        "capability_sha256": ctx.cap_sha, "action_sha256": action_hash(req),
        "state_digest": state_digest(ctx) if ctx.contract is not None else None,
        "policy_sha256": policy_sha(ctx), "evaluated_at": iso(ctx.now), "suggestions": ctx.suggestions}
    if decision == "ALLOW" and key:
        result["reservation_key"] = key
    try:
        audit_append(ctx, result, "recheck" if prior is not None else "evaluate")
    except OSError as e:
        if decision == "ALLOW":
            raise RuntimeError("audit no escribible, no se concede: %s" % e)
    return result


def verify_audit(path=None):
    path = path or os.path.join(home(), ".savia", "authority", "audit.jsonl")
    try:
        with open(path, "rb") as f:
            lines = [l for l in f.read().split(b"\n") if l]
    except FileNotFoundError:
        return []
    prev = "0" * 64
    for i, l in enumerate(lines, 1):
        try:
            e = json.loads(l.decode("utf-8"))
        except ValueError:
            return ["linea %d no es JSON" % i]
        if e.get("prev_sha256") != prev:
            return ["cadena rota en la linea %d" % i]
        prev = sha(l)
    return []


EXIT = {"ALLOW": 0, "DENY": 1, "REQUIRES_APPROVAL": 4}


def main(argv, stdin_text):
    cmd = argv[0] if argv else ""
    if cmd in ("evaluate", "recheck"):
        try:
            req = json.loads(stdin_text)
            validate_request(req)
            prior = None
            if cmd == "recheck":
                if len(argv) != 3 or argv[1] != "--prior":
                    raise BadRequest("uso: recheck --prior RECIBO")
                with open(argv[2], encoding="utf-8") as f:
                    prior = json.load(f)
                if not isinstance(prior, dict) or prior.get("decision") != "ALLOW":
                    raise BadRequest("el recibo previo no es un ALLOW")
            result = evaluate(req, prior)
        except (BadRequest, ValueError, OSError) as e:
            sys.stderr.write("authority_kernel: peticion no valida: %s\n" % e)
            return 2, ""
        return EXIT[result["decision"]], json.dumps(result, sort_keys=True, ensure_ascii=False)
    if cmd == "check-ontology":
        root = root_dir()
        path = argv[1] if len(argv) > 1 else os.path.join(root, "contracts", "ontology", "savia-operational.yaml")
        try:
            errs = ontology_errors(load_yaml_file(path), root)
        except (OSError, ValueError) as e:
            sys.stderr.write("authority_kernel: ontologia ilegible: %s\n" % e)
            return 2, ""
        return (1 if errs else 0), ("FAIL: " + "; ".join(errs) if errs else "PASS: ontologia valida")
    if cmd == "check-contract":
        if len(argv) != 2:
            sys.stderr.write("uso: check-contract FICHERO\n")
            return 2, ""
        try:
            with open(argv[1], "rb") as f:
                raw = f.read()
            c = json.loads(raw.decode("utf-8"))
        except (OSError, ValueError) as e:
            sys.stderr.write("authority_kernel: contrato ilegible: %s\n" % e)
            return 2, ""
        errs = contract_errors(c, root_dir(), raw)
        return (1 if errs else 0), ("FAIL: " + " ".join(errs) if errs else "PASS: contrato valido")
    if cmd == "verify-audit":
        errs = verify_audit()
        return (1 if errs else 0), ("FAIL: " + "; ".join(errs) if errs else "PASS: cadena de audit integra")
    sys.stderr.write(__doc__)
    return 2, ""


def cli():
    try:
        data = sys.stdin.read() if sys.argv[1:2] in (["evaluate"], ["recheck"]) else ""
        code, out = main(sys.argv[1:], data)
    except SystemExit:
        raise
    except BaseException as e:  # fallo interno: sin decision, nunca exit 0
        sys.stderr.write("authority_kernel: fallo interno: %r\n" % (e,))
        sys.exit(2)
    if out:
        print(out)
    sys.exit(code)


if __name__ == "__main__":
    cli()
