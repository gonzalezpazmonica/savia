#!/usr/bin/env bats
# tests/test-se-332-handback.bats — SE-332 Handback Obligation
# Ref: docs/specs/SE-332-handback-obligation.spec.md
# Covers: resolution per mode, invariant exit 5, reference-first schema,
# enum, audit log, artifact emission.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/handback-resolve.sh"
ENVSH="${BATS_TEST_DIRNAME}/../scripts/savia-env.sh"
AUTOSAFE="${BATS_TEST_DIRNAME}/../docs/rules/domain/autonomous-safety.md"
TSP="${BATS_TEST_DIRNAME}/../docs/rules/domain/terminal-state-protocol.md"

setup() {
  set -uo pipefail
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
  export SAVIA_WORKSPACE_DIR="$TMP_DIR"
  export SAVIA_AUTONOMOUS_REVIEWER="@test-reviewer"
}

teardown() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

# --- AC-1 / AC-2: normative docs -------------------------------------------------

@test "se-332: autonomous-safety.md has Handback Obligation section" {
  grep -q "Handback Obligation" "$AUTOSAFE"
}

@test "se-332: terminal-state-protocol.md enum includes handback" {
  grep -q "handback" "$TSP"
}

# --- Chain resolution per mode (AC-4) -------------------------------------------

@test "se-332: overnight-sprint resolves to AUTONOMOUS_REVIEWER" {
  source "$ENVSH"
  run savia_handback_chain "overnight-sprint"
  [ "$status" -eq 0 ]
  [ "$output" = "@test-reviewer" ]
}

@test "se-332: code-improvement-loop resolves to AUTONOMOUS_REVIEWER" {
  source "$ENVSH"
  run savia_handback_chain "code-improvement-loop"
  [ "$status" -eq 0 ]
  [ "$output" = "@test-reviewer" ]
}

@test "se-332: tech-research-agent resolves to AUTONOMOUS_REVIEWER" {
  source "$ENVSH"
  run savia_handback_chain "tech-research-agent"
  [ "$status" -eq 0 ]
  [ "$output" = "@test-reviewer" ]
}

@test "se-332: court-orchestrator resolves to dev-orchestrator" {
  source "$ENVSH"
  run savia_handback_chain "court-orchestrator"
  [ "$status" -eq 0 ]
  [ "$output" = "dev-orchestrator" ]
}

@test "se-332: truth-tribunal-orchestrator resolves to dev-orchestrator" {
  source "$ENVSH"
  run savia_handback_chain "truth-tribunal-orchestrator"
  [ "$status" -eq 0 ]
  [ "$output" = "dev-orchestrator" ]
}

@test "se-332: recommendation-tribunal-orchestrator resolves to dev-orchestrator" {
  source "$ENVSH"
  run savia_handback_chain "recommendation-tribunal-orchestrator"
  [ "$status" -eq 0 ]
  [ "$output" = "dev-orchestrator" ]
}

@test "se-332: subagent resolves to invoking orchestrator (env override)" {
  export SAVIA_HANDBACK_PARENT="dev-orchestrator"
  source "$ENVSH"
  run savia_handback_chain "subagent"
  [ "$status" -eq 0 ]
  [ "$output" = "dev-orchestrator" ]
}

# --- Invariant exit 5 (AC-5) ----------------------------------------------------

@test "se-332: unknown mode returns exit 5 (chain not manual)" {
  source "$ENVSH"
  run savia_handback_chain "unknown-mode"
  [ "$status" -eq 5 ]
}

@test "se-332: handback-resolve.sh exits 5 for unknown mode" {
  run bash "$SCRIPT" --modo "bogus-mode" --contexto-dir "$TMP_DIR"
  [ "$status" -eq 5 ]
}

# --- Artifact emission + reference-first schema (AC-4/AC-6) -----------------------

@test "se-332: emits artifact with reference-first contexto_ref (paths only)" {
  mkdir -p "$TMP_DIR/runctx"
  touch "$TMP_DIR/runctx/run-record.jsonl" "$TMP_DIR/runctx/terminal-state.jsonl"
  run bash "$SCRIPT" --modo "overnight-sprint" --contexto-dir "$TMP_DIR/runctx" \
    --motivo "guardrail_rechazo" --intentos-restantes 2
  [ "$status" -eq 0 ]
  artifact="$TMP_DIR/output/agent-runs/overnight-sprint-$(date +%Y%m%d)-handback.md"
  [ -f "$artifact" ]
  grep -q "escalado_a: @test-reviewer" "$artifact"
  grep -q "motivo: guardrail_rechazo" "$artifact"
  grep -q "intentos_restantes: 2" "$artifact"
  grep -q "contexto_ref:" "$artifact"
  # reference-first: contains routes, not bodies
  grep -q "runctx/run-record.jsonl" "$artifact"
  grep -q "runctx/terminal-state.jsonl" "$artifact"
  ! grep -q '{"' "$artifact"
}

@test "se-332: artifact is emitted under output/agent-runs/" {
  mkdir -p "$TMP_DIR/ctx"
  touch "$TMP_DIR/ctx/terminal-state.jsonl"
  bash "$SCRIPT" --modo "court-orchestrator" --contexto-dir "$TMP_DIR/ctx" >/dev/null
  [ -d "$TMP_DIR/output/agent-runs" ]
}

# --- Audit trail (AC-7) -----------------------------------------------------------

@test "se-332: audit log records handback_to" {
  mkdir -p "$TMP_DIR/ctx"
  touch "$TMP_DIR/ctx/terminal-state.jsonl"
  bash "$SCRIPT" --modo "court-orchestrator" --contexto-dir "$TMP_DIR/ctx" >/dev/null
  audit="$TMP_DIR/output/agent-runs/court-orchestrator-$(date +%Y%m%d)-audit.log"
  [ -f "$audit" ]
  grep -q "handback_to=dev-orchestrator" "$audit"
}

# --- Usage / failure paths ---------------------------------------------------------

@test "se-332: missing --contexto-dir is a usage error (exit 2)" {
  run bash "$SCRIPT" --modo "overnight-sprint"
  [ "$status" -eq 2 ]
}

@test "se-332: nonexistent contexto-dir is a usage error (exit 2)" {
  run bash "$SCRIPT" --modo "overnight-sprint" --contexto-dir "$TMP_DIR/nope"
  [ "$status" -eq 2 ]
}

# --- Behavior: refs, defaults, ordering, append semantics ---------------------------

_artifact() { echo "$TMP_DIR/output/agent-runs/$1-$(date +%Y%m%d)-handback.md"; }

@test "se-332: contexto_ref lists all five known record names in canonical order" {
  mkdir -p "$TMP_DIR/ctx"
  touch "$TMP_DIR/ctx/audit.log" "$TMP_DIR/ctx/results.tsv" "$TMP_DIR/ctx/terminal-state.jsonl" \
        "$TMP_DIR/ctx/run-record.json" "$TMP_DIR/ctx/run-record.jsonl"
  bash "$SCRIPT" --modo overnight-sprint --contexto-dir "$TMP_DIR/ctx" >/dev/null
  refs="$(grep -E '^    - ' "$(_artifact overnight-sprint)" | sed 's/.*\///' | tr '\n' ' ')"
  [ "$refs" = "run-record.jsonl run-record.json terminal-state.jsonl results.tsv audit.log " ]
}

@test "se-332: only existing record files are referenced, unknown files are not" {
  mkdir -p "$TMP_DIR/ctx"
  touch "$TMP_DIR/ctx/results.tsv" "$TMP_DIR/ctx/secret-notes.txt"
  bash "$SCRIPT" --modo overnight-sprint --contexto-dir "$TMP_DIR/ctx" >/dev/null
  a="$(_artifact overnight-sprint)"
  [ "$(grep -c '^    - ' "$a")" -eq 1 ]
  grep -q '^    - ctx/results.tsv$' "$a"
  ! grep -q "secret-notes" "$a"
}

@test "se-332: dir without known records falls back to the directory name as the single ref" {
  mkdir -p "$TMP_DIR/lonely-dir"
  bash "$SCRIPT" --modo overnight-sprint --contexto-dir "$TMP_DIR/lonely-dir" >/dev/null
  a="$(_artifact overnight-sprint)"
  [ "$(grep -c '^    - ' "$a")" -eq 1 ]
  grep -q '^    - lonely-dir/lonely-dir$' "$a"
}

@test "se-332: motivo defaults to otro and intentos_restantes line is omitted when not given" {
  mkdir -p "$TMP_DIR/ctx"; touch "$TMP_DIR/ctx/audit.log"
  bash "$SCRIPT" --modo court-orchestrator --contexto-dir "$TMP_DIR/ctx" >/dev/null
  a="$(_artifact court-orchestrator)"
  grep -q '^  motivo: otro$' "$a"
  ! grep -q 'intentos_restantes' "$a"
}

@test "se-332: intentos-restantes 0 is still emitted (zero is a value, not absence)" {
  mkdir -p "$TMP_DIR/ctx"; touch "$TMP_DIR/ctx/audit.log"
  bash "$SCRIPT" --modo court-orchestrator --contexto-dir "$TMP_DIR/ctx" --intentos-restantes 0 >/dev/null
  grep -q '^  intentos_restantes: 0$' "$(_artifact court-orchestrator)"
}

@test "se-332: artifact is a closed YAML front matter with escalado_desde, escalado_a and timestamp" {
  mkdir -p "$TMP_DIR/ctx"; touch "$TMP_DIR/ctx/audit.log"
  bash "$SCRIPT" --modo truth-tribunal-orchestrator --contexto-dir "$TMP_DIR/ctx" >/dev/null
  a="$(_artifact truth-tribunal-orchestrator)"
  [ "$(sed -n 1p "$a")" = "---" ]
  [ "$(tail -n1 "$a")" = "---" ]
  [ "$(sed -n 2p "$a")" = "handback:" ]
  grep -q '^  escalado_desde: truth-tribunal-orchestrator$' "$a"
  grep -q '^  escalado_a: dev-orchestrator$' "$a"
  grep -Eq '^  timestamp: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$' "$a"
}

@test "se-332: stdout reports the artifact path and the parent" {
  mkdir -p "$TMP_DIR/ctx"; touch "$TMP_DIR/ctx/audit.log"
  run bash "$SCRIPT" --modo court-orchestrator --contexto-dir "$TMP_DIR/ctx"
  [ "$status" -eq 0 ]
  [[ "$output" == *"handback artifact: $(_artifact court-orchestrator)"* ]]
  [[ "$output" == *"handback_to: dev-orchestrator"* ]]
}

@test "se-332: audit log appends one line per handback and keeps earlier ones" {
  mkdir -p "$TMP_DIR/ctx"; touch "$TMP_DIR/ctx/audit.log"
  bash "$SCRIPT" --modo court-orchestrator --contexto-dir "$TMP_DIR/ctx" --motivo primero >/dev/null
  bash "$SCRIPT" --modo court-orchestrator --contexto-dir "$TMP_DIR/ctx" --motivo segundo >/dev/null
  audit="$TMP_DIR/output/agent-runs/court-orchestrator-$(date +%Y%m%d)-audit.log"
  [ "$(wc -l < "$audit")" -eq 2 ]
  sed -n 1p "$audit" | grep -q "motivo=primero"
  sed -n 2p "$audit" | grep -q "motivo=segundo"
  grep -q "artifact=$(_artifact court-orchestrator)" "$audit"
}

@test "se-332: invariant failure (exit 5) emits no artifact and no audit line" {
  mkdir -p "$TMP_DIR/ctx"
  run bash "$SCRIPT" --modo bogus-mode --contexto-dir "$TMP_DIR/ctx"
  [ "$status" -eq 5 ]
  [[ "$output" == *"does not terminate in manual"* ]]
  [ ! -e "$TMP_DIR/output/agent-runs" ]
}

@test "se-332: chain check runs before directory check (unknown mode + missing dir is exit 5)" {
  run bash "$SCRIPT" --modo bogus-mode --contexto-dir "$TMP_DIR/nope"
  [ "$status" -eq 5 ]
}

@test "se-332: missing contexto dir reports the offending path and creates nothing" {
  run bash "$SCRIPT" --modo overnight-sprint --contexto-dir "$TMP_DIR/nope"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$TMP_DIR/nope"* ]]
  [ ! -e "$TMP_DIR/output" ]
}

@test "se-332: missing --modo, unknown flag and --help are all usage errors (exit 2)" {
  run bash "$SCRIPT" --contexto-dir "$TMP_DIR"
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" --modo overnight-sprint --contexto-dir "$TMP_DIR" --bogus
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" --help
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "se-332: contexto dir outside the workspace gets a relative path, never an empty one" {
  mkdir -p "$TMP_DIR/ws" "$TMP_DIR/outside"; touch "$TMP_DIR/outside/audit.log"
  SAVIA_WORKSPACE_DIR="$TMP_DIR/ws" bash "$SCRIPT" --modo overnight-sprint --contexto-dir "$TMP_DIR/outside" >/dev/null
  a="$TMP_DIR/ws/output/agent-runs/overnight-sprint-$(date +%Y%m%d)-handback.md"
  grep -qE '^    - \.\./outside/audit\.log$' "$a"
}

@test "se-332: subagent parent defaults to orquestador and honours SAVIA_HANDBACK_PARENT" {
  source "$ENVSH"
  unset SAVIA_HANDBACK_PARENT
  run savia_handback_chain subagent
  [ "$output" = "orquestador" ]
  for alias in subagente delegado delegate; do
    SAVIA_HANDBACK_PARENT="padre-x" run savia_handback_chain "$alias"
    [ "$status" -eq 0 ]
    [ "$output" = "padre-x" ]
  done
}

@test "se-332: empty mode is an invariant violation, not a silent default" {
  source "$ENVSH"
  run savia_handback_chain ""
  [ "$status" -eq 5 ]
}
