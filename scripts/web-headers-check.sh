#!/usr/bin/env bash
# SE-242 — Web Security Headers Check
# Verifica security headers HTTP usando solo curl (sin herramientas externas)
# Score 0-100 basado en headers presentes
# Uso: ./scripts/web-headers-check.sh --url <url> [--follow-redirects]
set -uo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
TARGET_URL=""
FOLLOW_REDIRECTS=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/output/security"
DATE=$(date +%Y%m%d)

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)              TARGET_URL="$2"; shift 2 ;;
    --follow-redirects) FOLLOW_REDIRECTS=true; shift ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TARGET_URL" ]]; then
  echo "Uso: $0 --url <url> [--follow-redirects]" >&2
  exit 1
fi

# ── Extraer hostname del URL ──────────────────────────────────────────────────
HOSTNAME=$(echo "$TARGET_URL" | sed 's|https\?://||' | sed 's|/.*||' | sed 's|:.*||')
SAFE_HOST="${HOSTNAME//./_}"
mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/headers-check-${SAFE_HOST}-${DATE}.json"

# ── Fetch headers con curl ────────────────────────────────────────────────────
CURL_OPTS="-s -I --max-time 30"
if [[ "$FOLLOW_REDIRECTS" == "true" ]]; then
  CURL_OPTS="$CURL_OPTS -L"
fi

HEADERS_RAW=$(curl $CURL_OPTS "$TARGET_URL" 2>/dev/null || echo "")

if [[ -z "$HEADERS_RAW" ]]; then
  echo "ERROR: No se pudo conectar a $TARGET_URL" >&2
  exit 1
fi

# Escapa un valor para incrustarlo en una cadena JSON.
json_esc() {
  local v="$1"
  v=${v//\\/\\\\}
  v=${v//\"/\\\"}
  printf '%s' "$v"
}

# ── Función: extraer header value ─────────────────────────────────────────────
get_header() {
  local name="$1"
  echo "$HEADERS_RAW" | grep -i "^${name}:" | head -1 | sed 's/^[^:]*: *//' | tr -d '\r'
}

header_present() {
  local name="$1"
  echo "$HEADERS_RAW" | grep -qi "^${name}:" && echo "true" || echo "false"
}

# ── Evaluar cada header ────────────────────────────────────────────────────────
CSP=$(get_header "content-security-policy")
CSP_PRESENT=$(header_present "content-security-policy")

XCTO=$(get_header "x-content-type-options")
XCTO_PRESENT=$(header_present "x-content-type-options")

XFO=$(get_header "x-frame-options")
XFO_PRESENT=$(header_present "x-frame-options")

HSTS=$(get_header "strict-transport-security")
HSTS_PRESENT=$(header_present "strict-transport-security")

REFERRER=$(get_header "referrer-policy")
REFERRER_PRESENT=$(header_present "referrer-policy")

PERMS=$(get_header "permissions-policy")
PERMS_PRESENT=$(header_present "permissions-policy")

SERVER=$(json_esc "$(get_header "server")")
X_POWERED=$(json_esc "$(get_header "x-powered-by")")

# ── Calcular score (0-100) ────────────────────────────────────────────────────
SCORE=0
FINDINGS_JSON=""

# Content-Security-Policy — 25 puntos
if [[ "$CSP_PRESENT" == "true" ]]; then
  SCORE=$((SCORE + 25))
else
  FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"Content-Security-Policy\",\"severity\":\"HIGH\",\"message\":\"Missing CSP header\"},"
fi

# HSTS — 20 puntos
if [[ "$HSTS_PRESENT" == "true" ]]; then
  SCORE=$((SCORE + 20))
  # Verificar max-age >= 31536000
  MAX_AGE=$(echo "$HSTS" | grep -oi "max-age=[0-9]*" | grep -oi "[0-9]*" || echo "0")
  if [[ "${MAX_AGE:-0}" -lt 31536000 ]]; then
    FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"HSTS\",\"severity\":\"MEDIUM\",\"message\":\"HSTS max-age < 31536000 (1 year)\"},"
  fi
else
  FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"Strict-Transport-Security\",\"severity\":\"HIGH\",\"message\":\"Missing HSTS header\"},"
fi

# X-Content-Type-Options — 15 puntos
if [[ "$XCTO_PRESENT" == "true" ]]; then
  SCORE=$((SCORE + 15))
else
  FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"X-Content-Type-Options\",\"severity\":\"MEDIUM\",\"message\":\"Missing X-Content-Type-Options: nosniff\"},"
fi

# X-Frame-Options — 15 puntos
if [[ "$XFO_PRESENT" == "true" ]] || echo "$CSP" | grep -qi "frame-ancestors"; then
  SCORE=$((SCORE + 15))
else
  FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"X-Frame-Options\",\"severity\":\"MEDIUM\",\"message\":\"Missing X-Frame-Options (or CSP frame-ancestors)\"},"
fi

# Referrer-Policy — 15 puntos
if [[ "$REFERRER_PRESENT" == "true" ]]; then
  SCORE=$((SCORE + 15))
else
  FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"Referrer-Policy\",\"severity\":\"LOW\",\"message\":\"Missing Referrer-Policy header\"},"
fi

# Permissions-Policy — 10 puntos
if [[ "$PERMS_PRESENT" == "true" ]]; then
  SCORE=$((SCORE + 10))
else
  FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"Permissions-Policy\",\"severity\":\"LOW\",\"message\":\"Missing Permissions-Policy header\"},"
fi

# Penalizaciones — información expuesta
if [[ -n "$SERVER" ]]; then
  # Detectar versión expuesta en Server header
  if echo "$SERVER" | grep -qiE "[0-9]+\.[0-9]+"; then
    SCORE=$((SCORE > 5 ? SCORE - 5 : 0))
    FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"Server\",\"severity\":\"LOW\",\"message\":\"Server header exposes version: ${SERVER}\"},"
  fi
fi
if [[ -n "$X_POWERED" ]]; then
  SCORE=$((SCORE > 5 ? SCORE - 5 : 0))
  FINDINGS_JSON="${FINDINGS_JSON}{\"header\":\"X-Powered-By\",\"severity\":\"LOW\",\"message\":\"X-Powered-By header exposes technology: ${X_POWERED}\"},"
fi

# Quitar trailing comma y envolver en array
FINDINGS_JSON="[${FINDINGS_JSON%,}]"

# ── Generar report JSON ───────────────────────────────────────────────────────
CSP=$(json_esc "$CSP"); HSTS=$(json_esc "$HSTS"); XCTO=$(json_esc "$XCTO"); XFO=$(json_esc "$XFO")
REFERRER=$(json_esc "$REFERRER"); PERMS=$(json_esc "$PERMS"); TARGET_URL=$(json_esc "$TARGET_URL")
cat > "$REPORT_FILE" <<EOF
{
  "url": "${TARGET_URL}",
  "hostname": "${HOSTNAME}",
  "date": "${DATE}",
  "tool": "web-headers-check",
  "score": ${SCORE},
  "follow_redirects": ${FOLLOW_REDIRECTS},
  "headers": {
    "content-security-policy": $([ "$CSP_PRESENT" = "true" ] && echo "\"${CSP}\"" || echo "null"),
    "strict-transport-security": $([ "$HSTS_PRESENT" = "true" ] && echo "\"${HSTS}\"" || echo "null"),
    "x-content-type-options": $([ "$XCTO_PRESENT" = "true" ] && echo "\"${XCTO}\"" || echo "null"),
    "x-frame-options": $([ "$XFO_PRESENT" = "true" ] && echo "\"${XFO}\"" || echo "null"),
    "referrer-policy": $([ "$REFERRER_PRESENT" = "true" ] && echo "\"${REFERRER}\"" || echo "null"),
    "permissions-policy": $([ "$PERMS_PRESENT" = "true" ] && echo "\"${PERMS}\"" || echo "null")
  },
  "findings": ${FINDINGS_JSON},
  "report_path": "${REPORT_FILE}"
}
EOF

echo "SCORE: ${SCORE}/100"
echo "Report: $REPORT_FILE"
