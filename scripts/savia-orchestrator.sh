#!/usr/bin/env bash
# savia-orchestrator.sh — SCL-011: orquestador SAGI mínimo.
#
# Integra los 4 pilares en un bucle de decisión continuo:
#   LEER (CRITERIO human_authored + cúpula SaviaLearning via recall)
#   DECIDIR (LLM como heurística sobre el contexto del sustrato — PURE_BASH
#            compone scripts existentes; el LLM se invoca vía contrato mínimo)
#   PERSISTIR (learning-proposal --persist)
#   MEDIR (learning-metric.sh → métrica L)
#   AJUSTAR (learning-autonomy.sh por p_consistent)
#
# COMPONE, no reimplementa (SCL-011 R1). CRITERIO y CONSTITUCION intocables
# (CRIT-031, ART-11): todo output termina en propuesta INFERRED. Sin vendor
# names, sin red salvo endpoints del sustrato local, PURE_BASH (parámetro: el
# LLM es opcional; si no está disponible o falla, el orquestador sigue con la
# ruta determinista shadow).
#
# Usage:
#   savia-orchestrator.sh --task "descripción" [--dry-run] [--iterations N]
#         [--decide "flash|none|local"] [--p-consistent X]
# Exit: 0 ok · 2 input inválido · 3 dependencia ausente
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SAVIA_WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-$ROOT}"

TASK=""
DRY_RUN=false
ITERATIONS=1
DECIDE="${SAGI_DECIDE:-none}"
P_CONSISTENT="${SAGI_P_CONSISTENT:-}"
SAGI_DECISION=""
META=false
SAGI_META_ACTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --iterations) ITERATIONS="$2"; shift 2 ;;
    --decide) DECIDE="$2"; shift 2 ;;
    --p-consistent) P_CONSISTENT="$2"; shift 2 ;;
    --meta) META=true; shift ;;
    *) echo "usage: $0 --task T [--dry-run] [--iterations N] [--decide none|flash|local] [--meta]" >&2; exit 2 ;;
  esac
done
[[ -z "$TASK" ]] && { echo "ERROR: --task requerido" >&2; exit 2; }
[[ "$ITERATIONS" =~ ^[0-9]+$ ]] || { echo "ERROR: --iterations entero" >&2; exit 2; }

# ── Dependencias (composición, no reimplementación) ──────────────────────────
for dep in learning-recall.sh learning-proposal.sh learning-metric.sh learning-autonomy.sh; do
  [[ -x "$ROOT/scripts/$dep" ]] || { echo "ERROR: dependencia ausente: scripts/$dep" >&2; exit 3; }
done

# ── Fase 1: LEER sustrato ────────────────────────────────────────────────────
read_sustrate() {
  # 1a. criterio human_authored
  local crit keyword
  crit="$ROOT/CRITERIO.md"
  keyword="criterio soberania dato self-hosted"
  if [[ -n "$TASK" ]]; then
    crit=$(echo "$TASK $keyword" | tr '[:upper:]' '[:lower:]' | tr -d 'áéíóúñ' | head -c 120)
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [leer] CRITERIO.md"
    return
  fi
  local recall_out
  if [[ "${SAVIA_LEARNING_APPLIED:-on}" == "off" ]]; then
    recall_out=$(bash "$ROOT/scripts/learning-recall.sh" --query "$TASK" --mode shadow --json 2>/dev/null | python3 -c "import sys,json;print(int(json.load(sys.stdin).get('shadow_hits',0)))" 2>/dev/null || echo 0)
    echo "  [leer] CRITERIO (+$recall_out shadow hits de SaviaLearning)"
    return
  fi
  # SE-515 S1: recall efectivo; si no está disponible, se declara shadow y el motivo.
  local rc
  recall_out=$(bash "$ROOT/scripts/learning-recall.sh" --query "$TASK" --mode effective --json 2>/dev/null)
  rc=$?
  if (( rc == 0 )) && [[ -n "$recall_out" ]]; then
    local ids
    ids=$(python3 -c "import sys,json;print(','.join(h['criterion_id'] for h in json.load(sys.stdin)['effective_hits']))" <<<"$recall_out" 2>/dev/null) || ids="?"
    echo "  [leer] recall=effective criterios=[${ids}]"
    return
  fi
  # Exit 3 (sin cúpula o sin CLI) no depende del modo: repetir en shadow solo añadiría otra fila
  # al log de recall con el mismo fallo. Ante otro error sí se intenta shadow (una fila por intento).
  if (( rc == 3 )); then
    echo "  [leer] recall=no disponible (sin cúpula o sin CLI); la decisión no usa criterios"
    return
  fi
  local reason="error (exit $rc)"
  recall_out=$(bash "$ROOT/scripts/learning-recall.sh" --query "$TASK" --mode shadow --json 2>/dev/null)
  if [[ $? -eq 0 && -n "$recall_out" ]]; then
    local hits
    hits=$(python3 -c "import sys,json;print(int(json.load(sys.stdin).get('shadow_hits',0)))" <<<"$recall_out" 2>/dev/null || echo 0)
    echo "  [leer] recall=shadow (declarado; efectivo no disponible: $reason) hits=$hits"
  else
    echo "  [leer] recall=no disponible ($reason); la decisión no usa criterios"
  fi
}

# ── Fase 2: DECIDIR (heurística; el LLM es opcional) ─────────────────────────
decide() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [decidir] heurística=$DECIDE (dry-run, sin ejecutar)"
    return
  fi
  case "$DECIDE" in
    llm|local)
      # LLM como heurística local (CRIT-001): Ollama en 127.0.0.1, sin cloud.
      local prompt
      prompt="Eres el algoritmo SAGI sobre el sustrato Savia. Tarea: $TASK. Lee el criterio CRITERIO.md (linea_roja sovereign del dato) y propone UNA mejora de proceso para el sustrato (skill/criterio/memoria) en una frase breve. Sin rellenar, directo. Output: propuesta en 1-2 frases."
      local resp
      resp=$(curl -s --max-time 20 http://127.0.0.1:11434/api/generate \
        -d "{\"model\":\"${SAGI_LLM_MODEL:-qwen2.5:3b}\",\"prompt\":\"$prompt\",\"stream\":false,\"options\":{\"num_predict\":120}}" 2>/dev/null \
        | python3 -c "import sys,json;print(json.load(sys.stdin).get('response',''))" 2>/dev/null || echo "")
      if [[ -n "$resp" ]]; then
        echo "  [decidir] heurística=local(${SAGI_LLM_MODEL:-qwen2.5:3b}) → $resp"
        SAGI_DECISION="$resp"
      else
        echo "  [decidir] heurística=local NO disponible (Ollama apagado?) — shadow determinista"
        SAGI_DECISION="propuesta determinista shadow"
      fi
      ;;
    *)
      # ruta determinista shadow: sin LLM, el bucle solo captura y mide.
      echo "  [decidir] heurística=$DECIDE — propuesta determinista shadow"
      SAGI_DECISION="propuesta determinista shadow"
      ;;
  esac
}

# ── Fase 3: PERSISTIR (solo propone; INFERRED, nunca human_authored) ─────────
persist() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [persistir] learning-proposal --persist (dry-run)"
    return
  fi
  local change="${SAGI_DECISION:-$1}"
  bash "$ROOT/scripts/learning-proposal.sh" \
    --origin "savia-orchestrator (SCL-011): tarea '$TASK'" \
    --evidence "$ROOT/scripts/savia-orchestrator.sh" \
    --diagnosis "orquestador SCL-011 procesó la tarea; propuesta de aprendizaje generada ($change)" \
    --change "$change" --target skill --trigger recurrence >/dev/null 2>&1 && echo "  [persistir] LP creada (INFERRED)"
}

# ── Fase 4: MEDIR (métrica L) ────────────────────────────────────────────────
measure() {
  local base_p="${P_CONSISTENT:-0.5}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [medir] L = f(p_consistent=$base_p, divergencia, ignorancia)"
    return
  fi
  if [[ "${SAVIA_LEARNING_APPLIED:-on}" == "off" ]]; then
    bash "$ROOT/scripts/learning-metric.sh" --p-consistent "$base_p" --divergence 0.2 --ignorance-resolved 0.1 2>/dev/null | tail -1
    return
  fi
  # SE-515 S1 (AC-4): solo es «medido» si llegan los tres componentes medidos;
  # con cualquier valor por defecto, la salida va marcada «no medido».
  local div="${SAGI_L_DIVERGENCE:-}" ign="${SAGI_L_IGNORANCE_RESOLVED:-}" defaults=()
  [[ -n "$P_CONSISTENT" ]] || defaults+=(p_consistent)
  [[ -n "$div" ]] || { div=0.2; defaults+=(divergence); }
  [[ -n "$ign" ]] || { ign=0.1; defaults+=(ignorance_resolved); }
  local args=(--p-consistent "$base_p" --divergence "$div" --ignorance-resolved "$ign" --json) out L
  (( ${#defaults[@]} == 0 )) && args+=(--measured)
  out=$(bash "$ROOT/scripts/learning-metric.sh" "${args[@]}" 2>/dev/null) || { echo "  [medir] L no calculable (entrada inválida)"; return; }
  # Refutación Codex (PR #1523): si la salida no se puede leer, no hay medida que declarar.
  L=$(python3 -c "import sys,json;v=json.load(sys.stdin)['L'];assert isinstance(v,(int,float)) and not isinstance(v,bool);print(v)" <<<"$out" 2>/dev/null) \
    || { echo "  [medir] L no calculable (salida de la métrica ilegible)"; return; }
  if (( ${#defaults[@]} == 0 )); then
    echo "  [medir] L=$L (medido)"
  else
    local IFS=,
    echo "  [medir] L=$L (no medido: valores por defecto en ${defaults[*]})"
  fi
}

# ── Fase 5: AJUSTAR autonomía por p_consistent (SCL-006) ─────────────────────
adjust() {
  local base_p="${P_CONSISTENT:-0.5}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [ajustar] autonomía L0-L3 por p_consistent=$base_p (dry-run)"
    return
  fi
  bash "$ROOT/scripts/learning-autonomy.sh" --p-consistent "$base_p" --requested L2 2>/dev/null | tail -1 || echo "  [ajustar] n/a"
}

# ── Capa metacognitiva (L13) ──────────────────────────────────────────────────
metacog() {
  # confianza declarada: el orquestador "cree" en su decisión (heurística o 0.6)
  local deconf="${SAGI_CONFIDENCE:-60}"
  local mout
  mout=$(bash "$ROOT/scripts/meta-monitor.sh" --task "$TASK" --confidence "$deconf" \
    --divergence "${SAGI_DIVERGENCE:-0.3}" --evidence "${SAGI_EVIDENCE:-0.6}" 2>/dev/null)
  if [[ -n "$mout" ]]; then
    local adjusted hint
    adjusted=$(echo "$mout" | python3 -c "import sys,json;print(json.load(sys.stdin)['confidence_adjusted'])" 2>/dev/null || echo 0)
    hint=$(echo "$mout" | python3 -c "import sys,json;print(json.load(sys.stdin)['action_hint'])" 2>/dev/null || echo "")
    echo "  [meta] confianza $deconf → ajustada $adjusted · $hint"
    # F2: meta-control decide la acción de control (propuesta, no ejecución)
    local ctl
    ctl=$(bash "$ROOT/scripts/meta-control.sh" --adjusted "$adjusted" \
          --divergence "${SAGI_DIVERGENCE:-0.3}" --calibration "${SAGI_CALIBRATION:-0.5}" \
          --requested decide --dry-run 2>/dev/null || echo "")
    if [[ -n "$ctl" ]]; then
      local caction
      caction=$(echo "$ctl" | python3 -c "import sys,json;print(json.load(sys.stdin)['action'])" 2>/dev/null || echo "")
      echo "  [meta] control → $caction (propuesta, no auto-ejecutada — CRIT-031)"
      SAGI_META_ACTION="$caction"
    fi
  else
    echo "  [meta] monitor no disponible (falta meta-monitor.sh) — omitido"
    SAGI_META_ACTION="UNKNOWN"
  fi
}

# ── N ciclos ─────────────────────────────────────────────────────────────────
for (( i=1; i<=ITERATIONS; i++ )); do
  echo "── ciclo $i/$ITERATIONS ──"
  read_sustrate
  decide
  if $META; then metacog; fi
  persist "el bucle SCL-011 mejora el recuerdo del criterio para la tarea: $TASK"
  measure
  adjust
done

echo "── done (dry_run=$DRY_RUN, iterations=$ITERATIONS) ──"
exit 0