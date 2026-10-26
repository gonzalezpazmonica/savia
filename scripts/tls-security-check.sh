#!/usr/bin/env bash
# SE-242 — TLS Security Check
# Verifica configuración TLS/SSL de un host con testssl.sh (o Docker fallback)
# También ejecuta wafw00f para detección de WAF si está disponible
# Uso: ./scripts/tls-security-check.sh --host <hostname> [--port 443] [--severity MEDIUM]
set -uo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
HOST=""
PORT=443
MIN_SEVERITY="MEDIUM"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/output/security"
DATE=$(date +%Y%m%d)

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    HOST="$2";         shift 2 ;;
    --port)    PORT="$2";         shift 2 ;;
    --severity) MIN_SEVERITY="$2"; shift 2 ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "Uso: $0 --host <hostname> [--port 443] [--severity HIGH|MEDIUM|LOW]" >&2
  exit 1
fi

if [[ ! "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]; then
  echo "ERROR: host inválido: $HOST" >&2
  exit 1
fi
# Sin ceros a la izquierda: bash leería 0443 como octal y el JSON quedaría inválido
if [[ ! "$PORT" =~ ^[1-9][0-9]{0,4}$ ]] || (( PORT > 65535 )); then
  echo "ERROR: puerto inválido: $PORT" >&2
  exit 1
fi

# ── Preparar output dir ───────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
SAFE_HOST="${HOST//:/_}"
REPORT_FILE="$OUTPUT_DIR/tls-check-${SAFE_HOST}-${DATE}.json"

# ── Detectar testssl.sh ───────────────────────────────────────────────────────
TESTSSL_CMD=""
if command -v testssl.sh &>/dev/null; then
  TESTSSL_CMD="testssl.sh"
elif command -v testssl &>/dev/null; then
  TESTSSL_CMD="testssl"
fi

if [[ -z "$TESTSSL_CMD" ]]; then
  echo "INFO: testssl.sh no instalado. Usando Docker fallback."
  echo "  docker run --rm drwetter/testssl.sh --host ${HOST} --port ${PORT}"
  TESTSSL_CMD="docker run --rm drwetter/testssl.sh"
fi

# ── Función de clasificación de severidad ─────────────────────────────────────
classify_finding() {
  local label="$1"
  local value="$2"
  # Protocolos obsoletos → CRITICAL/HIGH
  case "$label" in
    SSLv2|SSLv3) echo "CRITICAL" ;;
    TLSv1.0|TLSv1.1) echo "HIGH" ;;
    RC4|DES|EXPORT|NULL) echo "CRITICAL" ;;
    *weak*|*MEDIUM*) echo "MEDIUM" ;;
    *) echo "LOW" ;;
  esac
}

# ── Ejecutar testssl.sh ───────────────────────────────────────────────────────
TESTSSL_OUT="$OUTPUT_DIR/.testssl-raw-${SAFE_HOST}-${DATE}.json"

echo "INFO: Ejecutando análisis TLS en ${HOST}:${PORT}..."

if [[ "$TESTSSL_CMD" == "docker run --rm drwetter/testssl.sh" ]]; then
  # Docker fallback — no ejecutamos realmente, sólo mostramos el comando
  echo "DOCKER_FALLBACK: Para ejecutar manualmente:"
  echo "  docker run --rm drwetter/testssl.sh --jsonfile /tmp/out.json --severity ${MIN_SEVERITY} ${HOST}:${PORT}"
  # Generar report mínimo indicando fallback
  cat > "$REPORT_FILE" <<EOF
{
  "host": "${HOST}",
  "port": ${PORT},
  "date": "${DATE}",
  "tool": "testssl.sh",
  "mode": "docker_fallback",
  "message": "testssl.sh not installed. Run manually: docker run --rm drwetter/testssl.sh --severity ${MIN_SEVERITY} ${HOST}:${PORT}",
  "findings": [],
  "grade": "UNKNOWN",
  "waf": null
}
EOF
  echo "INFO: Report generado en $REPORT_FILE"
  echo "GRADE: UNKNOWN"
  # Exit 2 = desconocido (convención gate-result): sin escaneo no hay nota
  exit 2
fi

# testssl.sh disponible localmente. testssl no sobrescribe un --jsonfile existente:
# sin este borrado, un reintento el mismo día calificaría con el informe viejo.
rm -f "$TESTSSL_OUT"
# testssl siempre con LOW: la nota se calcula con todo el informe (TLS1 o 3DES
# suelen ser LOW/MEDIUM); --severity solo filtra la lista de hallazgos mostrada.
$TESTSSL_CMD --jsonfile "$TESTSSL_OUT" --severity LOW \
  --protocols --ciphers --headers --vulnerable \
  "${HOST}:${PORT}" 2>/dev/null || true

# ── Parsear output y clasificar ───────────────────────────────────────────────
FINDINGS="[]"
GRADE="A"
SCAN_OK=false

if [[ -f "$TESTSSL_OUT" ]]; then
  # Extraer findings relevantes con python3 o jq
  if command -v python3 &>/dev/null; then
    FINDINGS=$(python3 - "$TESTSSL_OUT" "$MIN_SEVERITY" <<'PYEOF'
import json, sys
raw_file = sys.argv[1]
min_sev = sys.argv[2].upper()

sev_order = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "INFO": 0}
min_order = sev_order.get(min_sev, 1)

with open(raw_file) as f:
    data = json.load(f)

findings = []
grade_lines = []
fatal = False
worst = 0
for item in data:
    sev = item.get("severity", "INFO").upper()
    if sev == "FATAL" or item.get("id") == "scanProblem":
        fatal = True  # testssl no pudo evaluar el host
    # Nota: solo hallazgos con severidad (LOW+); OK/INFO dicen "no SSLv3 support"
    if sev_order.get(sev, 0) >= 1 and not str(item.get("finding", "")).lower().startswith("not offered"):
        grade_lines.append(("%s %s" % (item.get("id", ""), item.get("finding", ""))).replace("\n", " "))
    if sev_order.get(sev, 0) >= min_order:
        findings.append({
            "id": item.get("id", ""),
            "severity": sev,
            "finding": item.get("finding", ""),
            "cve": item.get("cve") or ""
        })
        worst = max(worst, sev_order.get(sev, 0))

print(json.dumps({"findings": findings, "grade_text": "\n".join(grade_lines), "fatal": fatal}))
PYEOF
    ) && SCAN_OK=true
  fi
fi
GRADE_TEXT=""
if $SCAN_OK; then
  # Hallazgos (filtrados por --severity) y texto de calificación (informe completo)
  GRADE_TEXT=$(printf '%s' "$FINDINGS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["grade_text"])')
  SCAN_FATAL=$(printf '%s' "$FINDINGS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["fatal"])')
  FINDINGS=$(printf '%s' "$FINDINGS" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["findings"]))')
  [[ "$SCAN_FATAL" == "True" ]] && SCAN_OK=false
fi
if ! $SCAN_OK; then
  FINDINGS="[]"
  echo "WARN: testssl no produjo un informe legible; no se puede calificar el host." >&2
fi

# ── Grading ───────────────────────────────────────────────────────────────────
# Inspeccionar si SSLv3/cert invalid → F; TLS 1.0/1.1 → D; etc.
# Solo se miran id y finding (no cve ni claves JSON) y se ignoran los "not offered".
# Se califica sobre el informe completo, no sobre los hallazgos filtrados.
GRADE="B"  # default: TLS 1.2 presente
if ! $SCAN_OK; then
  GRADE="UNKNOWN"  # sin informe legible nunca se da nota (fail-closed)
elif echo "$GRADE_TEXT" | grep -qi "sslv3\|cert.*invalid\|expired"; then
  GRADE="F"
elif echo "$GRADE_TEXT" | grep -qiE '(^|[^a-z0-9_])tls ?v?1([._ ]?[01])?([^a-z0-9_.]|$)'; then
  GRADE="D"  # TLS 1.0/1.1 en cualquier grafía (TLSv1.0, TLS 1.1, TLSv1) o ids TLS1, TLS1_1
elif echo "$GRADE_TEXT" | grep -qiE '(^|[^a-z])(rc4|3?des|export|a?null)([^a-z]|$)'; then
  GRADE="C"
fi

# ── WAF detection con wafw00f ─────────────────────────────────────────────────
WAF_RESULT="null"
if command -v wafw00f &>/dev/null; then
  echo "INFO: Ejecutando wafw00f..."
  WAF_RAW=$(wafw00f -o json "https://${HOST}" 2>/dev/null || echo "")
  if [[ -n "$WAF_RAW" ]]; then
    WAF_RESULT="\"$(echo "$WAF_RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('detected','unknown'))" 2>/dev/null || echo 'detection_failed')\""
  fi
else
  echo "INFO: wafw00f no disponible — detección de WAF omitida."
fi

# ── Generar report final ──────────────────────────────────────────────────────
cat > "$REPORT_FILE" <<EOF
{
  "host": "${HOST}",
  "port": ${PORT},
  "date": "${DATE}",
  "tool": "testssl.sh",
  "grade": "${GRADE}",
  "min_severity_filter": "${MIN_SEVERITY}",
  "findings": ${FINDINGS},
  "waf": ${WAF_RESULT},
  "report_path": "${REPORT_FILE}"
}
EOF

echo "GRADE: ${GRADE}"
echo "Report: $REPORT_FILE"
# Exit 2 = desconocido (convención gate-result): el escaneo falló y no hay nota
$SCAN_OK || exit 2
