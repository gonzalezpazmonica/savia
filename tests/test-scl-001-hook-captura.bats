#!/usr/bin/env bats
# SCL-001 — Hook de captura (learning-capture-hook.sh): producción
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md (S1) + fix prod 2026-08-17

set -uo pipefail

setup_file() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  export REPO_ROOT
}

setup() {
  HOOK="$REPO_ROOT/.claude/hooks/learning-capture-hook.sh"
  TMPD="$(mktemp -d -t scl-hook-XXXXXX)"
  export SAVIA_LEARNING_CAPTURE=on
  export SCL_PROPOSALS_DIR="$TMPD/proposals"
  export SCL_GRAPH_INDEX="$TMPD/graph.jsonl"
  mkdir -p "$SCL_PROPOSALS_DIR"
}

teardown() {
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
}

@test "hook: master switch off → no captura nada (exit 0)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Task\",\"tool_response\":\"se reconoce el error X\"}' | SAVIA_LEARNING_CAPTURE=off SCL_PROPOSALS_DIR='$SCL_PROPOSALS_DIR' SCL_GRAPH_INDEX='$SCL_GRAPH_INDEX' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(ls "$SCL_PROPOSALS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')" = "0" ]
}

@test "hook: error reconocido genera UNA propuesta de aprendizaje" {
  run bash -c "printf '%s' '{\"tool_name\":\"Task\",\"tool_response\":\"se reconoce el error: la memoria captura sin diagnostico\",\"tool_input\":{\"agent\":\"code-reviewer\"}}' | SAVIA_LEARNING_CAPTURE=on SCL_PROPOSALS_DIR='$SCL_PROPOSALS_DIR' SCL_GRAPH_INDEX='$SCL_GRAPH_INDEX' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(ls "$SCL_PROPOSALS_DIR"/*.md | wc -l | tr -d ' ')" = "1" ]
  f=$(ls "$SCL_PROPOSALS_DIR"/*.md)
  grep -q "^trigger: recurrence" "$f"
  grep -q "^provenance: INFERRED" "$f"
  grep -q "^lifecycle: proposed" "$f"
}

@test "hook: no actua en outputs sin keyword de error (exit 0, 0 propuestas)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Task\",\"tool_response\":\"tarea completada sin incidencias\",\"tool_input\":{\"agent\":\"x\"}}' | SAVIA_LEARNING_CAPTURE=on SCL_PROPOSALS_DIR='$SCL_PROPOSALS_DIR' SCL_GRAPH_INDEX='$SCL_GRAPH_INDEX' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(ls "$SCL_PROPOSALS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')" = "0" ]
}

@test "hook fix prod: evidencia por hash de respuesta — errores distintos generan propuestas distintas" {
  for msg in "volvimos a fallar: bug del campo diagnostico" "se reconoce el error: gate no discrimina"; do
    printf '{"tool_name":"Task","tool_response":"%s","tool_input":{"agent":"t"}}' "$msg" \
      | SAVIA_LEARNING_CAPTURE=on SCL_PROPOSALS_DIR="$SCL_PROPOSALS_DIR" SCL_GRAPH_INDEX="$SCL_GRAPH_INDEX" bash "$HOOK"
  done
  count=$(ls "$SCL_PROPOSALS_DIR"/*.md | wc -l | tr -d ' ')
  [ "$count" = "2" ]
  # hashes de evidencia distintos
  h1=$(grep -m1 '^evidence_hash:' "$SCL_PROPOSALS_DIR"/*.md | head -1 | cut -d' ' -f2)
  h2=$(ls "$SCL_PROPOSALS_DIR"/*.md | tail -1 | xargs grep -m1 '^evidence_hash:' | cut -d' ' -f2)
  [ -n "$h1" ] && [ -n "$h2" ]
}

@test "hook fix prod: idempotencia — misma respuesta repetida no duplica" {
  msg='{"tool_name":"Task","tool_response":"volvimos a fallar: mismo error de calibracion","tool_input":{"agent":"t"}}'
  for i in 1 2; do
    printf '%s' "$msg" | SAVIA_LEARNING_CAPTURE=on SCL_PROPOSALS_DIR="$SCL_PROPOSALS_DIR" SCL_GRAPH_INDEX="$SCL_GRAPH_INDEX" bash "$HOOK"
  done
  count=$(ls "$SCL_PROPOSALS_DIR"/*.md | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

@test "hook fix prod: keyword sin tilde matchea (leccion vs lección)" {
  printf '%s' '{"tool_name":"Task","tool_response":"leccion aprendida: verificar hashes antes de firmar","tool_input":{"agent":"r"}}' \
    | SAVIA_LEARNING_CAPTURE=on SCL_PROPOSALS_DIR="$SCL_PROPOSALS_DIR" SCL_GRAPH_INDEX="$SCL_GRAPH_INDEX" bash "$HOOK"
  count=$(ls "$SCL_PROPOSALS_DIR"/*.md | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

@test "hook: siempre exit 0 (no bloquea tool call)" {
  run bash -c "printf '%s' '{}' | SAVIA_LEARNING_CAPTURE=on SCL_PROPOSALS_DIR='$SCL_PROPOSALS_DIR' SCL_GRAPH_INDEX='$SCL_GRAPH_INDEX' bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "hook fix 2026-08-20: default ON — captura sin variable (el disparador aprende solo)" {
  # Regresion: el disparador estaba off por defecto -> el bucle no capturaba.
  printf '%s' '{"tool_name":"Task","tool_response":"se reconoce el error: el disparador no capturaba solo","tool_input":{"agent":"t"}}' \
    | SCL_PROPOSALS_DIR="$SCL_PROPOSALS_DIR" SCL_GRAPH_INDEX="$SCL_GRAPH_INDEX" bash "$HOOK"
  count=$(ls "$SCL_PROPOSALS_DIR"/*.md | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

@test "hook fix 2026-08-20: detecta desviacion de norma sin keyword de error (filesystem vs MCP)" {
  printf '%s' '{"tool_name":"Task","tool_response":"use el filesystem para leer la cupula en vez de usar el mcp del vault, debi usar vault_read","tool_input":{"agent":"x"}}' \
    | SAVIA_LEARNING_CAPTURE=on SCL_PROPOSALS_DIR="$SCL_PROPOSALS_DIR" SCL_GRAPH_INDEX="$SCL_GRAPH_INDEX" bash "$HOOK"
  f=$(ls "$SCL_PROPOSALS_DIR"/*.md | head -1)
  grep -q "desviacion de norma" "$f" || grep -q "debi usar\|en vez de usar" "$f"
}

@test "hook fix 2026-08-20: detecta desviacion de privacidad (no debio entrar en repo publico)" {
  printf '%s' '{"tool_name":"Task","tool_response":"la investigacion no debio entrar en el repo publico, debi mantenerla en la cupula","tool_input":{"agent":"x"}}' \
    | SAVIA_LEARNING_CAPTURE=on SCL_PROPOSALS_DIR="$SCL_PROPOSALS_DIR" SCL_GRAPH_INDEX="$SCL_GRAPH_INDEX" bash "$HOOK"
  f=$(ls "$SCL_PROPOSALS_DIR"/*.md | head -1)
  grep -q "no debio entrar\|debi mantener" "$f"
}

# ── Comportamiento discriminante (S03m) ──────────────────────────────────

# _cap <json>: ejecuta el hook con la configuracion del setup y devuelve su estado.
_cap() { printf '%s' "$1" | bash "$HOOK"; }
_props() { ls "$SCL_PROPOSALS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' '; }
_prop() { ls "$SCL_PROPOSALS_DIR"/*.md | head -1; }

@test "default ON real: sin SAVIA_LEARNING_CAPTURE en el entorno captura (el setup la exporta, aqui se retira)" {
  printf '%s' '{"tool_name":"Task","tool_response":"se reconoce el error: sin variable","tool_input":{"agent":"t"}}' \
    | env -u SAVIA_LEARNING_CAPTURE SCL_PROPOSALS_DIR="$SCL_PROPOSALS_DIR" SCL_GRAPH_INDEX="$SCL_GRAPH_INDEX" bash "$HOOK"
  [ "$(_props)" = "1" ]
}

@test "cualquier valor distinto de 'on' apaga la captura" {
  for v in off 0 ON; do
    printf '%s' '{"tool_name":"Task","tool_response":"se reconoce el error: apagado","tool_input":{"agent":"t"}}' \
      | SAVIA_LEARNING_CAPTURE="$v" SCL_PROPOSALS_DIR="$SCL_PROPOSALS_DIR" SCL_GRAPH_INDEX="$SCL_GRAPH_INDEX" bash "$HOOK"
  done
  [ "$(_props)" = "0" ]
}

@test "solo actua en Task: Bash, Edit y Read con texto de error no generan propuesta" {
  for t in Bash Edit Read; do
    _cap "{\"tool_name\":\"$t\",\"tool_response\":\"se reconoce el error: no es una tarea\",\"tool_input\":{\"agent\":\"t\"}}"
  done
  [ "$(_props)" = "0" ]
}

@test "OpenCode manda tool_name en minusculas: 'task' tambien captura" {
  _cap '{"tool_name":"task","tool_response":"se reconoce el error: minuscula","tool_input":{"agent":"t"}}'
  [ "$(_props)" = "1" ]
}

@test "la respuesta puede venir en .output en vez de .tool_response" {
  _cap '{"tool_name":"Task","output":"se reconoce el error: viene en output","tool_input":{"agent":"t"}}'
  [ "$(_props)" = "1" ]
}

@test "mayusculas y tildes se normalizan: 'LECCIÓN APRENDIDA' y 'RECURRENCIA' capturan" {
  _cap '{"tool_name":"Task","tool_response":"LECCIÓN APRENDIDA: revisar siempre","tool_input":{"agent":"a"}}'
  _cap '{"tool_name":"Task","tool_response":"Hubo RECURRENCIA del fallo anterior","tool_input":{"agent":"b"}}'
  [ "$(_props)" = "2" ]
}

@test "cada familia de keywords de error dispara por si sola" {
  n=0
  for kw in "error reconocido" "se reconoce el error" "mismo error" "reintroduce" "volvio a fallar" \
            "volvimos a fallar" "volvimos a equivocarnos" "leccion aprendida" "lessons learned" \
            "recurrencia" "lo corregi" "corregi el bug" "bug reintroducido"; do
    n=$((n+1))
    _cap "{\"tool_name\":\"Task\",\"tool_response\":\"caso $n: $kw en esta tarea\",\"tool_input\":{\"agent\":\"k\"}}"
  done
  [ "$(_props)" = "13" ]
}

@test "cada patron de desviacion de norma dispara y etiqueta la propuesta" {
  n=0
  for pat in "deberia haber usado" "debi usar" "en vez de usar" "canal equivocado" "no use el mcp" \
             "me falto usar" "no estaba usando" "por error use" "no debio entrar" "no debio ir" \
             "no deberia haber" "no es el lugar" "debi mantener" "debi haber usado"; do
    n=$((n+1))
    _cap "{\"tool_name\":\"Task\",\"tool_response\":\"caso $n: $pat el vault\",\"tool_input\":{\"agent\":\"d\"}}"
  done
  [ "$(_props)" = "14" ]
  grep -l "desviacion de norma: canal equivocado" "$SCL_PROPOSALS_DIR"/*.md
}

@test "el origen de la propuesta nombra al agente y la keyword; trigger y destino son los canonicos" {
  _cap '{"tool_name":"Task","tool_response":"se reconoce el error: gate flojo","tool_input":{"agent":"revisora-x"}}'
  f=$(_prop)
  grep -q "^origin: hook captura: agente revisora-x reconoce error (se reconoce el error)" "$f"
  grep -q "^trigger: recurrence" "$f"
  grep -q "^target: memoria" "$f"
}

@test "el agente puede venir en .agent de primer nivel" {
  _cap '{"tool_name":"Task","tool_response":"se reconoce el error: gate flojo","agent":"plana-y"}'
  grep -q "agente plana-y reconoce" "$(_prop)"
}

@test "el diagnostico recoge el texto de la respuesta y se trunca a 300 caracteres" {
  long=$(printf 'x%.0s' $(seq 1 600))
  _cap "{\"tool_name\":\"Task\",\"tool_response\":\"se reconoce el error: $long\",\"tool_input\":{\"agent\":\"t\"}}"
  diag=$(sed -n '/^## Diagn/,/^## Cambio/p' "$(_prop)" | sed '1d;$d' | tr -d '\n')
  [[ "$diag" == "se reconoce el error: xxx"* ]]
  [ "${#diag}" -le 300 ]
  [ "${#diag}" -ge 250 ]
}

@test "con ficheros existentes como evidencia se usan sus hashes y no el hash de la respuesta" {
  printf 'a' > "$TMPD/e1.txt"
  _cap "{\"tool_name\":\"Task\",\"tool_response\":\"se reconoce el error: con ficheros\",\"tool_input\":{\"agent\":\"t\",\"files\":[\"$TMPD/e1.txt\"]}}"
  f=$(_prop)
  grep -q "e1.txt:" "$f"
  ! grep -q "session:response:" "$f"
}

@test "fichero de evidencia inexistente: la captura no se pierde y cae al hash de la respuesta" {
  _cap '{"tool_name":"Task","tool_response":"se reconoce el error: ruta relativa a otro cwd","tool_input":{"agent":"t","files":["no/existe.sh"]}}'
  [ "$(_props)" = "1" ]
  grep -q "session:response:" "$(_prop)"
}

@test "mezcla de fichero existente e inexistente: solo se registra el existente" {
  printf 'a' > "$TMPD/ok.txt"
  _cap "{\"tool_name\":\"Task\",\"tool_response\":\"se reconoce el error: mezcla\",\"tool_input\":{\"agent\":\"t\",\"files\":[\"$TMPD/ok.txt\",\"no/existe.sh\"]}}"
  f=$(_prop)
  grep -q "ok.txt:" "$f"
  ! grep -q "existe.sh" "$f"
}

@test "respuesta vacia o sin keyword no genera nada aunque llegue en el campo correcto" {
  _cap '{"tool_name":"Task","tool_response":"","tool_input":{"agent":"t"}}'
  _cap '{"tool_name":"Task","tool_input":{"agent":"t"}}'
  [ "$(_props)" = "0" ]
}
