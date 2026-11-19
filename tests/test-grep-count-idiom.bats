#!/usr/bin/env bats
# Ref: Fase A (ADR-002) — `grep -c ... || echo 0` returned "0\n0" on zero matches
# (grep -c prints 0 and exits 1). Canonical idiom:
#   $(grep -c PAT FILE || [ $? -eq 1 ] || echo 0)
# keeps the count, yields a single 0 on no match and 0 on a missing file.

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  FX="$(mktemp -d)"
  printf 'a\nb\na\n' > "$FX/f.txt"
}

teardown() {
  cd /
}

count() { # canonical idiom under test
  grep -c "$1" "$2" 2>/dev/null || [ $? -eq 1 ] || echo 0
}

@test "safety: this suite runs with pipefail like the scripts it guards" {
  [[ -o pipefail ]]
}

@test "positive: matches return the count" {
  [ "$(count a "$FX/f.txt")" = "2" ]
}

@test "zero: no match yields exactly one 0 (old idiom yielded 0 and 0)" {
  [ "$(count zzz "$FX/f.txt")" = "0" ]
  old="$(grep -c zzz "$FX/f.txt" || echo 0)"
  [ "$old" = $'0\n0' ]
}

@test "nonexistent: missing file yields 0" {
  [ "$(count a "$FX/nope.txt")" = "0" ]
}

@test "empty: empty input through a pipe yields 0 under pipefail" {
  out="$(printf '' | grep -c x || [ $? -eq 1 ] || echo 0)"
  [ "$out" = "0" ]
}

@test "boundary: the result is usable in arithmetic and numeric tests" {
  n="$(count zzz "$FX/f.txt")"
  [ $((n + 1)) -eq 1 ]
  [ "$n" -eq 0 ]
}

@test "reject: no script or hook reintroduces grep -c ... || echo 0" {
  run bash -c "grep -rnE 'grep -[a-zA-Z]*c[a-zA-Z]* [^)|]*(\\|[^|][^)]*)?\\|\\| *echo \"?0\"?' --include=*.sh scripts .claude/hooks | grep -v '\\[ \\\$? -eq 1 \\]'"
  [ -z "$output" ]
}

@test "error: a real grep error (exit 2) still falls back to 0" {
  [ "$(grep -c '[' "$FX/f.txt" 2>/dev/null || [ $? -eq 1 ] || echo 0)" = "0" ]
}

@test "coverage: criterio-validate.sh reports a single 'Entries found: 0' with no CRIT entries" {
  printf '# CRITERIO\n### tecnicas\n### comunicacion\n### priorizacion\n### riesgo\n### delegacion\n' > "$FX/CRITERIO.md"
  run bash scripts/criterio-validate.sh "$FX/CRITERIO.md"
  [[ "$output" == *"Entries found: 0"* ]]
  [[ "$output" != *$'Entries found: 0\n0'* ]]
  [[ "$(grep -c '^0$' <<< "$output" || [ $? -eq 1 ] || echo 0)" == "0" ]]
}

@test "coverage: every patched script still parses (bash -n)" {
  for f in scripts/criterio-validate.sh scripts/deps-validate.sh scripts/audit-receipts.sh scripts/skill-audit.sh; do
    run bash -n "$f"
    [[ "$status" -eq 0 ]]
  done
}
