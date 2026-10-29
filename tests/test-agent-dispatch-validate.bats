#!/usr/bin/env bats
# BATS tests for .opencode/hooks/agent-dispatch-validate.sh
# PreToolUse(Task) — validates subagent prompts have required context.
# Tier: strict
# Ref: batch 40 hook test coverage

HOOK=".opencode/hooks/agent-dispatch-validate.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  # Profile gate requires strict tier
  export SAVIA_HOOK_PROFILE=strict
}
teardown() { cd /; }

@test "hook exists" { [[ -f "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }

# ── Only Task tool is validated ──────────────────────────

@test "skip: non-Task tool exits 0" {
  run bash "$HOOK" <<< '{"tool_name":"Bash","tool_input":{}}'
  [ "$status" -eq 0 ]
}

@test "skip: Edit tool ignored" {
  run bash "$HOOK" <<< '{"tool_name":"Edit","tool_input":{"file_path":"/x"}}'
  [ "$status" -eq 0 ]
}

@test "skip: empty tool_name exits 0" {
  run bash "$HOOK" <<< '{"tool_input":{"prompt":"crear command"}}'
  [ "$status" -eq 0 ]
}

@test "skip: Task with empty prompt exits 0" {
  run bash "$HOOK" <<< '{"tool_name":"Task","tool_input":{"prompt":""}}'
  [ "$status" -eq 0 ]
}

# ── Command creation validation (ERROR cases block) ──────

@test "error: Task prompt creates commands but lacks name field" {
  local prompt='crear command en .opencode/commands/foo.md'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"DISPATCH"* ]]
}

@test "pass: Task prompt with proper command frontmatter" {
  local prompt='crear command .opencode/commands/foo.md con frontmatter name, description y ver ejemplo existente'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  # May warn but not block
  [[ "$status" -eq 0 || "$status" -eq 2 ]]
}

# ── CHANGELOG modification validation ───────────────────

@test "error: CHANGELOG edit without descending order mention" {
  local prompt='modifica CHANGELOG.md con nueva entrada'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHANGELOG"* ]]
}

@test "error: CHANGELOG edit without append/prepend mention" {
  local prompt='modifica CHANGELOG orden descendente'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  [ "$status" -eq 2 ]
}

# ── Skills creation validation ─────────────────────────

@test "warn: create skill without mentioning 150 line limit emits warning" {
  local prompt='crear skill en .opencode/skills/foo/SKILL.md'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  # Skills warning is non-blocking (only WARNINGS, no ERRORS)
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISPATCH"* ]]
}

# ── Git push/PR validation ──────────────────────────────

@test "warn: git push prompt without CI validation mention" {
  local prompt='git push al remoto tras commit'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISPATCH"* ]]
}

# ── Negative cases ──────────────────────────────────────

@test "negative: malformed JSON exits 0 (fail open)" {
  run bash "$HOOK" <<< "not json"
  [ "$status" -eq 0 ]
}

@test "negative: empty stdin handled" {
  run bash "$HOOK" <<< ""
  # jq on empty returns empty string, TOOL_NAME empty, exits 0
  [ "$status" -eq 0 ]
}

@test "negative: Task with null prompt exits 0" {
  run bash "$HOOK" <<< '{"tool_name":"Task","tool_input":{"prompt":null}}'
  [ "$status" -eq 0 ]
}

# ── Edge cases ──────────────────────────────────────────

@test "edge: Task prompt with NO trigger patterns is clean" {
  local prompt='investiga el backlog de Jira y reporta hallazgos'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  [ "$status" -eq 0 ]
  # No DISPATCH output expected
}

@test "edge: multiple triggers combine (command + changelog)" {
  local prompt='crear command foo.md y modificar CHANGELOG'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  [ "$status" -eq 2 ]
}

@test "edge: case-insensitive matching (uppercase CHANGELOG)" {
  local prompt='update CHANGELOG without context'
  run bash "$HOOK" <<< "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"$prompt\"}}"
  [ "$status" -eq 2 ]
}

# ── Coverage ────────────────────────────────────────────

@test "coverage: prompt_contains helper defined" {
  run grep -c 'prompt_contains()' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: all 5 validation categories present" {
  for pat in 'commands/' 'CHANGELOG' 'skills/' 'git push' 'rules/'; do
    grep -q "$pat" "$HOOK" || fail "missing validation category: $pat"
  done
}

@test "coverage: checklist reference declared" {
  run grep -c 'agent-dispatch-checklist' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: TMPDIR used in tests" {
  run grep -c 'TMPDIR\|mktemp' "$BATS_TEST_FILENAME"
  [[ "$output" -ge 1 ]]
}

# ── Isolation ─────────────────────────────────────────────

@test "isolation: exit codes are {0, 2} only (never 1)" {
  run bash "$HOOK" <<< ""
  [[ "$status" -eq 0 || "$status" -eq 2 ]]
  run bash "$HOOK" <<< '{"tool_name":"Task","tool_input":{"prompt":"modifica CHANGELOG"}}'
  [[ "$status" -eq 0 || "$status" -eq 2 ]]
}

@test "isolation: hook does not write to disk during validation" {
  local files_before
  files_before=$(find "$TMPDIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
  bash "$HOOK" <<< '{"tool_name":"Task","tool_input":{"prompt":"crear command"}}' >/dev/null 2>&1 || true
  local files_after
  files_after=$(find "$TMPDIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
  [[ "$files_before" == "$files_after" ]]
}

# ── Tool Agent + prompts de solo lectura (P2 de #1405) ───────────────────
# Entrada real: JSON por stdin con tool_name=Agent, perfil strict, HOME aislado.

agent_run() {
  local json
  json=$(jq -n --arg p "$1" '{tool_name:"Agent",tool_input:{prompt:$p}}')
  HOME="$BATS_TEST_TMPDIR/home" run bash "$HOOK" <<< "$json"
}

@test "agent read-only: leer CHANGELOG no se bloquea" {
  agent_run "Lee CHANGELOG.md y resume los cambios."
  [ "$status" -eq 0 ]
}

@test "agent read-only: leer un command no exige frontmatter" {
  agent_run "Lee .claude/commands/foo.md y describe su contenido"
  [ "$status" -eq 0 ]
}

@test "agent read-only: revisar una skill y una rule no avisa" {
  agent_run "Revisa .claude/skills/x/SKILL.md y docs/rules/domain/y.md y explica las diferencias"
  [ "$status" -eq 0 ]
  [[ "$output" != *"DISPATCH"* ]]
}

@test "agent write: modificar CHANGELOG sigue bloqueando" {
  agent_run "Modifica CHANGELOG.md con nueva entrada"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHANGELOG"* ]]
}

@test "agent mixed: leer y luego editar CHANGELOG sigue bloqueando" {
  agent_run "Lee CHANGELOG.md y añade una entrada"
  [ "$status" -eq 2 ]
}

@test "agent write: crear command sin name sigue bloqueando" {
  agent_run "Lee un ejemplo y crea .claude/commands/foo.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"name"* ]]
}

@test "agent sin verbo reconocible: se mantiene la validación" {
  agent_run "CHANGELOG.md nueva entrada"
  [ "$status" -eq 2 ]
}

@test "agent: perfil standard sigue saltando el hook" {
  SAVIA_HOOK_PROFILE=standard agent_run "Modifica CHANGELOG.md"
  [ "$status" -eq 0 ]
}

# ── Revisión 2 de #1412: verbos de escritura con prefijo, tilde o cortos ──
# Cada prompt contiene un verbo de lectura; si el de escritura no se detecta,
# el hook marca solo lectura y se salta las reglas 1, 2, 3 y 5 (falso verde).

@test "agent write prefijo: overwrite CHANGELOG sigue bloqueando" {
  agent_run "Read CHANGELOG.md and overwrite it with the new release notes"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHANGELOG"* ]]
}

@test "agent write prefijo: rewrite CHANGELOG sigue bloqueando" {
  agent_run "Review CHANGELOG.md and rewrite the top section"
  [ "$status" -eq 2 ]
}

@test "agent write prefijo: sobrescribe CHANGELOG sigue bloqueando" {
  agent_run "Lee CHANGELOG.md y sobrescribe la sección de cambios"
  [ "$status" -eq 2 ]
}

@test "agent write prefijo: reescribe CHANGELOG sigue bloqueando" {
  agent_run "Lee CHANGELOG.md y reescribe la sección"
  [ "$status" -eq 2 ]
}

@test "agent write tilde: reescríbelo sigue bloqueando" {
  agent_run "Lee CHANGELOG.md y reescríbelo"
  [ "$status" -eq 2 ]
}

@test "agent write tilde: añádele una entrada sigue bloqueando" {
  agent_run "Lee CHANGELOG.md y añádele una entrada"
  [ "$status" -eq 2 ]
}

@test "agent write prefijo: recreate command exige frontmatter" {
  agent_run "Read .claude/commands/foo.md and recreate it"
  [ "$status" -eq 2 ]
  [[ "$output" == *"name"* ]]
}

@test "agent write prefijo: regenerate rule avisa" {
  agent_run "Review docs/rules/domain/x.md and regenerate it"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISPATCH"* ]]
}

@test "agent write corto: pon una entrada en CHANGELOG sigue bloqueando" {
  agent_run "Lee CHANGELOG.md y pon una entrada nueva al principio"
  [ "$status" -eq 2 ]
}

@test "agent write corto: pon la lista en CHANGELOG sigue bloqueando" {
  agent_run "Pon en CHANGELOG.md la lista de cambios"
  [ "$status" -eq 2 ]
}

@test "agent write: vacía CHANGELOG sigue bloqueando" {
  agent_run "Lee CHANGELOG.md y vacía el fichero"
  [ "$status" -eq 2 ]
}

@test "agent read ambiguo: 'lead' no cuenta como verbo de lectura" {
  agent_run "CHANGELOG.md lead entry"
  [ "$status" -eq 2 ]
}

@test "agent read-only con tilde: léelo y descríbelo no se bloquea" {
  agent_run "Abre CHANGELOG.md, léelo y descríbelo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"DISPATCH"* ]]
}

@test "agent read-only: settings y output no cuentan como set/put" {
  agent_run "Lee CHANGELOG.md y el output de settings.json y resume"
  [ "$status" -eq 0 ]
}

@test "agent write prefijo: sobrescríbelo (sobr+escrib) sigue bloqueando" {
  agent_run "Lee CHANGELOG.md y sobrescríbelo"
  [ "$status" -eq 2 ]
}
