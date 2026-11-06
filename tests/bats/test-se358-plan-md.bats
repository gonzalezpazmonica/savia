#!/usr/bin/env bats
# test-se358-plan-md.bats — BATS tests for SE-358 plan.md verificado
# Ref: SE-358 — plan versionado + sync hook plan↔diff
# Ref: docs/specs/SE-358-plan-md-verified.spec.md · S03p (SE-376): cwd ajeno,
# --strict, --diff, lista con comas y validación de argumentos.
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/plan-validate.py"
  DIFFCHECK="$REPO_ROOT/scripts/plan-diff-check.sh"
  export REPO_ROOT VALIDATE DIFFCHECK

  # plan de ejemplo en tmp
  export PLAN_FILE="$(mktemp -d)/plan.md"
  cat > "$PLAN_FILE" << 'EOF'
# Plan: sample (from SPEC-000)

## Files that change
src/a.py (new)
src/b.py (modified)
tests/test_b.py (new)

## Order of work
1. Añadir b.py
2. Conectar a.py

## Risks
La API rate-limita; cachear.

## Proof
test_b.py cubre 3 estados.
EOF
}

teardown() {
  if [[ -n "${PLAN_FILE:-}" && -d "$(dirname "$PLAN_FILE")" ]]; then
    rm -rf "$(dirname "$PLAN_FILE")"
  fi
}

# ── T1: validador ─────────────────────────────────────────────────────────────

@test "plan válido → OK" {
  run python3 "$VALIDATE" --plan "$PLAN_FILE"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]
}

@test "plan válido --files lista archivos" {
  run python3 "$VALIDATE" --plan "$PLAN_FILE" --files
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"src/a.py"* ]]
  [[ "$output" == *"src/b.py"* ]]
}

@test "plan malformado → WARN (no bloquea)" {
  local bad="$(dirname "$PLAN_FILE")/bad.md"
  printf '# Plan\n\n## Solo\n' > "$bad"
  run python3 "$VALIDATE" --plan "$bad"
  [[ "$status" -eq 0 ]]  # fail-soft
  [[ "$output" == *"WARN"* ]]
}

@test "plan malformado --strict → exit != 0" {
  local bad="$(dirname "$PLAN_FILE")/bad2.md"
  printf '# Plan\n\n## Solo\n' > "$bad"
  run python3 "$VALIDATE" --plan "$bad" --strict
  [[ "$status" -ne 0 ]]
}

@test "plan inexistente → error" {
  run python3 "$VALIDATE" --plan "/no/existe/plan.md"
  [[ "$status" -ne 0 ]]
}

# ── T2: diff check ────────────────────────────────────────────────────────────

@test "diff dentro del plan → pass" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "src/a.py src/b.py"
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"WARN [SE-358]"* ]]
}

@test "diff con archivo fuera del plan → WARN (mode warn, exit 0)" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "src/a.py src/outside.py"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"WARN [SE-358]"* ]]
}

@test "diff fuera del plan mode block → exit 2" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "src/a.py src/outside.py" --mode block
  [[ "$status" -eq 2 ]]
}

@test "artefactos de proceso no son divergencia" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "src/a.py docs/specs/SE-358.spec.md CHANGELOG.d/x.md"
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"WARN [SE-358]"* ]]
}

@test "plan inexistente → fail-soft (exit 0)" {
  run bash "$DIFFCHECK" --plan "/no/existe/plan.md" --files "src/a.py"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"fail-soft"* ]]
}

@test "falta --plan o --files → error" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE"
  [[ "$status" -ne 0 ]]
}

# ── S03p: comportamiento adicional ───────────────────────────────────────────

@test "diff check from a foreign cwd still blocks files outside the plan" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "src/a.py src/outside.py" --mode block
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"WARN [SE-358]: archivos fuera del plan.md: src/outside.py"* ]]
  [[ "$output" != *"malformado"* ]]
}

@test "diff check from a foreign cwd passes files inside the plan" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "src/a.py tests/test_b.py" --mode block
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "--strict blocks a missing plan with exit 2" {
  run bash "$DIFFCHECK" --plan "/no/existe/plan.md" --files "src/a.py" --strict
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"no existe"* ]]
}

@test "--strict blocks a plan without files (malformed) with exit 2" {
  local bad="$BATS_TEST_TMPDIR/bad.md"
  printf '# Plan\n\n## Risks\nnada\n' > "$bad"
  run bash "$DIFFCHECK" --plan "$bad" --files "src/a.py" --strict
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"malformado"* ]]
  run bash "$DIFFCHECK" --plan "$bad" --files "src/a.py"
  [[ "$status" -eq 0 ]]
}

@test "--diff reads changed files one per line" {
  printf 'src/a.py\nsrc/rogue.py\n' > "$BATS_TEST_TMPDIR/changed.txt"
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --diff "$BATS_TEST_TMPDIR/changed.txt" --mode block
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"fuera del plan.md: src/rogue.py"* ]]
  printf 'src/a.py\nsrc/b.py\n' > "$BATS_TEST_TMPDIR/ok.txt"
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --diff "$BATS_TEST_TMPDIR/ok.txt" --mode block
  [[ "$status" -eq 0 ]]
}

@test "--diff with a nonexistent file is an error" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --diff "$BATS_TEST_TMPDIR/nope.txt"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"--diff requiere"* ]]
}

@test "empty --files is rejected with usage" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "   "
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Uso:"* ]]
}

@test "unknown argument and invalid mode are rejected" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "src/a.py" --bogus
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"argumento desconocido: --bogus"* ]]
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --files "src/a.py src/x.py" --mode blok
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"--mode debe ser warn o block"* ]]
}

@test "every process artefact path is exempt but similar paths are not" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --mode block \
    --files "plan.md docs/specs/x.md CHANGELOG.d/y.md .confidentiality-signature .scm/r.json"
  [[ "$status" -eq 0 ]]
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --mode block --files "docs/other/x.md"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"docs/other/x.md"* ]]
}

@test "partial path match is not accepted as planned (src/a vs src/a.py)" {
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --mode block --files "src/a.pyc"
  [[ "$status" -eq 2 ]]
  run bash "$DIFFCHECK" --plan "$PLAN_FILE" --mode block --files "src/a"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"fuera del plan.md: src/a"* ]]
}

@test "validator splits comma-separated files and strips backticks (spec format)" {
  local p="$BATS_TEST_TMPDIR/commas.md"
  printf '## Files that change\n- `path/a.ts` (new), path/b.py (modified), tests/test_b.py (new)\n- path/b.py\n\n## Order of work\n1.\n## Risks\nx\n## Proof\ny\n' > "$p"
  run python3 "$VALIDATE" --plan "$p" --files
  [[ "$status" -eq 0 ]]
  [[ "$output" == "path/a.ts"$'\n'"path/b.py"$'\n'"tests/test_b.py" ]]
}

@test "validator --json reports missing sections and empty file list" {
  local p="$BATS_TEST_TMPDIR/partial.md"
  printf '## Files that change\n\n## Risks\nx\n' > "$p"
  run python3 "$VALIDATE" --plan "$p" --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json,sys; d=json.load(sys.stdin)
assert d['valid'] is False and d['files']==[], d
assert 'faltan secciones: Order of work, Proof' in d['errors'], d['errors']
assert any('no se listan archivos' in e for e in d['errors']), d['errors']"
}

@test "validator --files on plan without files exits 2 with empty output" {
  local p="$BATS_TEST_TMPDIR/nofiles.md"
  printf '## Order of work\n## Risks\n## Proof\n' > "$p"
  run python3 "$VALIDATE" --plan "$p" --files
  [[ "$status" -eq 2 ]]
  [[ -z "$output" ]]
}

@test "validator stops the file list at the next heading and skips code fences" {
  local p="$BATS_TEST_TMPDIR/fence.md"
  printf '## Files that change\n```text\nsrc/x.py\n```\n## Order of work\nsrc/not-a-file.py\n## Risks\n## Proof\n' > "$p"
  run python3 "$VALIDATE" --plan "$p" --files
  [[ "$status" -eq 0 ]]
  [[ "$output" == "src/x.py" ]]
}
