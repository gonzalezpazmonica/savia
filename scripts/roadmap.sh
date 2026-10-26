#!/usr/bin/env bash
# roadmap.sh — SE-378: CLI del planning state machine.
# Uso: roadmap.sh current | next | history <ID> | validate | render
# Fuente de estado: docs/propuestas/planning-state.json (única representación actual).
# Transiciones: docs/propuestas/LOG.md (append-only, SE-222).
set -uo pipefail
ROOT="${REPO_ROOT:-$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)}"
STATE="$ROOT/docs/propuestas/planning-state.json"
MAIN_REF="${PLANNING_MAIN_REF:-origin/main}"
[[ -f "$STATE" ]] || { echo "ERROR: falta $STATE" >&2; exit 1; }
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/planning-completion.sh"
CMD="${1:-current}"

render_sessions() {
  jq -e '.route.session_plan | type == "array" and length > 0' "$STATE" >/dev/null 2>&1 || return 0
  echo "## Cola de sesiones (orden por gates, sin fechas)"
  echo
  jq -r '.route.session_plan[] |
    "- **\(.id) · \(.priority) · fase \(.phase)** — \(.title)\n  Acción: \(.action)\n  Entrada: \(.prerequisites)\n  Salida: \(.done)\n  Necesidad: \(.necessity); urgencia: \(.urgency); valor: \(.value); desbloqueo: \(.dependency_value); esfuerzo: \(.effort).\n"' "$STATE"
}

case "$CMD" in
  current)
    echo "# Roadmap Current (GENERATED — no editar; fuente: planning-state.json)"
    echo
    if jq -e '.route' "$STATE" >/dev/null 2>&1; then
      jq -r '"Fase \(.route.current_phase) · WIP \([.initiatives[] | select(.status=="IMPLEMENTING")] | length)/\(.route.wip_limit.savia_implementing). Estado y cola canónicos; ADR-002.\n"' "$STATE"
    fi
    render_sessions
    echo "## Iniciativas aprobadas o en curso"
    echo
    echo "Integrada en main no significa graduada; delivery no sustituye completion y revisión humana."
    echo
    jq -r '.initiatives[] | select(.status=="APPROVED" or .status=="IMPLEMENTING") | "- \(.id) [\(.status)] \(.title // "") — evidencia: \(.evidence // "n/a")\(if .delivery then " · integrada #\(.delivery.merge_pr); revisar evidencia/graduación" else "" end)"' "$STATE"
    ;;
  next)
    echo "# Siguiente (GENERATED)"
    echo
    PHASE=$(jq -r '.route.current_phase // empty' "$STATE")
    if [[ -n "$PHASE" ]]; then
      WIP=$(jq -r '.route.wip_limit.savia_implementing // empty' "$STATE")
      if ! [[ "$WIP" =~ ^[0-9]+$ ]]; then
        echo "ERROR: route.wip_limit.savia_implementing inválido" >&2
        exit 1
      fi
      NIMP=$(jq '[.initiatives[] | select(.status=="IMPLEMENTING")] | length' "$STATE")
      echo "Fase $PHASE · WIP $NIMP/$WIP"
      echo
      if (( NIMP >= WIP )); then
        echo "WIP completo ($NIMP/$WIP): continuar las iniciativas en curso antes de iniciar otra."
        jq -r '[.initiatives[] | select(.status=="IMPLEMENTING")] | sort_by(.session_order // 999, .id) | .[] | "- \(.id) [IMPLEMENTING] fase=\(.phase // "n/a") — \(.title // "")"' "$STATE"
        echo
        echo "Revisiones y diseño acotado: consultar la cola de sesiones en roadmap.sh current; ninguna entrada inicia una cuarta iniciativa."
        exit 0
      fi
    fi
    CANDIDATES=$(jq -r --arg phase "$PHASE" '
      [.initiatives[]
        | select(.status=="PROPOSED" or .status=="APPROVED")
        | select($phase=="" or .phase==$phase)]
      | sort_by((.priority // "P999" | ltrimstr("P") | tonumber? // 999), .id)
      | .[]
      | "- \(.id) [\(.status)] prioridad=\(.priority // "n/a") — \(.title // "")\(if .delivery then " (integrada; revisar evidencia/graduación)" elif .status=="PROPOSED" then " (requiere aprobación)" else "" end)"' "$STATE")
    if [[ -n "$CANDIDATES" ]]; then
      echo "$CANDIDATES"
    else
      echo "Sin candidatas en la fase activa."
    fi
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
    # 4b. Nuevos cierres requieren PR estructurado, evidencia AC y revisión humana.
    COMPLETION_FLOOR=$(jq -r '.completion_contract_floor // empty' "$STATE")
    if ! [[ "$COMPLETION_FLOOR" =~ ^[0-9]+$ ]]; then
      echo "FAIL: completion_contract_floor ausente o inválido"
      ERR=1
    else
      while IFS= read -r ID; do
        NUM=${ID#SE-}
        (( 10#$NUM < COMPLETION_FLOOR )) && continue
        COMPLETION=$(jq -c --arg id "$ID" '.initiatives[] | select(.id==$id) | .completion // null' "$STATE")
        if ! planning_acceptance_evidence_valid "$ROOT" "$COMPLETION"; then
          echo "FAIL: evidencia AC inválida para $ID"
          ERR=1
        fi
        PR=$(jq -r '.merge_pr // empty' <<<"$COMPLETION")
        if [[ -z "$PR" ]] || ! planning_pr_merged "$ROOT" "$MAIN_REF" "$PR"; then
          echo "FAIL: IMPLEMENTED sin PR mergeado verificable: $ID"
          ERR=1
        fi
        if ! planning_human_review_approved "$COMPLETION"; then
          echo "FAIL: IMPLEMENTED sin revisión humana aprobada: $ID"
          ERR=1
        fi
      done < <(jq -r '.initiatives[] | select(.status=="IMPLEMENTED") | .id | select(test("^SE-[0-9]+$"))' "$STATE")
    fi
    # 5. Cobertura explícita del registro para la era canónica.
    FLOOR=$(jq -r '.tracked_spec_floor // empty' "$STATE")
    if ! [[ "$FLOOR" =~ ^[0-9]+$ ]]; then
      echo "FAIL: tracked_spec_floor ausente o inválido"
      ERR=1
    else
      OMITTED=""
      while IFS= read -r spec; do
        ID=$(basename "$spec" | grep -oP '^SE-\d+(?=-)' || true)
        [[ -z "$ID" ]] && continue   # IDs no numéricos (p.ej. SE-GRC-001) fuera del floor numérico
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
    # 7. Estado vigente de cada iniciativa trazada registrado en LOG.md (SE-378, append-only).
    LOG="$ROOT/docs/propuestas/LOG.md"
    if [[ "$FLOOR" =~ ^[0-9]+$ ]]; then
      NOLOG=""
      while IFS=$'\t' read -r ID ST; do
        NUM=${ID#SE-}
        (( 10#$NUM < FLOOR )) && continue
        grep -qE "^## [0-9]{4}-[0-9]{2}-[0-9]{2} ${ID}( [^ ]+)* ${ST}$" "$LOG" 2>/dev/null \
          || NOLOG="${NOLOG}${NOLOG:+ }$ID"
      done < <(jq -r '.initiatives[] | select(.id | test("^SE-[0-9]+$")) | [.id, .status] | @tsv' "$STATE")
      [[ -n "$NOLOG" ]] && { echo "FAIL: estado vigente sin registro en LOG.md: $NOLOG"; ERR=1; }
    fi
    # 8. Ruta declarada (ADR-002): límite WIP y fase válida en iniciativas no terminales.
    if jq -e '.route' "$STATE" >/dev/null 2>&1; then
      WIP=$(jq -r '.route.wip_limit.savia_implementing // empty' "$STATE")
      NIMP=$(jq '[.initiatives[] | select(.status=="IMPLEMENTING")] | length' "$STATE")
      if ! [[ "$WIP" =~ ^[0-9]+$ ]]; then
        echo "FAIL: route.wip_limit.savia_implementing ausente o inválido"; ERR=1
      elif (( NIMP > WIP )); then
        echo "FAIL: WIP excedido: $NIMP IMPLEMENTING > límite $WIP"; ERR=1
      fi
      BADPH=$(jq -r '(.route.phases + ["aparcado"]) as $p | .tracked_spec_floor as $f
        | .initiatives[]
        | select(.id | test("^SE-[0-9]+$")) | select((.id | ltrimstr("SE-") | tonumber) >= $f)
        | select(.status | IN("PROPOSED","APPROVED","IMPLEMENTING","DEFERRED"))
        | select((.phase // "") as $x | $p | index($x) | not) | .id' "$STATE")
      [[ -n "$BADPH" ]] && { echo "FAIL: iniciativas sin fase válida de la ruta: $(echo $BADPH)"; ERR=1; }
      # 9. La cola editorial no puede apuntar a estados o fases inexistentes.
      if jq -e '.route | has("session_plan")' "$STATE" >/dev/null 2>&1; then
        if ! jq -e '
          [.initiatives[].id] as $ids | .route.phases as $phases |
          .route.session_plan |
          type == "array" and length > 0 and
          ((map(.id) | length) == (map(.id) | unique | length)) and
          all(.[];
            (.id | type == "string" and length > 0) and
            (.phase as $p | $phases | index($p) != null) and
            (.priority | test("^P[0-3]$")) and
            (.initiatives | type == "array" and all(.[]; . as $id | $ids | index($id) != null)) and
            all(.title, .action, .prerequisites, .done, .necessity, .urgency, .value, .dependency_value, .effort;
              type == "string" and length > 0))
        ' "$STATE" >/dev/null 2>&1; then
          echo "FAIL: cola de sesiones inválida (IDs, fases, referencias o criterios)"; ERR=1
        fi
        # 10. Una entrada no puede seguir pidiendo la aprobación de una spec ya aprobada.
        # Cubre enumeraciones («Aprobación de SE-A, SE-B y SE-C»). DEFERRED no cuenta como
        # resuelta: pedir su reactivación es legítimo. Si jq falla, el check falla cerrado.
        if STALE=$(jq -r '(.initiatives | map({(.id): .status}) | add) as $st
          | .route.session_plan[]? | .id as $s
          | (.prerequisites // ""
             | [scan("[Aa]probación de SE-[0-9]+(?:\\s*(?:,|\\by\\b|\\be\\b)\\s*SE-[0-9]+)*")]
             | map(scan("SE-[0-9]+")) | .[])
          | select($st[.] != null and ($st[.] | IN("IDEA","PROPOSED","DEFERRED") | not))
          | "\($s):\(.)=\($st[.])"' "$STATE" 2>/dev/null); then
          [[ -n "$STALE" ]] && { echo "FAIL: entrada de sesión pide aprobar una spec ya resuelta: ${STALE//$'\n'/ }"; ERR=1; }
        else
          echo "FAIL: check de aprobaciones obsoletas no evaluable (jq falló sobre $STATE)"; ERR=1
        fi
      fi
    fi
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
