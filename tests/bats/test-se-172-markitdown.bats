#!/usr/bin/env bats
# tests/bats/test-se-172-markitdown.bats
# SE-172 — markitdown como capa 0 universal de digestión
# AC-08: >= 20 tests

# ── Setup helpers ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
DIGEST_EXTRACT="$SCRIPT_DIR/scripts/digest-extract.sh"
WRAPPER="$SCRIPT_DIR/scripts/markitdown-digest-wrapper.py"
AGENTS_DIR="$SCRIPT_DIR/.opencode/agents"
TMP_DIR=""

setup() {
  # TMP_DIR must be inside WORKSPACE_ROOT so AC-07 path checks pass. The workspace is the test's own
  # temp dir, not the repo: files created inside the repo are seen by suites that walk it in parallel.
  export WORKSPACE_ROOT="$BATS_TEST_TMPDIR"
  TMP_DIR="$(mktemp -d "$WORKSPACE_ROOT/se172-XXXXXX")"
}

teardown() {
  rm -rf "$TMP_DIR"
}

# ── T01: digest-extract.sh existe y es ejecutable ────────────────────────────
@test "T01: digest-extract.sh existe y es ejecutable" {
  [ -f "$DIGEST_EXTRACT" ]
  [ -x "$DIGEST_EXTRACT" ]
}

# ── T02: markitdown-digest-wrapper.py existe ─────────────────────────────────
@test "T02: markitdown-digest-wrapper.py existe" {
  [ -f "$WRAPPER" ]
}

# ── T03: AC-07 — rechaza path fuera de workspace sin --external ──────────────
@test "T03: AC-07 rechaza path fuera de workspace sin --external" {
  run bash "$DIGEST_EXTRACT" /tmp/some-outside-file.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARNING"* ]] || [[ "$stderr" == *"WARNING"* ]] || \
    echo "$output $stderr" | grep -q "WARNING\|rejected\|outside"
}

# ── T04: AC-07 — acepta path fuera de workspace con --external ───────────────
@test "T04: AC-07 acepta path externo con --external (fichero inexistente → WARNING distinto)" {
  # Con --external, el gate de workspace se salta pero el fichero no existe
  run bash "$DIGEST_EXTRACT" /tmp/nonexistent-test-file.txt --external
  # Debe fallar por fichero no encontrado, no por path fuera de workspace
  [ "$status" -eq 1 ]
  echo "$output $stderr" | grep -qi "not found\|WARNING"
}

# ── T05: con .txt simple produce markdown con front-matter ───────────────────
@test "T05: con .txt produce markdown con front-matter" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  local txt_file="$TMP_DIR/test.txt"
  echo "Hello world from SE-172 test" > "$txt_file"

  run bash "$DIGEST_EXTRACT" "$txt_file"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "mime:"
  echo "$output" | grep -q "hash_original:"
  echo "$output" | grep -q "timestamp:"
}

# ── T06: front-matter contiene mime ──────────────────────────────────────────
@test "T06: front-matter contiene campo mime" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  local txt_file="$TMP_DIR/test2.txt"
  echo "SE-172 mime test content" > "$txt_file"

  run bash "$DIGEST_EXTRACT" "$txt_file"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^mime:"
}

# ── T07: front-matter contiene hash_original ─────────────────────────────────
@test "T07: front-matter contiene hash_original" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  local txt_file="$TMP_DIR/test3.txt"
  echo "SE-172 hash test" > "$txt_file"

  run bash "$DIGEST_EXTRACT" "$txt_file"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^hash_original:"
}

# ── T08: front-matter contiene timestamp ─────────────────────────────────────
@test "T08: front-matter contiene timestamp" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  local txt_file="$TMP_DIR/test4.txt"
  echo "SE-172 timestamp test" > "$txt_file"

  run bash "$DIGEST_EXTRACT" "$txt_file"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^timestamp:"
}

# ── T09: front-matter contiene markitdown_version ────────────────────────────
@test "T09: front-matter contiene markitdown_version" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  local txt_file="$TMP_DIR/test5.txt"
  echo "SE-172 version test" > "$txt_file"

  run bash "$DIGEST_EXTRACT" "$txt_file"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^markitdown_version:"
}

# ── T10: front-matter delimitado por --- ─────────────────────────────────────
@test "T10: output tiene front-matter delimitado por ---" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  local txt_file="$TMP_DIR/frontmatter-test.txt"
  echo "Front-matter test" > "$txt_file"

  run bash "$DIGEST_EXTRACT" "$txt_file"
  [ "$status" -eq 0 ]
  # Primer y segundo --- deben estar presentes
  local count
  count=$(echo "$output" | grep -c "^---$" || true)
  [ "$count" -ge 2 ]
}

# ── T11: AC-07 — sin input: exit 1 con mensaje de uso ────────────────────────
@test "T11: sin input muestra uso y exit 1" {
  run bash "$DIGEST_EXTRACT"
  [ "$status" -eq 1 ]
  echo "$output $stderr" | grep -qi "usage\|Usage"
}

# ── T12: MARKITDOWN_ENABLED=false en wrapper → fallback_used=true ─────────────
@test "T12: MARKITDOWN_ENABLED=false en wrapper produce fallback_used=true" {
  local txt_file="$TMP_DIR/disabled-test.txt"
  echo "test content" > "$txt_file"

  run env MARKITDOWN_ENABLED=false python3 "$WRAPPER" --file "$txt_file" --agent pdf
  # Puede exit 1 (fallback) o 0
  local json_out="$output"
  echo "$json_out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['fallback_used']==True, f'Expected fallback_used=True, got {d}'"
  [ "$?" -eq 0 ]
}

# ── T13: wrapper devuelve JSON válido ────────────────────────────────────────
@test "T13: wrapper devuelve JSON válido" {
  local txt_file="$TMP_DIR/json-test.txt"
  echo "json validity test" > "$txt_file"

  run python3 "$WRAPPER" --file "$txt_file" --agent pdf
  # Intentar parsear el JSON
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin); print('valid')" | grep -q "valid"
}

# ── T14: wrapper devuelve campo markitdown_version ───────────────────────────
@test "T14: wrapper devuelve campo markitdown_version en JSON" {
  local txt_file="$TMP_DIR/version-test.txt"
  echo "version test" > "$txt_file"

  run python3 "$WRAPPER" --file "$txt_file" --agent word
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'markitdown_version' in d, 'Missing markitdown_version'
print('OK')
" | grep -q "OK"
}

# ── T15: wrapper rechaza --file vacío ────────────────────────────────────────
@test "T15: wrapper rechaza --file vacío" {
  run python3 "$WRAPPER" --file "" --agent pdf
  [ "$status" -ne 0 ] || echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d.get('fallback_used') == True or d.get('ok') == False
"
}

# ── T16: pdf-digest.md tiene Fase 1 Markitdown ───────────────────────────────
@test "T16: pdf-digest.md tiene sección Fase 1 Markitdown" {
  grep -q "MARKITDOWN_ENABLED" "$AGENTS_DIR/pdf-digest.md"
}

# ── T17: word-digest.md tiene Fase 1 Markitdown ──────────────────────────────
@test "T17: word-digest.md tiene sección Fase 1 Markitdown" {
  grep -q "MARKITDOWN_ENABLED" "$AGENTS_DIR/word-digest.md"
}

# ── T18: excel-digest.md tiene Fase 1 Markitdown ─────────────────────────────
@test "T18: excel-digest.md tiene sección Fase 1 Markitdown" {
  grep -q "MARKITDOWN_ENABLED" "$AGENTS_DIR/excel-digest.md"
}

# ── T19: pptx-digest.md tiene Fase 1 Markitdown ──────────────────────────────
@test "T19: pptx-digest.md tiene sección Fase 1 Markitdown" {
  grep -q "MARKITDOWN_ENABLED" "$AGENTS_DIR/pptx-digest.md"
}

# ── T20: visual-digest.md tiene Fase 1 Markitdown ────────────────────────────
@test "T20: visual-digest.md tiene sección Fase 1 Markitdown" {
  grep -q "MARKITDOWN_ENABLED" "$AGENTS_DIR/visual-digest.md"
}

# ── T21: meeting-digest.md tiene Fase 1 Markitdown ───────────────────────────
@test "T21: meeting-digest.md tiene sección Fase 1 Markitdown" {
  grep -q "MARKITDOWN_ENABLED" "$AGENTS_DIR/meeting-digest.md"
}

# ── T22: archive-digest.md existe ────────────────────────────────────────────
@test "T22: archive-digest.md existe" {
  [ -f "$AGENTS_DIR/archive-digest.md" ]
}

# ── T23: archive-digest.md contiene Fase 1 Markitdown ────────────────────────
@test "T23: archive-digest.md contiene Fase 1 Markitdown" {
  grep -q "MARKITDOWN_ENABLED" "$AGENTS_DIR/archive-digest.md"
}

# ── T24: AC-05 wrapper usa convert_local (grep en wrapper) ───────────────────
@test "T24: AC-05 wrapper referencia convert_local en su código" {
  grep -q "convert_local" "$WRAPPER"
}

# ── T25: AC-05 digest-extract.sh referencia convert_local ────────────────────
@test "T25: AC-05 digest-extract.sh referencia convert_local" {
  grep -q "convert_local" "$DIGEST_EXTRACT"
}

# ── T26: digest-extract.sh tiene umask 077 (AC-07) ───────────────────────────
@test "T26: AC-07 digest-extract.sh tiene umask 077" {
  grep -q "umask 077" "$DIGEST_EXTRACT"
}

# ── T27: --output escribe fichero en workspace ────────────────────────────────
@test "T27: --output escribe el fichero de salida correctamente" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  local ws_txt="$TMP_DIR/output-test.txt"
  local ws_out="$TMP_DIR/output-result.md"
  echo "output test" > "$ws_txt"

  run bash "$DIGEST_EXTRACT" "$ws_txt" --output "$ws_out"

  [ "$status" -eq 0 ]
  [ -f "$ws_out" ]
  grep -q "mime:" "$ws_out"
}

# ── T28: digest-extract detecta MIME por extensión .pdf ──────────────────────
@test "T28: digest-extract produce mime application/pdf para .pdf" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  # Crear un PDF mínimo válido dentro del workspace
  local pdf_file="$TMP_DIR/test.pdf"
  # PDF mínimo que markitdown puede intentar abrir
  printf '%%PDF-1.0\n1 0 obj<</Type /Catalog /Pages 2 0 R>>endobj\n2 0 obj<</Type /Pages /Kids [3 0 R] /Count 1>>endobj\n3 0 obj<</Type /Page /MediaBox [0 0 3 3]>>endobj\nxref\n0 4\n0000000000 65535 f \ntail -0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \ntrailer<</Size 4 /Root 1 0 R>>\nstartxref\n190\n%%%%EOF\n' > "$pdf_file"

  run bash "$DIGEST_EXTRACT" "$pdf_file"

  # Puede fallar si markitdown no puede parsear el PDF mínimo, pero el mime debe ser correcto si pasa
  if [ "$status" -eq 0 ]; then
    echo "$output" | grep -q "application/pdf"
  fi
  # Si falla el parse, al menos debe estar el WARNING en stderr
  [ "$status" -eq 0 ] || echo "$stderr" | grep -qi "WARNING"
}

# ── T29: archive-digest.md soporta ZIP ───────────────────────────────────────
@test "T29: archive-digest.md menciona soporte ZIP" {
  grep -qi "zip" "$AGENTS_DIR/archive-digest.md"
}

# ── T30: archive-digest.md soporta EPub ──────────────────────────────────────
@test "T30: archive-digest.md menciona soporte EPub" {
  grep -qi "epub" "$AGENTS_DIR/archive-digest.md"
}

# ── T31: markitdown está instalado ───────────────────────────────────────────
@test "T31: markitdown está instalado y tiene versión" {
  python3 -c "import markitdown" 2>/dev/null || skip "markitdown not installed in CI"
  run python3 -c "import markitdown; print(markitdown.__version__)"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+ ]]
}

# ── T32: wrapper campo agent en JSON output ───────────────────────────────────
@test "T32: wrapper incluye campo agent en JSON output" {
  local txt_file="$TMP_DIR/agent-field-test.txt"
  echo "agent field test" > "$txt_file"

  run python3 "$WRAPPER" --file "$txt_file" --agent excel
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'agent' in d, 'Missing agent field'
assert d['agent'] == 'excel', f'Expected excel, got {d[\"agent\"]}'
print('OK')
" | grep -q "OK"
}
