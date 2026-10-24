#!/usr/bin/env bash
# SE-240 — Mobile Security Scan
# Análisis estático de APK/AAB con MobSF (Docker) o fallback básico (apktool + grep)
# Uso: ./scripts/mobile-security-scan.sh --apk <path> [--mode static|dynamic]
set -uo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
APK_PATH=""
MODE="static"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/output/security"
DATE=$(date +%Y%m%d)
MOBSF_API_KEY="${MOBSF_API_KEY:-}"
MOBSF_URL="${MOBSF_URL:-http://localhost:8000}"
# SE-453: la última línea de stdout es el resultado (clean|findings|unknown). Los códigos no cambian:
# 0 con informe, 1 argumentos. Lo que no se pudo analizar es un hueco, no un «limpio».
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh"
GAPS=()

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk)  APK_PATH="$2"; shift 2 ;;
    --mode) MODE="$2";     shift 2 ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$APK_PATH" ]]; then
  echo "Uso: $0 --apk <path/to/app.apk> [--mode static|dynamic]" >&2
  exit 1
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "ERROR: APK no encontrado: $APK_PATH" >&2
  exit 1
fi

# ── Preparar output dir ───────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
APK_BASENAME=$(basename "$APK_PATH" .apk)
REPORT_FILE="$OUTPUT_DIR/mobile-scan-${DATE}.json"

# ── Verificar modo dynamic ────────────────────────────────────────────────────
if [[ "$MODE" == "dynamic" ]]; then
  echo "INFO: Modo dynamic requiere dispositivo ADB conectado."
  # El análisis dinámico no está implementado: siempre degrada a static y queda como hueco.
  GAPS+=("dynamic:missing_tool")
  if ! command -v adb &>/dev/null; then
    echo "WARN: adb no disponible. Degradando a modo static."
    MODE="static"
  else
    ADB_DEVICES=$(adb devices 2>/dev/null | grep -v "List of devices" | grep -v "^$" || echo "")
    if [[ -z "$ADB_DEVICES" ]]; then
      echo "WARN: No hay dispositivo ADB conectado. Degradando a modo static."
      MODE="static"
    fi
  fi
fi

# ── Detectar MobSF ────────────────────────────────────────────────────────────
MOBSF_AVAILABLE=false

if curl -s --max-time 3 "${MOBSF_URL}/api/v1/api_docs" &>/dev/null; then
  MOBSF_AVAILABLE=true
  echo "INFO: MobSF detectado en ${MOBSF_URL}"
elif command -v docker &>/dev/null; then
  echo "INFO: MobSF no corriendo. Docker fallback disponible."
  echo "  Para iniciar MobSF:"
  echo "  docker run --rm -p 8000:8000 opensecurity/mobile-security-framework-mobsf"
  echo "INFO: Usando análisis básico (apktool + grep)."
else
  echo "INFO: MobSF no disponible y Docker no instalado. Usando análisis básico."
fi

# ── Análisis con MobSF ────────────────────────────────────────────────────────
if [[ "$MOBSF_AVAILABLE" == "true" && -n "$MOBSF_API_KEY" ]]; then
  echo "INFO: Ejecutando MobSF static analysis..."

  UPLOAD_RESP=$(curl -s -F "file=@${APK_PATH}" \
    -H "Authorization: ${MOBSF_API_KEY}" \
    "${MOBSF_URL}/api/v1/upload" 2>/dev/null || echo "")

  if [[ -n "$UPLOAD_RESP" ]]; then
    FILE_HASH=$(echo "$UPLOAD_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hash',''))" 2>/dev/null || echo "")
    if [[ -n "$FILE_HASH" ]]; then
      # Trigger scan
      curl -s -F "hash=${FILE_HASH}" \
        -H "Authorization: ${MOBSF_API_KEY}" \
        "${MOBSF_URL}/api/v1/scan" &>/dev/null || true

      # Get report
      MOBSF_REPORT=$(curl -s -F "hash=${FILE_HASH}" \
        -H "Authorization: ${MOBSF_API_KEY}" \
        "${MOBSF_URL}/api/v1/report_json" 2>/dev/null || echo "{}")

      echo "$MOBSF_REPORT" > "$REPORT_FILE"
      echo "INFO: MobSF analysis completo. Report: $REPORT_FILE"
      # El script no tria el informe de MobSF: sin veredicto automático (lectura humana).
      if ! printf '%s' "$MOBSF_REPORT" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin) else 1)' 2>/dev/null; then
        GAPS+=("mobsf_report:unreadable")
      else
        GAPS+=("mobsf_triage:unreadable")
      fi
      gate_result_emit unknown "${GAPS[@]}"
      exit 0
    fi
  fi
  echo "WARN: MobSF upload falló. Fallback a análisis básico."
fi

# ── Análisis básico: apktool + grep de patterns peligrosos ───────────────────
echo "INFO: Ejecutando análisis básico de seguridad..."

FINDINGS_LIST=""
DECOMPILE_DIR="/tmp/mobsf-basic-${DATE}-$$"

# Intentar decompilación con apktool si disponible
if command -v apktool &>/dev/null; then
  apktool d -o "$DECOMPILE_DIR" "$APK_PATH" -f &>/dev/null || true
elif command -v unzip &>/dev/null; then
  # Fallback: extraer como ZIP para acceder a AndroidManifest binario.
  # Sin apktool no hay smali ni manifiesto en texto: el análisis queda incompleto.
  GAPS+=("apktool:missing_tool")
  mkdir -p "$DECOMPILE_DIR"
  unzip -q "$APK_PATH" -d "$DECOMPILE_DIR" 2>/dev/null || true
else
  GAPS+=("decompile:missing_tool")
fi
# Descompilación intentada que no dejó ficheros (apktool o unzip fallidos): nada analizado.
if [[ " ${GAPS[*]} " != *" decompile:missing_tool "* ]] \
   && [[ -z "$(find "$DECOMPILE_DIR" -type f -print -quit 2>/dev/null)" ]]; then
  GAPS+=("decompile:unreadable")
fi

# Analizar AndroidManifest si accesible en texto
MANIFEST_PATH=""
if [[ -f "$DECOMPILE_DIR/AndroidManifest.xml" ]]; then
  MANIFEST_PATH="$DECOMPILE_DIR/AndroidManifest.xml"
  # Usar android-manifest-audit.sh si disponible
  if [[ -f "$SCRIPT_DIR/android-manifest-audit.sh" ]]; then
    MANIFEST_FINDINGS=$(bash "$SCRIPT_DIR/android-manifest-audit.sh" "$MANIFEST_PATH" 2>/dev/null || echo "[]")
  fi
fi

# Buscar patterns peligrosos en el código descompilado
HARDCODED_SECRETS=0
DEBUG_CODE=0
DANGEROUS_PERMS=0

if [[ -d "$DECOMPILE_DIR" ]]; then
  # Secrets hardcodeados
  HARDCODED_SECRETS=$(find "$DECOMPILE_DIR" -name "*.xml" -o -name "*.smali" 2>/dev/null | \
    xargs grep -li "password\|api_key\|secret\|token\|private_key" 2>/dev/null | wc -l)

  # Código de debug
  DEBUG_CODE=$(find "$DECOMPILE_DIR" -name "*.smali" 2>/dev/null | \
    xargs grep -l "Landroid/util/Log;\|Log\.d\|Log\.v\|BuildConfig\.DEBUG" 2>/dev/null | wc -l)
fi

# Limpiar directorio temporal
rm -rf "$DECOMPILE_DIR" 2>/dev/null || true

# ── Resultado (SE-453) ────────────────────────────────────────────────────────
if [[ "${HARDCODED_SECRETS:-0}" -gt 0 || "${DEBUG_CODE:-0}" -gt 0 ]]; then
  RESULT="findings"
elif [[ ${#GAPS[@]} -gt 0 ]]; then
  RESULT="unknown"
else
  RESULT="clean"
fi
GATE_LINE="$(gate_result_emit "$RESULT" "${GAPS[@]}")"
GAPS_JSON="${GATE_LINE#*\"gaps\":}"; GAPS_JSON="${GAPS_JSON%\}}"

# ── Generar report ────────────────────────────────────────────────────────────
cat > "$REPORT_FILE" <<EOF
{
  "apk": "${APK_PATH}",
  "date": "${DATE}",
  "mode": "${MODE}",
  "tool": "basic-analysis",
  "mobsf_available": ${MOBSF_AVAILABLE},
  "result": "${RESULT}",
  "gaps": ${GAPS_JSON},
  "findings": [
    $([ "${HARDCODED_SECRETS:-0}" -gt 0 ] && echo "{\"severity\":\"CRITICAL\",\"type\":\"hardcoded_secrets\",\"count\":${HARDCODED_SECRETS}}," || echo "")
    $([ "${DEBUG_CODE:-0}" -gt 0 ] && echo "{\"severity\":\"HIGH\",\"type\":\"debug_code_in_release\",\"count\":${DEBUG_CODE}}," || echo "")
    {"severity":"INFO","type":"scan_complete","message":"Basic analysis done. Install MobSF for full analysis."}
  ],
  "mobsf_docker_command": "docker run --rm -p 8000:8000 opensecurity/mobile-security-framework-mobsf",
  "report_path": "${REPORT_FILE}"
}
EOF

echo "Report: $REPORT_FILE"
echo "$GATE_LINE"
