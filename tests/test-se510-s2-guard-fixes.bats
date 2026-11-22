#!/usr/bin/env bats

# Ref: docs/specs/SE-510-guardas-sin-bloqueos-falsos-despachador.spec.md (S2: AC-4, AC-7, AC-10)
# Parte de S2 que no depende de deducir el directorio de `gh pr create`: paridad de
# veredictos bash/TS, registro de bloqueos con redacción, plantilla del resumen. El arreglo
# del gate (F3) queda fuera: con los hooks de main, F3 sigue siendo el único bloqueo falso
# (lo fija tests/test-se510-guard-allow-corpus.bats) y aquí se comprueba que no tapa la paridad.
setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  export S2_OUT="$BATS_FILE_TMPDIR/s2" MUT_OUT="$BATS_FILE_TMPDIR/mut"
  local rc=0
  python3 scripts/ablation_kernel.py guard-corpus --ts --out "$S2_OUT" >"$BATS_FILE_TMPDIR/s2.log" 2>&1 || rc=$?
  echo "$rc" >"$BATS_FILE_TMPDIR/s2.rc"
  # Mutante: los guards TS sin validateBashGlobal (el hueco previo a S2) → la paridad tiene que fallar.
  cat >"$BATS_FILE_TMPDIR/mutant.ts" <<EOF
import { BEFORE_GUARDS as G } from "$PWD/.opencode/plugins/lib/before-guards.ts";
export const BEFORE_GUARDS = G.filter((g: any) => g.name !== "validateBashGlobal");
EOF
  rc=0
  python3 scripts/ablation_kernel.py guard-corpus --ts --ts-entry "$BATS_FILE_TMPDIR/mutant.ts" \
    --out "$MUT_OUT" >"$BATS_FILE_TMPDIR/mut.log" 2>&1 || rc=$?
  echo "$rc" >"$BATS_FILE_TMPDIR/mut.rc"
}

absent() {
  run grep -q -- "$1" "$2"
  [ "$status" -eq 1 ]
}

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  TMP=$(mktemp -d)
  export SAVIA_GUARD_BLOCKS_LOG="$TMP/blocks.jsonl" SAVIA_GUARD_BLOCKS_KEY="$TMP/key"
  unset SAVIA_GUARD_LOG_INPUT
}

teardown() {
  rm -rf "$TMP"
}

receipt() {
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1]+"/se510-guard-corpus-receipt.json")); print(eval(sys.argv[2]))' "$1" "$2"
}

# ── AC-2 / AC-7: corpus en bash y TS ──────────────────────────────────────────
@test "SE-510 AC-2/AC-7: TS sin bloqueos falsos; en bash solo F3 (el gate de main, fuera de esta PR)" {
  [ "$(cat "$BATS_FILE_TMPDIR/s2.rc")" -eq 1 ]
  [ "$(receipt "$S2_OUT" 'r["decision"], r["false_block_rate"], r["false_blocks"], r["ts_false_blocks"]')" = "('FALSE_BLOCK', '1/4', ['F3'], [])" ]
  [ "$(receipt "$S2_OUT" '[c["id"] for c in r["cases"] if c["expected"]=="ALLOW" and c["ts"]["observed"]!="ALLOW"]')" = "[]" ]
}

@test "SE-510 AC-7: cada caso de los dos motores da el mismo veredicto" {
  [ "$(receipt "$S2_OUT" 'r["ts_compared"], r["parity_mismatches"]')" = "(True, [])" ]
  [ "$(receipt "$S2_OUT" 'sorted({c["ts"]["parity"] for c in r["cases"]})')" = "['MATCH']" ]
  # Los pares peligrosos siguen bloqueados en los dos motores donde hay guard TS.
  [ "$(receipt "$S2_OUT" '[c["ts"]["observed"] for c in r["cases"] if c["id"] in ("B1","B1b","B2","B5")]')" = "['BLOCK', 'BLOCK', 'BLOCK', 'BLOCK']" ]
}

@test "SE-510 AC-7: el recibo declara los límites de la paridad" {
  [ "$(receipt "$S2_OUT" '[l for l in r["limitations"] if l.startswith(("PARITY_", "NOT_EXPOSED_"))]')" = "['PARITY_COMPARES_DECISION_NOT_GUARD', 'NOT_EXPOSED_HOOKS_RELY_ON_SAVIA_GATES_BRIDGE', 'PARITY_CORPUS_SMALL_N=10']" ]
}

@test "SE-510 AC-3/AC-10: B3 y B4 siguen en BLOCK en bash" {
  [ "$(receipt "$S2_OUT" '[c["verdict"] for c in r["cases"] if c["id"] in ("B3","B4")]')" = "['MATCH', 'MATCH']" ]
  # Los bloquea pr-summary-gate. Con el gate de main, B4 cae por el resumen del proyecto (el
  # fallo F3), no por el encabezado: el motivo exacto queda para la PR del gate.
  [ "$(receipt "$S2_OUT" '[[b["hook"] for b in c["blocked_by"]] for c in r["cases"] if c["id"] in ("B3","B4")]')" = "[['pr-summary-gate.sh'], ['pr-summary-gate.sh']]" ]
}

@test "SE-510 AC-7 negativo: un guard TS desviado hace fallar la paridad (exit 4) aunque haya un bloqueo falso" {
  # Con F3 en FALSE_BLOCK, la divergencia tiene que ganar: antes salía exit 1 y la tapaba.
  [ "$(cat "$BATS_FILE_TMPDIR/mut.rc")" -eq 4 ]
  grep -q "PARITY_MISMATCH" "$BATS_FILE_TMPDIR/mut.log"
  [ "$(receipt "$MUT_OUT" 'sorted(r["parity_mismatches"])')" = "['B1:PARITY_MISMATCH', 'B1b:PARITY_MISMATCH']" ]
}

@test "SE-510 AC-7 negativo: un hook bloqueante sin clasificar en la paridad no da MATCH" {
  run python3 -c 'import sys; sys.path.insert(0,"scripts"); import ablation_kernel as k
p={"ported":{"block-force-push":"blockForcePush"},"not_exposed":{}}
c={"blocked_by":[{"hook":"hook-nuevo.sh"}]}
print(k.parity_of(c,{"decision":"BLOCK"},p))
print(k.parity_of({"blocked_by":[{"hook":"block-force-push.sh"}]},{"decision":"ALLOW"},p))'
  [ "${lines[0]}" = "('UNKNOWN', 'PARITY_UNCLASSIFIED:hook-nuevo')" ]
  [ "${lines[1]}" = "('BLOCK', 'PARITY_MISMATCH')" ]
}

@test "SE-510 AC-7: el fichero de paridad sin motivo o con un hook en las dos listas no valida" {
  run python3 - "$TMP" <<'EOF'
import json, sys
sys.path.insert(0, "scripts")
import ablation_kernel as k
from pathlib import Path
for name, doc in [("vacio", {"ported": {}, "not_exposed": {}}),
                  ("doble", {"ported": {"a": "A"}, "not_exposed": {"a": "motivo suficiente"}}),
                  ("corto", {"ported": {"a": "A"}, "not_exposed": {"b": "x"}})]:
    p = Path(sys.argv[1]) / f"{name}.json"
    p.write_text(json.dumps(doc))
    try:
        k.load_parity(p); print(name, "OK")
    except k.InventoryError as e:
        print(name, e.code)
print("real", sorted(k.load_parity(Path(k.PARITY_PATH))["not_exposed"]))
EOF
  [ "$status" -eq 0 ]
  [ "$output" = $'vacio PARITY_SCHEMA\ndoble PARITY_SCHEMA\ncorto PARITY_SCHEMA\nreal [\'pr-summary-gate\']' ]
}

# ── Resolvedor común de destino (scripts/lib/git_op_targets.py) ──────────────
@test "SE-510 AC-7 (Codex a67920f): el resolvedor común ve git add partido por continuaciones de línea" {
  run bash -c "printf '%s' \"\$1\" | python3 scripts/lib/git_op_targets.py '$TMP'" _ $'gi\\\nt -C "$X" ad\\\nd -A'
  [ "$status" -eq 0 ]
  [ "$output" = $'add\t' ]
  # Negativo: sin git ni add tras unir las líneas no se emite nada.
  run bash -c "printf '%s' \"\$1\" | python3 scripts/lib/git_op_targets.py '$TMP'" _ $'ec\\\nho hola'
  [ -z "$output" ]
}

# ── AC-10: plantilla y aviso del encabezado ──────────────────────────────────
@test "SE-510 AC-10: pr-plan sin resumen imprime el encabezado literal y la plantilla" {
  run bash -c "ROOT='$TMP' && source scripts/pr-plan-gates.sh && g_summary"
  [[ "$output" == *"FAIL: missing .pr-summary.md"* ]]
  [[ "$output" == *"## Qué hace este PR (en lenguaje no técnico)"* ]]
  [[ "$output" == *"docs/templates/pr-summary.md"* ]]
  grep -qx '## Qué hace este PR (en lenguaje no técnico)' docs/templates/pr-summary.md
}

@test "SE-510 AC-10 negativo: con resumen válido pr-plan no imprime la plantilla" {
  { echo '## Qué hace este PR (en lenguaje no técnico)'; printf 'Texto llano de prueba. %.0s' $(seq 1 20); echo; } >"$TMP/.pr-summary.md"
  run bash -c "ROOT='$TMP' && source scripts/pr-plan-gates.sh && g_summary"
  [[ "$output" != *"FAIL"* ]]
  [[ "$output" != *"docs/templates/pr-summary.md"* ]]
}

# ── AC-4: registro de bloqueos ───────────────────────────────────────────────
hook2() { printf '#!/usr/bin/env bash\ncat >/dev/null\necho "BLOQUEADO: motivo de prueba" >&2\nexit %s\n' "$1" >"$TMP/h$1.sh"; }

@test "SE-510 AC-4: un exit 2 envuelto deja una línea sin la orden en claro" {
  hook2 2
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git push --force ghp_abcdefghijklmnopqrstuvwxyz0123\"}}' | bash scripts/guard-blocks.sh wrap --guard prueba -- bash '$TMP/h2.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO: motivo de prueba"* ]]
  [ "$(wc -l <"$SAVIA_GUARD_BLOCKS_LOG")" -eq 1 ]
  absent "ghp_" "$SAVIA_GUARD_BLOCKS_LOG"
  absent "git push" "$SAVIA_GUARD_BLOCKS_LOG"
  run python3 -c 'import json,os; r=json.loads(open(os.environ["SAVIA_GUARD_BLOCKS_LOG"]).read())
print(r["guard"], r["reason"], r["hmac"], len(r["cmd_hmac"]), "input" in r)'
  [ "$output" = "prueba BLOQUEADO: motivo de prueba ok 64 False" ]
  [ "$(stat -c %a "$SAVIA_GUARD_BLOCKS_KEY")" = "600" ]
}

@test "SE-510 AC-4 negativo: exit 0 y exit 1 no se registran y el código pasa tal cual" {
  hook2 0 && hook2 1
  run bash -c "echo '{}' | bash scripts/guard-blocks.sh wrap --guard p -- bash '$TMP/h0.sh'"
  [ "$status" -eq 0 ]
  run bash -c "echo '{}' | bash scripts/guard-blocks.sh wrap --guard p -- bash '$TMP/h1.sh'"
  [ "$status" -eq 1 ]
  [ ! -e "$SAVIA_GUARD_BLOCKS_LOG" ]
}

@test "SE-510 AC-4: con opt-in la orden se guarda redactada" {
  hook2 2
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"curl -H \\\"Authorization: Bearer abc123\\\" x ghp_abcdefghijklmnopqrstuvwxyz0123\"}}' | SAVIA_GUARD_LOG_INPUT=1 bash scripts/guard-blocks.sh wrap --guard p -- bash '$TMP/h2.sh'"
  [ "$status" -eq 2 ]
  grep -q '"input"' "$SAVIA_GUARD_BLOCKS_LOG"
  grep -q 'REDACTED' "$SAVIA_GUARD_BLOCKS_LOG"
  absent 'abc123' "$SAVIA_GUARD_BLOCKS_LOG"
  absent 'ghp_abcdef' "$SAVIA_GUARD_BLOCKS_LOG"
}

@test "SE-510 AC-4: el motivo del hook se guarda redactado y el log nace 0600" {
  printf '#!/usr/bin/env bash\ncat >/dev/null\necho "BLOQUEADO: token ghp_abcdefghijklmnopqrstuvwxyz0123 en /ruta/x" >&2\nexit 2\n' >"$TMP/hr.sh"
  run bash -c "umask 022; echo '{}' | bash scripts/guard-blocks.sh wrap --guard p -- bash '$TMP/hr.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ghp_abcdef"* ]]  # el hook habla tal cual; solo el registro se redacta
  absent 'ghp_abcdef' "$SAVIA_GUARD_BLOCKS_LOG"
  grep -q 'REDACTED' "$SAVIA_GUARD_BLOCKS_LOG"
  [ "$(stat -c %a "$SAVIA_GUARD_BLOCKS_LOG")" = "600" ]
}

@test "SE-510 AC-4 (seguridad a15100d P2-3): wrap pasa el motivo por el entorno, no por argv" {
  printf '#!/usr/bin/env bash\ncat >/dev/null\necho "BLOQUEADO: fragmento MOTIVOSECRETO" >&2\nexit 2\n' >"$TMP/hm.sh"
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/argv"\nprintf "%%s" "$SAVIA_GUARD_BLOCK_REASON" >"%s/env"\n' "$TMP" "$TMP" >"$TMP/bin/python3"
  chmod +x "$TMP/bin/python3"
  run bash -c "echo '{}' | PATH='$TMP/bin':\"\$PATH\" bash scripts/guard-blocks.sh wrap --guard p -- bash '$TMP/hm.sh'"
  [ "$status" -eq 2 ]
  absent 'MOTIVOSECRETO' "$TMP/argv"
  grep -q 'MOTIVOSECRETO' "$TMP/env"
  # Y el registrador real toma el motivo del entorno (redactado igual que antes).
  run bash -c "echo '{}' | bash scripts/guard-blocks.sh wrap --guard p -- bash '$TMP/hm.sh'"
  grep -q 'MOTIVOSECRETO' "$SAVIA_GUARD_BLOCKS_LOG"
}

@test "SE-510 AC-4: wrap entrega al hook los mismos bytes y no cambia su código con entradas grandes" {
  printf '#!/usr/bin/env bash\ncat >"%s"\nexit 0\n' "$TMP/got" >"$TMP/copy.sh"
  printf '{"tool_input":{"command":"ls"}}\n\n' >"$TMP/in"
  run bash -c "bash scripts/guard-blocks.sh wrap --guard p -- bash '$TMP/copy.sh' <'$TMP/in'"
  [ "$status" -eq 0 ]
  cmp "$TMP/in" "$TMP/got"
  # Hook que sale 0 sin leer stdin con una entrada mayor que el buffer del pipe.
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/noread.sh"
  head -c 300000 /dev/zero | tr '\0' 'a' >"$TMP/big"
  run bash -c "bash scripts/guard-blocks.sh wrap --guard p -- bash '$TMP/noread.sh' <'$TMP/big'"
  [ "$status" -eq 0 ]
}

@test "SE-510 AC-4: clave con permisos abiertos → cmd_hmac vacío, nunca un hash sin clave" {
  printf '%064d' 0 >"$SAVIA_GUARD_BLOCKS_KEY" && chmod 644 "$SAVIA_GUARD_BLOCKS_KEY"
  run bash -c "echo 'git push --force' | bash scripts/guard-blocks.sh record --guard p --reason r"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,os; r=json.loads(open(os.environ["SAVIA_GUARD_BLOCKS_LOG"]).read()); print(repr(r["cmd_hmac"]), r["hmac"])'
  [ "$output" = "'' no-key" ]
}

@test "SE-510 AC-4 negativo (seguridad P2): clave que es un enlace simbólico → cmd_hmac vacío" {
  printf '%064d' 0 >"$TMP/clave-real" && chmod 600 "$TMP/clave-real"
  ln -s "$TMP/clave-real" "$SAVIA_GUARD_BLOCKS_KEY"
  run bash -c "echo 'git push --force' | bash scripts/guard-blocks.sh record --guard p --reason r"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,os; r=json.loads(open(os.environ["SAVIA_GUARD_BLOCKS_LOG"]).read()); print(repr(r["cmd_hmac"]), r["hmac"])'
  [ "$output" = "'' no-key" ]
  # Negativo: la misma clave como fichero normal 0600 sí firma.
  rm "$SAVIA_GUARD_BLOCKS_KEY" "$SAVIA_GUARD_BLOCKS_LOG" && cp -p "$TMP/clave-real" "$SAVIA_GUARD_BLOCKS_KEY"
  echo 'git push --force' | bash scripts/guard-blocks.sh record --guard p --reason r >/dev/null
  run python3 -c 'import json,os; r=json.loads(open(os.environ["SAVIA_GUARD_BLOCKS_LOG"]).read()); print(len(r["cmd_hmac"]), r["hmac"])'
  [ "${output%% *}" = "64" ]
}

@test "SE-510 AC-4: report sin etiquetas da UNKNOWN; con una FP y una TP da 50.0%" {
  run bash scripts/guard-blocks.sh report --json
  [ "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["total"]["fp_rate"])' "$output")" = "UNKNOWN" ]
  a=$(echo x | bash scripts/guard-blocks.sh record --guard g1 --reason r)
  b=$(echo y | bash scripts/guard-blocks.sh record --guard g1 --reason r)
  run bash scripts/guard-blocks.sh report --json
  [ "$(python3 -c 'import json,sys; d=json.loads(sys.argv[1])["guards"]["g1"]; print(d["blocks"], d["fp_rate"], d["unlabeled"])' "$output")" = "2 UNKNOWN 2" ]
  bash scripts/guard-blocks.sh mark "$a" false-positive
  bash scripts/guard-blocks.sh mark "$b" true-positive
  run bash scripts/guard-blocks.sh report --json
  [ "$(python3 -c 'import json,sys; d=json.loads(sys.argv[1])["guards"]["g1"]; print(d["labeled"], d["fp"], d["fp_rate"], d["unlabeled"])' "$output")" = "2 1 50.0% 0" ]
  run bash scripts/guard-blocks.sh report
  [[ "$output" == *"g1"*"50.0%"* ]]
}

@test "SE-510 AC-4 negativo: mark con id inexistente, id mal formado o etiqueta rara falla" {
  echo x | bash scripts/guard-blocks.sh record --guard g --reason r >/dev/null
  run bash scripts/guard-blocks.sh mark 000000000000 false-positive
  [ "$status" -eq 1 ]
  run bash scripts/guard-blocks.sh mark zz false-positive
  [ "$status" -eq 2 ]
  run bash scripts/guard-blocks.sh mark 000000000000 quizas
  [ "$status" -eq 2 ]
  run bash scripts/guard-blocks.sh report --since ayer
  [ "$status" -eq 2 ]
}

@test "SE-510 AC-4 negativo: wrap sin guarda o sin orden no ejecuta nada y sale 2" {
  run bash scripts/guard-blocks.sh wrap -- true
  [ "$status" -eq 2 ]
  run bash scripts/guard-blocks.sh wrap --guard g
  [ "$status" -eq 2 ]
  [ ! -e "$SAVIA_GUARD_BLOCKS_LOG" ]
}

@test "SE-510 AC-4 negativo: opción de wrap sin valor sale 2 en vez de quedarse en bucle" {
  for opt in --guard --event --tool; do
    run timeout 5 bash scripts/guard-blocks.sh wrap $opt
    [ "$status" -eq 2 ] || { echo "$opt: status $status"; false; }
    [[ "$output" == *"sin valor"* ]]
  done
  run timeout 5 bash scripts/guard-blocks.sh wrap --guard g --event
  [ "$status" -eq 2 ]
}

@test "SE-510 AC-4: un motivo que empieza por guion se registra (no lo toma argparse por opción)" {
  printf '#!/bin/bash\necho "-motivo" >&2\nexit 2\n' >"$TMP/hg.sh"
  run bash -c "printf '{}' | bash scripts/guard-blocks.sh wrap --guard prueba -- bash '$TMP/hg.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" != *"AVISO"* ]]
  [ "$(wc -l <"$SAVIA_GUARD_BLOCKS_LOG")" -eq 1 ]
}

@test "SE-510 AC-4 negativo: el log no se escribe a través de un enlace simbólico" {
  : >"$TMP/destino"
  ln -s "$TMP/destino" "$TMP/enlace.jsonl"
  SAVIA_GUARD_BLOCKS_LOG="$TMP/enlace.jsonl" run python3 scripts/guard_blocks.py record --guard g --event PreToolUse --tool Bash --engine bash --reason x </dev/null
  [ "$status" -ne 0 ]
  [ ! -s "$TMP/destino" ]
}

# ── Revisión de c9eaee1 (Codex P1 ×3, correctness/seguridad P2) ─────────────
@test "SE-510 AC-4 negativo (Codex c9eaee1 P1-2): si wrap no puede copiar stdin, sale 2 sin ejecutar el hook" {
  printf '#!/usr/bin/env bash\ntouch "%s/ran"\nexit 0\n' "$TMP" >"$TMP/allow.sh"
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"x\"}}' | (ulimit -f 0; bash scripts/guard-blocks.sh wrap --guard g -- bash '$TMP/allow.sh')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se pudo copiar la entrada"* ]]
  [ ! -e "$TMP/ran" ]
  # Negativo: con la copia sana el hook corre y su 0 pasa tal cual.
  run bash -c "printf '%s' '{}' | bash scripts/guard-blocks.sh wrap --guard g -- bash '$TMP/allow.sh'"
  [ "$status" -eq 0 ]
  [ -e "$TMP/ran" ]
}

@test "SE-510 AC-4 (Codex c9eaee1 P1-3): la redacción tapa la palabra de shell entera, no su primer trozo" {
  # Muestras armadas en tiempo de ejecución (el guard de credenciales mira el texto de las órdenes).
  run python3 -c '
import sys; sys.path.insert(0, "scripts"); import guard_blocks as g
o = "-" + "p"; s = "abcdefghijk"
cases = [f"docker login {o} \"\"{s}", f"x {o} a\"b {s}\"d", "x --pass" + f"word=\"\"{s}",
         "x pass" + f"word=q\"{s}", f"x {o} ab\\ {s}", f"x {o} \"{s}"]
for c in cases:
    r = g.redact(c)
    print("FUGA" if s in r or "REDACTED" not in r else "ok", repr(r))
# Negativo: lo que no es credencial queda intacto.
print(g.redact("git status && echo hola"))'
  echo "$output"
  [[ "$output" != *FUGA* ]]
  [ "$(grep -c '^ok' <<<"$output")" -eq 6 ]
  [[ "$output" == *$'\n'"git status && echo hola" ]]
}

@test "SE-510 AC-4 (seguridad c9eaee1 P2-2): un log previo con 0644 queda en 0600 al registrar" {
  : >"$SAVIA_GUARD_BLOCKS_LOG" && chmod 644 "$SAVIA_GUARD_BLOCKS_LOG"
  run python3 scripts/guard_blocks.py record --guard g --event PreToolUse --tool Bash --engine bash --reason x </dev/null
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$SAVIA_GUARD_BLOCKS_LOG")" = "600" ]
  [ "$(wc -l <"$SAVIA_GUARD_BLOCKS_LOG")" -eq 1 ]
}

# ── Revisión de 2021f79 (correctness P1-1/P2-2/P2-3, seguridad P2-1, Codex) ──
@test "SE-510 AC-4 (Codex/correctness 2021f79): la redacción cruza continuaciones y comillas multilínea" {
  run python3 -c '
import sys; sys.path.insert(0, "scripts"); import guard_blocks as g
o = "-" + "p"; s = "defghijkl"
cases = ["x pass" + f"word=abc\\\n{s} && ls", f"x {o} \"abc\n{s}\"", f"x {o} \"abc\n{s}"]
for c in cases:
    r = g.redact(c)
    print("FUGA" if s in r or "REDACTED" not in r else "ok", repr(r))
print(g.redact("echo a\\\nb"))'
  echo "$output"
  [[ "$output" != *FUGA* ]]
  [ "$(grep -c '^ok' <<<"$output")" -eq 3 ]
  [[ "$output" == *$'\n'"echo a\\"$'\n'"b" ]]
}
