#!/usr/bin/env bats

# Ref: docs/specs/SE-510-guardas-sin-bloqueos-falsos-despachador.spec.md (S2: AC-2, AC-4, AC-7, AC-10)
# El hook pr-summary-gate.sh arreglado aún no está colocado en .claude/hooks (lo coloca la
# operadora): se prueba desde tests/fixtures/se510-s2/hooks con --overlay-hooks. Al colocarlo,
# el test de S1 «F3 es el único bloqueo falso» falla a propósito y pasa a «0 falsos».
# La comparación «antes/después» usa una copia fija del gate previo
# (tests/fixtures/se510-s2/hooks-pre), no la ruta viva: colocar el arreglo no la invierte.
setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  export S2_OUT="$BATS_FILE_TMPDIR/s2" MUT_OUT="$BATS_FILE_TMPDIR/mut"
  local rc=0
  python3 scripts/ablation_kernel.py guard-corpus --overlay-hooks tests/fixtures/se510-s2/hooks --ts \
    --out "$S2_OUT" >"$BATS_FILE_TMPDIR/s2.log" 2>&1 || rc=$?
  echo "$rc" >"$BATS_FILE_TMPDIR/s2.rc"
  # Mutante: los guards TS sin validateBashGlobal (el hueco previo a S2) → la paridad tiene que fallar.
  cat >"$BATS_FILE_TMPDIR/mutant.ts" <<EOF
import { BEFORE_GUARDS as G } from "$PWD/.opencode/plugins/lib/before-guards.ts";
export const BEFORE_GUARDS = G.filter((g: any) => g.name !== "validateBashGlobal");
EOF
  rc=0
  python3 scripts/ablation_kernel.py guard-corpus --overlay-hooks tests/fixtures/se510-s2/hooks --ts \
    --ts-entry "$BATS_FILE_TMPDIR/mutant.ts" --out "$MUT_OUT" >"$BATS_FILE_TMPDIR/mut.log" 2>&1 || rc=$?
  echo "$rc" >"$BATS_FILE_TMPDIR/mut.rc"
  # Espacio con la forma de .claude/hooks para ejecutar el gate arreglado (resuelve ../../scripts).
  export FIXED_WS="$BATS_FILE_TMPDIR/ws"
  mkdir -p "$FIXED_WS/.claude/hooks"
  cp -r .claude/hooks/lib "$FIXED_WS/.claude/hooks/lib"
  cp tests/fixtures/se510-s2/hooks/pr-summary-gate.sh "$FIXED_WS/.claude/hooks/"
  ln -s "$PWD/scripts" "$FIXED_WS/scripts"
  export FIXED_GATE="$FIXED_WS/.claude/hooks/pr-summary-gate.sh"
  export PRE_WS="$BATS_FILE_TMPDIR/ws-pre"
  mkdir -p "$PRE_WS/.claude/hooks"
  cp -r .claude/hooks/lib "$PRE_WS/.claude/hooks/lib"
  cp tests/fixtures/se510-s2/hooks-pre/pr-summary-gate.sh "$PRE_WS/.claude/hooks/"
  ln -s "$PWD/scripts" "$PRE_WS/scripts"
  export PRE_GATE="$PRE_WS/.claude/hooks/pr-summary-gate.sh"
}

# absent <patrón> <fichero>: el patrón no aparece (falla si aparece o si grep da error).
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
@test "SE-510 AC-2: con el gate arreglado, 0 bloqueos falsos en bash y en TS" {
  [ "$(cat "$BATS_FILE_TMPDIR/s2.rc")" -eq 0 ]
  [ "$(receipt "$S2_OUT" 'r["decision"], r["false_block_rate"], r["ts_false_blocks"]')" = "('PASS', '0/4', [])" ]
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

@test "SE-510 AC-3/AC-10: B3 y B4 siguen en BLOCK con el gate arreglado" {
  [ "$(receipt "$S2_OUT" '[c["verdict"] for c in r["cases"] if c["id"] in ("B3","B4")]')" = "['MATCH', 'MATCH']" ]
  grep -q "heading obligatorio" "$S2_OUT/se510-guard-corpus-receipt.json"
}

@test "SE-510 AC-7 negativo: un guard TS desviado hace fallar la paridad (exit 4)" {
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

# ── F3: árbol donde corre gh ─────────────────────────────────────────────────
@test "SE-510 F3: el resolvedor usa el cwd de la entrada y un cd literal" {
  git init -q "$TMP/wt" && mkdir -p "$TMP/wt/sub" "$TMP/otro"
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"},\"cwd\":\"$TMP/wt/sub\"}' | python3 scripts/lib/pr_summary_root.py '$TMP/otro'"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$TMP/wt" rev-parse --show-toplevel)" ]
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"cd $TMP/wt && gh pr create --draft\"},\"cwd\":\"$TMP/otro\"}' | python3 scripts/lib/pr_summary_root.py /"
  [ "$output" = "$(git -C "$TMP/wt" rev-parse --show-toplevel)" ]
  # Sin cwd: la raíz de respaldo (comportamiento anterior).
  run bash -c "printf 'gh pr create' | python3 scripts/lib/pr_summary_root.py '$TMP/otro'"
  [ "$output" = "$TMP/otro" ]
}

@test "SE-510 F3 negativo: varios cd, cd en subshell cerrado, pushd o env -C → exit 2" {
  for cmd in "cd $TMP && cd sub && gh pr create" "(cd $TMP); gh pr create --draft" \
             "pushd $TMP && gh pr create" "env -C $TMP gh pr create" "env --chdir=$TMP gh pr create" \
             "cd -P $TMP && gh pr create"; do
    run bash -c "jq -nc --arg c '$cmd' --arg d '$TMP' '{tool_input:{command:\$c},cwd:\$d}' | python3 scripts/lib/pr_summary_root.py /"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOQUEADO [pr-summary-gate]"* ]]
  done
}

@test "SE-510 F3: cd dentro del mismo subshell que gh, gh sin argumentos y env sin -C se resuelven" {
  git init -q "$TMP/wt" && mkdir -p "$TMP/otro"
  top=$(git -C "$TMP/wt" rev-parse --show-toplevel)
  run bash -c "jq -nc --arg c '(cd $TMP/wt; gh pr create)' --arg d '$TMP/otro' '{tool_input:{command:\$c},cwd:\$d}' | python3 scripts/lib/pr_summary_root.py /"
  [ "$status" -eq 0 ]
  [ "$output" = "$top" ]
  run bash -c "jq -nc --arg c 'cd $TMP/wt && (gh pr create)' --arg d '$TMP/otro' '{tool_input:{command:\$c},cwd:\$d}' | python3 scripts/lib/pr_summary_root.py /"
  [ "$output" = "$top" ]
  run bash -c "jq -nc --arg c 'env GH_PAGER=cat gh pr create' --arg d '$TMP/wt' '{tool_input:{command:\$c},cwd:\$d}' | python3 scripts/lib/pr_summary_root.py /"
  [ "$status" -eq 0 ]
  [ "$output" = "$top" ]
}

@test "SE-510 F3 negativo: cd no resoluble, directorio inexistente o JSON roto → exit 2" {
  for cmd in 'cd $HOME/x && gh pr create' 'cd $(pwd) && gh pr create' 'cd && gh pr create' 'cd - && gh pr create'; do
    run bash -c "jq -nc --arg c '$cmd' --arg d '$TMP' '{tool_input:{command:\$c},cwd:\$d}' | python3 scripts/lib/pr_summary_root.py /"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOQUEADO [pr-summary-gate]"* ]]
  done
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"gh pr create\"},\"cwd\":\"$TMP/no-existe\"}' | python3 scripts/lib/pr_summary_root.py /"
  [ "$status" -eq 2 ]
  run bash -c "printf '{\"tool_input\":' | python3 scripts/lib/pr_summary_root.py /"
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformada"* ]]
}

@test "SE-510 F3 negativo (revisión Codex/seguridad): cd fuera de la primera posición → exit 2" {
  # Cada una resolvía mal antes: otro árbol (builtin cd, echo previo) o el inverso (|| , pipe),
  # o un cd tras salto de línea, comilla, llave, if o bash -c que el analizador no veía.
  cmds=("builtin cd $TMP && gh pr create" "echo gh pr create; cd $TMP && gh pr create"
        "true || cd $TMP; gh pr create" "cd $TMP | cat; gh pr create"
        $'true\ncd '"$TMP"$'\ngh pr create' "bash -c 'cd $TMP && gh pr create'"
        "{ cd $TMP; gh pr create; }" "if cd $TMP; then gh pr create; fi" "command cd $TMP && gh pr create")
  for cmd in "${cmds[@]}"; do
    run bash -c "jq -nc --arg c \"\$1\" --arg d '$TMP' '{tool_input:{command:\$c},cwd:\$d}' | python3 scripts/lib/pr_summary_root.py /" _ "$cmd"
    [ "$status" -eq 2 ] || { echo "no bloqueó: $cmd"; false; }
  done
}

@test "SE-510 F3: un cd inicial literal con gh mencionado antes en texto sigue resolviendo el árbol del cd" {
  git init -q "$TMP/wt" && mkdir -p "$TMP/otro"
  top=$(git -C "$TMP/wt" rev-parse --show-toplevel)
  run bash -c "jq -nc --arg c 'cd $TMP/wt && gh pr create --body \"ver gh pr create\"' --arg d '$TMP/otro' '{tool_input:{command:\$c},cwd:\$d}' | python3 scripts/lib/pr_summary_root.py /"
  [ "$status" -eq 0 ]
  [ "$output" = "$top" ]
}

# summary <dir> <horas de antigüedad> — .pr-summary.md válido de más de 300 caracteres
summary() {
  { echo '## Qué hace este PR (en lenguaje no técnico)'; printf 'Texto llano de prueba. %.0s' $(seq 1 20); echo; } >"$1/.pr-summary.md"
  touch -d "-$2 hours" "$1/.pr-summary.md"
}

gate() {  # gate <hook> <cwd> <proyecto>
  jq -nc --arg d "$2" '{tool_input:{command:"gh pr create --draft --title t --body-file b.md"},cwd:$d}' \
    | CLAUDE_PROJECT_DIR="$3" ANTHROPIC_BASE_URL=http://127.0.0.1:9 ANTHROPIC_API_KEY=probe bash "$1"
}

@test "SE-510 F3 negativo: resumen viejo en el worktree bloquea aunque el del proyecto sea fresco" {
  git init -q "$TMP/wt" && git init -q "$TMP/proj"
  summary "$TMP/wt" 97 && summary "$TMP/proj" 0
  run gate "$FIXED_GATE" "$TMP/wt" "$TMP/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"97h"* ]]
  # El gate previo (sin el arreglo) mira el del proyecto y deja pasar: este test lo distingue.
  run gate "$PRE_GATE" "$TMP/wt" "$TMP/proj"
  [ "$status" -eq 0 ]
}

@test "SE-510 F3: resumen fresco en el worktree pasa aunque el del proyecto sea viejo" {
  git init -q "$TMP/wt" && git init -q "$TMP/proj"
  summary "$TMP/wt" 0 && summary "$TMP/proj" 97
  run gate "$FIXED_GATE" "$TMP/wt" "$TMP/proj"
  [ "$status" -eq 0 ]
  run gate "$PRE_GATE" "$TMP/wt" "$TMP/proj"
  [ "$status" -eq 2 ]
}

# ── AC-10: plantilla y aviso del encabezado ──────────────────────────────────
@test "SE-510 AC-10: pr-plan sin resumen imprime el encabezado literal y la plantilla" {
  run bash -c "ROOT='$TMP' && source scripts/pr-plan-gates.sh && g_summary"
  [[ "$output" == *"FAIL: missing .pr-summary.md"* ]]
  [[ "$output" == *"## Qué hace este PR (en lenguaje no técnico)"* ]]
  [[ "$output" == *"docs/templates/pr-summary.md"* ]]
}

@test "SE-510 AC-10: la plantilla lleva el encabezado exigido y el gate sin resumen lo enseña" {
  grep -qx '## Qué hace este PR (en lenguaje no técnico)' docs/templates/pr-summary.md
  git init -q "$TMP/wt"
  run gate "$FIXED_GATE" "$TMP/wt" "$TMP/wt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"## Qué hace este PR (en lenguaje no técnico)"* ]]
  [[ "$output" == *"docs/templates/pr-summary.md"* ]]
}

@test "SE-510 AC-10 negativo: resumen fresco sin el encabezado sigue bloqueado (B4)" {
  git init -q "$TMP/wt"
  printf 'Texto sin encabezado. %.0s' $(seq 1 20) >"$TMP/wt/.pr-summary.md"
  run gate "$FIXED_GATE" "$TMP/wt" "$TMP/wt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"heading obligatorio"* ]]
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
