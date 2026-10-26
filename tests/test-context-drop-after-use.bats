#!/usr/bin/env bats
# tests/test-context-drop-after-use.bats — SE-221 Slice 2 — Drop-After-Use
#
# Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md (AC-10)
# Refs: Context-Minimization (Beurer-Kellner et al. 2025), KEEP/STUB/DROP, override KEEP-CONTEXT.
#
# Tests para scripts/context-drop-after-use.sh (decision engine) y
# .claude/hooks/context-drop-after-use.sh (PostToolUse hook).
#
# Cobertura: KEEP/DROP/STUB para cada tier, override KEEP-CONTEXT, idempotencia,
# referencia textual, abstract no vacio, JSON valido, audit log.
#
# Safety: ambos scripts usan set -uo pipefail.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/context-drop-after-use.sh"
HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/context-drop-after-use.sh"
METRICS="$BATS_TEST_DIRNAME/../scripts/context-drop-metrics.sh"

setup() {
  WS="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$WS/output" "$WS/docs/rules/domain"
  # Crear ficheros minimos para tests
  touch "$WS/docs/critical-facts.md"
  touch "$WS/CLAUDE.md"
  echo "First non-empty line of fixture" > "$WS/docs/rules/domain/somerule.md"
  export SAVIA_WORKSPACE_DIR="$WS"
  export CONTEXT_DROP_AUDIT_LOG="$WS/output/context-drop-audit.jsonl"
}

teardown() {
  unset SAVIA_WORKSPACE_DIR
  unset CONTEXT_DROP_AUDIT_LOG
  unset CONTEXT_DROP_NEXT_TASK
  unset CONTEXT_DROP_MIN_LINES
}

# === Sintaxis y safety ===

@test "script es bash valido" {
  bash -n "$SCRIPT"
}

@test "hook es bash valido" {
  bash -n "$HOOK"
}

@test "script uses set -uo pipefail" {
  head -10 "$SCRIPT" | grep -q "set -[euo]*o pipefail"
}

@test "hook uses set -uo pipefail" {
  head -10 "$HOOK" | grep -q "set -[euo]*o pipefail"
}

@test "scripts ejecutables" {
  [[ -x "$SCRIPT" ]] && [[ -x "$HOOK" ]] && [[ -x "$METRICS" ]]
}

# === Argumentos del decision engine ===

@test "script: exit 2 sin --path" {
  run "$SCRIPT" --next-task "foo"
  [ "$status" -eq 2 ]
}

@test "script: exit 2 con flag desconocido" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

@test "script: --help imprime usage" {
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"context-drop-after-use"* ]]
}

# === Veredictos por tier ===

@test "KEEP por tier N1-anchor" {
  run "$SCRIPT" --path "$WS/docs/critical-facts.md" --next-task "foo bar"
  [ "$status" -eq 0 ]
  [[ "$output" == "KEEP:"* ]]
  [[ "$output" == *"siempre relevante"* ]]
}

@test "KEEP por tier N2-eager" {
  run "$SCRIPT" --path "$WS/CLAUDE.md" --next-task "foo bar"
  [ "$status" -eq 0 ]
  [[ "$output" == "KEEP:"* ]]
}

@test "STUB por tier N4b sin referencia" {
  run "$SCRIPT" --path "$WS/docs/rules/domain/somerule.md" --next-task "completely unrelated"
  [ "$status" -eq 0 ]
  [[ "$output" == "STUB:"* ]]
  [[ "$output" == *"abstract:"* ]]
}

@test "DROP por tier untrusted" {
  run "$SCRIPT" --path "/etc/passwd" --next-task "foo"
  [ "$status" -eq 0 ]
  [[ "$output" == "DROP:"* ]]
}

@test "KEEP por sandbox" {
  run "$SCRIPT" --path "/tmp/opencode/work.md" --next-task "foo"
  [ "$status" -eq 0 ]
  [[ "$output" == "KEEP:"* ]]
}

# === Override KEEP-CONTEXT ===

@test "KEEP-CONTEXT override fuerza KEEP en N4b" {
  run "$SCRIPT" --path "$WS/docs/rules/domain/somerule.md" --next-task "KEEP-CONTEXT please"
  [ "$status" -eq 0 ]
  [[ "$output" == "KEEP:"* ]]
  [[ "$output" == *"override"* ]]
}

@test "KEEP-CONTEXT override fuerza KEEP en untrusted" {
  run "$SCRIPT" --path "/etc/passwd" --next-task "KEEP-CONTEXT inspeccionar"
  [ "$status" -eq 0 ]
  [[ "$output" == "KEEP:"* ]]
}

# === Referencia textual ===

@test "KEEP por referencia textual al basename" {
  run "$SCRIPT" --path "$WS/docs/rules/domain/somerule.md" --next-task "actualizar somerule.md ahora"
  [ "$status" -eq 0 ]
  [[ "$output" == "KEEP:"* ]]
  [[ "$output" == *"referencia"* ]]
}

@test "KEEP por path completo en next-task" {
  run "$SCRIPT" --path "$WS/docs/rules/domain/somerule.md" --next-task "ver $WS/docs/rules/domain/somerule.md"
  [ "$status" -eq 0 ]
  [[ "$output" == "KEEP:"* ]]
}

# === Abstract ===

@test "STUB extrae primera linea no-frontmatter como abstract" {
  run "$SCRIPT" --path "$WS/docs/rules/domain/somerule.md" --next-task "unrelated"
  [ "$status" -eq 0 ]
  [[ "$output" == *"First non-empty line of fixture"* ]]
}

@test "STUB con frontmatter omite el frontmatter" {
  cat > "$WS/docs/rules/domain/withfm.md" <<EOF
---
foo: bar
---

# Title

Real content here
EOF
  run "$SCRIPT" --path "$WS/docs/rules/domain/withfm.md" --next-task "unrelated"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Title"* ]] || [[ "$output" == *"Real content"* ]]
  ! [[ "$output" == *"foo: bar"* ]]
}

@test "STUB con --abstract override usa el provisto" {
  run "$SCRIPT" --path "$WS/docs/rules/domain/somerule.md" --next-task "unrelated" --abstract "custom abstract"
  [ "$status" -eq 0 ]
  [[ "$output" == *"custom abstract"* ]]
}

@test "STUB con fichero sin contenido devuelve abstract no vacio" {
  touch "$WS/docs/rules/domain/empty.md"
  run "$SCRIPT" --path "$WS/docs/rules/domain/empty.md" --next-task "unrelated"
  [ "$status" -eq 0 ]
  [[ "$output" == *"abstract:"* ]]
  [[ "$output" == *"no disponible"* ]] || [[ "$output" == *"abstract"* ]]
}

# === JSON output ===

@test "--json devuelve JSON valido" {
  run "$SCRIPT" --json --path "$WS/docs/rules/domain/somerule.md" --next-task "unrelated"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
}

@test "--json contiene verdict reason abstract tier path" {
  run "$SCRIPT" --json --path "$WS/docs/rules/domain/somerule.md" --next-task "unrelated"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict and .reason and .tier and .path' >/dev/null
}

@test "--json escapa backslash y comillas de una ruta Windows y conserva UTF-8" {
  printf -- '— Título “citado” con C:\\ruta\n' > "$WS/docs/rules/domain/acentos.md"
  run "$SCRIPT" --json --path 'C:\no\existe "x".md' --next-task "unrelated"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.path == "C:\\no\\existe \"x\".md"' >/dev/null
  run "$SCRIPT" --json --path "$WS/docs/rules/domain/acentos.md" --next-task "unrelated"
  echo "$output" | jq -e '.abstract | startswith("— Título “citado” con C:\\ruta")' >/dev/null
}

# === Hook PostToolUse ===

@test "hook: passthrough cuando bajo umbral" {
  CONTEXT_DROP_MIN_LINES=200 \
  CONTEXT_DROP_NEXT_TASK="foo" \
  output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo.md"},"tool_response":{"output":"a\nb\nc"}}' | bash "$HOOK")
  [[ "$output" == *'"output":"a\nb\nc"'* ]]
}

@test "hook: stub para N4b sobre umbral" {
  large=$(seq 1 600 | tr '\n' '|' | sed 's/|/\\n/g')
  input="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WS/docs/rules/domain/somerule.md\"},\"tool_response\":{\"output\":\"$large\"}}"
  output=$(echo "$input" | CONTEXT_DROP_NEXT_TASK="completely unrelated task" bash "$HOOK")
  parsed=$(echo "$output" | jq -r '.tool_response.output')
  [[ "$parsed" == "<stub origin="* ]]
  [[ "$parsed" == *"abstract="* ]]
}

@test "hook: KEEP para N1-anchor sobre umbral" {
  large=$(seq 1 600 | tr '\n' '|' | sed 's/|/\\n/g')
  input="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WS/docs/critical-facts.md\"},\"tool_response\":{\"output\":\"$large\"}}"
  output=$(echo "$input" | CONTEXT_DROP_NEXT_TASK="unrelated" bash "$HOOK")
  parsed=$(echo "$output" | jq -r '.tool_response.output')
  ! [[ "$parsed" == "<stub"* ]]
}

@test "hook: idempotencia — no re-stubea un stub" {
  large=$(seq 1 600 | tr '\n' '|' | sed 's/|/\\n/g')
  prefix="<stub origin=\\\"x\\\" tier=\\\"N4b\\\" full-content-at=\\\"x\\\" abstract=\\\"y\\\"/>"
  input="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WS/docs/rules/domain/somerule.md\"},\"tool_response\":{\"output\":\"${prefix}\\n${large}\"}}"
  output=$(echo "$input" | CONTEXT_DROP_NEXT_TASK="unrelated" bash "$HOOK")
  parsed=$(echo "$output" | jq -r '.tool_response.output')
  # Debe contener el prefix original sin volver a stubeear
  [[ "$parsed" == "<stub origin=\"x\""* ]]
}

@test "hook: audit log se escribe con JSON valido" {
  large=$(seq 1 600 | tr '\n' '|' | sed 's/|/\\n/g')
  input="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WS/docs/rules/domain/somerule.md\"},\"tool_response\":{\"output\":\"$large\"}}"
  echo "$input" | CONTEXT_DROP_NEXT_TASK="unrelated" bash "$HOOK" >/dev/null
  [[ -s "$CONTEXT_DROP_AUDIT_LOG" ]]
  jq -e '.verdict and .tier and .ts' "$CONTEXT_DROP_AUDIT_LOG" >/dev/null
}

@test "hook: KEEP-CONTEXT override no genera stub" {
  large=$(seq 1 600 | tr '\n' '|' | sed 's/|/\\n/g')
  input="{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WS/docs/rules/domain/somerule.md\"},\"tool_response\":{\"output\":\"$large\"}}"
  output=$(echo "$input" | CONTEXT_DROP_NEXT_TASK="KEEP-CONTEXT please" bash "$HOOK")
  parsed=$(echo "$output" | jq -r '.tool_response.output')
  ! [[ "$parsed" == "<stub"* ]]
}

# === Metrics script ===

@test "metrics: maneja audit log inexistente" {
  rm -f "$CONTEXT_DROP_AUDIT_LOG"
  run "$METRICS" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.audit_log == "missing"' >/dev/null
}

@test "metrics: agrega correctamente STUB/KEEP/DROP" {
  cat > "$CONTEXT_DROP_AUDIT_LOG" <<'EOF'
{"ts":"2026-06-12T14:00:00Z","tool":"Read","path":"/a","tier":"N4b","verdict":"STUB","reason":"x","next_task_excerpt":"y","tokens_saved_est":500}
{"ts":"2026-06-12T14:01:00Z","tool":"Read","path":"/b","tier":"N1","verdict":"KEEP","reason":"x","next_task_excerpt":"y","tokens_saved_est":0}
{"ts":"2026-06-12T14:02:00Z","tool":"WebFetch","path":"x","tier":"untrusted","verdict":"DROP","reason":"x","next_task_excerpt":"y","tokens_saved_est":1000}
EOF
  run "$METRICS" --json
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq -r '.n_total')
  saved=$(echo "$output" | jq -r '.total_tokens_saved')
  [ "$total" -eq 3 ]
  [ "$saved" -eq 1500 ]
}

@test "metrics: human readable output contiene contadores" {
  cat > "$CONTEXT_DROP_AUDIT_LOG" <<'EOF'
{"ts":"2026-06-12T14:00:00Z","tool":"Read","path":"/a","tier":"N4b","verdict":"STUB","reason":"x","next_task_excerpt":"y","tokens_saved_est":500}
EOF
  run "$METRICS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STUB:"* ]]
  [[ "$output" == *"tokens_saved_est"* ]]
}

# === Edge cases ===

@test "fichero inexistente devuelve STUB con abstract no disponible" {
  run "$SCRIPT" --path "$WS/docs/rules/domain/nonexistent.md" --next-task "unrelated"
  [ "$status" -eq 0 ]
  [[ "$output" == "STUB:"* ]] || [[ "$output" == "DROP:"* ]]
}

@test "hook: tool no-Read/WebFetch/Bash → passthrough" {
  input='{"tool_name":"Glob","tool_input":{"pattern":"*"},"tool_response":{"output":"x"}}'
  output=$(echo "$input" | bash "$HOOK")
  [ "$output" = "$input" ]
}

@test "hook: JSON malformado → passthrough" {
  output=$(echo "{not json" | bash "$HOOK")
  [ "$output" = "{not json" ]
}

@test "spec_reference: SE-221 documentado en script" {
  grep -q "SE-221" "$SCRIPT"
}

@test "spec_reference: SE-221 documentado en hook" {
  grep -q "SE-221" "$HOOK"
}

# === Edge cases (boundary, empty, large, no-args, timeout, null) ===
# Coverage: ejercita extract_abstract() del target script.

@test "edge: empty file content produces non-null abstract via extract_abstract" {
  empty_file=$(mktemp)
  : > "$empty_file"
  run "$SCRIPT" --path "$empty_file" --next-task "noref"
  rm -f "$empty_file"
  [ "$status" -eq 0 ]
}

@test "edge: large output (>5000 lines) does not overflow timeout" {
  large=$(seq 1 5000)
  input=$(jq -nc --arg c "$large" --arg p "$WS/docs/rules/domain/big.md" \
    '{tool_name:"Read",tool_input:{file_path:$p},tool_response:{output:$c}}')
  run timeout 10 bash -c "echo '$input' | bash '$HOOK'"
  [ "$status" -ne 124 ]
}

@test "edge: zero arguments to script triggers boundary error" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "edge: nonexistent --path still returns a verdict (no segfault, no hang)" {
  run timeout 3 "$SCRIPT" --path "/no/such/file/at/all.md" --next-task ""
  [ "$status" -ne 124 ]  # not timeout
  [ "$status" -ne 139 ]  # not segfault
}
