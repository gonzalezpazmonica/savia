#!/usr/bin/env bats
# tests/test-token-meter.bats — SE-326 S3: token-meter (AC-S3).
# Ref: docs/propuestas/SE-326-harness-loop-hygiene.md

METER="scripts/token-meter.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

# ── AC-S3 ─────────────────────────────────────────────────────────────────

@test "S3.1: emite snapshot JSON con total/surface/nodes (AC-S3.1)" {
  run python3 "$METER" --session t1 --surface '[{"role":"user","text":"hola mundo"}]'
  [[ "$output" =~ '"total_tokens"' ]]
  [[ "$output" =~ '"surface_tokens"' ]]
  [[ "$output" =~ '"nodes"' ]]
  python3 -c "import json,sys; d=json.loads('''$output'''); assert 'total_tokens' in d and 'nodes' in d"
}

@test "S3.2: surface_tokens == suma de nodos (AC-S3.2)" {
  out=$(python3 "$METER" --session t2 --surface '[{"role":"user","text":"aaaa"}]')
  python3 -c "
import json,sys
d=json.loads('''$out''')
assert d['surface_tokens'] == sum(n['tokens'] for n in d['nodes']), d
"
}

@test "S3.3: medición no muta ficheros de sesión (AC-S3.3)" {
  export CLAUDE_PROJECT_DIR="$TMPD"
  mkdir -p "$TMPD/output"
  python3 "$METER" --session t3 --surface '[{"role":"user","text":"x"}]' --out "$TMPD/snap.json"
  # no toca agent-traces.jsonl ni crea estado de sesión
  [[ ! -f "$TMPD/output/agent-traces.jsonl" ]]
}

@test "S3.4: baseline usage se reutiliza (AC-S3.1 baseline)" {
  run python3 "$METER" --session t4 --surface '[{"role":"user","text":"aaaa"}]' --usage 1000
  [[ "$output" =~ '"kind": "usage"' ]]
  [[ "$output" =~ '"total_tokens": 1000' ]]
}

@test "S3.5: sin usage → baseline estimated (AC-S3.1)" {
  run python3 "$METER" --session t5 --surface '[{"role":"user","text":"aaaa"}]'
  [[ "$output" =~ '"kind": "estimated"' ]]
}

@test "S3.6: tool_result pesa más que user text (heurística x3)" {
  user=$(python3 "$METER" --session t6 --surface '[{"role":"user","text":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]' | python3 -c "import json,sys;print(json.load(sys.stdin)['surface_tokens'])")
  tool=$(python3 "$METER" --session t6 --surface '[{"role":"tool_result","text":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]' | python3 -c "import json,sys;print(json.load(sys.stdin)['surface_tokens'])")
  [[ "$tool" -gt "$user" ]]
}

# ── Comportamiento: heurística exacta, formas de entrada y baseline ───────

_m() { python3 "$METER" --session s "$@"; }
_j() { python3 -c "import json,sys;d=json.load(sys.stdin);print(eval('d'+sys.argv[1]))" "$1"; }

@test "heurística exacta por rol: 8 de marco + chars/4 por peso" {
  t=$(printf 'a%.0s' $(seq 1 40))
  [ "$(_m --surface "[{\"role\":\"user\",\"text\":\"$t\"}]" | _j "['surface_tokens']")" = "18" ]
  [ "$(_m --surface "[{\"role\":\"assistant\",\"text\":\"$t\"}]" | _j "['surface_tokens']")" = "20" ]
  [ "$(_m --surface "[{\"role\":\"tool_result\",\"text\":\"$t\"}]" | _j "['surface_tokens']")" = "46" ]
  [ "$(_m --surface "[{\"role\":\"tool_call\",\"text\":\"$t\"}]" | _j "['surface_tokens']")" = "18" ]
  [ "$(_m --surface "[{\"role\":\"system\",\"text\":\"$t\"}]" | _j "['surface_tokens']")" = "18" ]
}

@test "rol desconocido pesa 1.0; sin rol es user; texto vacío es solo el marco" {
  t=$(printf 'a%.0s' $(seq 1 40))
  [ "$(_m --surface "[{\"role\":\"otro\",\"text\":\"$t\"}]" | _j "['surface_tokens']")" = "18" ]
  [ "$(_m --surface "[{\"text\":\"$t\"}]" | _j "['surface_tokens']")" = "18" ]
  [ "$(_m --surface '[{"role":"user","text":""}]' | _j "['surface_tokens']")" = "8" ]
  [ "$(_m --surface '[{"role":"tool_result","text":""}]' | _j "['surface_tokens']")" = "16" ]
}

@test "redondeo: se trunca chars/4*peso (no se redondea hacia arriba)" {
  [ "$(_m --surface '[{"role":"user","text":"abc"}]' | _j "['surface_tokens']")" = "8" ]
  [ "$(_m --surface '[{"role":"user","text":"abcde"}]' | _j "['surface_tokens']")" = "9" ]
  [ "$(_m --surface '[{"role":"assistant","text":"abcd"}]' | _j "['surface_tokens']")" = "9" ]
}

@test "nodos con tokens explícitos se usan tal cual y respetan seq" {
  out=$(_m --surface '[{"seq":7,"tokens":100},{"tokens":50}]')
  [ "$(echo "$out" | _j "['nodes']")" = "[{'seq': 7, 'tokens': 100}, {'seq': 1, 'tokens': 50}]" ]
  [ "$(echo "$out" | _j "['surface_tokens']")" = "150" ]
}

@test "elementos que no son objeto cuentan como texto de usuario; seq es el índice" {
  out=$(_m --surface '["aaaaaaaa","bbbb"]')
  [ "$(echo "$out" | _j "['nodes']")" = "[{'seq': 0, 'tokens': 10}, {'seq': 1, 'tokens': 9}]" ]
}

@test "surface como objeto con 'nodes' se lee; sin 'nodes' queda vacío" {
  [ "$(_m --surface '{"nodes":[{"tokens":5}]}' | _j "['surface_tokens']")" = "5" ]
  [ "$(_m --surface '{"otra":1}' | _j "['surface_tokens']")" = "0" ]
}

@test "surface vacío, JSON inválido o escalar dan superficie 0 y exit 0" {
  for s in "" "   " "no es json" "42" '"texto"' "null"; do
    run _m --surface "$s"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | _j "['surface_tokens']")" = "0" ]
    [ "$(echo "$output" | _j "['nodes']")" = "[]" ]
  done
}

@test "--surface-file sustituye a --surface; fichero inexistente se ignora" {
  echo '[{"tokens":11}]' > "$TMPD/s.json"
  [ "$(_m --surface '[{"tokens":99}]' --surface-file "$TMPD/s.json" | _j "['surface_tokens']")" = "11" ]
  [ "$(_m --surface '[{"tokens":99}]' --surface-file "$TMPD/no.json" | _j "['surface_tokens']")" = "99" ]
}

@test "usage mayor que la superficie: total = usage y delta negativo" {
  out=$(_m --surface '[{"tokens":100}]' --usage 1000)
  [ "$(echo "$out" | _j "['total_tokens']")" = "1000" ]
  [ "$(echo "$out" | _j "['surface_delta_tokens']")" = "-900" ]
  [ "$(echo "$out" | _j "['baseline']")" = "{'kind': 'usage', 'anchor_tokens': 1000}" ]
}

@test "usage menor que la superficie: total = superficie y delta positivo" {
  out=$(_m --surface '[{"tokens":100}]' --usage 30)
  [ "$(echo "$out" | _j "['total_tokens']")" = "100" ]
  [ "$(echo "$out" | _j "['surface_delta_tokens']")" = "70" ]
}

@test "usage igual a la superficie: delta 0" {
  out=$(_m --surface '[{"tokens":100}]' --usage 100)
  [ "$(echo "$out" | _j "['surface_delta_tokens']")" = "0" ]
  [ "$(echo "$out" | _j "['total_tokens']")" = "100" ]
}

@test "usage 0 o negativo: baseline estimated, anchor tal cual y delta = superficie" {
  out=$(_m --surface '[{"tokens":100}]' --usage 0)
  [ "$(echo "$out" | _j "['baseline']['kind']")" = "estimated" ]
  [ "$(echo "$out" | _j "['surface_delta_tokens']")" = "100" ]
  out=$(_m --surface '[{"tokens":100}]' --usage -5)
  [ "$(echo "$out" | _j "['baseline']['kind']")" = "estimated" ]
  [ "$(echo "$out" | _j "['total_tokens']")" = "100" ]
}

@test "log_revision cuenta líneas no vacías del trace log; 0 sin fichero" {
  mkdir -p "$TMPD/proj/output"
  printf '{"a":1}\n\n{"b":2}\n   \n{"c":3}\n' > "$TMPD/proj/output/agent-traces.jsonl"
  [ "$(_m --project-dir "$TMPD/proj" | _j "['log_revision']")" = "3" ]
  [ "$(_m --project-dir "$TMPD/otro" | _j "['log_revision']")" = "0" ]
}

@test "project-dir por defecto sale de CLAUDE_PROJECT_DIR" {
  mkdir -p "$TMPD/envp/output"
  printf '{"a":1}\n' > "$TMPD/envp/output/agent-traces.jsonl"
  CLAUDE_PROJECT_DIR="$TMPD/envp" run python3 "$METER" --session s
  [ "$(echo "$output" | _j "['log_revision']")" = "1" ]
}

@test "snapshot incluye la sesión pedida" {
  [ "$(python3 "$METER" --session mi-sesion | _j "['session']")" = "mi-sesion" ]
}

@test "--out escribe el snapshot en fichero (creando directorios) y no imprime" {
  run _m --surface '[{"tokens":4}]' --out "$TMPD/a/b/snap.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(python3 -c "import json;print(json.load(open('$TMPD/a/b/snap.json'))['surface_tokens'])")" = "4" ]
}

@test "--session es obligatorio" {
  run python3 "$METER"
  [ "$status" -ne 0 ]
}

@test "--emit con script: lo invoca con evento y valores calculados" {
  cat > "$TMPD/emit.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$EMIT_LOG"
SH
  EMIT_LOG="$TMPD/emit.log" run python3 "$METER" --session ses --surface '[{"tokens":10},{"tokens":5}]' --usage 40 --emit ses --emit-script "$TMPD/emit.sh"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$TMPD/emit.log")" = "savia.token-meter" ]
  grep -qx "session=ses" "$TMPD/emit.log"
  grep -qx "total_tokens=40" "$TMPD/emit.log"
  grep -qx "surface_tokens=15" "$TMPD/emit.log"
  grep -qx "baseline=usage" "$TMPD/emit.log"
  grep -qx "nodes=2" "$TMPD/emit.log"
}

@test "--emit sin --emit o con script inexistente no emite ni falla" {
  cat > "$TMPD/emit.sh" <<'SH'
#!/usr/bin/env bash
touch "$EMIT_LOG"
SH
  EMIT_LOG="$TMPD/e1.log" run python3 "$METER" --session s --emit-script "$TMPD/emit.sh"
  [ ! -e "$TMPD/e1.log" ]
  EMIT_LOG="$TMPD/e2.log" run python3 "$METER" --session s --emit s --emit-script "$TMPD/falta.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$TMPD/e2.log" ]
}

@test "el producto se trunca una sola vez: 7 caracteres con peso fraccionario" {
  # int(7/4*1.2)=2 y int(7/4*3)=5; truncar antes (7//4) daría 1 y 3
  [ "$(_m --surface '[{"role":"assistant","text":"abcdefg"}]' | _j "['surface_tokens']")" = "10" ]
  [ "$(_m --surface '[{"role":"tool_result","text":"abcdefg"}]' | _j "['surface_tokens']")" = "21" ]
}

@test "usage 1 ya es baseline usage (frontera con 0)" {
  out=$(_m --surface '[{"tokens":100}]' --usage 1)
  [ "$(echo "$out" | _j "['baseline']['kind']")" = "usage" ]
  [ "$(echo "$out" | _j "['surface_delta_tokens']")" = "99" ]
  [ "$(echo "$out" | _j "['total_tokens']")" = "100" ]
}

@test "usage negativo no altera el delta: igual a la superficie" {
  out=$(_m --surface '[{"tokens":100}]' --usage -5)
  [ "$(echo "$out" | _j "['surface_delta_tokens']")" = "100" ]
  [ "$(echo "$out" | _j "['baseline']['anchor_tokens']")" = "-5" ]
}

@test "--emit: el evento lleva la sesión medida, no el id de --emit" {
  cat > "$TMPD/emit.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$EMIT_LOG"
SH
  EMIT_LOG="$TMPD/emit2.log" run python3 "$METER" --session medida --surface '[{"tokens":1}]' --emit otro-id --emit-script "$TMPD/emit.sh"
  grep -qx "session=medida" "$TMPD/emit2.log"
  if grep -q "otro-id" "$TMPD/emit2.log"; then return 1; fi
}
