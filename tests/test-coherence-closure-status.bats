#!/usr/bin/env bats
# SE-387 §17 — output/coherence-closure-status.{json,md}: informe de cierre del
# programa derivado de la evidencia (log de coherence-gates, matrices de
# cobertura, presupuesto de deuda, benchmark y frescura de derivados).
# Fail-closed: lo que no se puede medir sale NOT_MEASURED, nunca cumplido.
# Ref: docs/specs/SE-387-coherence-closure-program.spec.md §14 y §17
set -uo pipefail

GEN="scripts/coherence-closure-status.py"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  R="$(mktemp -d "$BATS_TEST_TMPDIR/closure.XXXXXX")"
  mkdir -p "$R/scripts" "$R/output" "$R/docs/propuestas" "$R/tests/self-evolution/results"
  cat > "$R/scripts/coherence-gate-policy.yaml" <<'Y'
gates:
  - id: negative-safety
    status: BLOCK
    risk_scope: [L4]
    calibration: complete
    evidence: guardrail-negative-tests.sh 11/11 (SE-377)
  - id: eval-coverage
    status: BLOCK
    risk_scope: [L4]
    calibration: complete
    evidence: eval L4 2/2 covered 9 piezas (SE-387 D)
  - id: constitutional-coverage
    status: BLOCK
    risk_scope: [L4]
    calibration: complete
    evidence: constitutional-coverage 2/2 COMPLETE (SE-387 B)
  - id: entropy
    status: WARN
    risk_scope: [L2]
    calibration: calibrating
    evidence: v0 provisional
Y
  cat > "$R/output/eval-coverage-matrix.json" <<'J'
{"rows": [{"capability": "agent:a", "risk": "L4", "covered": true, "missing": []},
          {"capability": "agent:b", "risk": "L4", "covered": true, "missing": []},
          {"capability": "skill:c", "risk": "L1", "covered": false, "missing": ["smoke"]}]}
J
  cat > "$R/output/constitutional-coverage.json" <<'J'
{"coverage": {"COMPLETE": 2}, "rows": [{"capability_id": "agent:a", "coverage_status": "COMPLETE"},
                                       {"capability_id": "agent:b", "coverage_status": "COMPLETE"}]}
J
  cat > "$R/docs/propuestas/SE-376-debt-budget.yaml" <<'Y'
current_wave: 0
targets:
  0: 133
  1: 95
Y
  cat > "$R/tests/self-evolution/results/aggregate.json" <<'J'
{"total": 4, "aggregate": {"PASS": 2, "CHECK_FAIL": 1, "READY": 1}, "tasks": []}
J
  cat > "$R/gates.log" <<'L'
--- Coherence gates (SE-377/380/381/383/386) ---
PASS coherence/negative-safety
PASS coherence/entropy
INFO coherence/entropy: PASS: entropía 1563 <= baseline 1625
PASS coherence/debt-budget
INFO coherence/debt-budget: PASS: deuda 115 <= target wave 0 (133)
PASS coherence/constitutional-coverage
WARN coherence/closure-grounding-verify.sh: DECLARED (presente, sin hook ni CI que lo aplique)
PASS coherence/closure-validate-handoff-integrity.sh: en el camino del efecto
WARN coherence/closure-checkpoint.sh: DECLARED (presente, sin hook ni CI que lo aplique)
WARN coherence/harness-closure: DECLARED (tooling presente, no todo en el camino del efecto)
PASS coherence/eval-coverage-L4: 2/2 cubiertas
-- coherence gates: sin bloqueo L4 (advisory/WARN restante)
L
  printf 'PASS Generado al día: registry\nPASS Generado al día: roadmap\n' > "$R/fresh.log"
}

gen() { python3 "$REPO_ROOT/$GEN" --root "$R" "$@"; }
jq_py() { python3 -c "import json,sys; d=json.load(open('$R/output/coherence-closure-status.json')); print($1)"; }

@test "genera json y md con las ocho secciones de §17" {
  run gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  [ "$status" -eq 0 ]
  [ -f "$R/output/coherence-closure-status.json" ]
  [ -f "$R/output/coherence-closure-status.md" ]
  run jq_py "sorted(d['sections'])"
  [ "$output" = "['benchmark', 'constitutional_coverage', 'debt', 'entropy', 'evals', 'gates', 'generated_truth', 'harness']" ]
  grep -q "AUTO-GENERATED" "$R/output/coherence-closure-status.md"
}

@test "lee las cifras reales: entropía, deuda, evals, constitucional y benchmark" {
  gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  run jq_py "d['sections']['entropy']['value'], d['sections']['entropy']['baseline']"
  [ "$output" = "1563 1625" ]
  run jq_py "d['sections']['debt']['current'], d['sections']['debt']['wave1_target']"
  [ "$output" = "115 95" ]
  run jq_py "d['sections']['evals']['l4_covered'], d['sections']['evals']['l4_total']"
  [ "$output" = "2 2" ]
  run jq_py "d['sections']['constitutional_coverage']['complete'], d['sections']['constitutional_coverage']['total']"
  [ "$output" = "2 2" ]
  run jq_py "d['sections']['benchmark']['executed'], d['sections']['benchmark']['total']"
  [ "$output" = "3 4" ]
}

@test "harness: F2 y F4 DECLARED no cuentan como cerrados; F3 cableado sí" {
  gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  run jq_py "d['definition_of_closed']['f2_grounding_fail_closed']['met'], d['definition_of_closed']['f3_handoff_active']['met'], d['definition_of_closed']['f4_checkpoint_proven']['met']"
  [ "$output" = "False True False" ]
}

@test "deuda por encima del objetivo wave 1 → criterio no cumplido" {
  gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  run jq_py "d['definition_of_closed']['debt_wave1_target']['met']"
  [ "$output" = "False" ]
  run jq_py "d['closed']"
  [ "$output" = "False" ]
}

@test "fail-closed: sin log de gates, gates/harness/evals salen NOT_MEASURED" {
  run gen --fresh-log "$R/fresh.log"
  [ "$status" -eq 0 ]
  run jq_py "d['sections']['gates']['status'], d['sections']['harness']['status'], d['sections']['evals']['status']"
  [ "$output" = "NOT_MEASURED NOT_MEASURED NOT_MEASURED" ]
  run jq_py "d['definition_of_closed']['gates_l4_blocking']['met'], d['definition_of_closed']['f2_grounding_fail_closed']['met']"
  [ "$output" = "False False" ]
}

@test "fail-closed: sin log de frescura, generated_truth no se da por cumplido" {
  gen --gates-log "$R/gates.log"
  run jq_py "d['sections']['generated_truth']['status'], d['definition_of_closed']['truth_derived_no_drift']['met']"
  [ "$output" = "NOT_MEASURED False" ]
}

@test "una línea BLOCK en el log deja gates en BLOCK y el criterio sin cumplir" {
  printf 'BLOCK coherence/eval-coverage-L4: capability L4 perdió cobertura (1/2) (SE-387 D)\n' >> "$R/gates.log"
  gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  run jq_py "d['sections']['gates']['status'], d['definition_of_closed']['gates_l4_blocking']['met']"
  [ "$output" = "BLOCK False" ]
}

@test "derivado desfasado → generated_truth DRIFT" {
  printf 'FAIL Generado desfasado: roadmap → regenerar: x\n' >> "$R/fresh.log"
  gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  run jq_py "d['sections']['generated_truth']['status']"
  [ "$output" = "DRIFT" ]
}

@test "la evidencia de la política que no casa con lo medido sale como deriva" {
  sed -i 's#eval L4 2/2#eval L4 8/8#' "$R/scripts/coherence-gate-policy.yaml"
  gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  run jq_py "[x['gate'] for x in d['policy_evidence_drift']]"
  [ "$output" = "['eval-coverage']" ]
}

@test "salida determinista: dos ejecuciones dan el mismo json" {
  gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  cp "$R/output/coherence-closure-status.json" "$R/a.json"
  gen --gates-log "$R/gates.log" --fresh-log "$R/fresh.log"
  cmp "$R/a.json" "$R/output/coherence-closure-status.json"
}

@test "repo real: la evidencia de coherence-gate-policy.yaml casa con lo medido" {
  python3 "$REPO_ROOT/scripts/eval-coverage-matrix.py" --root "$REPO_ROOT" >/dev/null
  python3 "$REPO_ROOT/scripts/constitutional-coverage.py" --root "$REPO_ROOT" >/dev/null
  run python3 "$REPO_ROOT/$GEN" --root "$REPO_ROOT" --out-dir "$R/real" --check-policy
  echo "$output"
  [ "$status" -eq 0 ]
}

# Fixture de coherence-gates.sh con todas sus dependencias simuladas.
gates_fixture() {
  G="$R/gates-repo"
  mkdir -p "$G/scripts" "$G/tests/chaos" "$G/output"
  cp "$REPO_ROOT/scripts/coherence-gates.sh" "$G/scripts/"
  cp "$R/scripts/coherence-gate-policy.yaml" "$G/scripts/"
  local f
  for f in guardrail-negative-tests.sh contract-check.sh law-check.sh frontend-probe.sh \
           grounding-verify.sh validate-handoff.sh validate-handoff-integrity.sh checkpoint.sh \
           debt-burn-down.sh planning-transition.sh report-benchmark.sh; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$G/scripts/$f"; chmod +x "$G/scripts/$f"
  done
  printf '#!/usr/bin/env bash\nexit 0\n' > "$G/tests/chaos/run-chaos-suite.sh"
  printf '#!/usr/bin/env bash\necho "PASS: deuda 115 <= target wave 0 (133)"\necho "INFO: wave 0 = baseline freeze"\n' > "$G/scripts/debt-budget-check.sh"
  printf 'print("PASS: entropía 1563 <= baseline 1625")\n' > "$G/scripts/capability-entropy.py"
  printf 'pass\n' > "$G/scripts/constitutional-coverage.py"
  printf 'import shutil\nshutil.copy("%s", "%s")\n' "$R/output/eval-coverage-matrix.json" "$G/output/eval-coverage-matrix.json" > "$G/scripts/eval-coverage-matrix.py"
}

@test "coherence-gates.sh deja en su salida la cifra de entropía y deuda (INFO)" {
  gates_fixture
  run bash "$G/scripts/coherence-gates.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qx 'INFO coherence/entropy: PASS: entropía 1563 <= baseline 1625' <<< "$output"
  grep -qx 'INFO coherence/debt-budget: PASS: deuda 115 <= target wave 0 (133)' <<< "$output"
}

@test "validate-ci-local.sh regenera el informe con el log que ya capturó" {
  V="$R/vci"
  mkdir -p "$V/scripts/lib" "$V/.claude/hooks/lib" "$R/no-lockfiles"
  cp "$REPO_ROOT/scripts/validate-ci-local.sh" "$REPO_ROOT/$GEN" "$V/scripts/"
  cp "$R/scripts/coherence-gate-policy.yaml" "$V/scripts/"
  cp "$REPO_ROOT/scripts/lib/mock-env.sh" "$V/scripts/lib/"
  source "$V/scripts/lib/mock-env.sh"
  git_env_clean --isolate-config
  git -C "$V" init -q -b agent/closure-tests
  git -C "$V" -c user.name=t -c user.email=t@t commit -q --allow-empty -m fixture
  printf '{}\n' > "$V/.claude/settings.json"
  printf '# Changelog\n\n## [1.0.0]\n' > "$V/CHANGELOG.md"
  touch "$V/LICENSE" "$V/README.md" "$V/CONTRIBUTING.md" "$V/CODE_OF_CONDUCT.md" "$V/SECURITY.md"
  printf 'raise SystemExit(0)\n' > "$V/scripts/validate-agent-catalog.py"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$V/.claude/hooks/lib/gate-result.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$V/scripts/vaults-freshness.sh"
  printf '#!/usr/bin/env bash\ncat "%s"\n' "$R/gates.log" > "$V/scripts/coherence-gates.sh"
  export SAVIA_FRESH_CHECKS_FOR_TESTS='fixture|true|sin regeneración'
  export SAVIA_LOCK_DIRS_FOR_TESTS="$R/no-lockfiles" SAVIA_AUTHORITY_REPORT=off
  cd "$V"
  run bash "$V/scripts/validate-ci-local.sh" --quick
  echo "$output"
  [ -f "$V/output/coherence-closure-status.json" ]
  run python3 -c "import json; d=json.load(open('$V/output/coherence-closure-status.json')); print(d['sections']['harness']['status'], d['sections']['generated_truth']['status'])"
  [ "$output" = "DECLARED OK" ]
}
