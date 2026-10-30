#!/usr/bin/env bats
# hook-bench-all.sh confirma con más muestras los críticos que superan el SLA,
# y ci-extended-checks.sh nombra a los infractores (#1412: "6 > 5" sin nombres).

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  FAKE="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FAKE/.opencode/hooks" "$FAKE/.claude"
  cat > "$FAKE/.claude/settings.json" <<'J'
{"hooks":{"PreToolUse":[{"hooks":[
 {"command":"bash .opencode/hooks/pre-flaky.sh"},
 {"command":"bash .opencode/hooks/pre-slow.sh"}]}]}}
J
  # Lento solo en las 3 primeras ejecuciones (ruido de arranque), luego rápido.
  cat > "$FAKE/.opencode/hooks/pre-flaky.sh" <<J
#!/usr/bin/env bash
c="$BATS_TEST_TMPDIR/count"; n=\$(cat "\$c" 2>/dev/null || echo 0); echo \$((n+1)) > "\$c"
[ "\$n" -lt 3 ] && sleep 0.06
exit 0
J
  printf '#!/usr/bin/env bash\nsleep 0.06\n' > "$FAKE/.opencode/hooks/pre-slow.sh"
}

report() { cat "$FAKE/output/hook-bench-report-"*.md; }

@test "ruido puntual no cuenta: el crítico se confirma con más muestras" {
  REPO_ROOT="$FAKE" run bash "$ROOT/scripts/hook-bench-all.sh" --runs 5 --quiet
  [ "$status" -eq 0 ]
  report | grep -q 'violations: 1)'
  report | grep -q '`pre-flaky` | critical .* PASS'
}

@test "negativo: un crítico lento de verdad sigue siendo violación" {
  REPO_ROOT="$FAKE" run bash "$ROOT/scripts/hook-bench-all.sh" --runs 5 --quiet
  report | grep -q '`pre-slow` | critical .* FAIL'
  report | grep -q '^- `pre-slow` (critical)'
}

@test "sin confirmación (CONFIRM_RUNS=5) el ruido sí cuenta" {
  CONFIRM_RUNS=5 REPO_ROOT="$FAKE" run bash "$ROOT/scripts/hook-bench-all.sh" --runs 5 --quiet
  report | grep -q 'violations: 2)'
}

@test "ci-extended-checks lista los hooks críticos infractores en regresión" {
  cd "$ROOT"
  CI_BASELINE_DIR="$BATS_TEST_TMPDIR/bl"; mkdir -p "$CI_BASELINE_DIR"
  cp .ci-baseline/*.count .ci-baseline/*.pct "$CI_BASELINE_DIR/"
  echo 0 > "$CI_BASELINE_DIR/hook-critical-violations.count"
  printf 'Critical hooks: 3 (violations: 1)\n- `pre-slow` (critical): p50=61ms, SLA=20ms\n' > "$BATS_TEST_TMPDIR/r.md"
  CI_BASELINE_DIR="$CI_BASELINE_DIR" HOOK_BENCH_REPORT="$BATS_TEST_TMPDIR/r.md" run bash scripts/ci-extended-checks.sh
  [[ "$output" == *"Hook latency: 1 critical violations > baseline 0"* ]]
  [[ "$output" == *'`pre-slow` (critical): p50=61ms'* ]]
}
