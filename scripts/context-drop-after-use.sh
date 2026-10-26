#!/usr/bin/env bash
set -uo pipefail
# context-drop-after-use.sh — SE-221 Slice 2 — Drop-After-Use decision engine
# Decide si un fichero leido en contexto debe mantenerse (KEEP), reemplazarse
# por un stub (STUB), o descartarse (DROP) tras la operacion.
#
# Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md (AC-06)
# Inspiracion: Context-Minimization (Beurer-Kellner et al. 2025, arXiv:2506.08837 §6).
#
# Uso:
#   scripts/context-drop-after-use.sh --path <PATH> --next-task <STRING>
#   scripts/context-drop-after-use.sh --json --path <PATH> --next-task <STRING>
#
# Heuristica:
#   KEEP — path es N1/N2 (siempre relevante), o aparece en next-task como
#          referencia textual (filename o subpath).
#   STUB — path es N4a/N4b/N5/N4-project, ultima lectura > umbral turnos,
#          NO aparece en next-task. Genera abstract de 1 linea.
#   DROP — path es untrusted, ya procesado, sin referencias futuras.
#   KEEP-CONTEXT — override explicito en next-task: si contiene "KEEP-CONTEXT",
#                  fuerza KEEP independientemente del tier.
#
# Salida:
#   stdout: una linea "VERDICT: <reason>" (humano)
#   o JSON con --json: {verdict, reason, abstract, tier}
#
# Exit codes:
#   0 — veredicto emitido (KEEP/STUB/DROP)
#   2 — argumentos invalidos

PATH_ARG=""
NEXT_TASK=""
JSON=0
ABSTRACT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) PATH_ARG="${2:-}"; shift 2 ;;
    --next-task) NEXT_TASK="${2:-}"; shift 2 ;;
    --abstract) ABSTRACT_OVERRIDE="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PATH_ARG" ]]; then
  echo "ERROR: --path required" >&2
  exit 2
fi

# Resolver workspace + tier via context-origin-tag
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG_SCRIPT="${SCRIPT_DIR}/context-origin-tag.sh"

TIER="untrusted"
if [[ -x "$TAG_SCRIPT" ]]; then
  TIER=$(bash "$TAG_SCRIPT" "$PATH_ARG" 2>/dev/null || echo "untrusted")
fi

# Helper: extrae primera linea no-frontmatter no vacia como abstract
extract_abstract() {
  local p="$1"
  local in_frontmatter=0
  local seen_open=0
  if [[ ! -f "$p" ]] || [[ ! -r "$p" ]]; then
    echo ""
    return
  fi
  while IFS= read -r line; do
    # Detectar frontmatter ---
    if [[ "$line" == "---" ]]; then
      if [[ "$seen_open" -eq 0 ]]; then
        in_frontmatter=1
        seen_open=1
        continue
      else
        in_frontmatter=0
        continue
      fi
    fi
    [[ "$in_frontmatter" -eq 1 ]] && continue
    # Trim leading whitespace
    cleaned="${line#"${line%%[! ]*}"}"
    # Saltar lineas vacias
    [[ -z "$cleaned" ]] && continue
    # Limpiar headers markdown (#, ##, ###, ...) — quitar # iniciales y el espacio
    while [[ "$cleaned" == \#* ]]; do
      cleaned="${cleaned#\#}"
    done
    cleaned="${cleaned#"${cleaned%%[! ]*}"}"
    # Si quedo vacio, sigue
    [[ -z "$cleaned" ]] && continue
    # Truncar a 200 chars
    if [[ ${#cleaned} -gt 200 ]]; then
      cleaned="${cleaned:0:197}..."
    fi
    echo "$cleaned"
    return
  done < "$p"
  echo ""
}

VERDICT=""
REASON=""
ABSTRACT=""

# === Heuristica de decision ===

# 1. Override explicito KEEP-CONTEXT
if [[ "$NEXT_TASK" == *"KEEP-CONTEXT"* ]]; then
  VERDICT="KEEP"
  REASON="override KEEP-CONTEXT in next-task"

# 2. Tier siempre relevante
elif [[ "$TIER" == "N1-anchor" ]] || [[ "$TIER" == "N2-eager" ]]; then
  VERDICT="KEEP"
  REASON="tier $TIER siempre relevante"

# 3. untrusted → DROP
elif [[ "$TIER" == "untrusted" ]]; then
  VERDICT="DROP"
  REASON="tier untrusted: descartado tras uso"

# 4. sandbox → KEEP (work-in-progress del agente)
elif [[ "$TIER" == "sandbox" ]]; then
  VERDICT="KEEP"
  REASON="sandbox: work-in-progress"

# 5. Si el path aparece en next-task → KEEP
else
  # Comprobar si filename o subpath aparece en next-task
  basename_path=$(basename "$PATH_ARG")
  if [[ -n "$NEXT_TASK" ]] && { [[ "$NEXT_TASK" == *"$basename_path"* ]] || [[ "$NEXT_TASK" == *"$PATH_ARG"* ]]; }; then
    VERDICT="KEEP"
    REASON="referencia textual a $basename_path en next-task"
  else
    # 6. N4a/N4b/N5/N4-project sin referencia futura → STUB
    VERDICT="STUB"
    REASON="tier $TIER sin referencia en next-task"
    if [[ -n "$ABSTRACT_OVERRIDE" ]]; then
      ABSTRACT="$ABSTRACT_OVERRIDE"
    else
      ABSTRACT=$(extract_abstract "$PATH_ARG")
    fi
    [[ -z "$ABSTRACT" ]] && ABSTRACT="(abstract no disponible)"
  fi
fi

# === Emitir resultado ===

if [[ "$JSON" -eq 1 ]]; then
  # JSON sin python: en Windows python decodifica stdin como cp1252 (mojibake) y
  # las rutas C:\... llevan "\" que hay que escapar en todos los campos.
  json_str() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
    s="${s//[[:cntrl:]]/}"
    printf '"%s"' "$s"
  }
  printf '{"verdict":%s,"reason":%s,"abstract":%s,"tier":%s,"path":%s}\n' \
    "$(json_str "$VERDICT")" "$(json_str "$REASON")" "$(json_str "$ABSTRACT")" \
    "$(json_str "$TIER")" "$(json_str "$PATH_ARG")"
else
  echo "$VERDICT: $REASON"
  if [[ "$VERDICT" == "STUB" ]] && [[ -n "$ABSTRACT" ]]; then
    echo "abstract: $ABSTRACT"
  fi
fi

exit 0
