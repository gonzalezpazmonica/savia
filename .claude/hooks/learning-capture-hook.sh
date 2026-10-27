#!/usr/bin/env bash
set -uo pipefail
# learning-capture-hook.sh — SCL-001 S1: disparador de captura para el bucle
#
# Detecta errores reconocidos / correcciones en output de agentes (PostToolUse
# Task) y genera una learning proposal canónica (PURE_BASH, sin bindings).
# Idempotente por hash de evidencia (AC-1.3). Siempre exit 0 — nunca bloquea.
#
# Master switch: SAVIA_LEARNING_CAPTURE=on|off (default ON — el bucle debe
#   capturar por sí solo; off solo para mantenimiento/CI). Rate-limit e
#   idempotencia por hash evitan saturación.
# Trigger: PostToolUse Task (output del agente contiene patrones de error
#         reconocido / corrección / lección aprendida)
#
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md (S1)
# Ref: docs/rules/domain/scl-001-learning-loop.md

# ── Master switch (default ON: el bucle captura solo; el bug del disparador
#    apagado se corrigio 2026-08-20 — un bucle con switch off no aprende) ──
SAVIA_LEARNING_CAPTURE="${SAVIA_LEARNING_CAPTURE:-on}"
if [[ "$SAVIA_LEARNING_CAPTURE" != "on" ]]; then
  exit 0
fi

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROPOSAL_SCRIPT="${REPO_ROOT}/scripts/learning-proposal.sh"
PROPOSALS_DIR="${SCL_PROPOSALS_DIR:-${REPO_ROOT}/docs/learning-proposals}"
GRAPH_INDEX="${SCL_GRAPH_INDEX:-${REPO_ROOT}/output/learning-loop/graph-index.jsonl}"

[[ -f "$PROPOSAL_SCRIPT" ]] || exit 0

# ── Read hook input (stdin JSON) ─────────────────────────────────────────
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null) || true
fi
[[ -z "$INPUT" ]] && exit 0

TOOL_NAME=""
TOOL_RESPONSE=""
AGENT_NAME=""
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(jq -r '.tool_name // ""' <<< "$INPUT" 2>/dev/null || true)
  TOOL_RESPONSE=$(jq -r '.tool_response // .output // ""' <<< "$INPUT" 2>/dev/null || true)
  AGENT_NAME=$(jq -r '.tool_input.agent // .agent // ""' <<< "$INPUT" 2>/dev/null || true)
fi

# Only act on Task tool outputs (agent completions)
if [[ "$TOOL_NAME" != "Task" && "$TOOL_NAME" != "task" && "$TOOL_NAME" != "Agent" ]]; then
  exit 0
fi
[[ -z "$TOOL_RESPONSE" ]] && exit 0

# ── Error-recognition keyword detection ──────────────────────────────────
# Normalize: lowercase + strip accents for robust matching (prod bugfix:
# "leccion aprendida" sin tilde no matcheaba "lección aprendida").
# tr no baja a minuscula las mayusculas acentuadas (multibyte): se mapean aparte.
normalize() { echo "$1" | LC_ALL=C.UTF-8 sed 's/[ÁÀÄÂ]/a/g;s/[ÉÈËÊ]/e/g;s/[ÍÌÏÎ]/i/g;s/[ÓÒÖÔ]/o/g;s/[ÚÙÜÛ]/u/g;s/Ñ/n/g' | tr '[:upper:]' '[:lower:]' | LC_ALL=C.UTF-8 sed 's/[áàäâ]/a/g;s/[éèëê]/e/g;s/[íìïî]/i/g;s/[óòöô]/o/g;s/[úùüû]/u/g;s/ñ/n/g'; }

ERROR_KEYWORDS=(
  "error reconocido" "se reconoce el error" "mismo error"
  "reintroduce" "volvio a fallar" "volvimos a fallar" "volvimos a equivocarnos"
  "leccion aprendida" "lessons learned" "recurrencia"
  "lo corregi" "corregi el bug" "bug reintroducido"
)

FOUND_KEYWORD=""
NORM_RESPONSE=$(normalize "$TOOL_RESPONSE")
for kw in "${ERROR_KEYWORDS[@]}"; do
  if echo "$NORM_RESPONSE" | grep -q "$kw"; then
    FOUND_KEYWORD="$kw"
    break
  fi
done

# ── Desviacion de norma (no verbalizada como error, detectable en el
#    razonamiento): cuando el agente reconoce que uso el canal/mecanismo
#    equivocado o que debio usar otro. Caso real 2026-08-20: filesystem vs MCP.
# ── (patron: autocorreccion metodologica del sustrato) ──
if [[ -z "$FOUND_KEYWORD" ]]; then
  # pares "regex a matchear|keyword limpio para diagnostico"
  DEVIATION_PATTERNS=(
    "deberia haber usado|deberia haber usado" "debi usar|debi usar"
    "en vez de usar|en vez de usar" "canal equivocado|canal equivocado"
    "no use el mcp|no use el mcp" "me falto usar|me falto usar"
    "no estaba usando|no estaba usando" "por error use|por error use"
    "no debio entrar|no debio entrar" "no debio ir|no debio ir"
    "no deberia haber|no deberia haber" "no es el lugar|no es el lugar"
    "debi mantener|debi mantener" "debi haber usado|debi haber usado"
  )
  for pat in "${DEVIATION_PATTERNS[@]}"; do
    rx="${pat%%|*}"
    label="${pat#*|}"
    if echo "$NORM_RESPONSE" | grep -qE "$rx"; then
      FOUND_KEYWORD="desviacion de norma: $label"
      break
    fi
  done
fi
[[ -z "$FOUND_KEYWORD" ]] && exit 0

# ── Extract evidence: the file(s) touched by this task if any ────────────
EVIDENCE=""
if command -v jq >/dev/null 2>&1; then
  EVIDENCE=$(jq -r '.tool_input.files[]? // .tool_input.file // ""' <<< "$INPUT" 2>/dev/null \
    | tr '\n' ',' | sed 's/,$//' | sed 's/,/,/g')
fi

# learning-proposal.sh rechaza rutas inexistentes y la captura se perdia en
# silencio (el agente suele dar rutas relativas a otro cwd): conservar solo
# las que existen y, si no queda ninguna, caer al hash de la respuesta.
if [[ -n "$EVIDENCE" ]]; then
  KEPT=""
  IFS=',' read -ra EV_PATHS <<< "$EVIDENCE"
  for ev in "${EV_PATHS[@]}"; do
    [[ -f "${ev%%:*}" || -f "$ev" ]] && KEPT="${KEPT:+$KEPT,}$ev"
  done
  EVIDENCE="$KEPT"
fi

# ── If no file evidence, hash the agent's response content ───────────────
# (Unique per turn — otherwise the hook would use a constant evidence and
#  idempotency would block ALL captures within 24h. Prod-verified bugfix.)
if [[ -z "$EVIDENCE" ]]; then
  RESP_HASH=$(printf '%s' "$TOOL_RESPONSE" | sha256sum | cut -d' ' -f1)
  EVIDENCE="session:response:${RESP_HASH}"
fi

# ── Extract diagnosis + change from the normalized response ──────────────
# (NORM_RESPONSE has no accents; FOUND_KEYWORD is accent-free — grep matches.)
# Para desviaciones de norma, FOUND_KEYWORD es una etiqueta construida (no
# aparece literal); el diagnostico usa la primera linea de la respuesta.
if [[ "$FOUND_KEYWORD" == "desviacion de norma:"* ]]; then
  DIAGNOSIS=$(echo "$NORM_RESPONSE" | head -1 | head -c 300 | tr -d '\n\r' | sed 's/["`'\'']/\"/g')
  CHANGE=$(echo "$NORM_RESPONSE" | tail -1 | head -c 300 | tr -d '\n\r')
else
  DIAGNOSIS=$(echo "$NORM_RESPONSE" \
    | grep -m1 -B1 "$FOUND_KEYWORD" \
    | head -c 300 \
    | tr -d '\n\r' \
    | sed 's/["`'\'']/\"/g')

  CHANGE=$(echo "$NORM_RESPONSE" \
    | grep -m1 -A2 "$FOUND_KEYWORD" \
    | tail -1 \
    | head -c 300 \
    | tr -d '\n\r')
fi
[[ -z "$CHANGE" ]] && CHANGE="Revisar y proponer correccion"

# ── Generate learning proposal (idempotent) ──────────────────────────────
bash "$PROPOSAL_SCRIPT" \
  --origin "hook captura: agente $AGENT_NAME reconoce error ($FOUND_KEYWORD)" \
  --evidence "$EVIDENCE" \
  --diagnosis "$DIAGNOSIS" \
  --change "$CHANGE" \
  --target memoria \
  --trigger recurrence \
  --output-dir "$PROPOSALS_DIR" \
  --graph-index "$GRAPH_INDEX" \
  >/dev/null 2>&1 || true

# Always exit 0 — never block
exit 0
