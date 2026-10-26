#!/usr/bin/env bats
# tests/test-se-260-blast-radius.bats — Tests for blast-radius.sh (SE-260)

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/blast-radius.sh"

setup() {
  [[ -x "$SCRIPT" ]] || skip "blast-radius.sh missing"
}

@test "T01: rejects missing file" {
  run bash "$SCRIPT" no-existe.ts
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "not found" ]]
}

@test "T02: rejects depth out of range" {
  run bash "$SCRIPT" --depth 10 scripts/workspace-health.sh
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "depth must be 1-5" ]]
}

@test "T03: accepts depth 1" {
  run bash "$SCRIPT" --depth 1 scripts/workspace-health.sh
  [[ "$status" -eq 0 ]]
}

@test "T04: accepts depth 5" {
  run bash "$SCRIPT" --depth 5 scripts/workspace-health.sh
  [[ "$status" -eq 0 ]]
}

@test "T05: table mode produces output with Blast Radius header" {
  run bash "$SCRIPT" --depth 1 --format table scripts/workspace-health.sh
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "Blast Radius" ]]
  [[ "$output" =~ "Summary" ]]
}

@test "T06: json mode produces valid JSON" {
  run bash "$SCRIPT" --depth 1 --format json scripts/workspace-health.sh
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"file"'
  echo "$output" | grep -q '"risk_score"'
}

@test "T07: json mode has required fields" {
  run bash "$SCRIPT" --depth 1 --format json scripts/workspace-health.sh
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"total_impacted"'
  echo "$output" | grep -q '"risk_level"'
  echo "$output" | grep -q '"impacted"'
}

@test "T08: no args shows error" {
  run bash "$SCRIPT"
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "at least one file required" ]]
}

@test "T09: help flag works" {
  run bash "$SCRIPT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "Usage" ]]
}

@test "T10: returns success for existing file" {
  run bash "$SCRIPT" --depth 1 scripts/pr-thermal-receipt.sh
  [[ "$status" -eq 0 ]]
}


# ═══════════════════════════════════════════════════════════════════════════
# Comportamiento: proyecto git temporal con dependencias conocidas. El script
# se copia solo (sin otel-emit) para que no emita telemetría real.
# ═══════════════════════════════════════════════════════════════════════════

mk_proj() {
  P="$(mktemp -d)"
  TOOL="$(mktemp -d)"
  mkdir -p "$P/lib"
  cp "$SCRIPT" "$TOOL/blast-radius.sh"
  BR="$TOOL/blast-radius.sh"
  git -C "$P" init -q
  git -C "$P" config user.email t@example.invalid
  git -C "$P" config user.name T
  printf 'helper() { echo hi; }\n' > "$P/lib/util.sh"
  printf 'source lib/util.sh\nhelper\n' > "$P/app.sh"
  printf 'bash app.sh\n' > "$P/run.sh"
  printf 'unrelated\n' > "$P/solo.sh"
  printf '# notes about util\n' > "$P/notes.md"
  git -C "$P" add -A
  git -C "$P" commit -qm base
}

rm_proj() { find "${P:-/nonexistent}" "${TOOL:-/nonexistent}" -delete 2>/dev/null; true; }
# También en teardown: si un test falla a mitad, sus temporales no quedan en /tmp
teardown() { rm_proj; }

br() { run bash "$BR" --project "$P" "$@"; }
jf() { echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(($1))"; }

@test "BR-B01: direct and transitive dependents get depth, risk level and relation" {
  mk_proj
  br --format json lib/util.sh
  [ "$status" -eq 0 ]
  [ "$(jf "sorted((i['file'], i['depth'], i['risk']) for i in d['impacted'])")" = "[('app.sh', 1, 'HIGH'), ('notes.md', 1, 'HIGH'), ('run.sh', 2, 'MEDIUM')]" ]
  [ "$(jf "d['direct'], d['transitive'], d['total_impacted']")" = "(2, 1, 3)" ]
  rm_proj
}

@test "BR-B02: a sourced file is classified as imports, a plain mention as references" {
  mk_proj
  br --format json lib/util.sh
  [ "$(jf "sorted((i['file'], i['relation']) for i in d['impacted'])")" = "[('app.sh', 'imports'), ('notes.md', 'references'), ('run.sh', 'references')]" ]
  rm_proj
}

@test "BR-B03: relation detection reads the project files, not the current directory" {
  mk_proj
  cd /
  br --format json lib/util.sh
  [ "$(jf "[i['relation'] for i in d['impacted'] if i['file']=='app.sh']")" = "['imports']" ]
  rm_proj
}

@test "BR-B04: depth 1 stops at direct dependents" {
  mk_proj
  br --format json --depth 1 lib/util.sh
  [ "$(jf "d['total_impacted'], d['transitive'], d['depth']")" = "(2, 0, 1)" ]
  rm_proj
}

@test "BR-B05: risk is weighted by depth and graded" {
  mk_proj
  br --format json --depth 1 lib/util.sh
  [ "$(jf "d['risk_score'], d['risk_level']")" = "(100, 'CRITICAL')" ]
  br --format json --depth 2 lib/util.sh
  # (10 + 10 + 6) * 100 // 30
  [ "$(jf "d['risk_score'], d['risk_level']")" = "(86, 'CRITICAL')" ]
  rm_proj
}

@test "BR-B06: a file nobody references has risk 0 and level LOW" {
  mk_proj
  br --format json solo.sh
  [ "$status" -eq 0 ]
  [ "$(jf "d['total_impacted'], d['risk_score'], d['risk_level'], d['impacted']")" = "(0, 0, 'LOW', [])" ]
  rm_proj
}

@test "BR-B07: table mode prints one row per dependent and a single risk line" {
  mk_proj
  br lib/util.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Blast Radius: lib/util.sh"* ]]
  [[ "$output" == *"Summary: 3 files impacted, 2 direct, 1 transitive"* ]]
  [ "$(echo "$output" | grep -c 'Risk score:')" -eq 1 ]
  [[ "$output" == *"Risk score: 86/"*"(CRITICAL)"* ]]
  [[ "$output" == *"app.sh"*"HIGH"*"imports"* ]]
  rm_proj
}

@test "BR-B08: table mode with no dependents says so" {
  mk_proj
  br solo.sh
  [[ "$output" == *"No dependents found"* ]]
  [[ "$output" == *"Summary: 0 files impacted"* ]]
  rm_proj
}

@test "BR-B09: a missing file among several fails the run but the others are still analysed" {
  mk_proj
  br --format json lib/util.sh nope.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"file not found: nope.sh"* ]]
  [[ "$output" == *'"file": "lib/util.sh"'* ]]
  rm_proj
}

@test "BR-B10: absolute and ./-prefixed paths are normalised to project-relative" {
  mk_proj
  br --format json "$P/lib/util.sh"
  [ "$(jf "d['file']")" = "lib/util.sh" ]
  br --format json ./lib/util.sh
  [ "$(jf "d['file']")" = "lib/util.sh" ]
  rm_proj
}

@test "BR-B11: invalid options and values are rejected with exit 1" {
  mk_proj
  br --bogus lib/util.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option: --bogus"* ]]
  br --format xml lib/util.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"format must be table or json"* ]]
  for d in 0 6 x; do
    br --depth "$d" lib/util.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"depth must be 1-5, got '$d'"* ]]
  done
  rm_proj
}

@test "BR-B12: --symbol lists files that use the symbol" {
  mk_proj
  cd "$P"
  run bash "$BR" --symbol helper
  [ "$status" -eq 0 ]
  # lib/util.sh solo define helper (sintaxis bash name() {): no es usuario
  [ "$(jf "d['symbol'], d['backend'], d['direct']")" = "('helper', 'grep', ['app.sh'])" ]
  rm_proj
}

@test "BR-B13: --symbol with a symbol nobody uses returns an empty result" {
  mk_proj
  cd "$P"
  run bash "$BR" --symbol zzz_unused
  [ "$status" -eq 0 ]
  [ "$(jf "d['total'], d['direct']")" = "(0, [])" ]
  rm_proj
}

@test "BR-B14: --symbol without a name fails" {
  mk_proj
  cd "$P"
  run bash "$BR" --symbol
  [ "$status" -eq 1 ]
  [[ "$output" == *"--symbol requiere nombre"* ]]
  rm_proj
}

@test "BR-B15: --symbol restricted with --file only reports that file when it uses the symbol" {
  mk_proj
  cd "$P"
  run bash "$BR" --symbol helper --file app.sh
  [ "$status" -eq 0 ]
  [ "$(jf "d['symbol'], d['backend'], d['direct']")" = "('helper', 'grep', ['app.sh'])" ]
  run bash "$BR" --symbol helper --file solo.sh
  [ "$status" -eq 0 ]
  [ "$(jf "d['direct']")" = "[]" ]
  rm_proj
}

@test "BR-B16: --diff finds the symbols changed in the range and their users" {
  mk_proj
  printf 'newfn() { echo new; }\n' >> "$P/lib/util.sh"
  printf 'newfn\n' > "$P/uses.sh"
  git -C "$P" add -A
  git -C "$P" commit -qm second
  cd "$P"
  run bash "$BR" --diff HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [ "$(jf "d['mode'], d['symbols'], d['direct']")" = "('diff', ['newfn'], ['uses.sh'])" ]
  [[ "$output" == *'"uses.sh"'* ]]
  rm_proj
}

@test "BR-B17: --diff with no changed symbols reports the none backend" {
  mk_proj
  printf 'unrelated change\n' >> "$P/notes.md"
  git -C "$P" add -A
  git -C "$P" commit -qm second
  cd "$P"
  run bash "$BR" --diff HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [ "$(jf "d['backend'], d['total']")" = "('none', 0)" ]
  rm_proj
}

@test "BR-B18: --diff ignores generic names such as main or setup" {
  mk_proj
  printf 'main() { :; }\nsetup() { :; }\n' >> "$P/solo.sh"
  git -C "$P" add -A
  git -C "$P" commit -qm second
  cd "$P"
  run bash "$BR" --diff HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [ "$(jf "d['backend']")" = "none" ]
  rm_proj
}

@test "BR-B19: --diff without a range fails" {
  mk_proj
  cd "$P"
  run bash "$BR" --diff
  [ "$status" -eq 1 ]
  [[ "$output" == *"--diff requiere <base..head>"* ]]
  rm_proj
}

@test "BR-B20: BLAST_RADIUS_MAX_SYMBOLS caps how many changed symbols are traced" {
  mk_proj
  printf 'aaa_one() { :; }\nbbb_two() { :; }\nccc_three() { :; }\n' >> "$P/lib/util.sh"
  printf 'aaa_one\nbbb_two\nccc_three\n' > "$P/uses.sh"
  git -C "$P" add -A
  git -C "$P" commit -qm second
  cd "$P"
  BLAST_RADIUS_MAX_SYMBOLS=1 run bash "$BR" --diff HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [ "$(jf "d['symbols']")" = "['aaa_one']" ]
  run bash "$BR" --diff HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [ "$(jf "d['symbols']")" = "['aaa_one', 'bbb_two', 'ccc_three']" ]
  rm_proj
}

@test "BR-B21: --list-backends reports a backend line and exits 0" {
  mk_proj
  run bash "$BR" --list-backends
  [ "$status" -eq 0 ]
  [[ "$output" == "backend=grep"* || "$output" == "backend=codegraph" ]]
  rm_proj
}

@test "BR-B22: --symbol with --file ignores an indented definition" {
  mk_proj
  cd "$P"
  printf '  function zed() {\n    :\n  }\n' > only-def.sh
  run bash "$BR" --symbol zed --file only-def.sh
  [ "$status" -eq 0 ]
  [ "$(jf "d['total']")" = "0" ]
  rm_proj
}

@test "BR-B23: --symbol with --file on a missing file fails instead of reporting zero users" {
  mk_proj
  cd "$P"
  run bash "$BR" --symbol helper --file nope.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"file not found: nope.sh"* ]]
  rm_proj
}

@test "BR-B24: a bash name() { definition is not a user, a call with () still is" {
  mk_proj
  cd "$P"
  printf 'zork() {\n  :\n}\n' > def.sh
  printf 'zork()\n' > call.py
  git add -A
  run bash "$BR" --symbol zork
  [ "$status" -eq 0 ]
  [ "$(jf "d['direct']")" = "['call.py']" ]
  run bash "$BR" --symbol zork --file def.sh
  [ "$(jf "d['total']")" = "0" ]
  rm_proj
}
