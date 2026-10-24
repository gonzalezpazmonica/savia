#!/usr/bin/env bats
# tests/bats/test-se-080-attention-anchor.bats
# SE-080 — Attention-anchor vocabulary
# >= 4 tests

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ANCHOR_DOC="$REPO_ROOT/docs/rules/domain/attention-anchor.md"
CHECK_SCRIPT="$REPO_ROOT/scripts/attention-anchor-check.sh"

# ── Test 1: attention-anchor.md exists and mentions all 4 patterns ────────────
@test "SE-080 AC-01: attention-anchor.md exists and mentions B8, B9, A7, A9" {
  [[ -f "$ANCHOR_DOC" ]]
  grep -q "B8" "$ANCHOR_DOC"
  grep -q "B9" "$ANCHOR_DOC"
  grep -q "A7" "$ANCHOR_DOC"
  grep -q "A9" "$ANCHOR_DOC"
}

# ── Test 2: attention-anchor-check.sh produces valid JSON ────────────────────
@test "SE-080 AC-02: attention-anchor-check.sh produces valid JSON" {
  [[ -f "$CHECK_SCRIPT" ]]
  [[ -x "$CHECK_SCRIPT" ]]
  run bash "$CHECK_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool > /dev/null
  local checked
  checked=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['checked'])")
  [ "$checked" = "4" ]
}

# ── Test 3: B9 referenced in autonomous-safety or radical-honesty (GOAL STEWARD) ─
@test "SE-080 AC-03: B9 GOAL STEWARD referenced in radical-honesty.md or SE-079 spec" {
  local found=0
  grep -q "B9" "$REPO_ROOT/docs/rules/domain/radical-honesty.md" 2>/dev/null && found=1
  grep -q "B9" "$REPO_ROOT/docs/propuestas/SE-079-pr-plan-scope-trace-gate.md" 2>/dev/null && found=1
  [ "$found" -eq 1 ]
}

# ── Test 4: A9 referenced in autonomous-safety.md (SUPERVISED EXECUTION) ─────
@test "SE-080 AC-03: A9 SUPERVISED EXECUTION referenced in autonomous-safety.md" {
  grep -q "A9" "$REPO_ROOT/docs/rules/domain/autonomous-safety.md"
}

# ── Test 5: check script reports found=4, missing=[] in this workspace ────────
@test "SE-080: all 4 patterns found in workspace (found=4, missing empty)" {
  run bash "$CHECK_SCRIPT"
  [ "$status" -eq 0 ]
  local found missing_count
  found=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['found'])")
  missing_count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['missing']))")
  [ "$found" = "4" ]
  [ "$missing_count" = "0" ]
}

# ── Test 6: attention-anchor.md cites Genesis upstream (SE-080 AC-06) ────────
@test "SE-080 AC-06: attention-anchor.md cites Genesis upstream (danielmeppiel/genesis)" {
  grep -qi "genesis" "$ANCHOR_DOC"
}

# ── Comportamiento con árbol sintético (SE-456) ───────────────────────────────
# La raíz se deduce de la ruta del script: se copia a un árbol temporal para
# controlar exactamente qué ficheros mencionan cada patrón.

aa_root() {
  T="$(mktemp -d)"
  mkdir -p "$T/scripts" "$T/docs/rules" "$T/.opencode"
  cp "$CHECK_SCRIPT" "$T/scripts/attention-anchor-check.sh"
}

teardown() { [[ -n "${T:-}" ]] && rm -rf "$T"; true; }

@test "SE-080 comportamiento: sin ningún fichero que cite los patrones, los 4 faltan" {
  aa_root
  run bash "$T/scripts/attention-anchor-check.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r .checked <<<"$output")" -eq 4 ]
  [ "$(jq -r .found <<<"$output")" -eq 0 ]
  [ "$(jq -c '.missing|sort' <<<"$output")" = '["A7","A9","B8","B9"]' ]
  [ "$(jq -c .details <<<"$output")" = "{}" ]
}

@test "SE-080 comportamiento: el script no se cuenta a sí mismo como referencia" {
  aa_root
  echo "nada relevante" > "$T/docs/a.md"
  run bash "$T/scripts/attention-anchor-check.sh"
  [ "$(jq -r .found <<<"$output")" -eq 0 ]
  [[ "$(jq -r '.details|keys|length' <<<"$output")" -eq 0 ]]
}

@test "SE-080 comportamiento: cada patrón se localiza con fichero:línea del primer acierto" {
  aa_root
  printf 'intro\nlínea con B8 aquí\notra\n' > "$T/docs/uno.md"
  printf 'x\ny\nz\nA9 supervised\n' > "$T/docs/rules/dos.md"
  printf '# B9 goal steward\n' > "$T/scripts/tres.sh"
  run bash "$T/scripts/attention-anchor-check.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r .found <<<"$output")" -eq 3 ]
  [ "$(jq -c '.missing' <<<"$output")" = '["A7"]' ]
  [ "$(jq -r .details.B8 <<<"$output")" = "docs/uno.md:2" ]
  [ "$(jq -r .details.A9 <<<"$output")" = "docs/rules/dos.md:4" ]
  [ "$(jq -r .details.B9 <<<"$output")" = "scripts/tres.sh:1" ]
}

@test "SE-080 comportamiento: solo cuentan ficheros .md y .sh de docs, scripts y .opencode" {
  aa_root
  echo "A7 en texto plano" > "$T/docs/notas.txt"
  mkdir -p "$T/otro"
  echo "A7 fuera de las carpetas" > "$T/otro/x.md"
  run bash "$T/scripts/attention-anchor-check.sh"
  [ "$(jq -r .found <<<"$output")" -eq 0 ]
  echo "A7 en .opencode" > "$T/.opencode/regla.md"
  run bash "$T/scripts/attention-anchor-check.sh"
  [ "$(jq -r .found <<<"$output")" -eq 1 ]
  [ "$(jq -r .details.A7 <<<"$output")" = ".opencode/regla.md:1" ]
}

@test "SE-080 comportamiento: los 4 patrones presentes → found 4 y missing vacío" {
  aa_root
  printf 'B8\nB9\nA7\nA9\n' > "$T/docs/todos.md"
  run bash "$T/scripts/attention-anchor-check.sh"
  [ "$(jq -r .found <<<"$output")" -eq 4 ]
  [ "$(jq -c .missing <<<"$output")" = "[]" ]
  [ "$(jq -r '.details|length' <<<"$output")" -eq 4 ]
}
