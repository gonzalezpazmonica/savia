#!/usr/bin/env bash
# operator-grant.sh — Deterministic operator-grant ledger (SE-343)
#
# Replaces manual env-var setup for autonomous skills and the binary
# "never merge" rule with a LOCAL, auditable grant ledger written by Savia
# ONLY on the operator's express request.
#
#   grant  --scope <autonomy:<skill>|merge> --context "<why>" [--ttl-hours N]
#   grant  --scope merge --signature <fichero|->   # incorpora la firma de la operadora
#   check  --scope <scope>          # exit 0 vigente | 1 no/expirado | 2 invalido | 3 sin grant
#   revoke --scope <scope>
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
Usage: operator-grant.sh <grant|check|revoke|list> --scope SCOPE [opts]

Commands:
  grant   SCOPE  --context "reason" [--ttl-hours N]   emit grant (express request)
  grant   merge  --signature FILE|-                   attach the operator's signature
  check   SCOPE                                       exit: 0 vigente | 1 no | 2 inval | 3 sin grant
  revoke  SCOPE                                       revoke (remove grant and pending request)
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
request_file() { printf '%s/%s.request' "$GRANTS_DIR" "$1"; }

# JSON escapado (un --context con comillas no inyecta campos) y, para merge,
# petición canónica + verificación de la firma de la operadora con ssh-keygen.
GRANT_PY='
import json, os, subprocess, sys, tempfile, time
FIELDS = ("scope", "grantor", "request_context", "issued_at", "expires_at", "expires_epoch")
def payload(rec):
    """Bytes exactos que firma la operadora."""
    return json.dumps({f: rec.get(f) for f in FIELDS}, sort_keys=True,
                      ensure_ascii=True, separators=(",", ":")).encode()
def verify(rec, sig, signers, ns):
    g = rec.get("grantor")
    if not (isinstance(sig, str) and "BEGIN SSH SIGNATURE" in sig and os.path.isfile(signers)
            and isinstance(g, str) and g and not g.startswith("-")
            and isinstance(rec.get("expires_epoch"), int) and rec["expires_epoch"] >= time.time()):
        return False
    with tempfile.TemporaryDirectory() as d:
        sp = os.path.join(d, "grant.sig")
        with open(sp, "w") as f:
            f.write(sig)
        try:
            r = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", signers, "-I", g, "-n", ns, "-s", sp],
                               input=payload(rec), capture_output=True, timeout=15)
        except (OSError, subprocess.SubprocessError):
            return False
    return r.returncode == 0
def dump(path, rec):
    with open(path, "w") as f:
        f.write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
op = sys.argv[1]
if op in ("write", "request"):
    out, scope, grantor, source, ctx, issued, expires_at, exp = sys.argv[2:10]
    rec = {"scope": scope, "grantor": grantor, "source": source, "request_context": ctx,
           "issued_at": issued, "expires_at": expires_at, "expires_epoch": int(exp)}
    if op == "write":
        dump(out, rec)
    else:
        with open(out, "wb") as f:
            f.write(payload(rec))
        print(payload(rec).decode())
elif op == "accept":
    req, sigsrc, out, signers, ns, slug = sys.argv[2:8]
    try:
        raw = open(req, "rb").read()
        rec = json.loads(raw)
        sig = sys.stdin.read() if sigsrc == "-" else open(sigsrc).read()
    except (OSError, ValueError) as e:
        print("ERROR: petición o firma ilegible: %s" % e, file=sys.stderr); sys.exit(2)
    if not isinstance(rec, dict) or rec.get("scope") != "merge" or payload(rec) != raw:
        print("ERROR: la petición no es canónica (alterada)", file=sys.stderr); sys.exit(1)
    if slug and rec.get("grantor") != slug:
        print("ERROR: la petición es de otra operadora", file=sys.stderr); sys.exit(1)
    if not verify(rec, sig, signers, ns):
        print("ERROR: firma no válida para esta petición (clave, namespace, caducidad o contenido)", file=sys.stderr); sys.exit(1)
    rec.update(source="operator-signature", sig=sig)
    dump(out, rec)
elif op == "verify":
    path, signers, ns = sys.argv[2:5]
    try:
        rec = json.load(open(path))
    except (OSError, ValueError):
        sys.exit(1)
    ok = (isinstance(rec, dict) and rec.get("scope") == "merge"
          and rec.get("source") == "operator-signature" and verify(rec, rec.get("sig"), signers, ns))
    sys.exit(0 if ok else 1)
'

# Campos de un grant nuevo, uno por línea: grantor, issued_at, expires_at, epoch.
grant_fields() {
  local scope="$1" ttl="$2" slug="$3" grantor="$4" now exp
  now="$(now_epoch)"
  exp=$(( now + ttl * 3600 ))
  # Reuse existing grantor if already present (stability); else active slug.
  if [[ -z "$grantor" && -f "$(scope_file "$scope")" ]]; then
    grantor="$(grep -oP '"grantor":\s*"\K[^"]+' "$(scope_file "$scope")" 2>/dev/null | head -1 || true)"
  fi
  [[ -z "$grantor" ]] && grantor="$slug"
  printf '%s\n%s\n%s\n%s\n' "$grantor" \
    "$(date -u -d @"$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "epoch-$now")" \
    "$(date -u -d @"$exp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$exp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "epoch-$exp")" \
    "$exp"
}

ensure_grants_dir() {
  mkdir -p "$GRANTS_DIR" 2>/dev/null || { echo "ERROR: cannot create $GRANTS_DIR" >&2; exit 2; }
  chmod 700 "$GRANTS_DIR" 2>/dev/null || true
}

# op = write (autonomy:*, grant en vigor) | request (merge, pendiente de firma).
emit() {
  local op="$1" scope="$2" context="$3" ttl="$4" slug="$5" grantor="$6" out f
  ensure_grants_dir
  mapfile -t f < <(grant_fields "$scope" "$ttl" "$slug" "$grantor")
  if [[ "$op" == "write" ]]; then out="$(scope_file "$scope")"; else out="$(request_file "$scope")"; fi
  ( umask 077
    python3 -c "$GRANT_PY" "$op" "$out" "$scope" "${f[0]}" express-request "$context" "${f[1]}" "${f[2]}" "${f[3]}" ) \
    || { echo "ERROR: cannot write $out" >&2; exit 2; }
  chmod 600 "$out" 2>/dev/null || true
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
  # merge: la firma de la operadora es la única prueba aceptada de que hubo persona.
  if [[ "$scope" == "merge" ]]; then
    python3 -c "$GRANT_PY" verify "$file" "$SIGNERS_FILE" "$SIG_NAMESPACE" || return 1
  fi
  return 0
}

# ── guard: hook PreToolUse (registro en .claude/settings.json, matcher
# "Bash|Edit|Write|MultiEdit|NotebookEdit", orden
# `"$CLAUDE_PROJECT_DIR"/scripts/operator-grant.sh guard`) ──────────────────
# Veta a las herramientas modificar la raíz de confianza
# (config/operator-grant-signers): con ella, un agente añadiría su propia clave
# pública y firmaría él. Leerla con Read sigue permitido (es pública).
# Límite: ve el texto de la orden, no lo que ejecuta un script escrito antes ni
# un cambio de rama; el cambio versionado del fichero lo revisa la operadora en
# su PR. Sin entrada evaluable: exit 2 (SE-453), nunca 0 sin evaluar.
GUARD_PY='
import json, os, sys
try:
    ev = json.load(sys.stdin)
except ValueError:
    print("BLOQUEADO [operator-grant-guard]: entrada no es JSON", file=sys.stderr); sys.exit(2)
if not isinstance(ev, dict):
    print("BLOQUEADO [operator-grant-guard]: entrada no es un evento", file=sys.stderr); sys.exit(2)
tool = ev.get("tool_name", "")
ti = ev.get("tool_input") or {}
signers = os.path.realpath(os.environ["GUARD_SIGNERS_FILE"])
marker = os.path.basename(signers)
def deny():
    print("BLOQUEADO [operator-grant-guard]: " + marker + " es la raíz de confianza del grant de merge;"
          " solo la operadora la cambia, por PR. Para leerla usa Read.", file=sys.stderr)
    sys.exit(2)
if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
    for f in ("file_path", "notebook_path"):
        p = ti.get(f)
        if isinstance(p, str) and p and (marker in p or os.path.realpath(os.path.expanduser(p)) == signers):
            deny()
elif tool == "Bash" and marker in str(ti.get("command") or ""):
    deny()
sys.exit(0)
'

guard_main() {
  local input=""
  if [[ ! -t 0 ]]; then input=$(timeout 3 cat 2>/dev/null) || true; fi
  [[ -z "$input" ]] && { echo "BLOQUEADO [operator-grant-guard]: sin entrada del hook" >&2; return 2; }
  printf '%s' "$input" | GUARD_SIGNERS_FILE="$SIGNERS_FILE" python3 -c "$GUARD_PY"
}
[[ "${1:-}" == "guard" ]] && { guard_main; exit $?; }

# ── Parse ──────────────────────────────────────────────────────────────
ACTION="" SCOPE="" CONTEXT="" TTL="" GRANTOR="" SIGNATURE=""

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
    --signature) SIGNATURE="$2"; shift 2 ;;
    --signature=*) SIGNATURE="${1#--signature=}"; shift ;;
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
    rm -f "$(scope_file "$SCOPE")" "$(request_file "$SCOPE")" 2>/dev/null; exit 0 ;;
  grant)
    if [[ -n "$SIGNATURE" ]]; then
      [[ "$SCOPE" == "merge" ]] || { echo "ERROR: --signature solo aplica a --scope merge" >&2; exit 2; }
      [[ -f "$(request_file merge)" ]] || { echo "ERROR: no hay petición pendiente; antes: grant --scope merge --context \"...\"" >&2; exit 2; }
      ensure_grants_dir
      ( umask 077
        python3 -c "$GRANT_PY" accept "$(request_file merge)" "$SIGNATURE" "$(scope_file merge)" \
          "$SIGNERS_FILE" "$SIG_NAMESPACE" "$SLUG" ) || exit $?
      rm -f "$(request_file merge)"
      echo "granted: merge -> $SLUG (source operator-signature)"
      check_scope merge "$SLUG"; exit $?
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
      echo "Petición de grant de merge pendiente de tu firma (todavía NO hay grant)."
      echo "Texto exacto a firmar, sin salto de línea final ($(request_file merge)):"
      emit request "$SCOPE" "$CONTEXT" "$TTL" "$SLUG" "$GRANTOR"
      echo "Firma: ssh-keygen -Y sign -f <tu clave> -n $SIG_NAMESPACE <petición>"
      echo "Después: operator-grant.sh grant --scope merge --signature <petición>.sig (o --signature - y pega la firma)"
      exit 4
    fi
    emit write "$SCOPE" "$CONTEXT" "$TTL" "$SLUG" "$GRANTOR"
    echo "granted: $SCOPE -> $SLUG (ttl ${TTL}h, source express-request)"
    check_scope "$SCOPE" "$SLUG"; exit $? ;;
esac
exit 2
