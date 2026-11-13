#!/usr/bin/env bats
# Tests de scripts/resolve-all-open-prs.sh --select-targets y de su uso en
# .github/workflows/auto-rebase-open-prs.yml.
#
# Regresión del 2026-11-11: tras cada push a main GitHub devuelve UNKNOWN para
# todas las PR y el workflow las trataba como rebasables → integraba main en
# todas las PR abiertas. Solo deben tocarse las PR con conflicto real.
# Safety: el script usa `set -uo pipefail`; gh simulado, sin red.
# Ref: .github/workflows/auto-rebase-open-prs.yml — runs 43082135464, 43086438753,
# 43090813976 y 43095072062 (2026-11-11): todas las PR en UNKNOWN/UNKNOWN y empujadas.

bats_require_minimum_version 1.5.0

SCRIPT="scripts/resolve-all-open-prs.sh"
WF=".github/workflows/auto-rebase-open-prs.yml"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/bin" "$T/state"
  export AUTO_REBASE_POLL_SECONDS=0 AUTO_REBASE_POLL_ROUNDS=3
  # gh simulado: `gh pr view <n> --json ... --jq ...` responde con
  # $T/state/<n> (una línea por ronda; la última se repite). Registra cada llamada.
  cat > "$T/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/gh.calls"
[[ "\$1 \$2" == "pr view" ]] || exit 1
n="\$3"; f="$T/state/\$n"
[[ -f "\$f" ]] || exit 1
c=\$(grep -c "^pr view \$n " "$T/gh.calls")
total=\$(wc -l < "\$f")
(( c > total )) && c=\$total
sed -n "\${c}p" "\$f"
EOF
  chmod +x "$T/bin/gh"
  export GH_BIN="$T/bin/gh"
  : > "$T/gh.calls"
}

teardown() { cd /; }

targets() { bash "$SCRIPT" --select-targets <<<"$1"; }

@test "script ejecutable y con set -uo pipefail" {
  [ -x "$SCRIPT" ]
  grep -qE '^set -uo pipefail' "$SCRIPT"
}

@test "select_targets/classify: CONFLICTING o DIRTY → objetivo; CLEAN y BLOCKED → no se tocan" {
  run --separate-stderr targets '[
    {"number":1,"headRefName":"a","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY"},
    {"number":2,"headRefName":"b","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"},
    {"number":3,"headRefName":"c","mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED"},
    {"number":4,"headRefName":"d","mergeable":"MERGEABLE","mergeStateStatus":"DIRTY"}]'
  [ "$status" -eq 0 ]
  [ "$output" = $'1 a\n4 d' ]
  [ ! -s "$T/gh.calls" ]   # nada UNKNOWN: no hace falta sondear
}

@test "regresión 11-11: todas UNKNOWN y GitHub resuelve a CLEAN → ninguna se toca" {
  printf 'MERGEABLE CLEAN\n' > "$T/state/10"
  printf 'MERGEABLE BLOCKED\n' > "$T/state/11"
  run --separate-stderr targets '[
    {"number":10,"headRefName":"x","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"},
    {"number":11,"headRefName":"y","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"}]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(grep -c '^pr view' "$T/gh.calls")" -eq 2 ]
}

@test "UNKNOWN que pasa a CONFLICTING en la segunda ronda → objetivo" {
  printf 'UNKNOWN UNKNOWN\nCONFLICTING DIRTY\n' > "$T/state/20"
  run --separate-stderr targets '[{"number":20,"headRefName":"z","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"}]'
  [ "$status" -eq 0 ]
  [ "$output" = "20 z" ]
  [ "$(grep -c '^pr view 20 ' "$T/gh.calls")" -eq 2 ]
}

@test "boundary: UNKNOWN persistente → no se toca y se sondea exactamente ROUNDS veces" {
  printf 'UNKNOWN UNKNOWN\n' > "$T/state/30"
  run --separate-stderr targets '[{"number":30,"headRefName":"w","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"}]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(grep -c '^pr view 30 ' "$T/gh.calls")" -eq 3 ]
  [[ "$stderr" == *"sin calcular tras 3 rondas"* ]]
}

@test "boundary zero: ROUNDS=0 → UNKNOWN no se sondea y no se toca" {
  printf 'CONFLICTING DIRTY\n' > "$T/state/31"
  AUTO_REBASE_POLL_ROUNDS=0 run --separate-stderr targets '[{"number":31,"headRefName":"v","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"}]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$T/gh.calls" ]
}

@test "fail: gh falla en todas las rondas → la PR no se toca" {
  # sin $T/state/40 el gh simulado sale con 1
  run --separate-stderr targets '[{"number":40,"headRefName":"u","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"}]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(grep -c '^pr view 40 ' "$T/gh.calls")" -eq 3 ]
}

@test "invalid: entrada no válida → exit 2 y ningún objetivo (fail-closed)" {
  for bad in 'no-json' '{"number":1}' '[{"number":"1;rm","headRefName":"a"}]'; do
    run --separate-stderr targets "$bad"
    [ "$status" -eq 2 ] || { echo "entrada aceptada: $bad"; false; }
    [ -z "$output" ]
  done
}

@test "error: AUTO_REBASE_POLL_ROUNDS no numérico → exit 2" {
  AUTO_REBASE_POLL_ROUNDS=abc run --separate-stderr targets '[]'
  [ "$status" -eq 2 ]
}

@test "empty: lista vacía → exit 0 sin objetivos" {
  run --separate-stderr targets '[]'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "null: mergeable/mergeStateStatus null o ausentes se tratan como UNKNOWN y se sondean" {
  printf 'CONFLICTING DIRTY\n' > "$T/state/60"
  printf 'MERGEABLE CLEAN\n' > "$T/state/61"
  run --separate-stderr targets '[
    {"number":60,"headRefName":"n1","mergeable":null,"mergeStateStatus":null},
    {"number":61,"headRefName":"n2"}]'
  [ "$status" -eq 0 ]
  [ "$output" = "60 n1" ]
  [ "$(grep -c '^pr view' "$T/gh.calls")" -eq 2 ]
}

@test "help: usage documenta el modo --select-targets" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--select-targets"* ]]
}

# ── El paso real del workflow, con git/gh/resolutor simulados ───────────────

wf_rebase_step() {  # ejecuta «Rebase each conflicting PR» del workflow real en un sandbox
  python3 -c 'import sys,yaml
w=yaml.safe_load(open(sys.argv[1]))
print(next(s["run"] for s in w["jobs"]["rebase"]["steps"] if s.get("name")=="Rebase each conflicting PR"))' "$WF" > "$T/step.sh"
  local sb="$T/sandbox"; mkdir -p "$sb/scripts"
  cp "$SCRIPT" "$sb/scripts/"
  : > "$sb/scripts/derived.sh"; : > "$sb/scripts/derived-paths.txt"
  printf '#!/usr/bin/env bash\necho "$2" >> "%s"\n' "$T/resolved" > "$sb/scripts/resolve-pr-conflicts.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/git"; chmod +x "$T/bin/git"
  : > "$T/resolved"
  (cd "$sb" && PATH="$T/bin:$PATH" PRS="$1" bash "$T/step.sh")
}

@test "workflow: todas UNKNOWN, solo una con conflicto real → el resolutor solo corre para esa" {
  printf 'MERGEABLE CLEAN\n' > "$T/state/50"
  printf 'CONFLICTING DIRTY\n' > "$T/state/51"
  printf 'MERGEABLE BLOCKED\n' > "$T/state/52"
  run wf_rebase_step '[
    {"number":50,"headRefName":"agent/a","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"},
    {"number":51,"headRefName":"agent/b","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"},
    {"number":52,"headRefName":"agent/c","mergeable":"UNKNOWN","mergeStateStatus":"UNKNOWN"}]'
  [ "$status" -eq 0 ]
  [ "$(cat "$T/resolved")" = "agent/b" ]
}

@test "workflow invalid: entrada no válida → el paso falla y no toca ninguna rama" {
  # número no entero: el YAML anterior lo procesaba y lanzaba el resolutor
  run wf_rebase_step '[{"number":"7;x","headRefName":"agent/a","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY"}]'
  [ "$status" -ne 0 ]
  [ ! -s "$T/resolved" ]
}

@test "workflow: UNKNOWN ya no aparece como estado rebasable en el YAML" {
  run grep -nE '"\$state" != "UNKNOWN"' "$WF"
  [ "$status" -eq 1 ]
  grep -qE 'bash scripts/resolve-all-open-prs\.sh --select-targets' "$WF"
}
