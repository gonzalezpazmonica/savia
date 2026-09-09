#!/usr/bin/env bash
# roadmap.sh — SE-378: CLI del planning state machine.
# Uso: roadmap.sh current | next | history <ID> | validate | render
# Fuente de estado: docs/propuestas/planning-state.json (única representación actual).
# Transiciones: docs/propuestas/LOG.md (append-only, SE-222).
set -uo pipefail
ROOT="${REPO_ROOT:-$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)}"
STATE="$ROOT/docs/propuestas/planning-state.json"
[[ -f "$STATE" ]] || { echo "ERROR: falta $STATE" >&2; exit 1; }
CMD="${1:-current}"

case "$CMD" in
  current)
    echo "# Roadmap Current (GENERATED — no editar; fuente: planning-state.json)"
    echo
    jq -r '.initiatives[] | select(.status=="APPROVED" or .status=="IMPLEMENTING") | "- \(.id) [\(.status)] \(.title // "") — evidencia: \(.evidence // "n/a")"' "$STATE"
    ;;
  next)
    echo "# Siguiente (GENERATED)"
    echo
    jq -r '.initiatives[] | select(.status=="PROPOSED" or .status=="APPROVED") | "- \(.id) [\(.status)] prioridad=\(.priority // "n/a") — \(.title // "")"' "$STATE"
    ;;
  history)
    ID="${2:-}"
    [[ -z "$ID" ]] && { echo "uso: roadmap.sh history SE-XXX" >&2; exit 1; }
    jq -r --arg id "$ID" '.initiatives[] | select(.id==$id) | "id: \(.id)\nestado: \(.status)\nevidencia: \(.evidence // "n/a")\naprobación: \(.approval // "n/a")\ntítulo: \(.title // "")"' "$STATE"
    grep -h "$ID" "$ROOT/docs/propuestas/LOG.md" 2>/dev/null | tail -5 || true
    ;;
  validate)
    ERR=0
    # 1. IDs únicos
    DUP=$(jq -r '.initiatives[].id' "$STATE" | sort | uniq -d)
    [[ -n "$DUP" ]] && { echo "FAIL: IDs duplicados: $DUP"; ERR=1; }
    # 2. Estados válidos
    BAD=$(jq -r '.initiatives[].status' "$STATE" | grep -vE '^(IDEA|PROPOSED|APPROVED|IMPLEMENTING|IMPLEMENTED|REJECTED|SUPERSEDED|DEFERRED|RETIRED)$' | sort -u)
    [[ -n "$BAD" ]] && { echo "FAIL: estados inválidos: $BAD"; ERR=1; }
    # 3. IMPLEMENTED requiere evidencia
    NOEV=$(jq -r '.initiatives[] | select(.status=="IMPLEMENTED") | select((.evidence // "") == "") | .id' "$STATE")
    [[ -n "$NOEV" ]] && { echo "FAIL: IMPLEMENTED sin evidencia: $NOEV"; ERR=1; }
    # 4. APPROVED requiere aprobación
    NOAP=$(jq -r '.initiatives[] | select(.status=="APPROVED") | select((.approval // "") == "") | .id' "$STATE")
    [[ -n "$NOAP" ]] && { echo "FAIL: APPROVED sin aprobación registrada: $NOAP"; ERR=1; }
    # 5. Cobertura explícita del registro para la era canónica.
    FLOOR=$(jq -r '.tracked_spec_floor // empty' "$STATE")
    if ! [[ "$FLOOR" =~ ^[0-9]+$ ]]; then
      echo "FAIL: tracked_spec_floor ausente o inválido"
      ERR=1
    else
      OMITTED=""
      while IFS= read -r spec; do
        ID=$(basename "$spec" | grep -oP '^SE-\d+')
        NUM=${ID#SE-}
        (( 10#$NUM < FLOOR )) && continue
        if ! jq -e --arg id "$ID" '.initiatives[] | select(.id==$id)' "$STATE" >/dev/null; then
          OMITTED="${OMITTED}${OMITTED:+ }$ID"
        fi
      done < <(find "$ROOT/docs/specs" -name 'SE-*.spec.md' | sort -V)
      [[ -n "$OMITTED" ]] && { echo "FAIL: specs omitidas de planning-state: $OMITTED"; ERR=1; }
    fi
    # 6. Estado del spec en docs/specs vs state (YAML o Markdown legacy).
    while IFS= read -r spec; do
      ID=$(basename "$spec" | grep -oP '^SE-\d+')
      [[ -z "$ID" ]] && continue
      SPEC_STATUS=$(grep -m1 -oP '^(?:status:\s*|\*\*Estado:\*\*\s*)\K[A-Z_]+' "$spec" 2>/dev/null || echo "")
      STATE_STATUS=$(jq -r --arg id "$ID" '.initiatives[] | select(.id==$id) | .status' "$STATE" 2>/dev/null | head -1)
      if [[ -n "$STATE_STATUS" && -n "$SPEC_STATUS" && "$SPEC_STATUS" != "$STATE_STATUS" ]]; then
        COMPAT=0
        [[ "$STATE_STATUS" == "IMPLEMENTED" && "$SPEC_STATUS" == "APPROVED" ]] && COMPAT=1
        [[ "$STATE_STATUS" == "IMPLEMENTING" && "$SPEC_STATUS" == "APPROVED" ]] && COMPAT=1
        if [[ $COMPAT -eq 0 ]]; then
          echo "FAIL: $ID spec=$SPEC_STATUS vs state=$STATE_STATUS"
          ERR=1
        fi
      fi
    done < <(find "$ROOT/docs/specs" -name 'SE-*.spec.md' | sort)
    [[ $ERR -eq 0 ]] && echo "PASS: planning state consistente"
    exit $ERR
    ;;
  render)
    bash "$0" current > "$ROOT/docs/propuestas/ROADMAP-CURRENT.md"
    echo "rendered: docs/propuestas/ROADMAP-CURRENT.md"
    ;;
  *)
    echo "uso: roadmap.sh current | next | history <ID> | validate | render" >&2
    exit 1
    ;;
esac
