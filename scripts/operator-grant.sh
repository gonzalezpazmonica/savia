#!/usr/bin/env bash
# operator-grant.sh — Deterministic operator-grant ledger (SE-343)
#
# Replaces manual env-var setup for autonomous skills and the binary
# "never merge" rule with a LOCAL, auditable grant ledger written by Savia
# ONLY on the operator's express request.
#
#   grant  --scope <autonomy:<skill>|merge> --context "<why>" [--ttl-hours N]
#   check  --scope <scope>          # exit 0 vigente | 1 no/expirado | 2 invalido | 3 sin grant
#   revoke --scope <scope>
#   list
#   guard                           # hook PreToolUse (lee el evento por stdin)
#
# Ledger: ~/.savia/grants/<scope>.json  (local infra, CRIT-001 — never in repo)
# Grantor: resolved from .claude/profiles/active-user.md (slug). NEVER "self".
#
# Scope merge (LAW-HUMAN-002, patrón Yema F4): emitir exige prueba de persona,
# medida y no afirmada — o la terminal de la operadora (escribe MERGE en
# /dev/tty, source=tty) o un ticket de un solo uso (5 min) que deja el hook
# `operator-grant.sh guard` al pedir el diálogo nativo del arnés, que el modelo no
# puede pulsar (source=harness-ask). El grant se firma con HMAC-SHA256 y una
# clave local fuera del repo (~/.savia/grant-keys/, 0600, vetada por el hook);
# check solo da por vigente un grant de merge cuya firma verifica.
#
# Exit: 0 ok | 1 not valid/expired | 2 invalid invocation | 3 no grant
#       4 merge grant refused: no proof of human interaction
# Ref: SE-343, SE-433 D7, SPEC-186, autonomous-safety.md

set -uo pipefail

GRANTS_DIR="${SAVIA_GRANTS_DIR:-$HOME/.savia/grants}"
GRANT_KEY_FILE="${SAVIA_GRANT_KEY_FILE:-$HOME/.savia/grant-keys/operator-grant.key}"
TICKETS_DIR="${SAVIA_GRANT_TICKETS_DIR:-$HOME/.savia/grant-tickets}"
TICKET_WINDOW_S=300
# Resuelto desde la raíz del repo (no desde el cwd); override para tests.
ACTIVE_USER_FILE="${SAVIA_ACTIVE_USER_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/profiles/active-user.md}"

usage() {
  cat <<'USAGE'
Usage: operator-grant.sh <grant|check|revoke|list> --scope SCOPE [opts]

Commands:
  grant   SCOPE  --context "reason" [--ttl-hours N]   emit grant (express request)
  check   SCOPE                                       exit: 0 vigente | 1 no | 2 inval | 3 sin grant
  revoke  SCOPE                                       revoke (remove file)
  list                                                show all grants
  guard                                               PreToolUse hook (event on stdin)

Scopes:
  autonomy:<skill>   enables double-optin "intent" factor for the skill
                     (overnight-sprint, code-improvement-loop, adversarial-security,
                      tech-research-agent, savia-dual)
  merge              enables PR merge (--merge in push-pr.sh)

Rules:
  - grantor = active user slug (active-user.md). NEVER "self".
  - source  = autonomy:* express-request; merge = canal medido (tty | harness-ask).
  - merge: exige la terminal de la operadora (escribir MERGE) o el ticket del
    diálogo de permisos del arnés, y se firma con HMAC (clave local fuera del
    repo). Sin prueba de persona: exit 4, no se escribe nada.
  - default TTL: autonomy:* = 24h, merge = 6h.
  - grant (idempotent): renews expires_at of an existing valid grant.
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

# JSON escapado y, para merge, firma HMAC-SHA256 sobre los campos canónicos.
# La clave solo se crea al emitir, después de la prueba de persona.
GRANT_PY='
import hashlib, hmac, json, os, secrets, sys
FIELDS = ("scope", "grantor", "source", "request_context", "issued_at", "expires_epoch")
def key(path, create):
    if os.path.exists(path):
        return bytes.fromhex(open(path).read().strip())
    if not create:
        return None
    d = os.path.dirname(path)
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    k = secrets.token_bytes(32)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(k.hex() + "\n")
    return k
def sig(rec, k):
    msg = json.dumps({f: rec.get(f) for f in FIELDS}, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hmac.new(k, msg.encode(), hashlib.sha256).hexdigest()
op = sys.argv[1]
if op == "write":
    out, keyfile, scope, grantor, source, ctx, issued, expires_at, exp = sys.argv[2:11]
    rec = {"scope": scope, "grantor": grantor, "source": source, "request_context": ctx,
           "issued_at": issued, "expires_at": expires_at, "expires_epoch": int(exp)}
    if scope == "merge":
        rec["sig"] = sig(rec, key(keyfile, True))
    with open(out, "w") as f:
        f.write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
elif op == "verify":
    path, keyfile = sys.argv[2:4]
    try:
        rec = json.load(open(path))
        k = key(keyfile, False)
    except (OSError, ValueError):
        sys.exit(1)
    ok = (k is not None and rec.get("source") in ("tty", "harness-ask")
          and isinstance(rec.get("sig"), str) and hmac.compare_digest(rec["sig"], sig(rec, k)))
    sys.exit(0 if ok else 1)
'

# Ticket que deja guard_main: liga la respuesta del diálogo a
# este scope y a este contexto exactos (mismo cálculo en el hook).
ticket_file() {
  local h
  h="$(printf '%s\n%s' "$1" "$2" | sha256sum | cut -c1-16)"
  printf '%s/%s-%s.json' "$TICKETS_DIR" "$1" "$h"
}

# Prueba de persona para merge. Imprime el canal medido o devuelve 1.
human_presence() {
  local scope="$1" context="$2" t ts answer
  if [[ -t 0 ]] && { : < /dev/tty; } 2>/dev/null; then
    printf 'Grant de merge: «%s». Escribe MERGE para concederlo: ' "$context" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    [[ "$answer" == "MERGE" ]] && { echo tty; return 0; }
    return 1
  fi
  t="$(ticket_file "$scope" "$context")"
  [[ -f "$t" ]] || return 1
  ts="$(grep -oP '"ts":\s*\K[0-9]+' "$t" 2>/dev/null | head -1)"
  unlink "$t" 2>/dev/null   # un solo uso, también si está caducado
  [[ -n "$ts" ]] && (( $(now_epoch) - ts <= TICKET_WINDOW_S )) || return 1
  echo harness-ask
}

write_grant() {
  local scope="$1" context="$2" ttl="$3" slug="$4" grantor="$5" source="$6"
  local file now exp expires_at
  file="$(scope_file "$scope")"
  mkdir -p "$GRANTS_DIR" 2>/dev/null || { echo "ERROR: cannot create $GRANTS_DIR" >&2; exit 2; }
  chmod 700 "$GRANTS_DIR" 2>/dev/null || true
  now="$(now_epoch)"
  exp=$(( now + ttl * 3600 ))
  # Reuse existing grantor if already present (stability); else active slug.
  if [[ -z "$grantor" && -f "$(scope_file "$scope")" ]]; then
    grantor="$(grep -oP '"grantor":\s*"\K[^"]+' "$(scope_file "$scope")" 2>/dev/null | head -1 || true)"
  fi
  [[ -z "$grantor" ]] && grantor="$slug"
  expires_at="$(date -u -d @"$exp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$exp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "epoch-$exp")"
  ( umask 077
    python3 -c "$GRANT_PY" write "$file" "$GRANT_KEY_FILE" "$scope" "$grantor" "$source" "$context" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$expires_at" "$exp" ) \
    || { echo "ERROR: cannot write grant $file" >&2; exit 2; }
  chmod 600 "$file" 2>/dev/null || true
}

check_scope() {
  local scope="$1" slug="$2"
  local file exp expires_at grantor
  file="$(scope_file "$scope")"
  [[ ! -f "$file" ]] && return 3
  exp="$(grep -oP '"expires_epoch":\s*\K[0-9]+' "$file" 2>/dev/null | head -1)"
  if [[ -z "$exp" ]]; then
    expires_at="$(grep -oP '"expires_at":\s*"\K[^"]+' "$file" 2>/dev/null | head -1)"
    exp="$(date -u -d "$expires_at" +%s 2>/dev/null || echo 0)"
  fi
  [[ "$(( $(now_epoch) ))" -gt "$exp" ]] && return 1
  grantor="$(grep -oP '"grantor":\s*"\K[^"]+' "$file" 2>/dev/null | head -1)"
  # A valid grant must be tied to the ACTIVE operator, never self/empty.
  if [[ -z "$grantor" || "$grantor" == "self" ]]; then return 1; fi
  if [[ -n "$slug" && "$grantor" != "$slug" ]]; then return 1; fi
  # merge: la firma HMAC es la única prueba aceptada de que hubo persona.
  if [[ "$scope" == "merge" ]]; then
    python3 -c "$GRANT_PY" verify "$file" "$GRANT_KEY_FILE" || return 1
  fi
  return 0
}

# ── guard: hook PreToolUse (registro en .claude/settings.json, matcher
# "Bash|Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob", orden
# `"$CLAUDE_PROJECT_DIR"/scripts/operator-grant.sh guard`) ──────────────────
# 1. `grant --scope merge` nunca pasa en silencio: en bypassPermissions/dontAsk
#    deniega (exit 2); si no, deja un ticket de un solo uso ligado a
#    scope+contexto y responde «ask», el diálogo que el modelo no puede pulsar.
# 2. Veta a las herramientas la clave HMAC y los tickets: rutas, carpetas que
#    los contienen y las variables que los redirigen.
# Límite: ve el texto de la orden, no lo que ejecuta un script escrito antes.
# Sin entrada evaluable: exit 2 (SE-453), nunca 0 sin evaluar.
GUARD_PY='
import hashlib, json, os, shlex, sys, time
try:
    ev = json.load(sys.stdin)
except ValueError:
    print("BLOQUEADO [operator-grant-guard]: entrada no es JSON", file=sys.stderr); sys.exit(2)
tool = ev.get("tool_name", "")
ti = ev.get("tool_input") or {}
key_file = os.path.realpath(os.path.expanduser(os.environ["GUARD_KEY_FILE"]))
tickets = os.path.realpath(os.path.expanduser(os.environ["GUARD_TICKETS_DIR"]))
protected = [os.path.dirname(key_file), tickets]
markers = [os.path.basename(p) for p in protected] + [os.path.basename(key_file),
           "SAVIA_GRANT_KEY_FILE", "SAVIA_GRANT_TICKETS_DIR"]
VETO = "la clave de grants y los tickets de aprobación no son accesibles a las herramientas"

def deny(why):
    print("BLOQUEADO [operator-grant-guard]: " + why, file=sys.stderr); sys.exit(2)

def touches(path):
    if not isinstance(path, str) or not path:
        return False
    if any(m in path for m in markers):
        return True
    rp = os.path.realpath(os.path.expanduser(path))
    # La ruta protegida o una carpeta que la contenga (Grep/Glob la leerían entera).
    return any(rp == p or p.startswith(rp.rstrip("/") + "/") for p in protected)

if tool != "Bash":
    for f in ("file_path", "path", "notebook_path"):
        if touches(ti.get(f)):
            deny(VETO)
    if tool == "Glob" and touches(ti.get("pattern")):
        deny(VETO)
    sys.exit(0)

cmd = ti.get("command") or ""
if any(m in cmd for m in markers):
    deny(VETO)
if "operator-grant" not in cmd:
    sys.exit(0)

def merge_grant(cmd):
    """(es grant de merge, contexto; None si no se lee con certeza)."""
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()")
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        return True, None
    found, res = False, None
    for i, t in enumerate(toks):
        if "operator-grant" not in t:
            continue
        seg = []
        for u in toks[i + 1:]:
            if u and all(c in ";&|()" for c in u):
                break
            seg.append(u)
        scope = ctx = None
        j = 0
        while j < len(seg):
            a = seg[j]
            if a in ("--scope", "--context") and j + 1 < len(seg):
                if a == "--scope":
                    scope = seg[j + 1]
                else:
                    ctx = seg[j + 1]
                j += 2
                continue
            if a.startswith("--scope="):
                scope = a.split("=", 1)[1]
            if a.startswith("--context="):
                ctx = a.split("=", 1)[1]
            j += 1
        if "grant" in seg and scope in ("merge", None):
            if found:
                return True, None   # dos emisiones en una orden: sin ticket
            found, res = True, (ctx if scope == "merge" else None)
    if found:
        return True, res
    # Mención sin invocación legible (eval, base64, variables): se pregunta sin ticket.
    return ("grant" in cmd.replace("=", " ").split() and "merge" in cmd), None

is_merge, ctx = merge_grant(cmd)
if not is_merge:
    sys.exit(0)
mode = ev.get("permission_mode", "")
if mode in ("bypassPermissions", "dontAsk"):
    deny("el grant de merge lo concede una persona y el modo " + mode + " no pregunta. Cambia a modo normal o usa tu terminal.")
if ctx:
    h = hashlib.sha256(("merge\n" + ctx).encode()).hexdigest()[:16]
    os.makedirs(tickets, mode=0o700, exist_ok=True)
    with open(os.path.join(tickets, "merge-" + h + ".json"), "w") as f:
        json.dump({"ts": int(time.time())}, f)
reason = "Grant de merge (LAW-HUMAN-002): solo la operadora lo concede. Contexto: " + (ctx or "(no legible: el grant se rechazará)")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
      "permissionDecision": "ask", "permissionDecisionReason": reason}}, ensure_ascii=False))
'

guard_main() {
  local input=""
  if [[ ! -t 0 ]]; then input=$(timeout 3 cat 2>/dev/null) || true; fi
  [[ -z "$input" ]] && { echo "BLOQUEADO [operator-grant-guard]: sin entrada del hook" >&2; return 2; }
  printf '%s' "$input" | GUARD_KEY_FILE="$GRANT_KEY_FILE" GUARD_TICKETS_DIR="$TICKETS_DIR" python3 -c "$GUARD_PY"
}
[[ "${1:-}" == "guard" ]] && { guard_main; exit $?; }

# ── Parse ──────────────────────────────────────────────────────────────
ACTION="" SCOPE="" CONTEXT="" TTL="" GRANTOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    grant|check|revoke|list) ACTION="$1"; shift ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --scope=*) SCOPE="${1#--scope=}"; shift ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --context=*) CONTEXT="${1#--context=}"; shift ;;
    --ttl-hours) TTL="$2"; shift 2 ;;
    --ttl-hours=*) TTL="${1#--ttl-hours=}"; shift ;;
    --grantor) GRANTOR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) shift ;;
  esac
done

[[ -z "$ACTION" ]] && { echo "ERROR: action required (grant|check|revoke|list)" >&2; usage >&2; exit 2; }
[[ "$ACTION" == "list" ]] && {
  if [[ -d "$GRANTS_DIR" ]]; then
    ls -1 "$GRANTS_DIR"/*.json 2>/dev/null | while read -r f; do
      b="$(basename "$f" .json)"
      if check_scope "$b" ""; then v=yes; else v=no; fi
      printf '%s\tvalid=%s\t%s\n' "$b" "$v" "$(grep -oP '"request_context":\s*"\K[^"]+' "$f" 2>/dev/null | head -1)"
    done
  fi
  exit 0
}

[[ -z "$SCOPE" ]] && { echo "ERROR: --scope required" >&2; exit 2; }
if ! valid_scope "$SCOPE"; then
  echo "ERROR: invalid scope '$SCOPE' (merge | autonomy:<skill>)" >&2; exit 2
fi

SLUG="$(active_slug)"

case "$ACTION" in
  check)
    check_scope "$SCOPE" "$SLUG"
    exit $? ;;
  revoke)
    rm -f "$(scope_file "$SCOPE")" 2>/dev/null; exit 0 ;;
  grant)
    [[ -z "$CONTEXT" ]] && { echo "ERROR: --context required (why is this grant being issued)" >&2; exit 2; }
    [[ -z "$TTL" ]] && TTL="$(default_ttl "$SCOPE")"
    # Fail-closed: sin operadora identificable no se emite un grant (antes se
    # escribía uno con grantor vacío que check rechazaba después).
    if [[ -z "$GRANTOR" && -z "$SLUG" ]]; then
      echo "ERROR: no active operator (active_slug in $ACTIVE_USER_FILE) — grant not issued" >&2
      exit 2
    fi
    SOURCE="express-request"
    if [[ "$SCOPE" == "merge" ]]; then
      if ! SOURCE="$(human_presence "$SCOPE" "$CONTEXT")"; then
        echo "ERROR: un grant de merge exige a la operadora: su terminal (escribir MERGE) o el diálogo de permisos del arnés (ticket de operator-grant.sh guard). Grant no emitido." >&2
        exit 4
      fi
    fi
    write_grant "$SCOPE" "$CONTEXT" "$TTL" "$SLUG" "$GRANTOR" "$SOURCE"
    echo "granted: $SCOPE -> $SLUG (ttl ${TTL}h, source $SOURCE)"
    check_scope "$SCOPE" "$SLUG"; exit $? ;;
esac
exit 2
