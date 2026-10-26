#!/usr/bin/env bats
# test-spec188-f4-survival.bats — SPEC-188 F4 tests
# Tests for Fix Survival Check and Monthly Diagnostic Report
# Run: bats tests/test-spec188-f4-survival.bats
# Ref: SPEC-188 F4 — docs/propuestas/SPEC-188-root-cause-investigation-architecture.md

setup() {
  REPO_ROOT="$(git -C "$(dirname "$BATS_TEST_FILENAME")" rev-parse --show-toplevel 2>/dev/null || pwd)"
  SURVIVAL_SCRIPT="${REPO_ROOT}/scripts/fix-survival-check.sh"
  MONTHLY_SCRIPT="${REPO_ROOT}/scripts/monthly-diagnostic-report.sh"
  REPORTS_DIR="${REPO_ROOT}/output/reports"
  TMPDIR_REPORTS="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$REPO_ROOT"
}

teardown() {
  rm -rf "$TMPDIR_REPORTS"
}

# 1 — fix-survival-check.sh exists and is executable
@test "fix-survival-check.sh exists and is executable" {
  [ -f "$SURVIVAL_SCRIPT" ]
  [ -x "$SURVIVAL_SCRIPT" ]
}

# 2 — --json flag produces valid JSON
@test "fix-survival-check.sh --json produces valid JSON" {
  run bash "$SURVIVAL_SCRIPT" --json --days 7
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; json.load(sys.stdin)"
}

# 3 — survival_rate is in [0, 1]
@test "fix-survival-check.sh survival_rate is in [0.0, 1.0]" {
  OUTPUT=$(bash "$SURVIVAL_SCRIPT" --json --days 7)
  python3 -c "
import sys, json
d = json.loads('''$OUTPUT''')
rate = d.get('survival_rate', -1)
assert 0.0 <= float(rate) <= 1.0, f'survival_rate {rate} not in [0,1]'
print('ok:', rate)
"
}

# 4 — JSON output contains all required fields
@test "fix-survival-check.sh JSON has required fields" {
  OUTPUT=$(bash "$SURVIVAL_SCRIPT" --json --days 7)
  python3 -c "
import sys, json
d = json.loads('''$OUTPUT''')
required = ['week', 'checked_at', 'days_back', 'fixes_total', 'fixes_survived', 'survival_rate', 'reverted']
missing = [k for k in required if k not in d]
if missing:
    print('Missing fields:', missing, file=sys.stderr)
    sys.exit(1)
print('all fields present')
"
}

# 5 — reverted field is a list
@test "fix-survival-check.sh reverted field is a JSON array" {
  OUTPUT=$(bash "$SURVIVAL_SCRIPT" --json --days 7)
  python3 -c "
import sys, json
d = json.loads('''$OUTPUT''')
assert isinstance(d.get('reverted'), list), 'reverted is not a list'
print('reverted is list, len:', len(d['reverted']))
"
}

# 6 — monthly-diagnostic-report.sh exists and is executable
@test "monthly-diagnostic-report.sh exists and is executable" {
  [ -f "$MONTHLY_SCRIPT" ]
  [ -x "$MONTHLY_SCRIPT" ]
}

# 7 — report is generated in output/reports/
@test "monthly-diagnostic-report.sh generates report in output/reports/" {
  TEST_MONTH="2026-06"
  run bash "$MONTHLY_SCRIPT" --month "$TEST_MONTH"
  [ "$status" -eq 0 ]
  [ -f "${REPORTS_DIR}/diagnostic-${TEST_MONTH}.md" ]
}

# 8 — generated report contains required sections
@test "monthly-diagnostic-report.sh report has required sections" {
  TEST_MONTH="2026-06"
  bash "$MONTHLY_SCRIPT" --month "$TEST_MONTH" >/dev/null 2>&1 || true
  REPORT="${REPORTS_DIR}/diagnostic-${TEST_MONTH}.md"
  [ -f "$REPORT" ]
  grep -qi "survival" "$REPORT"
  grep -qi "accuracy" "$REPORT"
  grep -q "SPEC-188" "$REPORT"
}

# 9 — fix-survival-check.sh handles zero commits gracefully
@test "fix-survival-check.sh handles zero fix commits (--days 0)" {
  run bash "$SURVIVAL_SCRIPT" --json --days 0
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['fixes_total'] >= 0
print('fixes_total:', d['fixes_total'])
"
}

# 10 — monthly report frontmatter contains month field
@test "monthly-diagnostic-report.sh report has valid frontmatter" {
  TEST_MONTH="2026-06"
  bash "$MONTHLY_SCRIPT" --month "$TEST_MONTH" >/dev/null 2>&1 || true
  REPORT="${REPORTS_DIR}/diagnostic-${TEST_MONTH}.md"
  [ -f "$REPORT" ]
  grep -q "month: ${TEST_MONTH}" "$REPORT"
  grep -q "report_type:" "$REPORT"
}

# ── Comportamiento con repositorio git sintético (SE-456) ─────────────────────

fs_repo() {
  FSR="$(mktemp -d)"
  git -C "$FSR" init -q -b main
  git -C "$FSR" config user.email t@example.org
  git -C "$FSR" config user.name t
  git -C "$FSR" config commit.gpgsign false
  echo base > "$FSR/f.txt"
  git -C "$FSR" add f.txt
  git -C "$FSR" commit -q -m "chore: base"
}

fs_commit() {  # fs_commit "<asunto>"
  echo "$RANDOM$RANDOM" >> "$FSR/f.txt"
  git -C "$FSR" commit -q -am "$1"
}

fs_run() { CLAUDE_PROJECT_DIR="$FSR" run bash "$SURVIVAL_SCRIPT" "$@"; }

@test "SPEC-188 F4: solo cuentan commits fix(, fix:, hotfix y bugfix; el resto no" {
  fs_repo
  fs_commit "fix: uno"
  fs_commit "fix(core): dos"
  fs_commit "hotfix: tres"
  fs_commit "bugfix(x): cuatro"
  fs_commit "feat: nueva cosa"
  fs_commit "chore: fix de estilo en medio"
  fs_commit "docs: prefix fixed"
  fs_run --json --days 7
  [ "$status" -eq 0 ]
  [ "$(jq -r .fixes_total <<<"$output")" -eq 4 ]
  [ "$(jq -r .fixes_survived <<<"$output")" -eq 4 ]
  [ "$(jq -r .survival_rate <<<"$output")" = "1.0" ]
  [ "$(jq -c .reverted <<<"$output")" = "[]" ]
  rm -rf "$FSR"
}

@test "SPEC-188 F4: un fix revertido con git revert no sobrevive y se lista con su SHA corto" {
  fs_repo
  fs_commit "fix: bueno"
  fs_commit "fix: malo"
  bad="$(git -C "$FSR" rev-parse HEAD)"
  git -C "$FSR" revert --no-edit HEAD >/dev/null
  fs_run --json --days 7
  [ "$status" -eq 0 ]
  [ "$(jq -r .fixes_total <<<"$output")" -eq 2 ]
  [ "$(jq -r .fixes_survived <<<"$output")" -eq 1 ]
  [ "$(jq -r .survival_rate <<<"$output")" = "0.5" ]
  [ "$(jq -r '.reverted|length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.reverted[0].commit' <<<"$output")" = "${bad:0:7}" ]
  [ "$(jq -r '.reverted[0].subject' <<<"$output")" = "fix: malo" ]
  [ "$(jq -r '.reverted[0].reason' <<<"$output")" = "revert detected" ]
  rm -rf "$FSR"
}

@test "SPEC-188 F4: la tasa de supervivencia se redondea a 4 decimales (2 de 3)" {
  fs_repo
  fs_commit "fix: a"
  fs_commit "fix: b"
  fs_commit "fix: c"
  git -C "$FSR" revert --no-edit HEAD >/dev/null
  fs_run --json --days 7
  [ "$(jq -r .survival_rate <<<"$output")" = "0.6667" ]
  [ "$(jq -r .fixes_survived <<<"$output")" -eq 2 ]
  rm -rf "$FSR"
}

@test "SPEC-188 F4: asunto del fix con comillas no rompe el JSON del revertido" {
  fs_repo
  fs_commit 'fix: arregla "el" caso'
  git -C "$FSR" revert --no-edit HEAD >/dev/null
  fs_run --json --days 7
  [ "$status" -eq 0 ]
  [ "$(jq -r '.reverted[0].subject' <<<"$output")" = 'fix: arregla "el" caso' ]
  rm -rf "$FSR"
}

@test "SPEC-188 F4: sin commits fix la tasa es 1.0 y el total 0" {
  fs_repo
  fs_commit "feat: algo"
  fs_run --json --days 7
  [ "$(jq -r .fixes_total <<<"$output")" -eq 0 ]
  [ "$(jq -r .survival_rate <<<"$output")" = "1.0" ]
  rm -rf "$FSR"
}

@test "SPEC-188 F4: --branch limita la búsqueda a esa rama" {
  fs_repo
  git -C "$FSR" checkout -q -b otra
  fs_commit "fix: solo en otra"
  git -C "$FSR" checkout -q main
  fs_run --json --days 7 --branch main
  [ "$(jq -r .fixes_total <<<"$output")" -eq 0 ]
  fs_run --json --days 7 --branch otra
  [ "$(jq -r .fixes_total <<<"$output")" -eq 1 ]
  rm -rf "$FSR"
}

@test "SPEC-188 F4: salida de texto con resumen, periodo y lista de revertidos" {
  fs_repo
  fs_commit "fix: bueno"
  fs_commit "fix: malo"
  git -C "$FSR" revert --no-edit HEAD >/dev/null
  fs_run --days 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fix Survival Report"* ]]
  [[ "$output" == *"last 3 days"* ]]
  [[ "$output" == *"Fixes:    1/2 survived"* ]]
  [[ "$output" == *"Rate:     0.5"* ]]
  [[ "$output" == *"Reverted:"* ]]
  [[ "$output" == *"fix: malo"* ]]
}

@test "SPEC-188 F4: salida de texto sin revertidos no imprime la sección Reverted" {
  fs_repo
  fs_commit "fix: bueno"
  fs_run
  [[ "$output" == *"Fixes:    1/1 survived"* ]]
  [[ "$output" != *"Reverted:"* ]]
  rm -rf "$FSR"
}

@test "SPEC-188 F4: fuera de un repositorio git sale con 1 y error JSON" {
  d="$(mktemp -d)"
  CLAUDE_PROJECT_DIR="$d" run bash "$SURVIVAL_SCRIPT" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
  rm -rf "$d"
}

@test "SPEC-188 F4: days_back y la semana ISO salen en el JSON" {
  fs_repo
  fs_run --json --days 14
  [ "$(jq -r .days_back <<<"$output")" -eq 14 ]
  [[ "$(jq -r .week <<<"$output")" =~ ^[0-9]{4}-W[0-9]{2}$ ]]
  [[ "$(jq -r .checked_at <<<"$output")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  rm -rf "$FSR"
}
