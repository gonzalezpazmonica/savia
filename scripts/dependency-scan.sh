#!/usr/bin/env bash
# dependency-scan.sh — Dependency Vulnerability Scanning con Trivy
# SE-244: Escanea dependencias de proyectos con trivy fs
#
# Uso:
#   bash scripts/dependency-scan.sh --path ./project/ [--severity CRITICAL,HIGH] [--generate-sbom] [--skip-update]
#
# Salida:
#   output/security/dep-scan-YYYYMMDD.json    (report de vulnerabilidades, JSON de Trivy)
#   output/security/sbom-YYYYMMDD.json        (SBOM CycloneDX, con --generate-sbom)
#   DEP_SCAN_OUTPUT_DIR cambia el directorio de salida. El nombre es por día, no por proyecto:
#   para varios proyectos el mismo día, un DEP_SCAN_OUTPUT_DIR por proyecto.
#
# Exit codes:
#   0 = sin vulnerabilidades en las severidades pedidas
#   1 = hallazgos en las severidades pedidas (por defecto CRITICAL o HIGH; bloquea CI)
#   2 = error: argumentos, Trivy/Docker no disponibles, escaneo fallido o SBOM no generado.
#       Un error nunca se presenta como «limpio» ni como «vulnerabilidades».
#   Contrato SE-453: la última línea de stdout es `gate-result: {...}` (clean|findings|unknown).
#   Código 2 = unknown (Trivy/jq ausente → missing_tool; escaneo o SBOM fallido → unreadable/timeout).
#   Precedencia: 2 gana a 1 (hallazgos + SBOM fallido → 2; los hallazgos se listan igualmente).
#
# Artefactos ante fallo: el informe se escribe a un temporal único (.tmp.XXXXXX) y solo se publica si es JSON de Trivy
#   válido (SchemaVersion 2); si no, queda como dep-scan-YYYYMMDD.json.failed y el informe
#   válido anterior del mismo día no se toca. Un SBOM fallido queda como sbom-YYYYMMDD.json.failed
#   y un SBOM anterior del mismo día se renombra a .stale.
#
# Manifiestos soportados: Node (package.json), Python (requirements.txt, pyproject.toml),
#   C# (*.csproj), Java (pom.xml, build.gradle), Go (go.mod), Rust (Cargo.toml), Ruby (Gemfile)
# Requiere Trivy >= 0.37 (--scanners) y jq.
#
# Ref: docs/rules/domain/dependency-security-policy.md — SE-244
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh"

# ── Valores por defecto ──────────────────────────────────────────────────────
SCAN_PATH=""
SEVERITY="CRITICAL,HIGH"
GENERATE_SBOM=false
SKIP_UPDATE=false
DATE="$(date +%Y%m%d)"
OUTPUT_DIR="${DEP_SCAN_OUTPUT_DIR:-$ROOT/output/security}"

usage_error() {
  echo "ERROR: $1" >&2
  echo "  Uso: $0 --path <dir> [--severity CRITICAL,HIGH] [--generate-sbom] [--skip-update]" >&2
  exit 2
}

# ── Parser de argumentos ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)          [[ $# -ge 2 ]] || usage_error "--path necesita un valor"; SCAN_PATH="$2"; shift 2 ;;
    --severity)      [[ $# -ge 2 ]] || usage_error "--severity necesita un valor"; SEVERITY="$2"; shift 2 ;;
    --generate-sbom) GENERATE_SBOM=true; shift ;;
    --skip-update)   SKIP_UPDATE=true;  shift ;;
    *) usage_error "argumento desconocido: $1" ;;
  esac
done

[[ -n "$SCAN_PATH" ]] || usage_error "especifica --path <dir>"
[[ -d "$SCAN_PATH" ]] || usage_error "el path no existe: $SCAN_PATH"
[[ "$SEVERITY" =~ ^[A-Z]+(,[A-Z]+)*$ ]] || usage_error "severidades inválidas: $SEVERITY"
command -v jq &>/dev/null || { echo "ERROR: jq no disponible; no se puede interpretar el informe." >&2; gate_result_emit unknown "jq:missing_tool"; exit 2; }

SCAN_PATH="$(cd "$SCAN_PATH" && pwd)"
mkdir -p "$OUTPUT_DIR" || { echo "ERROR: no se puede crear el directorio de salida: $OUTPUT_DIR" >&2; gate_result_emit unknown "output-dir:unreadable"; exit 2; }

# ── Detección de Trivy ────────────────────────────────────────────────────────
TRIVY_CMD=""
if command -v trivy &>/dev/null; then
  TRIVY_CMD="trivy"
else
  echo "WARN: Trivy no instalado localmente. Usando fallback Docker." >&2
  echo "  Fallback: docker run --rm -v \"\$(pwd):/workspace\" aquasec/trivy:latest fs /workspace" >&2
  if ! command -v docker &>/dev/null; then
    echo "ERROR: Ni Trivy ni Docker disponibles. Instala Trivy: https://aquasecurity.github.io/trivy/latest/getting-started/installation/" >&2
    gate_result_emit unknown "trivy:missing_tool"
    exit 2
  fi
  TRIVY_CMD="docker"
fi

# ── Ejecutar trivy fs (local o Docker) con salida a fichero ──────────────────
# run_trivy_fs <fichero de salida> <banderas...>: el path escaneado va al final (en Docker, /workspace).
run_trivy_fs() {
  local out="$1"; shift
  if [[ "$TRIVY_CMD" == "docker" ]]; then
    docker run --rm \
      -v "$SCAN_PATH:/workspace" \
      -v "$HOME/.cache/trivy:/root/.cache/trivy" \
      aquasec/trivy:latest fs "$@" /workspace > "$out"
  else
    trivy fs "$@" --output "$out" "$SCAN_PATH"
  fi
}

# ── Auto-detección del tipo de proyecto ──────────────────────────────────────
detect_project_type() {
  local path="$1" types=() pair name type
  for pair in package.json:node requirements.txt:python-requirements pyproject.toml:python-pyproject \
      Pipfile:python-pipenv '*.csproj:dotnet' pom.xml:java-maven build.gradle:java-gradle \
      go.mod:go Cargo.toml:rust Gemfile:ruby composer.json:php; do
    name="${pair%%:*}" type="${pair##*:}"
    if find "$path" -maxdepth 5 -name "$name" -not -path "*/node_modules/*" 2>/dev/null | grep -q .; then
      types+=("$type")
    fi
  done
  if [[ ${#types[@]} -eq 0 ]]; then echo "unknown"; else echo "${types[*]}"; fi
}

# ── Banderas de Trivy ─────────────────────────────────────────────────────────
FLAGS=(--severity "$SEVERITY" --scanners vuln)
[[ "$SKIP_UPDATE" == "true" ]] && FLAGS+=(--skip-db-update)
# .trivyignore en el path o en la raíz (en Docker solo el del path, que está montado)
if [[ -f "$SCAN_PATH/.trivyignore" ]]; then
  if [[ "$TRIVY_CMD" == "docker" ]]; then FLAGS+=(--ignorefile /workspace/.trivyignore)
  else FLAGS+=(--ignorefile "$SCAN_PATH/.trivyignore"); fi
elif [[ -f "$ROOT/.trivyignore" && "$TRIVY_CMD" != "docker" ]]; then
  FLAGS+=(--ignorefile "$ROOT/.trivyignore")
fi

REPORT_JSON="$OUTPUT_DIR/dep-scan-${DATE}.json"
SBOM_JSON="$OUTPUT_DIR/sbom-${DATE}.json"
# Temporales únicos por ejecución: dos escaneos simultáneos en el mismo directorio de salida
# (p. ej. dos proyectos en CI el mismo día) no pueden leer ni mover el informe del otro.
REPORT_TMP="$(mktemp "$REPORT_JSON.tmp.XXXXXX")" || { echo "ERROR: no se puede escribir en $OUTPUT_DIR" >&2; gate_result_emit unknown "output-dir:unreadable"; exit 2; }

echo "Escaneando dependencias en: $SCAN_PATH"
echo "Tipos de proyecto detectados: $(detect_project_type "$SCAN_PATH")"
echo "Severidades: $SEVERITY"
echo ""

# ── Escaneo: una sola pasada en JSON; el veredicto sale del informe ──────────
# Se escribe al temporal único y solo se publica si es un informe Trivy válido: un fallo nunca pisa
# el informe bueno de una ejecución anterior; lo recibido se conserva como .failed para diagnóstico.
# Esquema exigido: SchemaVersion 2 y Results array (o null) de objetos. Un esquema distinto
# (p. ej. una versión futura de Trivy) es error, no «limpio».
SCHEMA_OK='.SchemaVersion == 2 and ((.Results // []) | type == "array" and all(.[]; type == "object"))'
scan_failed() {
  if [[ -s "$REPORT_TMP" ]]; then mv -f "$REPORT_TMP" "$REPORT_JSON.failed"
  else rm -f "$REPORT_TMP"; echo "  (Trivy no dejó salida que conservar)" >&2; fi
  echo "ERROR: el escaneo no se completó ($1). Diagnóstico: $REPORT_JSON.failed" >&2
  echo "  Ni limpio ni vulnerable: revisa Trivy (versión >= 0.37, base de datos, red) y repite." >&2
  gate_result_emit unknown "trivy:${2:-unreadable}"
  exit 2
}
rc=0
run_trivy_fs "$REPORT_TMP" "${FLAGS[@]}" --format json || rc=$?
if [[ $rc -ne 0 ]]; then
  if [[ $rc -eq 124 ]]; then scan_failed "trivy rc=$rc" timeout; else scan_failed "trivy rc=$rc"; fi
fi
jq -e "$SCHEMA_OK" "$REPORT_TMP" >/dev/null 2>&1 || scan_failed "informe ilegible o esquema desconocido"

FINDINGS=$(jq -r --arg sev "$SEVERITY" '
  ($sev | split(",")) as $wanted
  | [.Results[]? | .Target as $t | .Vulnerabilities[]?
     | select(.Severity as $s | $wanted | index($s))
     | "\(.Severity)\t\(.VulnerabilityID)\t\(.PkgName) \(.InstalledVersion) → \(.FixedVersion // "sin fix")\t\($t)"]
  | .[]' "$REPORT_TMP") || scan_failed "jq no pudo extraer los hallazgos"
mv -f "$REPORT_TMP" "$REPORT_JSON"

if [[ -n "$FINDINGS" ]]; then
  echo "Hallazgos ($(printf '%s\n' "$FINDINGS" | wc -l)):"
  printf '%s\n' "$FINDINGS" | sed 's/^/  /'
fi

# ── Generación de SBOM CycloneDX ─────────────────────────────────────────────
SBOM_FAILED=false
if [[ "$GENERATE_SBOM" == "true" ]]; then
  echo ""
  echo "Generando SBOM (CycloneDX JSON)..."
  sbom_rc=0
  SBOM_TMP="$(mktemp "$SBOM_JSON.tmp.XXXXXX")" || { echo "ERROR: no se puede escribir en $OUTPUT_DIR" >&2; gate_result_emit unknown "sbom:unreadable"; exit 2; }
  run_trivy_fs "$SBOM_TMP" --format cyclonedx || sbom_rc=$?
  if [[ $sbom_rc -eq 0 ]] && jq -e '.bomFormat == "CycloneDX"' "$SBOM_TMP" >/dev/null 2>&1; then
    mv -f "$SBOM_TMP" "$SBOM_JSON"
    echo "SBOM generado: $SBOM_JSON"
  else
    # Nunca se fabrica un SBOM vacío: un artefacto de release sin componentes reales es evidencia falsa.
    # Lo recibido queda como .failed (diagnóstico) y un SBOM anterior del mismo día pasa a .stale
    # para que nadie lo tome por el de esta ejecución.
    if [[ -s "$SBOM_TMP" ]]; then mv -f "$SBOM_TMP" "$SBOM_JSON.failed"
    else rm -f "$SBOM_TMP"; echo "  (Trivy no dejó salida de SBOM que conservar)" >&2; fi
    if [[ -f "$SBOM_JSON" ]]; then
      mv -f "$SBOM_JSON" "$SBOM_JSON.stale"
      echo "WARN: el SBOM anterior de hoy se renombra a $SBOM_JSON.stale (no corresponde a esta ejecución)." >&2
    fi
    echo "ERROR: SBOM no generado (trivy rc=$sbom_rc). No se escribe $SBOM_JSON." >&2
    SBOM_FAILED=true
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────"
echo "Report: $REPORT_JSON"
[[ "$GENERATE_SBOM" == "true" && "$SBOM_FAILED" == "false" ]] && echo "SBOM:   $SBOM_JSON"
echo "────────────────────────────────────────────────────"

if [[ -n "$FINDINGS" ]]; then
  echo ""
  echo "FAIL: Vulnerabilidades $SEVERITY detectadas en dependencias."
  echo "Accion requerida: actualizar las dependencias vulnerables o suprimir"
  echo "  con justificación en .trivyignore."
  echo "Ref: docs/rules/domain/dependency-security-policy.md"
fi

# Precedencia: el error (2) gana a los hallazgos (1). Con hallazgos y SBOM fallido sale 2:
# la ejecución no produjo lo pedido y un pipeline que solo mire el rc debe enterarse de que
# falta el artefacto de release; los hallazgos ya se han listado arriba.
if [[ "$SBOM_FAILED" == "true" ]]; then
  gate_result_emit unknown "sbom:unreadable"
  exit 2
fi
if [[ -n "$FINDINGS" ]]; then
  gate_result_emit findings
  exit 1
fi

echo ""
echo "PASS: Sin vulnerabilidades en severidades $SEVERITY."
gate_result_emit clean
exit 0
