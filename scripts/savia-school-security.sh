#!/bin/bash
# Savia School Security Layer: Encryption, Access Control, GDPR
# Datos de menores: falla en cerrado; nada de contenido ni claves en argv ni logs.
# Max 150 lines

set -euo pipefail
umask 077

SCHOOL_BASE="${SCHOOL_BASE:-${SCHOOL_ROOT:-.}}"  # SCHOOL_ROOT: compatibilidad
SCHOOL_DIR="${SCHOOL_BASE}/school-savia"
ENCRYPTION_KEY_FILE="${SCHOOL_KEY_FILE:-${HOME}/.school-keys/encryption.key}"
AUDIT_LOG="${SCHOOL_DIR}/.audit.log"
KDF_ITER=200000

die() { echo "❌ $*" >&2; exit 1; }
usage() { echo "Usage: $0 {verify-role|check-isolation|encrypt-eval|decrypt-eval|audit-access|gdpr-consent|filter-content} ..." >&2; exit 2; }
need() { [ "$1" -ge "$2" ] || usage; }
valid_alias() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]] || die "Invalid alias"; }
current_user() { printf '%s' "${USER:-$(id -un)}" | tr -cd 'A-Za-z0-9._-'; }
teacher_of() { sed -n 's/^teacher:[[:space:]]*//p' "${SCHOOL_DIR}/.school-config.md" 2>/dev/null | head -1; }

# ── Verify Role ───────────────────────────────────────────────────────────────
verify_role() {
  local handle="$1" teacher
  teacher="$(teacher_of)"
  if [ -n "${teacher}" ] && [ "${handle}" = "${teacher}" ]; then echo "teacher"
  elif [[ "${handle}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]] && \
       [ -d "${SCHOOL_DIR}/classroom/${handle}" ]; then echo "student"
  else echo "unknown"; fi
}

# ── Check Student Isolation: carpeta propia, real y sin acceso de grupo/otros ─
check_student_isolation() {
  valid_alias "$1"
  local d="${SCHOOL_DIR}/classroom/$1"
  [ -d "$d" ] && [ ! -L "$d" ] || die "Access denied: $1"
  [[ "$(stat -c %a "$d")" == *00 ]] || die "Isolation broken: $1 readable by group/others"
  echo "✅ Student isolation verified: $1"
}

# ── Key: 32 bytes (64 hex), 0600, del usuario actual; se crea si falta ────────
load_key() {
  if [ ! -e "${ENCRYPTION_KEY_FILE}" ]; then
    mkdir -p -m 700 "$(dirname "${ENCRYPTION_KEY_FILE}")"
    openssl rand -hex 32 > "${ENCRYPTION_KEY_FILE}"
  fi
  [ -f "${ENCRYPTION_KEY_FILE}" ] && [ -O "${ENCRYPTION_KEY_FILE}" ] || die "Key file not owned by current user"
  [ "$(stat -c %a "${ENCRYPTION_KEY_FILE}")" = "600" ] || die "Key file permissions must be 0600"
  local k; k="$(tr -d '[:space:]' < "${ENCRYPTION_KEY_FILE}")"
  [[ "$k" =~ ^[0-9a-fA-F]{64}$ ]] || \
    { [[ "$k" =~ ^[A-Za-z0-9+/]{43}=$ ]] && [ "$(printf '%s' "$k" | base64 -d | wc -c)" -eq 32 ]; } || \
    die "Invalid key: expected 32 random bytes (openssl rand -hex 32)"
}

# HMAC-SHA256(stdin) con clave derivada de la clave maestra, sin exponerla en argv.
hmac_hex() {
  local mk ipad="" opad="" i b
  mk="$(tr -d '[:space:]' < "${ENCRYPTION_KEY_FILE}" | openssl dgst -sha256 -r | cut -c1-64)"
  mk="${mk}$(printf '0%.0s' {1..64})"
  for ((i = 0; i < 128; i += 2)); do
    b=$((16#${mk:i:2}))
    ipad+="$(printf '\\x%02x' $((b ^ 0x36)))"; opad+="$(printf '\\x%02x' $((b ^ 0x5c)))"
  done
  { printf "${opad}"; { printf "${ipad}"; cat; } | openssl dgst -sha256 -binary; } \
    | openssl dgst -sha256 -r | cut -c1-64
}

# ── Encrypt Evaluation: AES-256-CBC (PBKDF2) + HMAC-SHA256, contenido por stdin ─
encrypt_evaluation() {
  valid_alias "$1"; load_key
  local dir="${SCHOOL_DIR}/teacher/evaluations/$1" f tag
  [ -d "${SCHOOL_DIR}" ] || die "School not set up: ${SCHOOL_DIR}"
  mkdir -p "${dir}"
  f="$(mktemp --suffix=.enc "${dir}/eval-$(date +%Y%m%dT%H%M%S)-XXXXXX")"
  if [ "${2:--}" = "-" ]; then cat; else printf '%s\n' "$2"; fi | \
    openssl enc -aes-256-cbc -pbkdf2 -iter "${KDF_ITER}" -salt \
      -pass "file:${ENCRYPTION_KEY_FILE}" -out "$f" || { rm -f "$f"; die "Encryption failed"; }
  tag="$(hmac_hex < "$f")"
  printf '%s' "${tag}" | xxd -r -p >> "$f"
  audit_access "$1" "encrypt" >/dev/null
  echo "✅ Encrypted: $f"
}

# ── Decrypt Evaluation (Teacher Only): verifica MAC antes de descifrar ────────
decrypt_evaluation() {
  valid_alias "$1"
  local file="$2" dir real want got
  [ "$(verify_role "$(current_user)")" = "teacher" ] || die "Access denied: teacher only"
  dir="$(realpath -e "${SCHOOL_DIR}/teacher/evaluations/$1" 2>/dev/null)" || die "No evaluations for $1"
  real="$(realpath -e "${file}" 2>/dev/null)" || die "Evaluation not found"
  [[ "${real}" == "${dir}/"*.enc ]] || die "Access denied: file outside evaluations of $1"
  load_key
  [ "$(stat -c %s "${real}")" -gt 48 ] || die "Decryption failed: integrity check"
  want="$(tail -c 32 "${real}" | xxd -p -c 64)"
  got="$(head -c -32 "${real}" | hmac_hex)"
  [ "${want}" = "${got}" ] || die "Decryption failed: integrity check"
  audit_access "$1" "decrypt" >/dev/null
  head -c -32 "${real}" | openssl enc -d -aes-256-cbc -pbkdf2 -iter "${KDF_ITER}" \
    -pass "file:${ENCRYPTION_KEY_FILE}" 2>/dev/null || die "Decryption failed"
}

# ── Audit Access Logging: solo alias y acción validados, nunca contenido ──────
audit_access() {
  valid_alias "$1"
  [[ "$2" =~ ^[a-z0-9][a-z0-9_-]{0,40}$ ]] || die "Invalid audit action"
  [ -d "${SCHOOL_DIR}" ] || die "School not set up: ${SCHOOL_DIR}"
  [ ! -e "${AUDIT_LOG}" ] || [ -f "${AUDIT_LOG}" ] || die "Audit log is not a regular file"
  echo "[$(date -Iseconds)] $(current_user) - $2 - $1" >> "${AUDIT_LOG}" || die "Audit log not writable"
  chmod 600 "${AUDIT_LOG}"
  echo "📋 Audit logged"
}

# ── GDPR Consent Check ────────────────────────────────────────────────────────
gdpr_consent_check() {
  valid_alias "$1"
  [ -f "${SCHOOL_DIR}/classroom/$1/.consent" ] || die "No parental consent found"
  echo "✅ Consent verified"
}

# ── Age-Appropriate Content Filter (SCHOOL_FORBIDDEN_KEYWORDS) ────────────────
content_filter() {
  local forbidden="${SCHOOL_FORBIDDEN_KEYWORDS:-violence|adult|explicit|hate|discrimination}"
  if printf '%s\n' "$1" | grep -iqE "(${forbidden})"; then
    echo "❌ Content rejected"; return 1
  fi
  echo "✅ Content approved"
}

# ── Main dispatcher ───────────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}" n=$#
  case "${cmd}" in
    verify-role) need "$n" 2; verify_role "$2" ;;
    check-isolation) need "$n" 2; check_student_isolation "$2" ;;
    encrypt-eval) need "$n" 2; encrypt_evaluation "$2" "${3:--}" ;;
    decrypt-eval) need "$n" 3; decrypt_evaluation "$2" "$3" ;;
    audit-access) need "$n" 3; audit_access "$2" "$3" ;;
    gdpr-consent) need "$n" 2; gdpr_consent_check "$2" ;;
    filter-content) need "$n" 2; content_filter "$2" ;;
    *) usage ;;
  esac
}

main "$@"
