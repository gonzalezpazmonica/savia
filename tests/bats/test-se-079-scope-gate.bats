#!/usr/bin/env bats
# tests/bats/test-se-079-scope-gate.bats
# SE-079 — G13 Scope-trace gate
# >= 5 tests

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/scope-trace-gate.sh"

# ── Test 1: Script exists and is executable ────────────────────────────────────
@test "SE-079 AC-01: scope-trace-gate.sh exists and is executable" {
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

# ── Test 2: Files within declared spec scope → passed=true ────────────────────
@test "SE-079 AC-03: files in scope → passed=true, files_outside_scope empty" {
  run bash "$SCRIPT" --spec SE-079 --files \
    "scripts/scope-trace-gate.sh" \
    "tests/bats/test-se-079-scope-gate.bats" \
    "CHANGELOG.d/se-079-scope-gate.md"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool > /dev/null
  local passed
  passed=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['passed'])")
  [ "$passed" = "True" ]
  local outside
  outside=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['files_outside_scope']))")
  [ "$outside" = "0" ]
}

# ── Test 3: Files outside scope → passed=false, files_outside_scope non-empty ─
@test "SE-079 AC-03: files outside scope → passed=false, files_outside_scope non-empty" {
  run bash "$SCRIPT" --spec SE-079 --files "src/totally/unrelated/widget.py"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool > /dev/null
  local passed
  passed=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['passed'])")
  [ "$passed" = "False" ]
  local outside
  outside=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['files_outside_scope']))")
  [ "$outside" -gt 0 ]
}

# ── Test 4: Output is always valid JSON ───────────────────────────────────────
@test "SE-079 AC-07: output is valid JSON in all scenarios" {
  # No spec
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool > /dev/null

  # With spec, in-scope files
  run bash "$SCRIPT" --spec SE-079 --files "scripts/scope-trace-gate.sh"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool > /dev/null

  # With spec, out-of-scope files
  run bash "$SCRIPT" --spec SE-079 --files "some/unrelated/path.go"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool > /dev/null

  # Non-existent spec
  run bash "$SCRIPT" --spec SE-NONEXIST --files "any/file.sh"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool > /dev/null
}

# ── Test 5: No spec → exit 0, verdict SKIP ────────────────────────────────────
@test "SE-079 AC-04: no spec → exit 0, graceful SKIP" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['verdict'])")
  [ "$verdict" = "SKIP" ]
  local spec_id
  spec_id=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['spec_id'])")
  [ "$spec_id" = "None" ]
}

# ── Test 6: CHANGELOG.d/* and .scm/* are always whitelisted ──────────────────
@test "SE-079 AC-06: CHANGELOG.d and .scm paths always whitelisted" {
  run bash "$SCRIPT" --spec SE-079 --files \
    "CHANGELOG.d/se-079-fragment.md" \
    ".scm/some-signature-file" \
    ".confidentiality-signature" \
    ".pr-summary.md"
  [ "$status" -eq 0 ]
  local passed
  passed=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['passed'])")
  [ "$passed" = "True" ]
  local verdict
  verdict=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['verdict'])")
  [ "$verdict" = "PASS" ]
}

# ── Test 7: gate field is always G13-SCOPE-TRACE ─────────────────────────────
@test "SE-079: gate field is always 'G13-SCOPE-TRACE'" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local gate
  gate=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['gate'])")
  [ "$gate" = "G13-SCOPE-TRACE" ]
}

# ── Comportamiento aislado: arbol temporal con una spec propia ───────────────
mk_scope_tree() {
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts" "$T/docs/propuestas"
  cp "$SCRIPT" "$T/scripts/scope-trace-gate.sh"
  cat > "$T/docs/propuestas/SE-900-widget.md" <<'EOF'
# SE-900 widget
Toca `scripts/frobnicate.sh` y el fichero mapper.py.
- [ ] AC-01 el calculador de gravity funciona
- [x] AC-02 el exportador de reports escribe json
EOF
  G="$T/scripts/scope-trace-gate.sh"
}

jq_field() { python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d['$1']))"; }

@test "scope aislado: fichero citado como ruta en la spec esta dentro" {
  mk_scope_tree
  run bash "$G" --spec SE-900 --files other/dir/frobnicate.sh other/mapper.py
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_field files_in_scope)" = '["other/dir/frobnicate.sh", "other/mapper.py"]' ]
  [ "$(echo "$output" | jq_field files_outside_scope)" = '[]' ]
  [ "$(echo "$output" | jq_field verdict)" = '"PASS"' ]
  [ "$(echo "$output" | jq_field passed)" = 'true' ]
}

@test "scope aislado: coincidencia por token de un AC (>=4 letras) y rechazo del resto" {
  mk_scope_tree
  run bash "$G" --spec SE-900 --files src/gravity_calc.py src/report-exporter.ts src/unrelated.py
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_field files_in_scope)" = '["src/gravity_calc.py", "src/report-exporter.ts"]' ]
  [ "$(echo "$output" | jq_field files_outside_scope)" = '["src/unrelated.py"]' ]
  [ "$(echo "$output" | jq_field verdict)" = '"WARN"' ]
  [ "$(echo "$output" | jq_field passed)" = 'false' ]
}

@test "scope aislado: un token de menos de 4 letras no basta" {
  mk_scope_tree
  run bash "$G" --spec SE-900 --files src/el.py src/de-la.py
  [ "$(echo "$output" | jq_field files_outside_scope)" = '["src/el.py", "src/de-la.py"]' ]
}

@test "scope aislado: la propia spec y la lista blanca estan dentro aunque no casen" {
  mk_scope_tree
  run bash "$G" --spec SE-900 --files docs/propuestas/SE-900-otra.md CHANGELOG.md CHANGELOG.d/x.md .scm/a .confidentiality-signature .pr-summary.md
  [ "$(echo "$output" | jq_field files_outside_scope)" = '[]' ]
  [ "$(echo "$output" | jq_field verdict)" = '"PASS"' ]
  run bash "$G" --spec SE-900 --files docs/propuestas/SE-901-ajena.md
  [ "$(echo "$output" | jq_field verdict)" = '"WARN"' ]
}

@test "scope aislado: spec inexistente da WARN con todos los ficheros dentro y spec_id" {
  mk_scope_tree
  run bash "$G" --spec SE-777 --files a/b.sh c.py
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq_field verdict)" = '"WARN"' ]
  [ "$(echo "$output" | jq_field spec_id)" = '"SE-777"' ]
  [ "$(echo "$output" | jq_field files_in_scope)" = '["a/b.sh", "c.py"]' ]
  [ "$(echo "$output" | jq_field passed)" = 'true' ]
}

@test "scope aislado: sin --files usa git diff; sin cambios da SKIP y con cambios los evalua" {
  mk_scope_tree
  git -C "$T" init -q
  git -C "$T" config user.email t@t; git -C "$T" config user.name t
  echo a > "$T/tracked.txt"; git -C "$T" add -A; git -C "$T" commit -qm init
  run bash "$G" --spec SE-900
  [ "$(echo "$output" | jq_field verdict)" = '"SKIP"' ]
  [ "$(echo "$output" | jq_field spec_id)" = '"SE-900"' ]
  echo b > "$T/tracked.txt"
  run bash "$G" --spec SE-900
  [ "$(echo "$output" | jq_field verdict)" = '"WARN"' ]
  [ "$(echo "$output" | jq_field files_outside_scope)" = '["tracked.txt"]' ]
}

@test "scope aislado: --files solo recoge posicionales tras la bandera y se ignoran flags desconocidos" {
  mk_scope_tree
  run bash "$G" stray.py --spec SE-900 --verbose --files mapper.py
  [ "$(echo "$output" | jq_field files_in_scope)" = '["mapper.py"]' ]
  [ "$(echo "$output" | jq_field files_outside_scope)" = '[]' ]
}

@test "scope aislado: un token de exactamente 4 letras (json) basta para casar" {
  mk_scope_tree
  run bash "$G" --spec SE-900 --files src/mi-json.py
  [ "$(echo "$output" | jq_field files_in_scope)" = '["src/mi-json.py"]' ]
}
