#!/usr/bin/env bats
# tests/test-repeat-tool-guard.bats — SE-326 S1: repeat-tool-guard (AC-S1).
# Ref: docs/propuestas/SE-326-harness-loop-hygiene.md

GUARD="scripts/repeat-tool-guard.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

guard() { # session tool args [turn]
  python3 "$GUARD" --session "$1" --tool "$2" --args "$3" --turn "${4:-turn1}" --state-dir "$TMPD/state" 2>"$TMPD/stderr.txt"
}

# ── AC-S1 ─────────────────────────────────────────────────────────────────

@test "S1.1: 3 llamadas idénticas seguidas → nudge genérico (AC-S1.1)" {
  guard s1 Read '{"file_path":"a.py"}' >/dev/null
  guard s1 Read '{"file_path":"a.py"}' >/dev/null
  run guard s1 Read '{"file_path":"a.py"}'
  grep -q "repeating the exact same tool call" "$TMPD/stderr.txt"
}

@test "S1.2: 5 llamadas idénticas → recordatorio detallado con tool y run length (AC-S1.2)" {
  for i in 1 2 3 4; do guard s2 Read '{"file_path":"a.py"}' >/dev/null; done
  run guard s2 Read '{"file_path":"a.py"}'
  grep -q "Repeated tool call detected" "$TMPD/stderr.txt"
  grep -q "tool: Read" "$TMPD/stderr.txt"
  grep -q "consecutive_calls: 5" "$TMPD/stderr.txt"
}

@test "S1.3: tool excluida no lava la cadena (AC-S1.3)" {
  guard s3 Grep '{"pattern":"x"}' >/dev/null
  python3 "$GUARD" --session s3 --tool todo_write --args '{"task":"x"}' --turn turn1 --exclude todo_write,todowrite --state-dir "$TMPD/state" >/dev/null 2>&1
  guard s3 Grep '{"pattern":"x"}' >/dev/null
  guard s3 Grep '{"pattern":"x"}' >/dev/null
  # 4ª llamada Grep (todo_write excluida no lava): aún no es threshold 5 → sin mensaje
  guard s3 Grep '{"pattern":"x"}' >/dev/null 2>"$TMPD/stderr3.txt"
  # 5ª llamada → threshold 5 → detalle con consecutive_calls: 5 (cadena NO se reinició)
  run guard s3 Grep '{"pattern":"x"}'
  grep -q "consecutive_calls: 5" "$TMPD/stderr.txt"
}

@test "S1.4: args en distinto orden cuentan como idénticas (AC-S1.4)" {
  guard s4 Bash '{"command":"ls","cwd":"/tmp"}' >/dev/null
  guard s4 Bash '{"cwd":"/tmp","command":"ls"}' >/dev/null
  guard s4 Bash '{"command":"ls","cwd":"/tmp"}' >/dev/null
  guard s4 Bash '{"cwd":"/tmp","command":"ls"}' >/dev/null
  run guard s4 Bash '{"command":"ls","cwd":"/tmp"}'
  grep -q "consecutive_calls: 5" "$TMPD/stderr.txt"
}

@test "S1.5: una llamada distinta resetea la cadena (AC-S1.5)" {
  guard s5 Read '{"file_path":"a.py"}' >/dev/null
  guard s5 Read '{"file_path":"b.py"}' >/dev/null
  guard s5 Read '{"file_path":"b.py"}' >/dev/null
  guard s5 Read '{"file_path":"b.py"}' >/dev/null
  guard s5 Read '{"file_path":"b.py"}' >/dev/null
  run guard s5 Read '{"file_path":"b.py"}'
  grep -q "consecutive_calls: 5" "$TMPD/stderr.txt"
}

@test "S1.6: el guard nunca bloquea — exit 0 siempre (AC-S1.6)" {
  for i in 1 2 3 4 5; do guard s6 Read '{"file_path":"a.py"}' >/dev/null; done
  guard s6 Read '{"file_path":"a.py"}' >/dev/null
  [[ $? -eq 0 ]]
  run python3 "$GUARD" --session s6 --tool Read --args '{"file_path":"a.py"}' --turn turn2 --state-dir "$TMPD/state"
  [[ $? -eq 0 ]]
}

@test "S1.7: cambio de turno resetea la cadena (AC-S1.1 + reset)" {
  guard s7 Read '{"file_path":"a.py"}' >/dev/null
  guard s7 Read '{"file_path":"a.py"}' >/dev/null
  guard s7 Read '{"file_path":"a.py"}' turn2 >/dev/null 2>"$TMPD/stderr2.txt"
  [[ ! -s "$TMPD/stderr2.txt" ]]
}

@test "S1.8: threshold configurable (--thresholds 2,4)" {
  python3 "$GUARD" --session s8 --tool Read --args '{"file_path":"a.py"}' --thresholds 2,4 --state-dir "$TMPD/state" 2>"$TMPD/e1" >/dev/null
  # 2ª llamada → threshold 2 (primero) → nudge genérico
  python3 "$GUARD" --session s8 --tool Read --args '{"file_path":"a.py"}' --thresholds 2,4 --state-dir "$TMPD/state" 2>"$TMPD/e2" >/dev/null
  grep -q "repeating the exact same tool call" "$TMPD/e2"
}

# --- S03c: umbrales, truncado, estado y modo pre del núcleo (SE-326 / SE-445) ---

rep() { # rep N session tool args [extra...] → N llamadas; deja stderr de la última en $TMPD/last
  local n="$1" s="$2" t="$3" a="$4"; shift 4
  local i
  for ((i = 1; i <= n; i++)); do
    python3 "$GUARD" --session "$s" --tool "$t" --args "$a" --turn t1 --state-dir "$TMPD/state" "$@" 2>"$TMPD/last" >/dev/null
  done
}

@test "umbrales por defecto 3,5,8: 4ª y 6ª llamada no emiten nada (borde entre umbrales)" {
  rep 4 u1 Read '{"f":1}'
  [[ ! -s "$TMPD/last" ]]
  rep 1 u1 Read '{"f":1}'
  grep -q "consecutive_calls: 5" "$TMPD/last"
  rep 1 u1 Read '{"f":1}'
  [[ ! -s "$TMPD/last" ]]
}

@test "la 8ª llamada idéntica emite el recordatorio detallado con consecutive_calls: 8" {
  rep 8 u2 Read '{"f":1}'
  grep -q "consecutive_calls: 8" "$TMPD/last"
  ! grep -q "repeating the exact same tool call" "$TMPD/last"
}

@test "--thresholds inválidos (menor que 2, duplicados, no numéricos) caen a los por defecto" {
  for bad in "1,4" "3,3" "a,b"; do
    rm_state="$TMPD/state"; find "$rm_state" -name '*.json' -delete 2>/dev/null || true
    rep 3 "bad$RANDOM" Read '{"f":1}' --thresholds "$bad"
    grep -q "repeating the exact same tool call" "$TMPD/last"
  done
}

@test "--preview recorta los argumentos y cuenta los caracteres omitidos" {
  long=$(python3 -c "import json; print(json.dumps({'k': 'v' * 300}))")
  rep 5 u3 Read "$long" --preview 40
  grep -qE "\(\+[0-9]+ more chars\)" "$TMPD/last"
  line=$(grep "^- arguments:" "$TMPD/last")
  [ "${#line}" -lt 120 ]
}

@test "args vacíos y JSON inválido son cadenas estables, no errores" {
  rep 3 u4 Read ''
  grep -q "repeating the exact same tool call" "$TMPD/last"
  rep 3 u5 Read 'no-es-json'
  grep -q "repeating the exact same tool call" "$TMPD/last"
}

@test "args anidados con distinto orden de claves cuentan como idénticos" {
  python3 "$GUARD" --session u6 --tool Edit --args '{"a":{"x":1,"y":[1,2]},"b":2}' --turn t1 --state-dir "$TMPD/state" 2>/dev/null >/dev/null
  python3 "$GUARD" --session u6 --tool Edit --args '{"b":2,"a":{"y":[1,2],"x":1}}' --turn t1 --state-dir "$TMPD/state" 2>/dev/null >/dev/null
  python3 "$GUARD" --session u6 --tool Edit --args '{"a":{"y":[1,2],"x":1},"b":2}' --turn t1 --state-dir "$TMPD/state" 2>"$TMPD/last" >/dev/null
  grep -q "repeating the exact same tool call" "$TMPD/last"
}

@test "listas con distinto orden NO son idénticas (el orden de arrays importa)" {
  python3 "$GUARD" --session u7 --tool Edit --args '{"l":[1,2]}' --turn t1 --state-dir "$TMPD/state" 2>/dev/null >/dev/null
  python3 "$GUARD" --session u7 --tool Edit --args '{"l":[2,1]}' --turn t1 --state-dir "$TMPD/state" 2>/dev/null >/dev/null
  python3 "$GUARD" --session u7 --tool Edit --args '{"l":[1,2]}' --turn t1 --state-dir "$TMPD/state" 2>"$TMPD/last" >/dev/null
  [[ ! -s "$TMPD/last" ]]
}

@test "estado persistido: fichero <sesión>.json con tool, count y canónico" {
  rep 2 u8 Read '{"b":1,"a":2}'
  python3 - "$TMPD/state/u8.json" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
chain = st["u8:::t1"]
assert chain["tool"] == "Read" and chain["count"] == 2, chain
assert chain["canonical"] == '{"a":2,"b":1}', chain
PY
}

@test "--no-persist no deja fichero de estado ni acumula entre procesos" {
  rep 4 u9 Read '{"f":1}' --no-persist
  [[ ! -e "$TMPD/state/u9.json" ]]
  [[ ! -s "$TMPD/last" ]]
}

@test "estado corrupto se ignora y la cadena empieza de cero (sin traza de error)" {
  mkdir -p "$TMPD/state"
  echo '{{{ corrupto' > "$TMPD/state/u10.json"
  rep 1 u10 Read '{"f":1}'
  [[ ! -s "$TMPD/last" ]]
  python3 -c "import json; json.load(open('$TMPD/state/u10.json'))"
}

@test "herramientas por defecto excluidas (todo_write/TodoWrite) no cuentan ni persisten" {
  rep 6 u11 TodoWrite '{"t":1}'
  [[ ! -s "$TMPD/last" ]]
  [[ ! -e "$TMPD/state/u11.json" ]]
}

@test "--exclude es insensible a mayúsculas" {
  rep 6 u12 BASH '{"c":1}' --exclude bash
  [[ ! -s "$TMPD/last" ]]
}

@test "telemetría: con --emit-telemetry se invoca el emisor con tool y run_length" {
  cat > "$TMPD/emit.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$(dirname "$0")/emitted.txt"
EOF
  rep 3 u13 Grep '{"p":1}' --emit-telemetry "$TMPD/emit.sh"
  grep -qx "savia.loop-guard" "$TMPD/emitted.txt"
  grep -qx "tool=Grep" "$TMPD/emitted.txt"
  grep -qx "run_length=3" "$TMPD/emitted.txt"
}

@test "telemetría: emisor inexistente no rompe el guard (exit 0)" {
  run python3 "$GUARD" --session u14 --tool Read --args '{}' --turn t1 --thresholds 2 --state-dir "$TMPD/state" --emit-telemetry /no/existe.sh
  [ "$status" -eq 0 ]
}

@test "modo pre: 2ª idéntica avisa (exit 0), 3ª bloquea (exit 2) con mensaje de handback" {
  run python3 "$GUARD" --mode pre --session p1 --tool Bash --args '{"command":"ls"}' --state-dir "$TMPD/state"
  [ "$status" -eq 0 ]
  run python3 "$GUARD" --mode pre --session p1 --tool Bash --args '{"command":"ls"}' --state-dir "$TMPD/state"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2/3 antes de bloqueo"
  run python3 "$GUARD" --mode pre --session p1 --tool Bash --args '{"command":"ls"}' --state-dir "$TMPD/state"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "BLOQUEADO"
  echo "$output" | grep -q "Handback (SE-332)"
}

@test "modo pre: --block-at 2 adelanta el bloqueo a la 2ª llamada" {
  python3 "$GUARD" --mode pre --session p2 --tool Read --args '{}' --block-at 2 --state-dir "$TMPD/state" 2>/dev/null
  run python3 "$GUARD" --mode pre --session p2 --tool Read --args '{}' --block-at 2 --state-dir "$TMPD/state"
  [ "$status" -eq 2 ]
}

@test "modo pre: --window 0 reinicia la cadena en cada llamada (nunca bloquea)" {
  for i in 1 2 3 4; do
    run python3 "$GUARD" --mode pre --session p3 --tool Read --args '{}' --window 0 --state-dir "$TMPD/state"
    sleep 0.01
  done
  [ "$status" -eq 0 ]
}

@test "modo pre: la clave de sesión con ../ se sanea y no escapa del state-dir" {
  python3 "$GUARD" --mode pre --session '../../fuga' --tool Read --args '{}' --state-dir "$TMPD/state" 2>/dev/null
  [[ ! -e "$TMPD/fuga.pre.json" ]]
  [[ ! -e "$TMPD/../fuga.pre.json" ]]
  ls -a "$TMPD/state" | grep -q "fuga.pre.json"
}

@test "modo pre: Bash ignora description y espacios; otras tools no" {
  for i in 1 2; do
    python3 "$GUARD" --mode pre --session p5 --tool Bash --args '{"command":"ls   -la","description":"d'$i'"}' --state-dir "$TMPD/state" 2>/dev/null
  done
  run python3 "$GUARD" --mode pre --session p5 --tool Bash --args '{"command":"ls -la","description":"otro"}' --state-dir "$TMPD/state"
  [ "$status" -eq 2 ]
  python3 "$GUARD" --mode pre --session p6 --tool Edit --args '{"command":"x","description":"a"}' --state-dir "$TMPD/state" 2>/dev/null
  python3 "$GUARD" --mode pre --session p6 --tool Edit --args '{"command":"x","description":"b"}' --state-dir "$TMPD/state" 2>/dev/null
  run python3 "$GUARD" --mode pre --session p6 --tool Edit --args '{"command":"x","description":"c"}' --state-dir "$TMPD/state"
  [ "$status" -eq 0 ]
}

@test "modo pre: TodoWrite excluida nunca bloquea aunque se repita" {
  for i in 1 2 3 4; do
    run python3 "$GUARD" --mode pre --session p7 --tool TodoWrite --args '{"t":1}' --state-dir "$TMPD/state"
  done
  [ "$status" -eq 0 ]
}
