#!/usr/bin/env bash
# ternary-verdict.sh — Unified data contract for ternary verdicts (SE-269 S2)
# Usage: bash scripts/ternary-verdict.sh --banda PASA|RESERVAS|FALLA [--motivo "..."] [--dimensiones JSON] [--owner "..."] [--engram-op "id"] [--origen "autor|generado"]
# Outputs structured JSON verdict to stdout

set -uo pipefail

BANDA=""
MOTIVO=""
OWNER=""
ENGRAM_OP=""
ORIGEN="autor"
DIMENSIONES_JSON="[]"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

usage() {
  cat <<EOF
Uso: ternary-verdict.sh --banda <BANDA> [opciones]

Bandas válidas (S2): PASA | RESERVAS | FALLA
Bandas válidas (S1): ENDURECIDA | MAS_CLARA | MUERTA
Bandas válidas (S3): APROBAR | REHACER | SEGUIR

Opciones:
  --banda        Banda del veredicto (obligatorio)
  --motivo       Texto explicativo (obligatorio si banda != PASA)
  --dimensiones  JSON array de dimensiones [{nombre, banda, hallazgos}]
  --owner        Dueño de la reserva (obligatorio si banda == RESERVAS)
  --engram-op    ID de sesión de forja (S1)
  --origen       autor | generado (S3, orden de lectura)
  --validate     Solo valida la banda, no emite JSON

Salida: JSON estructurado con los campos del contrato unificado.
Códigos de salida: 0=OK, 1=error de validación, 2=banda inválida.
EOF
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --banda) BANDA="$2"; shift 2 ;;
    --motivo) MOTIVO="$2"; shift 2 ;;
    --dimensiones) DIMENSIONES_JSON="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --engram-op) ENGRAM_OP="$2"; shift 2 ;;
    --origen) ORIGEN="$2"; shift 2 ;;
    --validate) VALIDATE_ONLY=true; shift ;;
    --help|-h) usage ;;
    *) echo "ERROR: opción desconocida: $1" >&2; usage ;;
  esac
done

[[ -z "$BANDA" ]] && { echo '{"error":"--banda es obligatorio"}' >&2; exit 1; }

# Normalize
BANDA=$(echo "$BANDA" | tr '[:lower:]' '[:upper:]')

# Validate band
ALL_BANDS="PASA RESERVAS FALLA ENDURECIDA MAS_CLARA MUERTA APROBAR REHACER SEGUIR"
valid=false
for b in $ALL_BANDS; do
  [[ "$BANDA" == "$b" ]] && valid=true && break
done

if ! $valid; then
  echo "{\"error\":\"banda inválida: $BANDA\",\"validas\":\"$ALL_BANDS\"}" >&2
  exit 2
fi

# Hard gate: security/confidenciality/linea_roja gates cannot emit RESERVAS (AC-2.2)
if [[ -n "${GATE_TYPE:-}" ]]; then
  case "$GATE_TYPE" in
    security|confidencialidad|linea_roja)
      if [[ "$BANDA" == "RESERVAS" ]]; then
        echo "{\"error\":\"RESERVAS rechazada: gate de frontera ($GATE_TYPE) no admite banda intermedia (CRIT-023)\"}" >&2
        exit 1
      fi
      ;;
  esac
fi

# Validate RESERVAS must have owner (AC-2.3)
if [[ "$BANDA" == "RESERVAS" && -z "$OWNER" ]]; then
  echo "{\"error\":\"RESERVAS requiere --owner (dueño del follow-up)\"}" >&2
  exit 1
fi

# Validate non-PASA must have motivo
if [[ "$BANDA" != "PASA" && "$BANDA" != "ENDURECIDA" && "$BANDA" != "APROBAR" && -z "$MOTIVO" ]]; then
  echo "{\"error\":\"banda $BANDA requiere --motivo\"}" >&2
  exit 1
fi

# Validate dimensiones JSON
if ! echo "$DIMENSIONES_JSON" | python3 -m json.tool >/dev/null 2>&1; then
  echo "{\"error\":\"--dimensiones no es JSON válido\"}" >&2
  exit 1
fi

# Validate-only mode
if [[ "${VALIDATE_ONLY:-false}" == "true" ]]; then
  echo "OK: $BANDA"
  exit 0
fi

# Build output JSON — los valores viajan por entorno, nunca interpolados en el
# código Python (comillas/backslashes/$ en motivo u owner lo corrompían).
VT_BANDA="$BANDA" VT_MOTIVO="$MOTIVO" VT_OWNER="$OWNER" VT_ENGRAM="$ENGRAM_OP" \
VT_ORIGEN="$ORIGEN" VT_TS="$TIMESTAMP" VT_DIMS="$DIMENSIONES_JSON" python3 -c "
import json, os

e = os.environ
output = {
    'veredicto': e['VT_BANDA'],
    'motivo': e['VT_MOTIVO'],
    'owner': e['VT_OWNER'] or None,
    'engram_op': e['VT_ENGRAM'] or None,
    'origen': e['VT_ORIGEN'],
    'timestamp': e['VT_TS'],
    'dimensiones': json.loads(e['VT_DIMS']),
}
print(json.dumps(output, indent=2, ensure_ascii=False))
"
exit $?
