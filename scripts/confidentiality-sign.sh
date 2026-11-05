#!/usr/bin/env bash
set -uo pipefail
# confidentiality-sign.sh — Cryptographic signature for confidentiality audit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIG_FILE="${CONFIDENTIALITY_SIG_FILE:-$ROOT_DIR/.confidentiality-signature}"  # override: tests/aislamiento
SECRET_FILE="$HOME/.savia/confidentiality-key"
ACTION="${1:-status}"

get_diff_hash() {
  cd "$ROOT_DIR" || exit 2
  # Hash the HEAD tree of all tracked files, excluding self-referencing files.
  # Uses git's content-addressed blob SHAs (ls-tree output) — fully deterministic
  # across environments (no diff format dependencies, no merge-base volatility).
  # Rationale: signature asserts approval of a specific tree state. Any commit
  # that changes tracked files → tree changes → sig invalid. Rebase/merge that
  # doesn't touch tracked files → tree unchanged → sig still valid. See SPEC-111.
  git ls-tree -r HEAD \
    | awk -F'\t' '$2 != ".confidentiality-signature" && $2 != ".github/workflows/confidentiality-gate.yml"' \
    | sha256sum | awk '{print $1}'
}

# Clave: CONFIDENTIALITY_HMAC_KEY (secreto de CI) o el fichero local; vacía = ausente.
# CONFIDENTIALITY_REQUIRE_HMAC=1: sin clave, sign y verify fallan cerrado.
hmac_key() {
  # El secreto de CI puede llegar con salto de línea final; se trata igual que el fichero.
  local env_key="${CONFIDENTIALITY_HMAC_KEY:-}"
  env_key="${env_key//[$'\r\n']/}"
  if [ -n "$env_key" ]; then printf '%s' "$env_key"
  elif [ -f "$SECRET_FILE" ]; then cat "$SECRET_FILE" 2>/dev/null | tr -d '\n'
  fi
}

require_hmac() { [ "${CONFIDENTIALITY_REQUIRE_HMAC:-0}" = "1" ]; }

ensure_secret() {
  [ -n "$(hmac_key)" ] && return 0
  if require_hmac; then
    echo "ERROR: HMAC requerido y sin clave: define CONFIDENTIALITY_HMAC_KEY o $SECRET_FILE" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$SECRET_FILE")"
  openssl rand -hex 32 > "$SECRET_FILE" 2>/dev/null \
    || head -c 32 /dev/urandom | xxd -p -c 64 > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
}

# La clave va por stdin, nunca en argv (visible en ps).
compute_hmac() {
  { hmac_key; printf '\n%s' "$1"; } | python3 -c 'import hmac,hashlib,sys; k,m=sys.stdin.read().split("\n",1); print(hmac.new(k.encode(),m.encode(),hashlib.sha256).hexdigest())'
}

do_sign() {
  echo "Confidentiality Signature — Sign"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ensure_secret
  local diff_hash branch head_commit signature
  diff_hash=$(get_diff_hash)
  branch=$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
  head_commit=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null)
  signature=$(compute_hmac "$diff_hash")
  cat > "$SIG_FILE" <<SIGEOF
# Confidentiality audit signature — DO NOT EDIT
diff_hash=$diff_hash
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
branch=$branch
head_commit=$head_commit
signature=$signature
SIGEOF
  echo "SIGNED  hash=${diff_hash:0:16}..."
}

do_verify() {
  echo "Confidentiality Signature — Verify"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [ ! -f "$SIG_FILE" ]; then
    echo "ERROR: No .confidentiality-signature file."
    exit 1
  fi
  local saved_diff saved_sig
  saved_diff=$(grep '^diff_hash=' "$SIG_FILE" | cut -d= -f2)
  saved_sig=$(grep '^signature=' "$SIG_FILE" | cut -d= -f2)
  [ -z "$saved_diff" ] || [ -z "$saved_sig" ] && echo "ERROR: Malformed." && exit 1
  local current_diff
  current_diff=$(get_diff_hash)
  echo "  Saved:   ${saved_diff:0:24}..."
  echo "  Current: ${current_diff:0:24}..."
  if [ "$current_diff" != "$saved_diff" ]; then
    echo "ERROR: Diff hash mismatch."
    exit 1
  fi
  if [ -n "$(hmac_key)" ]; then
    [ "$(compute_hmac "$saved_diff")" != "$saved_sig" ] && echo "ERROR: HMAC mismatch." && exit 1
    echo "  HMAC: VERIFIED"
  elif require_hmac; then
    echo "ERROR: HMAC requerido y sin clave: define CONFIDENTIALITY_HMAC_KEY (secreto de CI)"
    exit 1
  else
    echo "  HMAC: SKIPPED (no local key at $SECRET_FILE)"
    echo "  WARNING: Verification is diff-hash only — no cryptographic proof" >&2
  fi
  echo "  Diff: MATCH"
  echo "VERIFIED"
}

# Para los firmantes automáticos (bots): firma y comprueba la firma recién escrita.
# Nunca deja una firma obsoleta en silencio: si falta la clave o la verificación falla, sale != 0.
do_resign() {
  export CONFIDENTIALITY_REQUIRE_HMAC=1   # un bot nunca firma con clave efímera
  local rc=0
  do_sign || rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q "^signature=" "$SIG_FILE" 2>/dev/null; then
    echo "ERROR: re-firma fallida: no se ha generado una firma válida (¿CONFIDENTIALITY_HMAC_KEY?)" >&2
    exit 1
  fi
  ( do_verify ) >/dev/null || { echo "ERROR: re-firma fallida: la firma recién escrita no verifica" >&2; exit 1; }
  echo "RESIGNED"
}

do_status() {
  [ ! -f "$SIG_FILE" ] && echo "No signature." && exit 0
  grep -v '^#' "$SIG_FILE" | grep -v '^$'
}

# verify-main <sha|ref> [--repo owner/name] — SE-501 I2 (antes confidentiality-main-verify.sh):
# prueba de que un commit de main pasó la auditoría completa. La prueba es una ejecución de
# .github/workflows/confidentiality-main.yml con event=push, head_branch=main, head_sha=<X> y
# conclusion=success. Un commit status o un check publicado por una PR no cuentan: una PR con
# statuses: write podría falsificarlos; una ejecución push en main no.
# Salida: 0 hay prueba · 1 no la hay · 2 error (API caída, respuesta no JSON, sha ilegible). Fail-closed.
# Entorno: SAVIA_GH (binario gh, para tests) · SAVIA_GH_REPO (repo por defecto).
do_verify_main() {
  local gh="${SAVIA_GH:-gh}" wf=".github/workflows/confidentiality-main.yml" ref="" repo="${SAVIA_GH_REPO:-}" sha raw
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) repo="${2:-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
      *) ref="$1"; shift ;;
    esac
  done
  [ -n "$ref" ] || { echo "uso: confidentiality-sign.sh verify-main <sha|ref>" >&2; exit 2; }
  if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then sha="$ref"
  else sha=$(git rev-parse -q --verify "$ref^{commit}" 2>/dev/null) || { echo "FAIL: ref ilegible: $ref" >&2; exit 2; }; fi
  if [ -z "$repo" ]; then
    repo=$($gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) \
      || { echo "FAIL: no se pudo resolver el repo" >&2; exit 2; }
  fi
  raw=$($gh api "repos/$repo/actions/runs?head_sha=$sha&per_page=100" 2>/dev/null) \
    || { echo "FAIL: la API de GitHub no respondió; sin prueba para ${sha:0:12}" >&2; exit 2; }
  SAVIA_RAW="$raw" python3 - "$sha" "$wf" <<'PY'
import json, os, sys
sha, wf = sys.argv[1], sys.argv[2]
try:
    runs = json.loads(os.environ["SAVIA_RAW"])["workflow_runs"]
    assert isinstance(runs, list)
except Exception:
    print("FAIL: respuesta de la API no válida", file=sys.stderr); sys.exit(2)
ok = [r for r in runs if isinstance(r, dict) and r.get("path") == wf and r.get("event") == "push"
      and r.get("head_branch") == "main" and r.get("head_sha") == sha and r.get("conclusion") == "success"]
if ok:
    print(f"PASS: {sha[:12]} auditado en main (run {ok[0].get('id')})"); sys.exit(0)
print(f"FAIL: ninguna ejecución push de {wf} en main con éxito para {sha[:12]}"); sys.exit(1)
PY
  exit $?
}

# SE-501: firma retirada del flujo. La prueba de que main pasó la auditoría es una ejecución de
# confidentiality-main.yml (verify-main); la PR pasa «Confidentiality scan (PR)».
# Este script verifica firmas históricas (verify/status) y la prueba de main; sign y resign ya no escriben nada.
retired() {
  echo "confidentiality-sign.sh $ACTION: retirado (SE-501). La firma ya no se versiona: usa" >&2
  echo "  bash scripts/confidentiality-scan.sh --pr (PR) · bash scripts/confidentiality-sign.sh verify-main <sha> (main)" >&2
  exit 2
}
case "$ACTION" in
  sign|resign) retired ;;
  verify) do_verify ;;
  verify-main) shift; do_verify_main "$@" ;;
  status) do_status ;;
  *) echo "Usage: $0 {verify|verify-main <sha>|status} (sign/resign retirados por SE-501)"; exit 2 ;;
esac
