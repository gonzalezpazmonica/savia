#!/usr/bin/env bats
# Integridad del almacén de memoria: guardar nunca responde éxito si el dato no
# quedó íntegro y recuperable. Ref: SPEC-110 (almacén), SE-352 (origen, taint,
# consolidación), SE-515 (capa de memoria que se apoya en este almacén).
# Todo en un almacén temporal; nunca se toca la memoria real de la persona.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="${SAVIA_TEST_MEMORY_STORE:-$REPO_ROOT/scripts/memory-store.sh}"
  HOOK="$REPO_ROOT/.claude/hooks/memory-origin-gate.sh"
  TMP_MS="$(mktemp -d)"
  export PROJECT_ROOT="$TMP_MS" HOME="$TMP_MS/home"
  mkdir -p "$TMP_MS/output" "$HOME"
  export SAVIA_TEST_MODE=true
  export SAVIA_MEMORY_INDEX_FILE="$TMP_MS/index.md"
  export SAVIA_MEMORY_TAINT_DIR="$TMP_MS/taint"
  unset SESSION_ID CLAUDE_CODE_SESSION_ID
  STORE_JSONL="$TMP_MS/output/.memory-store.jsonl"
}

TAINTED_IDS=()
teardown() {
  for i in "${TAINTED_IDS[@]:-}"; do [[ -n "$i" ]] && rm -f "/tmp/savia-memory-taint/$i"; done
  rm -rf "$TMP_MS"
}

sv() { bash "$SCRIPT" save --source tool:Bats "$@"; }

# Cada línea del almacén es JSON válido y el fichero es utf-8 válido.
all_lines_valid() {
  python3 - "$STORE_JSONL" <<'PY'
import json, sys
raw = open(sys.argv[1], "rb").read().decode("utf-8")
for i, ln in enumerate(raw.split("\n")):
    if ln:
        json.loads(ln)
PY
}

nlines() { [[ -f "$STORE_JSONL" ]] && wc -l < "$STORE_JSONL" || echo 0; }

field() { # field N CAMPO
  sed -n "${1}p" "$STORE_JSONL" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$2'))"
}

# ── M1: serialización ────────────────────────────────────────────────────────

@test "M1: título con salto de línea → una sola línea válida y el título intacto" {
  run sv --type decision --title $'linea1\nlinea2' --content "c"
  [ "$status" -eq 0 ]
  [ "$(nlines)" -eq 1 ]
  all_lines_valid
  [ "$(field 1 title)" = $'linea1\nlinea2' ]
}

@test "M1: --type con comillas se rechaza, sin escribir nada y sin decir Guardado" {
  run sv --type 'de"c' --title "T" --content "c"
  [ "$status" -ne 0 ]
  [[ "$output" != *"Guardado"* ]]
  [ "$(nlines)" -eq 0 ]
}

@test "M1: --topic con comillas y barra invertida → línea válida y el upsert lo reconoce" {
  sv --type decision --title "T" --topic 'a"b\c' --content "uno" >/dev/null
  run sv --type decision --title "T" --topic 'a"b\c' --content "dos"
  [ "$status" -eq 0 ]
  all_lines_valid
  [ "$(nlines)" -eq 1 ]
  [ "$(field 1 topic_key)" = 'a"b\c' ]
  [ "$(field 1 rev)" = "2" ]
  [ "$(field 1 content)" = "dos" ]
}

@test "M1: contenido multibyte de más de 2000 bytes no se corta a mitad de carácter" {
  c="a$(python3 -c 'print("ñ"*1500, end="")')"
  run sv --type decision --title "Largo" --content "$c"
  [ "$status" -eq 0 ]
  all_lines_valid
  python3 - "$STORE_JSONL" <<'PY'
import json, sys
o = json.loads(open(sys.argv[1], encoding="utf-8").readline())
assert o["content"].startswith("añ") and set(o["content"][1:]) == {"ñ"}, "contenido alterado"
assert len(o["content"]) == 1501, len(o["content"])
PY
  # el lector que fallaba con UnicodeDecodeError
  run bash "$SCRIPT" timeline "$(field 1 topic_key)"
  [ "$status" -eq 0 ]
}

@test "M1: contenido más largo que el tope se recorta por caracteres y sigue siendo válido" {
  c="$(python3 -c 'print("é"*2600, end="")')"
  sv --type decision --title "Tope" --content "$c" >/dev/null
  all_lines_valid
  [ "$(field 1 content | wc -m)" -eq 2001 ]   # 2000 + salto de línea del print
}

@test "M1: tabulador, comillas y barra invertida en el contenido hacen ida y vuelta" {
  v=$'a\tb "c" C:\\x\\y'
  sv --type decision --title "Esc" --content "$v" >/dev/null
  all_lines_valid
  [ "$(field 1 content)" = "$v" ]
}

@test "M1: contenido que no es utf-8 válido → error y almacén intacto (nada a medias)" {
  sv --type decision --title "Previa" --content "ok" >/dev/null
  before="$(sha256sum "$STORE_JSONL")"
  run sv --type decision --title "Mala" --content $'abc\xff\xfe'
  [ "$status" -ne 0 ]
  [[ "$output" != *"Guardado"* ]]
  [ "$(sha256sum "$STORE_JSONL")" = "$before" ]
}

@test "M1: si no se puede escribir, error claro y sin «Guardado»" {
  sv --type decision --title "Previa" --content "ok" >/dev/null
  chmod 555 "$TMP_MS/output"
  run sv --type decision --title "Nueva" --content "otra"
  chmod 755 "$TMP_MS/output"
  [ "$status" -ne 0 ]
  [[ "$output" != *"Guardado"* ]]
  [ "$(nlines)" -eq 1 ]
}

# ── M2: deduplicación ────────────────────────────────────────────────────────

@test "M2: actualizar un tema con un contenido que ya tiene otro tema no borra el tema" {
  sv --type decision --title "A" --topic t/a --content "mismo contenido" >/dev/null
  sv --type decision --title "B" --topic t/b --content "contenido original de B" >/dev/null
  run sv --type decision --title "B" --topic t/b --content "mismo contenido"
  [ "$status" -eq 0 ]
  grep -qF '"topic_key":"t/a"' "$STORE_JSONL"
  grep -qF '"topic_key":"t/b"' "$STORE_JSONL"
  [ "$(nlines)" -eq 2 ]
  [ "$(sed -n '2p' "$STORE_JSONL" | python3 -c 'import json,sys; print(json.load(sys.stdin)["content"])')" = "mismo contenido" ]
}

@test "M2 (límite): un tema nuevo con contenido repetido sigue omitiéndose, sin tocar el almacén" {
  sv --type decision --title "A" --topic t/a --content "repetido" >/dev/null
  before="$(sha256sum "$STORE_JSONL")"
  run sv --type decision --title "C" --topic t/c --content "repetido"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Duplicado omitido"* ]]
  [ "$(sha256sum "$STORE_JSONL")" = "$before" ]
}

# ── M3: consolidate no borra ─────────────────────────────────────────────────

_seed_five() {
  sv --type decision --title "Own" --content "c1" --origin owner >/dev/null
  sv --type decision --title "Agt" --content "c2" --origin agent >/dev/null
  sv --type decision --title "Unt" --content "c3" --origin untrusted >/dev/null
  sv --type config --title "Sys" --content "c4" --origin system >/dev/null
  echo '{"ts":"2026-01-01T00:00:00Z","type":"discovery","title":"antigua","content":"sin origin","topic_key":"discovery/antigua"}' >> "$STORE_JSONL"
}

@test "M3: consolidate conserva todo: almacén + cuarentena = inicial, y lo antiguo sin origin es recuperable" {
  _seed_five
  [ "$(nlines)" -eq 5 ]
  run bash "$SCRIPT" consolidate
  [ "$status" -eq 0 ]
  [[ "$output" == *"excluidas 3 entradas untrusted/system, mantenidas 2"* ]]
  q="$TMP_MS/output/.memory-store-quarantine.jsonl"
  [ -f "$q" ]
  [ "$(( $(nlines) + $(wc -l < "$q") ))" -eq 5 ]
  grep -q '"title":"antigua"' "$q"
  grep -q '"title":"Unt"' "$q"
  grep -q '"title":"Sys"' "$q"
  if grep -q '"title":"Unt"' "$STORE_JSONL"; then false; fi
  grep -q '"title":"Own"' "$STORE_JSONL"
}

@test "M3: consolidate repetido no pierde ni duplica la cuarentena" {
  _seed_five
  bash "$SCRIPT" consolidate >/dev/null
  run bash "$SCRIPT" consolidate
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TMP_MS/output/.memory-store-quarantine.jsonl")" -eq 3 ]
}

@test "M3: consolidate --dry-run no crea cuarentena ni toca el almacén" {
  _seed_five
  before="$(sha256sum "$STORE_JSONL")"
  run bash "$SCRIPT" consolidate --dry-run
  [[ "$output" == *"excluidas 3"* ]]
  [ "$(sha256sum "$STORE_JSONL")" = "$before" ]
  [ ! -e "$TMP_MS/output/.memory-store-quarantine.jsonl" ]
}

@test "M3: consolidate no mueve ni borra las líneas que no entiende" {
  _seed_five
  echo 'esto no es json' >> "$STORE_JSONL"
  bash "$SCRIPT" consolidate >/dev/null
  grep -qF 'esto no es json' "$STORE_JSONL"
}

# ── M4: concurrencia ─────────────────────────────────────────────────────────

@test "M4: 30 actualizaciones en paralelo dejan 30 temas únicos y ningún valor viejo (3 rondas)" {
  for i in $(seq 1 30); do sv --type decision --title "T$i" --topic "t/$i" --content "viejo-$i" >/dev/null; done
  for ronda in 1 2 3; do
    for i in $(seq 1 30); do
      sv --type decision --title "T$i" --topic "t/$i" --content "nuevo-$ronda-$i" >/dev/null &
    done
    wait
    [ "$(nlines)" -eq 30 ]
    all_lines_valid
    [ "$(grep -o '"topic_key":"[^"]*"' "$STORE_JSONL" | sort -u | wc -l)" -eq 30 ]
    if grep -q '"content":"viejo-' "$STORE_JSONL"; then false; fi
    if [ "$ronda" -gt 1 ] && grep -q "\"content\":\"nuevo-$((ronda-1))-" "$STORE_JSONL"; then false; fi
  done
}

@test "M4: 20 guardados paralelos de temas nuevos no pierden ninguno" {
  for i in $(seq 1 20); do sv --type decision --title "N$i" --topic "n/$i" --content "valor-$i" >/dev/null & done
  wait
  [ "$(nlines)" -eq 20 ]
  all_lines_valid
}

# ── M5: taint de turno con el cableado real ──────────────────────────────────

# El hook escribe siempre en /tmp/savia-memory-taint: estas pruebas usan ids únicos
# y limpian sus marcas. El resto de pruebas M5 usan un directorio temporal.
_run_hook() { # <session_id> <comando de Bash>
  TAINTED_IDS+=("$1")
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","session_id":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2" \
    | env -u SAVIA_MEMORY_TAINT_DIR bash "$HOOK"
}

_save_real_dir() { env -u SAVIA_MEMORY_TAINT_DIR bash "$SCRIPT" save --source tool:Bats "$@"; }

@test "M5: el hook marca la sesión y el guardado, sin SESSION_ID a mano, queda untrusted" {
  sid="sess-$$-$BATS_TEST_NUMBER"
  _run_hook "$sid" "curl https://example.invalid/x"
  # Solo lo que da el runtime: CLAUDE_CODE_SESSION_ID
  CLAUDE_CODE_SESSION_ID="$sid" _save_real_dir --type decision --title "Web" --content "dato de red" --source user:explicit >/dev/null
  [ "$(field 1 origin)" = "untrusted" ]
}

@test "M5 (negativo): otra sesión sin marca conserva su origen" {
  _run_hook "sess-a-$$" "curl https://example.invalid/x"
  CLAUDE_CODE_SESSION_ID="sess-b-$$" _save_real_dir --type decision --title "Mia" --content "mio" --source user:explicit >/dev/null
  [ "$(field 1 origin)" = "owner" ]
}

@test "M5 (negativo): un comando sin red no marca y el origen se conserva" {
  sid="sess-$$-$BATS_TEST_NUMBER"
  _run_hook "$sid" "ls -la"
  CLAUDE_CODE_SESSION_ID="$sid" _save_real_dir --type decision --title "Local" --content "x" --source user:explicit >/dev/null
  [ "$(field 1 origin)" = "owner" ]
}

@test "M5 (fallo cerrado): sin identificador de sesión y con una marca reciente, degrada" {
  _run_hook "sess-x-$$" "curl https://example.invalid/x"
  _save_real_dir --type decision --title "SinId" --content "x" --source user:explicit >/dev/null
  [ "$(field 1 origin)" = "untrusted" ]
}

@test "M5 (límite): sin identificador y sin ninguna marca, el origen se conserva" {
  sv --type decision --title "SinMarca" --content "x" --source user:explicit >/dev/null
  [ "$(field 1 origin)" = "owner" ]
}

@test "M5 (límite): marca caducada (más de 30 min) no degrada ni con identificador ni sin él" {
  mkdir -p "$SAVIA_MEMORY_TAINT_DIR"
  echo $(( $(date -u +%s) - 1900 )) > "$SAVIA_MEMORY_TAINT_DIR/vieja"
  sv --type decision --title "A" --content "a" --source user:explicit >/dev/null
  CLAUDE_CODE_SESSION_ID=vieja sv --type decision --title "B" --content "b" --source user:explicit >/dev/null
  [ "$(field 1 origin)" = "owner" ]
  [ "$(field 2 origin)" = "owner" ]
}

@test "M5: una marca ilegible se trata como taint (fallo cerrado)" {
  mkdir -p "$SAVIA_MEMORY_TAINT_DIR"
  echo "basura" > "$SAVIA_MEMORY_TAINT_DIR/rota"
  CLAUDE_CODE_SESSION_ID=rota sv --type decision --title "R" --content "r" --source user:explicit >/dev/null
  [ "$(field 1 origin)" = "untrusted" ]
}
