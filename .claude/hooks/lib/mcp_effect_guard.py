#!/usr/bin/env python3
"""mcp_effect_guard.py — núcleo del guard previo para tools MCP y WebFetch/WebSearch (SE-508 S1).

Lo usan los dos frontends con la misma entrada (el payload PreToolUse por stdin):
- Claude Code: `.claude/hooks/mcp-effect-guard.sh` (`--frontend claude --hook`).
- OpenCode: `scripts/opencode-plugin/savia-gates/lib/mcp-effect-guard.ts` (`--frontend opencode --json`).

Orden de evaluación fijo (spec SE-508, punto 6):
  1. leer y validar stdin; vacío o malformado → ask
  2. leer catálogos; ausentes o ilegibles → ask
  3. clasificar (lo más estricto entre el catálogo del árbol y el del `main` remoto)
  4. merge → deny
  5. delegación a Space (solo OpenCode con pin fijado, nunca en un run sin persona)
  6. reglas: read_only pasa, write y no catalogada → ask, WebFetch por host y forma, WebSearch se registra
  7. ejecución sin persona → todo ask pasa a deny

El catálogo y la lista de hosts no se pueden aflojar desde el árbol: el núcleo lee también los del
`main` de CANONICAL_REMOTE en un repositorio temporal vacío, sin configuración git de trabajo,
global ni de sistema, y aplica lo más estricto. Sin remoto legible, todo pregunta (falla cerrado).
Límite declarado: este fichero vive en el árbol; protegerlo de su edición es cosa del pin de guards
de Space (guard-pin.ts) y de la revisión de la PR.
Solo biblioteca estándar (arranque blindado: sin dependencias externas).
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit

# Fin del modo observación de WebFetch/WebSearch en sesiones con persona (fusión de S1 + 14 días).
# Manda la más temprana entre esta y la del `main` remoto; ilegible → enforce.
OBSERVE_UNTIL = "2026-11-24"

# Referencia del catálogo: URL fija, nunca un nombre de remoto. Un fork la cambia con una PR en su fork.
CANONICAL_REMOTE = "https://github.com/gonzalezpazmonica/savia.git"

CATALOG_PATH = "config/mcp-effect-catalog.yaml"
HOSTS_PATH = "config/webfetch-allow-hosts"
CORE_PATH = ".claude/hooks/lib/mcp_effect_guard.py"

LS_REMOTE_TIMEOUT = 3
FETCH_TIMEOUT = 6
# Tope global de la lectura del remoto. Cada orden git tiene el suyo, pero sumados (init, ls-remote, 2 fetch,
# 3 ls-tree, 3 cat-file) llegaban a ~50 s: el `timeout 20` del hook mataba a python3 y los git, lanzados en su
# propia sesión, quedaban huérfanos. Con este tope el núcleo termina antes y mata él mismo cada grupo.
REMOTE_BUDGET = 15
MAX_PATH = 200
MAX_SEGMENT = 64

RANK = {"read_only": 0, "write": 1, "merge": 2}

MERGE_REASON = ("Rechazado: fusionar una PR por una tool MCP no está permitido. Los merges van por "
                "push-pr.sh --merge o merge-sprint.sh con grant (SE-343). No se ha fusionado nada.")
MERGE_SUMMARY = "se bloqueó un merge por MCP; los merges van con grant"

_CATALOG_LINE = re.compile(r"^([A-Za-z0-9_.-]+):\s*(read_only|write|merge)\s*(?:#.*)?$")
_UNTIL_LINE = re.compile(r'^OBSERVE_UNTIL\s*=\s*"(\d{4}-\d{2}-\d{2})"\s*(?:#.*)?$', re.M)


# ---------------------------------------------------------------- entorno


def test_mode(env) -> bool:
    """La inyección de remoto y reloj solo vale dentro de bats. Los hooks heredan el entorno con el que
    arrancó el frontend, no el del shell de una tool, así que un agente no la activa desde una orden."""
    return env.get("SAVIA_MCP_GUARD_TEST") == "1" and bool(env.get("BATS_TEST_FILENAME"))


def autonomous(env) -> bool:
    return bool(env.get("SAVIA_RUN_ID")) or env.get("SAVIA_AUTONOMOUS_RUN") == "1"


def today(env) -> _dt.date:
    if test_mode(env) and env.get("SAVIA_MCP_GUARD_TEST_TODAY"):
        return _dt.date.fromisoformat(env["SAVIA_MCP_GUARD_TEST_TODAY"])
    return _dt.date.today()


def remote_url(env) -> str:
    if test_mode(env) and env.get("SAVIA_MCP_GUARD_TEST_REMOTE"):
        return env["SAVIA_MCP_GUARD_TEST_REMOTE"]
    return CANONICAL_REMOTE


# ---------------------------------------------------------------- catálogos


class Unreadable(Exception):
    pass


def parse_catalog(text: str) -> dict[str, str]:
    """Mapa plano `tool: clase`. Una línea fuera de formato, una clave repetida o un catálogo vacío → ilegible."""
    out: dict[str, str] = {}
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = _CATALOG_LINE.match(s)
        if not m:
            raise Unreadable(f"línea {n} fuera de formato")
        if m.group(1) in out:
            raise Unreadable(f"línea {n}: {m.group(1)} repetida")
        out[m.group(1)] = m.group(2)
    if not out:
        raise Unreadable("catálogo vacío")
    return out


def normalize_host(host: str) -> str | None:
    """Minúsculas, sin punto final, IDN a punycode. None si no es un host válido."""
    h = (host or "").strip().lower().rstrip(".")
    if not h or any(c in h for c in "/@:?# \t[]\\"):
        return None
    try:
        h = h.encode("idna").decode("ascii")
    except (UnicodeError, ValueError):
        return None
    return h.lower() or None


def parse_hosts(text: str) -> set[str]:
    out: set[str] = set()
    for n, line in enumerate(text.splitlines(), 1):
        s = line.split("#", 1)[0].strip()
        if not s:
            continue
        h = normalize_host(s)
        if not h:
            raise Unreadable(f"línea {n}: host no válido")
        out.add(h)
    return out


def parse_until(text: str | None) -> _dt.date | None:
    if text is None:
        return None
    m = _UNTIL_LINE.search(text)
    if not m:
        return None
    try:
        return _dt.date.fromisoformat(m.group(1))
    except ValueError:
        return None


def read_tree(root: str, rel: str) -> str | None:
    """Contenido del fichero en el árbol; None si no existe. Error de lectura → Unreadable."""
    p = os.path.join(root, rel)
    if not os.path.lexists(p):
        return None
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise Unreadable(str(e)) from e


# ---------------------------------------------------------------- remoto


def _git_env(tmp: str) -> dict[str, str]:
    """Sin GIT_* heredadas ni configuración global o de sistema: ni insteadOf, ni sshCommand, ni credenciales."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update({
        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
        "GIT_NO_LAZY_FETCH": "1", "HOME": tmp, "XDG_CONFIG_HOME": tmp, "GIT_ASKPASS": "/bin/false",
        "SSH_ASKPASS": "/bin/false", "LC_ALL": "C",
    })
    return env


def _run(args: list[str], cwd: str, env: dict[str, str], timeout: float, deadline: float | None = None) -> bytes:
    """git con tiempo máximo; al agotarse mata el grupo de procesos entero (git-remote-https incluido).

    `deadline` (reloj monotónico) recorta el tiempo de esta orden a lo que quede del presupuesto global."""
    if deadline is not None:
        timeout = min(timeout, deadline - time.monotonic())
        if timeout <= 0:
            raise Unreadable("tiempo agotado")
    p = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.communicate()
        raise Unreadable("tiempo agotado")
    if p.returncode != 0:
        raise Unreadable(f"git terminó con {p.returncode}")
    return out


def read_remote(url: str) -> dict[str, str | None] | None:
    """Ficheros del guard en el `main` remoto: {ruta: contenido, o None si ese main no lo tiene}.

    None si el remoto no contesta a tiempo o algo no se puede leer (quien llama falla cerrado).
    """
    deadline = time.monotonic() + REMOTE_BUDGET
    tmp = tempfile.mkdtemp(prefix="savia-mcp-guard-")
    try:
        env = _git_env(tmp)
        repo = os.path.join(tmp, "r.git")
        git = ["git", "-c", "core.hooksPath=/dev/null"]
        _run(git + ["init", "-q", "--bare", repo], tmp, env, 5, deadline)
        out = _run(git + ["-C", repo, "ls-remote", url, "refs/heads/main"], tmp, env, LS_REMOTE_TIMEOUT, deadline)
        line = out.decode("ascii", "replace").strip().split("\n")[0]
        sha = line.split("\t")[0] if line.endswith("\trefs/heads/main") else ""
        if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", sha):
            return None
        _run(git + ["-C", repo, "fetch", "-q", "--no-tags", "--depth=1", "--filter=blob:none", url, sha],
             tmp, env, FETCH_TIMEOUT, deadline)
        blobs: dict[str, str | None] = {}
        for rel in (CATALOG_PATH, HOSTS_PATH, CORE_PATH):
            listed = _run(git + ["-C", repo, "ls-tree", sha, "--", rel], tmp, env, 5, deadline).decode("utf-8", "replace")
            m = re.match(r"^\d+ blob ([0-9a-f]+)\t", listed)
            blobs[rel] = m.group(1) if m else None
        wanted = sorted({b for b in blobs.values() if b})
        if wanted:  # una sola ida y vuelta para los tres ficheros
            _run(git + ["-C", repo, "fetch", "-q", "--no-tags", "--depth=1", url, *wanted], tmp, env, FETCH_TIMEOUT, deadline)
        result: dict[str, str | None] = {}
        for rel, blob in blobs.items():
            result[rel] = None if blob is None else _run(git + ["-C", repo, "cat-file", "blob", blob], tmp, env, 5, deadline).decode("utf-8")
        return result
    except (Unreadable, OSError, UnicodeDecodeError, ValueError):
        return None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- descripción en llano


def _count(*values) -> int:
    n = 0
    for v in values:
        if isinstance(v, list):
            n += sum(1 for x in v if isinstance(x, (str, dict)))
        elif isinstance(v, str) and v.strip():
            n += len([x for x in v.split(",") if x.strip()])
    return n


def _people(n: int) -> str:
    return "1 persona" if n == 1 else f"{n} personas"


def describe(tool: str, args: dict) -> tuple[str, str, str]:
    """(texto para la persona, destino, efecto) de una tool `write`."""
    parts = tool.split("__")
    server = parts[1] if len(parts) >= 3 else tool
    service = server.replace("claude_ai_", "").replace("_", " ")
    if tool == "mcp__claude_ai_Gmail__send_message":
        if args.get("draftId"):
            return "Savia quiere enviar un borrador guardado de Gmail. ¿Lo envío?", "destinatarios del borrador", "enviar un correo"
        n = _count(args.get("to"), args.get("cc"), args.get("bcc"))
        subject = str(args.get("subject") or "").strip()[:80]
        text = f"Savia quiere enviar un correo a {_people(n)}" + (f' (asunto: "{subject}").' if subject else " (sin asunto).")
        return text + " ¿Lo envío?", _people(n), "enviar un correo"
    if tool == "mcp__claude_ai_Gmail__forward":
        n = _count(args.get("to"), args.get("cc"), args.get("bcc"))
        return f"Savia quiere reenviar un correo a {_people(n)}. ¿Lo reenvío?", _people(n), "reenviar un correo"
    if tool == "mcp__claude_ai_Gmail__reply":
        if args.get("replyAll"):
            return "Savia quiere responder a todos en un correo. ¿Lo envío?", "remitente y destinatarios", "responder a un correo"
        return "Savia quiere responder a un correo. ¿Lo envío?", "remitente", "responder a un correo"
    if tool == "mcp__claude_ai_Google_Calendar__create_event":
        n = _count(args.get("attendees"), args.get("attendeeEmails"))
        title = str(args.get("summary") or "").strip()[:80]
        return (f'Savia quiere crear un evento de calendario ("{title}") con {n} invitados. ¿Lo creo?',
                f"{n} invitados", "crear un evento")
    if tool == "mcp__claude_ai_Google_Drive__share_file":
        if args.get("permissionId") == "anyoneWithLink":
            dest = "cualquiera con el enlace"
        elif args.get("chatSpaceId"):
            dest = "un espacio de Chat"
        elif args.get("emailAddress"):
            dest = str(args.get("emailAddress"))[:120]
        else:
            dest = "un grupo o audiencia"
        role = str(args.get("role") or "lector")
        return f"Savia quiere compartir un fichero de Drive con {dest} como {role}. ¿Lo comparto?", dest, "compartir un fichero"
    action = parts[-1].replace("_", " ")
    return f"Savia quiere usar {service} para «{action}», que escribe fuera de aquí. ¿Sigo?", service, action


# ---------------------------------------------------------------- WebFetch


def check_url(url: str, hosts: set[str]) -> tuple[bool, str, str, int]:
    """(pasa, motivo, host, caracteres de más)."""
    try:
        p = urlsplit(url)
        port = p.port
    except ValueError:
        return False, "Savia quiere abrir una dirección que no se puede comprobar (formato no válido). ¿La abro?", "", 0
    host = normalize_host(p.hostname or "") or ""
    shown = host or "desconocido"
    bad = []
    if p.scheme.lower() != "https":
        bad.append(f"esquema {p.scheme or 'vacío'}, solo vale https")
    if p.username is not None or p.password is not None or "@" in p.netloc:
        bad.append("lleva un usuario delante del sitio")
    if port is not None and port != 443:
        bad.append(f"puerto {port}")
    if not host:
        bad.append("sitio ilegible")
    if bad:
        return False, f"Savia quiere abrir una dirección que no se puede comprobar ({'; '.join(bad)}). Sitio: {shown}. ¿La abro?", shown, 0
    excess = 0
    detail = []
    if p.query:
        excess += len(p.query)
        detail.append("datos después del ?")
    if p.fragment:
        excess += len(p.fragment)
        detail.append("datos después del #")
    if len(p.path) > MAX_PATH:
        excess += len(p.path) - MAX_PATH
        detail.append(f"ruta de más de {MAX_PATH} caracteres")
    long_segments = [s for s in p.path.split("/") if len(s) > MAX_SEGMENT]
    if long_segments:
        excess += sum(len(s) - MAX_SEGMENT for s in long_segments)
        detail.append(f"un tramo de la ruta de más de {MAX_SEGMENT} caracteres")
    allowed = host in hosts
    if allowed and not detail:
        return True, "", host, 0
    extra = f"La dirección lleva {excess} caracteres de más" + (f" ({', '.join(detail)})." if detail else ".")
    if allowed:
        return False, f"Savia quiere abrir una web de tu lista con datos en la dirección. Sitio: {host}. {extra} ¿La abro?", host, excess
    return False, f"Savia quiere abrir una web que no está en tu lista. Sitio: {host}. {extra} ¿La abro?", host, excess


# ---------------------------------------------------------------- decisión


class Verdict:
    def __init__(self, decision: str, reason: str = "", log: dict | None = None):
        self.decision = decision  # pass | ask | deny
        self.reason = reason
        self.log = log  # línea del registro de decisiones (sin datos de la llamada)

    def as_dict(self) -> dict:
        return {"decision": self.decision, "reason": self.reason}


def strictest_class(tool: str, tree: dict[str, str], remote: dict[str, str]) -> str:
    """merge > (falta en alguno → unknown) > write > read_only."""
    a, b = tree.get(tool), remote.get(tool)
    if "merge" in (a, b):
        return "merge"
    if a is None or b is None:
        return "unknown"
    return a if RANK[a] >= RANK[b] else b


def decide(raw: bytes, root: str, env, frontend: str = "claude", pin_fixed: bool = False,
           remote_reader=read_remote) -> Verdict:
    auto = autonomous(env)
    v = _decide(raw, root, env, frontend, pin_fixed, auto, remote_reader)
    # 7. sin persona delante nadie contesta un ask
    if auto and v.decision == "ask":
        log = dict(v.log or {})
        log["decision"] = "deny"
        v = Verdict("deny", v.reason, log)
    return v


def _ask(reason: str, tool: str, cls: str, summary: str) -> Verdict:
    return Verdict("ask", reason, {"tool": tool, "class": cls, "decision": "ask", "summary": summary})


def _decide(raw: bytes, root: str, env, frontend: str, pin_fixed: bool, auto: bool, remote_reader) -> Verdict:
    # 1. entrada
    try:
        payload = json.loads(raw.decode("utf-8")) if raw and raw.strip() else None
    except (UnicodeDecodeError, ValueError):
        payload = None
    if not isinstance(payload, dict) or not isinstance(payload.get("tool_name"), str) or not payload["tool_name"]:
        return _ask("Guard de efectos: la llamada llega vacía o ilegible; no se puede comprobar qué hace. ¿Sigo?",
                    "?", "invalid", "llamada ilegible")
    tool = payload["tool_name"]
    if not (tool.startswith("mcp__") or tool in ("WebFetch", "WebSearch")):
        return Verdict("pass")  # fuera del alcance de este guard
    args = payload.get("tool_input", {})
    if args is None:
        args = {}
    if not isinstance(args, dict):
        return _ask(f"Guard de efectos: los argumentos de {tool} son ilegibles. ¿Sigo?", tool, "invalid", "argumentos ilegibles")
    if tool == "WebFetch" and not (isinstance(args.get("url"), str) and args["url"].strip()):
        return _ask("Guard de efectos: WebFetch sin dirección legible. ¿Sigo?", tool, "invalid", "WebFetch sin dirección")
    if tool == "WebSearch" and not isinstance(args.get("query"), str):
        return _ask("Guard de efectos: WebSearch sin búsqueda legible. ¿Sigo?", tool, "invalid", "WebSearch sin búsqueda")

    # 2. catálogos del árbol. Ausente o ilegible no decide todavía: se consulta el remoto, porque un merge del
    # remoto sigue siendo deny (revisión Codex #1525 P1-3: borrar el catálogo local rebajaba merge a ask).
    tree_cat: dict[str, str] | None
    try:
        text = read_tree(root, CATALOG_PATH)
        if text is None:
            raise Unreadable("ausente")
        tree_cat = parse_catalog(text)
        bad_tree = None
    except Unreadable as e:
        tree_cat = None
        bad_tree = _ask(f"Guard de efectos: el catálogo {CATALOG_PATH} falta o es ilegible ({e}); no se puede clasificar {tool}. ¿Sigo?",
                        tool, "invalid", "catálogo ilegible")
    try:
        htext = read_tree(root, HOSTS_PATH)
        tree_hosts = parse_hosts(htext) if htext is not None else set()
    except Unreadable:
        tree_hosts = set()
    try:
        tree_until = parse_until(read_tree(root, CORE_PATH))
    except Unreadable:
        tree_until = None

    # Atajo sin cambio de resultado: lo más estricto de un merge del árbol es merge.
    if tree_cat is not None and tree_cat.get(tool) == "merge":
        return Verdict("deny", MERGE_REASON, {"tool": tool, "class": "merge", "decision": "deny", "summary": MERGE_SUMMARY})

    remote = remote_reader(remote_url(env))
    if remote is None:
        if bad_tree is not None:
            return bad_tree
        return _ask("Guard de efectos: no se pudo leer el catálogo de referencia del repositorio (sin red o sin respuesta), "
                    f"así que no se puede confirmar qué hace {tool}. ¿Sigo?", tool, "no_remote", "sin catálogo de referencia")
    try:
        rtext = remote.get(CATALOG_PATH)
        remote_cat = parse_catalog(rtext) if rtext is not None else {}
    except Unreadable:
        return _ask(f"Guard de efectos: el catálogo del main remoto es ilegible; no se puede clasificar {tool}. ¿Sigo?",
                    tool, "invalid", "catálogo remoto ilegible")
    if bad_tree is not None:
        # Sin catálogo local nada pasa: merge del remoto → deny; lo demás → ask.
        if remote_cat.get(tool) == "merge":
            return Verdict("deny", MERGE_REASON, {"tool": tool, "class": "merge", "decision": "deny", "summary": MERGE_SUMMARY})
        return bad_tree
    try:
        rh = remote.get(HOSTS_PATH)
        remote_hosts = parse_hosts(rh) if rh is not None else set()
    except Unreadable:
        remote_hosts = set()
    hosts = tree_hosts & remote_hosts

    # Modo observación: la fecha más temprana; si el main aún no tiene el núcleo, manda la del árbol.
    rcore = remote.get(CORE_PATH)
    if tree_until is None:
        until = None
    elif rcore is None:
        until = tree_until
    else:
        r_until = parse_until(rcore)
        until = None if r_until is None else min(tree_until, r_until)
    observe = until is not None and today(env) <= until

    # 3. clasificar
    if tool == "WebFetch":
        cls = "webfetch"
    elif tool == "WebSearch":
        cls = "websearch"
    else:
        cls = strictest_class(tool, tree_cat, remote_cat)

    # 4. merge
    if cls == "merge":
        return Verdict("deny", MERGE_REASON, {"tool": tool, "class": "merge", "decision": "deny", "summary": MERGE_SUMMARY})

    # 5. delegación: solo OpenCode con el pin de Space fijado en el proceso del plugin, nunca sin persona
    if (frontend == "opencode" and pin_fixed and env.get("SAVIA_GATES_PIN") == "1" and not auto
            and cls in ("write", "unknown", "webfetch", "websearch")):
        return Verdict("pass", "", {"tool": tool, "class": cls, "decision": "delegated",
                                    "summary": "decisión delegada en Savia Space"})

    # 6. reglas
    if cls == "read_only":
        return Verdict("pass")
    if cls == "write":
        text, dest, effect = describe(tool, args)
        return _ask(f"{text} (tool {tool}; destino: {dest}; efecto: {effect})", tool, cls,
                    f"{effect} por {tool.split('__')[1] if tool.count('__') >= 2 else tool}")
    if cls == "unknown":
        return _ask(f"Savia quiere usar una herramienta sin clasificar: {tool}. No se sabe si escribe fuera. ¿La uso?",
                    tool, cls, "herramienta sin clasificar")
    if cls == "webfetch":
        ok, reason, host, excess = check_url(args["url"].strip(), hosts)
        if ok:
            return Verdict("pass")
        if observe and not auto:  # sin persona, WebFetch va en enforce desde S1
            return Verdict("pass", "", {"tool": tool, "class": cls, "decision": "would_ask", "host": host,
                                        "excess": excess, "summary": "web que habría preguntado"})
        return Verdict("ask", reason, {"tool": tool, "class": cls, "decision": "ask", "host": host, "excess": excess,
                                       "summary": "web fuera de la lista o con datos en la dirección"})
    # websearch: no hay lista de búsquedas permitidas; se registra hasta OBSERVE_UNTIL, también sin persona
    qlen = len(args["query"])
    if observe:
        return Verdict("pass", "", {"tool": tool, "class": cls, "decision": "observed", "query_len": qlen,
                                    "summary": "búsqueda web registrada"})
    return Verdict("ask", f"Savia quiere buscar en la web ({qlen} caracteres que salen al buscador). ¿Busco?",
                   {"tool": tool, "class": cls, "decision": "ask", "query_len": qlen, "summary": "búsqueda web"})


# ---------------------------------------------------------------- registro y salida


def log_path(root: str, env) -> str:
    """Ruta del registro. Desviarla es solo de tests (SAVIA_MCP_GUARD_TEST_LOG dentro de bats): en producción una
    variable heredada no puede mandar el registro a otra ruta ni esconderlo."""
    if test_mode(env) and env.get("SAVIA_MCP_GUARD_TEST_LOG"):
        return env["SAVIA_MCP_GUARD_TEST_LOG"]
    return os.path.join(root, "output", "mcp-effect-guard", "decisions.jsonl")


def write_log(v: Verdict, root: str, env, frontend: str) -> None:
    """Una línea por decisión que no es «pasa en silencio». Si falla, la decisión no cambia."""
    if not v.log:
        return
    entry = {"ts": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "frontend": frontend,
             "autonomous": autonomous(env), **v.log}
    try:
        path = log_path(root, env)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


def main(argv: list[str]) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Guard previo de efectos MCP/WebFetch/WebSearch (SE-508)")
    ap.add_argument("--root", required=True)
    ap.add_argument("--frontend", choices=("claude", "opencode"), default="claude")
    ap.add_argument("--pin-fixed", action="store_true", help="solo OpenCode: el plugin tiene fijado el pin de guards")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--hook", action="store_true", help="salida PreToolUse de Claude Code")
    mode.add_argument("--json", action="store_true", help='salida {"decision","reason"}')
    a = ap.parse_args(argv)
    raw = sys.stdin.buffer.read()
    v = decide(raw, a.root, os.environ, a.frontend, a.pin_fixed and a.frontend == "opencode")
    write_log(v, a.root, os.environ, a.frontend)
    if a.json:
        sys.stdout.write(json.dumps(v.as_dict(), ensure_ascii=False) + "\n")
    elif v.decision in ("ask", "deny"):
        sys.stdout.write(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": v.decision,
            "permissionDecisionReason": v.reason}}, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
