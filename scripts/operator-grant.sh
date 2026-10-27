#!/usr/bin/env bash
# operator-grant.sh — Deterministic operator-grant ledger (SE-343)
#
# Replaces manual env-var setup for autonomous skills and the binary
# "never merge" rule with a LOCAL, auditable grant ledger written by Savia
# ONLY on the operator's express request.
#
#   grant   --scope autonomy:<skill> --context "<why>" [--ttl-hours N]
#   grant   --scope merge --resource pr:<n>|task:<id> --context "<why>" [--ttl-hours N]
#   grant   --scope merge --signature <fichero|->   # incorpora la firma de la operadora
#   check   --scope <scope> [--resource R]  # exit 0 vigente | 1 no/expirado | 2 invalido | 3 sin grant
#   consume --scope merge --resource R      # uso único: gasta el grant tras el merge
#   revoke  --scope <scope>
#   list
#   guard                           # hook PreToolUse (lee el evento por stdin)
#
# Ledger: ~/.savia/grants/<scope>.json  (local infra, CRIT-001 — never in repo)
# Grantor: resolved from .claude/profiles/active-user.md (slug). NEVER "self".
#
# Scope merge (LAW-HUMAN-002, firma asimétrica): Savia no puede emitirlo sola.
# `grant --scope merge` deja una petición sin firmar (~/.savia/grants/
# merge.request); la operadora la firma con su clave ed25519 privada, que vive
# en su móvil o en Savia Space y nunca en este equipo
# (`ssh-keygen -Y sign -n savia-operator-grant`), y `grant --scope merge
# --signature FICHERO|-` la incorpora. `check` verifica la firma con
# `ssh-keygen -Y verify` contra la clave pública versionada en
# config/operator-grant-signers (sin override por variable de entorno).
#
# Exit: 0 ok | 1 not valid/expired/bad signature | 2 invalid invocation
#       3 no grant | 4 merge grant pending: falta la firma de la operadora
# Ref: SE-343, SE-433 D7, SPEC-186, autonomous-safety.md

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# PATH fijo de sistema: python3, ssh-keygen y git no se resuelven por un PATH que
# el llamante controle (un ssh-keygen falso que sale con 0 daría PASS sin firma).
# Junto con `python3 -I` (sin PYTHONPATH, sitecustomize del usuario ni cwd en
# sys.path), el entorno no sustituye el verificador sin dejar rastro.
SAFE_PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
export PATH="$SAFE_PATH"
GRANTS_DIR="${SAVIA_GRANTS_DIR:-$HOME/.savia/grants}"
# Raíz de confianza del grant de merge: clave(s) pública(s) de la operadora en
# formato allowed_signers de OpenSSH. Versionada y sin override: si una variable
# pudiera redirigirla, un agente apuntaría a su propia clave y firmaría él.
SIGNERS_FILE="$REPO_ROOT/config/operator-grant-signers"
SIG_NAMESPACE="savia-operator-grant"
# Resuelto desde la raíz del repo (no desde el cwd); override para tests.
ACTIVE_USER_FILE="${SAVIA_ACTIVE_USER_FILE:-$REPO_ROOT/.claude/profiles/active-user.md}"

usage() {
  cat <<'USAGE'
Usage: operator-grant.sh <grant|check|consume|revoke|list> --scope SCOPE [opts]

Commands:
  grant   SCOPE  --context "reason" [--ttl-hours N]   emit grant (express request)
          merge also needs --resource pr:<n>|task:<id> (the PR or task it covers)
  grant   merge  --signature FILE|-                   attach the operator's signature
  check   SCOPE  [--resource R]                       exit: 0 vigente | 1 no | 2 inval | 3 sin grant
                                                      (merge: --resource required)
  consume merge  --resource R                         one-shot: spend the grant after merging
  revoke  SCOPE                                       revoke (grant id marked spent, request removed)
  list                                                show all grants
  guard                                               PreToolUse hook (event on stdin)

Scopes:
  autonomy:<skill>   enables double-optin "intent" factor for the skill
                     (overnight-sprint, code-improvement-loop, adversarial-security,
                      tech-research-agent, savia-dual)
  merge              enables PR merge (--merge in push-pr.sh)

Rules:
  - grantor = active user slug (active-user.md). NEVER "self".
  - autonomy:* source express-request; merge source operator-signature.
  - merge: `grant --context` only writes a pending request (exit 4). The
    operator signs it with her ed25519 key (phone or Savia Space, never this
    machine): ssh-keygen -Y sign -f KEY -n savia-operator-grant REQUEST
    and `grant --scope merge --signature REQUEST.sig` attaches it. check
    verifies it against config/operator-grant-signers.
  - merge grant: unique id, grantor, scope, repo (origin remote), resource and
    validity are signed; check verifies each one against this checkout and
    rejects ids already consumed or revoked (revoke also spends the pending request).
  - default TTL: autonomy:* = 24h, merge = 6h (counted from the request).
  - grant (idempotent): renews expires_at of an existing autonomy grant.
USAGE
}

# ── Helpers ────────────────────────────────────────────────────────────

active_slug() {
  if [[ -f "$ACTIVE_USER_FILE" ]]; then
    grep -oP 'active_slug:\s*"\K[^"]+' "$ACTIVE_USER_FILE" 2>/dev/null | head -1
  else
    echo ""
  fi
}

now_epoch() { date +%s 2>/dev/null || echo 0; }

default_ttl() {
  case "$1" in
    merge)             echo 6 ;;
    autonomy:*)        echo 24 ;;
    *)                 echo 0 ;;
  esac
}

valid_scope() {
  case "$1" in
    merge) return 0 ;;
    autonomy:overnight-sprint|autonomy:code-improvement-loop|autonomy:adversarial-security|autonomy:tech-research-agent|autonomy:savia-dual) return 0 ;;
    *) return 1 ;;
  esac
}

scope_file() { printf '%s/%s.json' "$GRANTS_DIR" "$1"; }
# Identidad del repositorio en el que corre el script (remoto origin de REPO_ROOT).
repo_id() {
  local u
  u="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" || return 0
  python3 -I -c "$GRANT_PY" repo "$u" 2>/dev/null || true
}
request_file() { printf '%s/%s.request' "$GRANTS_DIR" "$1"; }
spent_file() { printf '%s/%s.spent' "$GRANTS_DIR" "$1"; }

# JSON escapado (un --context con comillas no inyecta campos) y, para merge,
# petición canónica + verificación de la firma de la operadora con ssh-keygen.
# Un grant de merge lleva id único, grantor (principal), scope, resource (PR o
# tarea) y vigencia, todo dentro de lo firmado; check verifica cada campo y
# rechaza los ids consumidos o revocados (merge.spent), así que una copia
# guardada del grant no se puede volver a usar.
GRANT_PY='
import json, os, re, subprocess, sys, tempfile, time
FIELDS = ("id", "scope", "repo", "resource", "grantor", "request_context",
          "issued_at", "issued_epoch", "expires_at", "expires_epoch")
ID_RE = re.compile(r"^[0-9a-f]{32}$")
RES_RE = re.compile(r"^(pr|task):[A-Za-z0-9._-]{1,64}$")
def payload(rec):
    """Bytes exactos que firma la operadora."""
    return json.dumps({f: rec.get(f) for f in FIELDS}, sort_keys=True,
                      ensure_ascii=True, separators=(",", ":")).encode()
def spent_ids(path):
    try:
        return {l.split("\t", 1)[0] for l in open(path) if l.strip()}
    except FileNotFoundError:
        return set()
def repo_of(url):
    """Identidad del repositorio (host/owner/name) desde la URL del remoto origin.
    Sin credenciales ni .git; vacía si no es una URL de forja reconocible."""
    u = url.strip()
    m = (re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]*://(?:[^@/]*@)?([^/:@]+)(?::[0-9]+)?/(.+?)(?:\.git)?/*", u)
         or re.fullmatch(r"(?:[^@/:]+@)?([^/:@]+):(?!/)(.+?)(?:\.git)?/*", u))
    if not m or not re.fullmatch(r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)+", m.group(2)):
        return ""
    return (m.group(1) + "/" + m.group(2)).lower()
def fields_ok(rec, slug, resource, spent, repo):
    """Campos del grant de merge, sin la firma. resource None = el suyo.
    repo = identidad del checkout que lo usa: un grant de A#41 no vale en B#41."""
    now = time.time()
    g, i, r = rec.get("grantor"), rec.get("id"), rec.get("resource")
    ie, ee, rp = rec.get("issued_epoch"), rec.get("expires_epoch"), rec.get("repo")
    return (rec.get("scope") == "merge"
            and isinstance(rp, str) and rp != "" and rp == repo
            and isinstance(i, str) and ID_RE.match(i) is not None and i not in spent
            and isinstance(r, str) and RES_RE.match(r) is not None
            and (resource is None or r == resource)
            and isinstance(g, str) and g != "" and g != "self" and not g.startswith("-")
            and (not slug or g == slug)
            and isinstance(ie, int) and isinstance(ee, int)
            and ie <= now + 60 and ie <= ee and ee >= now)
def verify(rec, sig, signers, ns):
    if not (isinstance(sig, str) and "BEGIN SSH SIGNATURE" in sig and os.path.isfile(signers)):
        return False
    with tempfile.TemporaryDirectory() as d:
        sp = os.path.join(d, "grant.sig")
        with open(sp, "w") as f:
            f.write(sig)
        try:
            r = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", signers, "-I", rec["grantor"], "-n", ns, "-s", sp],
                               input=payload(rec), capture_output=True, timeout=15)
        except (OSError, subprocess.SubprocessError):
            return False
    return r.returncode == 0
def dump(path, rec):
    with open(path, "w") as f:
        f.write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
def load(path):
    try:
        rec = json.load(open(path))
    except (OSError, ValueError):
        return None
    return rec if isinstance(rec, dict) else None
op = sys.argv[1]
if op in ("write", "request"):
    out, scope, grantor, source, ctx, issued, expires_at, exp, now, resource, repo = sys.argv[2:13]
    rec = {"scope": scope, "grantor": grantor, "source": source, "request_context": ctx,
           "issued_at": issued, "expires_at": expires_at, "expires_epoch": int(exp)}
    if op == "write":
        dump(out, rec)
    else:
        rec.update(id=os.urandom(16).hex(), repo=repo, resource=resource, issued_epoch=int(now))
        with open(out, "wb") as f:
            f.write(payload(rec))
        print(payload(rec).decode())
elif op == "accept":
    req, sigsrc, out, signers, ns, slug, spent, repo = sys.argv[2:10]
    try:
        raw = open(req, "rb").read()
        rec = json.loads(raw)
        sig = sys.stdin.read() if sigsrc == "-" else open(sigsrc).read()
    except (OSError, ValueError) as e:
        print("ERROR: petición o firma ilegible: %s" % e, file=sys.stderr); sys.exit(2)
    if not isinstance(rec, dict) or payload(rec) != raw:
        print("ERROR: la petición no es canónica (alterada)", file=sys.stderr); sys.exit(1)
    if slug and rec.get("grantor") != slug:
        print("ERROR: la petición es de otra operadora", file=sys.stderr); sys.exit(1)
    if not (fields_ok(rec, slug, None, spent_ids(spent), repo) and verify(rec, sig, signers, ns)):
        print("ERROR: firma no válida para esta petición (clave, namespace, caducidad, repositorio, revocada o contenido)", file=sys.stderr); sys.exit(1)
    rec.update(source="operator-signature", sig=sig)
    dump(out, rec)
elif op == "check":
    # Exit 0 vigente | 1 no válido. resource "*" = el del propio grant (solo list).
    path, scope, slug, resource, signers, ns, spent, repo = sys.argv[2:10]
    rec = load(path)
    if rec is None or rec.get("scope") != scope:
        sys.exit(1)
    if scope != "merge":
        g, ee = rec.get("grantor"), rec.get("expires_epoch")
        ok = (isinstance(g, str) and g != "" and g != "self" and (not slug or g == slug)
              and isinstance(ee, int) and ee >= time.time())
        sys.exit(0 if ok else 1)
    ok = (rec.get("source") == "operator-signature"
          and fields_ok(rec, slug, None if resource == "*" else resource, spent_ids(spent), repo)
          and verify(rec, rec.get("sig"), signers, ns))
    sys.exit(0 if ok else 1)
elif op == "spend":
    # Apunta en el libro de gastados (consumido o revocado) el id del grant y el
    # de la petición pendiente: revocar antes de firmar también la invalida, y
    # una copia guardada de la petición ya no se puede firmar e incorporar.
    spent, why = sys.argv[2:4]
    ids = []
    for path in sys.argv[4:]:
        rec = load(path)
        i = rec.get("id") if rec else None
        if isinstance(i, str) and ID_RE.match(i) and i not in ids:
            ids.append(i)
    if ids:
        with open(spent, "a") as f:
            for i in ids:
                f.write("%s\t%s\t%d\n" % (i, why, int(time.time())))
elif op == "repo":
    print(repo_of(sys.argv[2]))
elif op == "field":
    rec = load(sys.argv[2]) or {}
    v = rec.get(sys.argv[3])
    print(v if isinstance(v, (str, int)) else "")
'

# Campos de un grant nuevo, uno por línea: grantor, issued_at, expires_at, epoch, now.
grant_fields() {
  local scope="$1" ttl="$2" slug="$3" grantor="$4" now exp
  now="$(now_epoch)"
  exp=$(( now + ttl * 3600 ))
  # Reuse existing grantor if already present (stability); else active slug.
  if [[ -z "$grantor" && -f "$(scope_file "$scope")" ]]; then
    grantor="$(python3 -I -c "$GRANT_PY" field "$(scope_file "$scope")" grantor 2>/dev/null || true)"
  fi
  [[ -z "$grantor" ]] && grantor="$slug"
  printf '%s\n%s\n%s\n%s\n%s\n' "$grantor" \
    "$(date -u -d @"$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "epoch-$now")" \
    "$(date -u -d @"$exp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$exp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "epoch-$exp")" \
    "$exp" "$now"
}

ensure_grants_dir() {
  mkdir -p "$GRANTS_DIR" 2>/dev/null || { echo "ERROR: cannot create $GRANTS_DIR" >&2; exit 2; }
  chmod 700 "$GRANTS_DIR" 2>/dev/null || true
}

# op = write (autonomy:*, grant en vigor) | request (merge, pendiente de firma).
emit() {
  local op="$1" scope="$2" context="$3" ttl="$4" slug="$5" grantor="$6" resource="$7" out f
  ensure_grants_dir
  mapfile -t f < <(grant_fields "$scope" "$ttl" "$slug" "$grantor")
  if [[ "$op" == "write" ]]; then out="$(scope_file "$scope")"; else out="$(request_file "$scope")"; fi
  ( umask 077
    python3 -I -c "$GRANT_PY" "$op" "$out" "$scope" "${f[0]}" express-request "$context" "${f[1]}" "${f[2]}" "${f[3]}" "${f[4]}" "$resource" "$(repo_id)" ) \
    || { echo "ERROR: cannot write $out" >&2; exit 2; }
  chmod 600 "$out" 2>/dev/null || true
}

# $3 = recurso para merge (pr:N | task:ID); "*" = el del propio grant (solo list).
check_scope() {
  local scope="$1" slug="$2" resource="${3:-}" file
  file="$(scope_file "$scope")"
  [[ ! -f "$file" ]] && return 3
  python3 -I -c "$GRANT_PY" check "$file" "$scope" "$slug" "$resource" \
    "$SIGNERS_FILE" "$SIG_NAMESPACE" "$(spent_file "$scope")" "$(repo_id)" || return 1
  return 0
}

# Gasta el grant y la petición pendiente (sus ids al libro merge.spent) y los
# retira; why = consumed | revoked.
spend_scope() {
  local scope="$1" why="$2" file req
  file="$(scope_file "$scope")" req="$(request_file "$scope")"
  if [[ "$scope" == "merge" && ( -f "$file" || -f "$req" ) ]]; then
    ensure_grants_dir
    ( umask 077; python3 -I -c "$GRANT_PY" spend "$(spent_file "$scope")" "$why" "$file" "$req" ) \
      || { echo "ERROR: cannot record spent grant" >&2; return 2; }
  fi
  rm -f "$file" "$(request_file "$scope")" 2>/dev/null
  return 0
}

# ── guard: hook PreToolUse (registro en .claude/settings.json, matcher
# "Bash|Edit|Write|MultiEdit|NotebookEdit", orden
# `"$CLAUDE_PROJECT_DIR"/scripts/operator-grant.sh guard`) ──────────────────
# Veta a las herramientas modificar la raíz de confianza
# (config/operator-grant-signers): con ella, un agente añadiría su propia clave
# pública y firmaría él. Leerla con Read sigue permitido (es pública); en Bash
# se veta cualquier mención del nombre exacto, también las lecturas
# (`git status -- …`): distinguir lectura de escritura en el texto de una orden
# no es fiable (git checkout --, sed -i, tee, cp…).
# Bash: antes de buscar el nombre, resuelve lo que el shell resolvería en el
# propio texto: comillas ANSI-C ($'\x69', $'\151', $'i'), $"…",
# continuaciones de línea, comillas y barras (operator-grant-''signers), y
# también los escapes \xHH/\NNN que expandirían printf o echo -e. Resuelve globs
# y llaves (signer[s], {signers,x}) contra el cwd del evento.
# Límite: ve el texto de la orden, no lo que ejecuta un script escrito antes,
# una variable que compone el nombre ni un cambio de rama; el cambio versionado
# del fichero lo revisa la operadora en su PR. Borrarlo o vaciarlo no da poder
# (sin claves ningún grant vale). Evento malformado o incompleto, o cualquier
# error al evaluarlo (excepción, python ausente): exit 2 (SE-453), nunca 0 ni 1.
GUARD_PY='
import fnmatch, glob, json, os, re, shlex, sys
def block(why):
    print("BLOQUEADO [operator-grant-guard]: " + why, file=sys.stderr); sys.exit(2)
ESC = {"a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "n": "\n", "r": "\r",
       "t": "\t", "v": "\v", "\\": "\\", "\x27": "\x27", "\"": "\"", "?": "?"}
ESC_RE = re.compile(r"\\(x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8}|0?[0-7]{1,3}|c.|.)", re.S)
def unescape(s):
    """Escapes de las comillas ANSI-C de bash (y de printf/echo -e): xHH, NNN, uHHHH, cX, n…"""
    def one(m):
        e = m.group(1)
        if e[0] in "xuU":
            return chr(int(e[1:], 16))
        if e[0] in "01234567":
            return chr(int(e, 8) & 0xFF)
        if e[0] == "c":
            return chr(ord(e[1].upper()) ^ 0x40) if e[1].isascii() else e[1]
        return ESC.get(e, "\\" + e)
    return ESC_RE.sub(one, s)
def ansi_c(s):
    # Comillas ANSI-C (dólar + comilla simple) → su contenido decodificado entre comillas
    # simples, con la comilla escapada; dólar + comilla doble (locale) → comilla doble.
    s = re.sub(r"\$\x27((?:[^\x27\\]|\\.)*)\x27",
               lambda m: "\x27" + unescape(m.group(1)).replace("\x27", "\x27\\\x27\x27") + "\x27", s, flags=re.S)
    return re.sub(r"\$\"", "\"", s)
MAX_ALTS = 512
def braces(t):
    """Expansión de llaves iterativa y acotada (una orden hostil no tumba el guard)."""
    out, todo, steps = [], [t], 0
    while todo:
        s = todo.pop()
        steps += 1
        m = re.search(r"\{([^{}]*)\}", s)
        if not m:
            out.append(s)
        else:
            todo.extend(s[:m.start()] + alt + s[m.end():] for alt in m.group(1).split(","))
        if len(out) + len(todo) > MAX_ALTS or steps > 20 * MAX_ALTS:
            block("orden con demasiadas expansiones de llaves para evaluarla")
    return out
def main():
    try:
        ev = json.load(sys.stdin)
    except ValueError:
        block("entrada no es JSON")
    if not isinstance(ev, dict):
        block("entrada no es un evento")
    tool, ti = ev.get("tool_name"), ev.get("tool_input")
    if not isinstance(tool, str) or not tool:
        block("evento sin tool_name")
    if not isinstance(ti, dict):
        block("evento sin tool_input evaluable")
    signers = os.path.realpath(os.environ["GUARD_SIGNERS_FILE"])
    marker = os.path.basename(signers)
    tail = os.path.join(os.path.basename(os.path.dirname(signers)), marker)
    # El nombre exacto, no uno más largo (operator-grant-signers-notes.md es otro fichero).
    named = re.compile(re.escape(marker) + r"(?![A-Za-z0-9_.-])")
    cwd = ev.get("cwd") if isinstance(ev.get("cwd"), str) and os.path.isdir(ev.get("cwd")) else os.getcwd()
    def deny():
        block(marker + " es la raíz de confianza del grant de merge; solo la operadora la cambia, por PR. Para leerla usa Read.")
    def is_signers(p):
        rp = os.path.realpath(os.path.join(cwd, os.path.expanduser(p)))
        # También la copia de otro worktree o checkout: <raíz>/config/operator-grant-signers.
        return rp == signers or rp.endswith(os.sep + tail)
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        paths = [ti.get(f) for f in ("file_path", "notebook_path") if ti.get(f) is not None]
        if not paths or not all(isinstance(p, str) and p for p in paths):
            block("evento " + tool + " sin ruta evaluable")
        if any(is_signers(p) for p in paths):
            deny()
    elif tool == "Bash":
        cmd = ti.get("command")
        if not isinstance(cmd, str):
            block("evento Bash sin command")
        cmd = ansi_c(re.sub(r"\\\n", "", cmd))
        for form in (cmd, unescape(cmd)):
            if named.search(re.sub(r"[\"\x27\\\\]", "", form)):
                deny()
        try:
            toks = shlex.split(cmd, comments=False, posix=True)
        except ValueError:
            toks = cmd.split()
        for tok in toks:
            for piece in re.split(r"[<>|;&=()`]", tok):
                for cand in braces(piece):
                    if not cand:
                        continue
                    if "{" in piece and is_signers(cand):
                        deny()
                    if any(c in cand for c in "*?["):
                        if any(is_signers(g) for g in glob.glob(os.path.join(cwd, os.path.expanduser(cand)))):
                            deny()
                        if ("signer" in cand or "operator-grant" in cand) and any(
                                fnmatch.fnmatchcase(x, cand) for x in (marker, tail, signers)):
                            deny()
    sys.exit(0)
try:
    main()
except SystemExit:
    raise
except BaseException as e:
    block("error al evaluar el evento (%s); sin evaluar no se deja pasar" % type(e).__name__)
'

guard_main() {
  local input="" rc=0
  if [[ ! -t 0 ]]; then input=$(timeout 3 cat 2>/dev/null) || true; fi
  [[ -z "$input" ]] && { echo "BLOQUEADO [operator-grant-guard]: sin entrada del hook" >&2; return 2; }
  printf '%s' "$input" | GUARD_SIGNERS_FILE="$SIGNERS_FILE" python3 -I -c "$GUARD_PY" || rc=$?
  # Claude Code solo bloquea con 2: cualquier otro fallo (python ausente = 127,
  # señal, excepción no prevista) sería fallo abierto.
  if (( rc != 0 )); then
    (( rc == 2 )) || echo "BLOQUEADO [operator-grant-guard]: el guard falló (exit $rc); sin evaluar no se deja pasar" >&2
    return 2
  fi
  return 0
}
[[ "${1:-}" == "guard" ]] && { guard_main; exit $?; }

# ── Parse ──────────────────────────────────────────────────────────────
ACTION="" SCOPE="" CONTEXT="" TTL="" GRANTOR="" SIGNATURE="" RESOURCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    grant|check|consume|revoke|list) ACTION="$1"; shift ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --scope=*) SCOPE="${1#--scope=}"; shift ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --context=*) CONTEXT="${1#--context=}"; shift ;;
    --ttl-hours) TTL="$2"; shift 2 ;;
    --ttl-hours=*) TTL="${1#--ttl-hours=}"; shift ;;
    --grantor) GRANTOR="$2"; shift 2 ;;
    --signature) SIGNATURE="$2"; shift 2 ;;
    --signature=*) SIGNATURE="${1#--signature=}"; shift ;;
    --resource) RESOURCE="$2"; shift 2 ;;
    --resource=*) RESOURCE="${1#--resource=}"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) shift ;;
  esac
done

[[ -z "$ACTION" ]] && { echo "ERROR: action required (grant|check|consume|revoke|list)" >&2; usage >&2; exit 2; }
[[ "$ACTION" == "list" ]] && {
  if [[ -d "$GRANTS_DIR" ]]; then
    ls -1 "$GRANTS_DIR"/*.json 2>/dev/null | while read -r f; do
      b="$(basename "$f" .json)"
      if check_scope "$b" "" "*"; then v=yes; else v=no; fi
      printf '%s\tvalid=%s\t%s\t%s\n' "$b" "$v" "$(python3 -I -c "$GRANT_PY" field "$f" resource)" \
        "$(python3 -I -c "$GRANT_PY" field "$f" request_context)"
    done
  fi
  exit 0
}

[[ -z "$SCOPE" ]] && { echo "ERROR: --scope required" >&2; exit 2; }
if ! valid_scope "$SCOPE"; then
  echo "ERROR: invalid scope '$SCOPE' (merge | autonomy:<skill>)" >&2; exit 2
fi

SLUG="$(active_slug)"

# merge: el grant vale para un recurso concreto (pr:N | task:ID), firmado.
if [[ "$SCOPE" == "merge" && ( "$ACTION" == "check" || "$ACTION" == "consume" || ( "$ACTION" == "grant" && -z "$SIGNATURE" ) ) ]]; then
  [[ "$RESOURCE" =~ ^(pr|task):[A-Za-z0-9._-]{1,64}$ ]] || {
    echo "ERROR: --resource pr:<n>|task:<id> required for scope merge" >&2; exit 2; }
fi

case "$ACTION" in
  check)
    check_scope "$SCOPE" "$SLUG" "$RESOURCE"
    exit $? ;;
  consume)
    # Uso único: solo un grant válido para ese recurso se gasta; su id queda
    # en merge.spent y check rechaza cualquier copia posterior.
    [[ "$SCOPE" == "merge" ]] || { echo "ERROR: consume solo aplica a --scope merge" >&2; exit 2; }
    check_scope merge "$SLUG" "$RESOURCE" || exit $?
    spend_scope merge consumed; exit $? ;;
  revoke)
    spend_scope "$SCOPE" revoked; exit $? ;;
  grant)
    if [[ -n "$SIGNATURE" ]]; then
      [[ "$SCOPE" == "merge" ]] || { echo "ERROR: --signature solo aplica a --scope merge" >&2; exit 2; }
      [[ -f "$(request_file merge)" ]] || { echo "ERROR: no hay petición pendiente; antes: grant --scope merge --context \"...\"" >&2; exit 2; }
      ensure_grants_dir
      ( umask 077
        python3 -I -c "$GRANT_PY" accept "$(request_file merge)" "$SIGNATURE" "$(scope_file merge)" \
          "$SIGNERS_FILE" "$SIG_NAMESPACE" "$SLUG" "$(spent_file merge)" "$(repo_id)" ) || exit $?
      rm -f "$(request_file merge)"
      RESOURCE="$(python3 -I -c "$GRANT_PY" field "$(scope_file merge)" resource)"
      echo "granted: merge $RESOURCE -> $SLUG (source operator-signature)"
      check_scope merge "$SLUG" "$RESOURCE"; exit $?
    fi
    [[ -z "$CONTEXT" ]] && { echo "ERROR: --context required (why is this grant being issued)" >&2; exit 2; }
    [[ -z "$TTL" ]] && TTL="$(default_ttl "$SCOPE")"
    # Fail-closed: sin operadora identificable no se emite un grant (antes se
    # escribía uno con grantor vacío que check rechazaba después).
    if [[ -z "$GRANTOR" && -z "$SLUG" ]]; then
      echo "ERROR: no active operator (active_slug in $ACTIVE_USER_FILE) — grant not issued" >&2
      exit 2
    fi
    if [[ "$SCOPE" == "merge" ]]; then
      [[ -n "$(repo_id)" ]] || {
        echo "ERROR: sin remoto origin identificable en $REPO_ROOT; el grant de merge se firma para un repositorio concreto" >&2
        exit 2; }
      echo "Petición de grant de merge pendiente de tu firma (todavía NO hay grant)."
      echo "Texto exacto a firmar, sin salto de línea final ($(request_file merge)):"
      emit request "$SCOPE" "$CONTEXT" "$TTL" "$SLUG" "$GRANTOR" "$RESOURCE"
      echo "Firma: ssh-keygen -Y sign -f <tu clave> -n $SIG_NAMESPACE <petición>"
      echo "Después: operator-grant.sh grant --scope merge --signature <petición>.sig (o --signature - y pega la firma)"
      exit 4
    fi
    emit write "$SCOPE" "$CONTEXT" "$TTL" "$SLUG" "$GRANTOR" ""
    echo "granted: $SCOPE -> $SLUG (ttl ${TTL}h, source express-request)"
    check_scope "$SCOPE" "$SLUG"; exit $? ;;
esac
exit 2
