#!/usr/bin/env bash
# guard-decision-log.sh — medición de las decisiones de los guards (allow y block).
#
# Uso (source):
#   guard_decision_log <guard> <allow|block> <motivo-corto>
# Añade UNA línea JSON a output/guard-decisions/<guard>.jsonl:
#   {"ts":"2026-01-01T00:00:00Z","guard":"<guard>","verdict":"allow|block","reason":"<motivo>"}
# Solo se registra un código de motivo corto, NUNCA la orden, el contenido de
# ficheros ni rutas: el motivo se reduce a [a-z0-9-] y 64 caracteres.
# Raíz: $CLAUDE_PROJECT_DIR/output/guard-decisions (output/ está en .gitignore),
# si no la raíz del repo de esta librería.
# Registrar nunca cambia la decisión: cualquier fallo de escritura se ignora y
# la función devuelve 0 siempre.

guard_decision_log() {
  local guard="${1:-}" verdict="${2:-}" reason="${3:-sin-motivo}" dir file ts
  case "$verdict" in allow|block) ;; *) return 0 ;; esac
  guard="${guard,,}"; guard="${guard//[^a-z0-9-]/-}"
  [[ -n "$guard" ]] || return 0
  reason="${reason,,}"; reason="${reason//[^a-z0-9-]/-}"; reason="${reason:0:64}"
  [[ -n "$reason" ]] || reason="sin-motivo"
  # Sin variable propia para el directorio (revisión #1628): no se redirige fuera de output/.
  dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)}/output/guard-decisions"
  file="$dir/$guard.jsonl"
  mkdir -p "$dir" 2>/dev/null || return 0
  # Ni el directorio ni el fichero pueden ser enlaces: no se añade a otro fichero (revisión #1628).
  [[ -L "$dir" || -L "$file" ]] && return 0
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || return 0
  printf '{"ts":"%s","guard":"%s","verdict":"%s","reason":"%s"}\n' \
    "$ts" "$guard" "$verdict" "$reason" >> "$file" 2>/dev/null || true
  return 0
}
