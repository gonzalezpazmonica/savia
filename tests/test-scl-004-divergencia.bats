#!/usr/bin/env bats
# SCL-004 — Labs L1: divergencia grafo-modelo como instrumento del bucle
# Ref: docs/specs/SCL-004-labs-instrumentos.spec.md

set -uo pipefail

setup_file() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  export REPO_ROOT
}

setup() {
  DIV="$REPO_ROOT/scripts/learning-divergence.sh"
  TMPD="$(mktemp -d -t scl-s4-XXXXXX)"
  mkdir -p "$TMPD/proposals"
}

teardown() {
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
}

@test "AC-1: claim alineado con el grafo → divergencia <= umbral, exit 0" {
  run bash "$DIV" --claim "el hook de captura debe generar diagnostico no vacio" \
    --graph-text "captura diagnostico hook memoria error causa raiz"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALINEADO"* ]]
}

@test "AC-2: claim divergente → divergencia > umbral, exit 1" {
  run bash "$DIV" --claim "la receta de paella lleva arroz bomba y azafran" \
    --graph-text "captura diagnostico hook memoria error"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DIVERGENCIA"* ]]
}

@test "AC-3: divergencia determinista — misma entrada → mismo valor" {
  a=$(bash "$DIV" --claim "el hook de captura diagnostico" --graph-text "captura diagnostico hook memoria error" --json)
  b=$(bash "$DIV" --claim "el hook de captura diagnostico" --graph-text "captura diagnostico hook memoria error" --json)
  [ "$a" = "$b" ]
  echo "$a" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['divergence'] == 0.4, d"
}

@test "AC-4: --propose genera propuesta con trigger divergence" {
  run bash "$DIV" --claim "vamos a hardcodear el PAT en el script de azure" \
    --graph-text "captura diagnostico hook memoria PAT" --threshold 0.5 \
    --propose --output-dir "$TMPD/proposals"
  [ "$status" -ne 0 ]
  f=$(ls "$TMPD/proposals/"*.md 2>/dev/null | head -1)
  [ -n "$f" ]
  grep -q "^trigger: divergence" "$f"
}

@test "AC-5: claim alineado con --propose NO genera propuesta" {
  run bash "$DIV" --claim "el hook de captura genera diagnostico de error" \
    --graph-text "captura diagnostico hook memoria error causa raiz" --propose --output-dir "$TMPD/proposals"
  [ "$status" -eq 0 ]
  count=$(find "$TMPD/proposals" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" = "0" ]
}

@test "AC-6: grafo vacio → divergencia maxima (exit 1)" {
  run bash "$DIV" --claim "algo" --graph-text ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"1.0000"* ]]
}

@test "AC-7: --json emite JSON valido" {
  run bash "$DIV" --claim "el hook de captura diagnostico" --graph-text "captura diagnostico hook memoria" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'divergence' in d, d"
}

# ── Comportamiento: números exactos, umbral, consulta a la cúpula y propuesta ──
# Repo aislado con learning-proposal.sh y learning-recall.sh simulados que registran lo que reciben.

mk_div() {
  SB="$TMPD/repo"
  mkdir -p "$SB/scripts" "$SB/docs/learning-proposals"
  cp "$DIV" "$SB/scripts/"
  D="$SB/scripts/learning-divergence.sh"
  cat > "$SB/scripts/learning-proposal.sh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_DIR/proposal-args"
while [[ $# -gt 0 ]]; do [[ "$1" == "--evidence" ]] && cat "$2" > "$STUB_DIR/proposal-evidence"; shift; done
exit "${PROPOSAL_EXIT:-0}"
EOS
  cat > "$SB/scripts/learning-recall.sh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_DIR/recall-args"
printf '%s' "${RECALL_OUT:-}"
exit "${RECALL_EXIT:-0}"
EOS
  export STUB_DIR="$TMPD/stub"; mkdir -p "$STUB_DIR"
}

dj() { bash "$D" --json "$@"; }
# dje <VAR> <valor> <args...>: ejecuta el script con una variable de entorno concreta
dje() { local n="$1" v="$2"; shift 2; env "$n=$v" bash "$D" --json "$@"; }
jv() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

@test "div: sin --claim muestra el uso y sale 2" {
  mk_div
  run bash "$D"
  [ "$status" -eq 2 ]
  [[ "$output" == *"learning-divergence.sh --claim"* ]]
  [[ "$output" == *"[--threshold <0-1>] [--propose] [--output-dir <dir>] [--json]"* ]]
  [[ "$output" == *"2 usage"* ]]
}

@test "div: -h muestra el uso y sale 2 aunque haya claim" {
  mk_div
  run bash "$D" --claim "algo" -h
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "div: JSON exacto con intersección parcial (2 de 4 términos del grafo = 0.5)" {
  mk_div
  run dj --claim "captura hook" --graph-text "captura diagnostico hook memoria"
  [ "$status" -eq 0 ]
  [ "$output" = '{"divergence":0.5000,"threshold":0.6,"triggered":false}' ]
}

@test "div: salida de texto con valor, umbral y veredicto ALINEADO" {
  mk_div
  run bash "$D" --claim "captura hook" --graph-text "captura diagnostico hook memoria"
  [ "${lines[0]}" = "divergencia grafo-modelo: 0.5000 (umbral 0.6)" ]
  [ "${lines[1]}" = "veredicto: ALINEADO" ]
}

@test "div: un solo término en común de 4 (0.75) supera el umbral por defecto -> exit 1 y DIVERGENCIA" {
  mk_div
  run bash "$D" --claim "captura" --graph-text "captura diagnostico hook memoria"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "divergencia grafo-modelo: 0.7500 (umbral 0.6)" ]
  [ "${lines[1]}" = "veredicto: DIVERGENCIA (revisar alineacion)" ]
}

@test "div: divergencia exactamente igual al umbral NO dispara (estricto >)" {
  mk_div
  run dj --claim "captura hook" --graph-text "captura diagnostico hook memoria" --threshold 0.5
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jv triggered)" = "False" ]
  run dj --claim "captura hook" --graph-text "captura diagnostico hook memoria" --threshold 0.49
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jv triggered)" = "True" ]
}

@test "div: la variable de entorno cambia el umbral por defecto y la opción lo pisa" {
  mk_div
  run dje SCL_DIVERGENCE_THRESHOLD 0.3 --claim "captura hook" --graph-text "captura diagnostico hook memoria"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jv threshold)" = "0.3" ]
  run dje SCL_DIVERGENCE_THRESHOLD 0.3 --claim "captura hook" --graph-text "captura diagnostico hook memoria" --threshold 0.9
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jv threshold)" = "0.9" ]
}

@test "div: términos de menos de 4 caracteres no cuentan (grafo solo con ellos = vacío)" {
  mk_div
  run dj --claim "abc xyz" --graph-text "abc xyz"
  [ "$(echo "$output" | jv divergence)" = "1.0" ]
  run dj --claim "abc captura" --graph-text "abc captura"
  [ "$(echo "$output" | jv divergence)" = "0.0" ]
}

@test "div: un término de exactamente 4 caracteres sí cuenta" {
  mk_div
  run dj --claim "hook" --graph-text "hook memoria"
  [ "$(echo "$output" | jv divergence)" = "0.5" ]
}

@test "div: stopwords no cuentan en ninguno de los dos lados" {
  mk_div
  run dj --claim "para como captura" --graph-text "para como captura"
  [ "$(echo "$output" | jv divergence)" = "0.0" ]
  run dj --claim "para como" --graph-text "captura"
  [ "$(echo "$output" | jv divergence)" = "1.0" ]
  run dj --claim "captura" --graph-text "para como sobre captura"
  [ "$(echo "$output" | jv divergence)" = "0.0" ]
}

@test "div: claim sin términos significativos con grafo no vacío -> 1.0" {
  mk_div
  run dj --claim "el de la" --graph-text "captura hook"
  [ "$(echo "$output" | jv divergence)" = "1.0" ]
  [ "$status" -eq 1 ]
}

@test "div: mayúsculas no importan y términos extra del claim no penalizan" {
  mk_div
  run dj --claim "CAPTURA Hook además hay muchísimas otras palabras irrelevantes" --graph-text "captura hook"
  [ "$(echo "$output" | jv divergence)" = "0.0" ]
}

@test "div: los dígitos forman términos (v2024 coincide, v2025 no)" {
  mk_div
  run dj --claim "release v2024" --graph-text "release v2025"
  [ "$(echo "$output" | jv divergence)" = "0.5" ]
}

@test "div: los términos repetidos cuentan una vez (conjuntos)" {
  mk_div
  run dj --claim "captura captura captura" --graph-text "captura hook hook hook"
  [ "$(echo "$output" | jv divergence)" = "0.5" ]
}

@test "div: --graph-query usa los snippets de learning-recall y le pasa top 5 y min-score 1" {
  mk_div
  run dje RECALL_OUT '{"hits":[{"snippet":"captura diagnostico"},{"snippet":"hook memoria"},{"id":"sin-snippet"}]}' \
    --claim "captura diagnostico hook memoria" --graph-query "como capturar"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jv divergence)" = "0.0" ]
  grep -qxF -- "--query" "$STUB_DIR/recall-args"
  grep -qxF -- "como capturar" "$STUB_DIR/recall-args"
  [ "$(grep -A1 -x -- '--top' "$STUB_DIR/recall-args" | tail -1)" = "5" ]
  [ "$(grep -A1 -x -- '--min-score' "$STUB_DIR/recall-args" | tail -1)" = "1" ]
  grep -qxF -- "--json" "$STUB_DIR/recall-args"
}

@test "div: --graph-text tiene prioridad y no se consulta la cúpula" {
  mk_div
  run dje RECALL_OUT '{"hits":[{"snippet":"captura"}]}' --claim "captura" --graph-text "otra cosa distinta" --graph-query "q"
  [ "$(echo "$output" | jv divergence)" = "1.0" ]
  [ ! -e "$STUB_DIR/recall-args" ]
}

@test "div: sin graph-text ni graph-query no se consulta la cúpula y el grafo queda vacío" {
  mk_div
  run dj --claim "captura"
  [ "$(echo "$output" | jv divergence)" = "1.0" ]
  [ ! -e "$STUB_DIR/recall-args" ]
}

@test "div: la cúpula devuelve JSON inválido, falla o no tiene hits -> grafo vacío, divergencia 1.0" {
  mk_div
  run dje RECALL_OUT 'esto no es json' --claim "captura" --graph-query "q"
  [ "$(echo "$output" | jv divergence)" = "1.0" ]
  run dje RECALL_EXIT 1 --claim "captura" --graph-query "q"
  [ "$(echo "$output" | jv divergence)" = "1.0" ]
  run dje RECALL_OUT '{"hits":[]}' --claim "captura" --graph-query "q"
  [ "$(echo "$output" | jv divergence)" = "1.0" ]
}

@test "div: --propose con disparo invoca learning-proposal con origen, trigger divergence y evidencia" {
  mk_div; mkdir -p "$TMPD/out"
  run bash "$D" --claim "xxxx yyyy" --graph-text "captura hook" --propose --output-dir "$TMPD/out"
  [ "$status" -eq 1 ]
  grep -qxF -- "--trigger" "$STUB_DIR/proposal-args"
  grep -qxF -- "divergence" "$STUB_DIR/proposal-args"
  grep -qxF -- "criterio" "$STUB_DIR/proposal-args"
  grep -qxF -- "Labs L1: divergencia grafo-modelo 1.0000 > umbral 0.6" "$STUB_DIR/proposal-args"
  grep -qxF -- "$TMPD/out" "$STUB_DIR/proposal-args"
  grep -qxF -- "$SB/output/learning-loop/graph-index.jsonl" "$STUB_DIR/proposal-args"
  [ "$(cat "$STUB_DIR/proposal-evidence")" = "divergence-evidence" ]
}

@test "div: el fichero de evidencia temporal se borra tras proponer" {
  mk_div; mkdir -p "$TMPD/out"
  run bash "$D" --claim "xxxx" --graph-text "captura" --propose --output-dir "$TMPD/out"
  [ -e "$STUB_DIR/proposal-args" ]
  [ -z "$(ls -A "$TMPD/out")" ]
}

@test "div: --propose sin disparo no invoca learning-proposal" {
  mk_div; mkdir -p "$TMPD/out"
  run bash "$D" --claim "captura" --graph-text "captura" --propose --output-dir "$TMPD/out"
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_DIR/proposal-args" ]
}

@test "div: con disparo pero sin --propose no invoca learning-proposal" {
  mk_div; mkdir -p "$TMPD/out"
  run bash "$D" --claim "xxxx" --graph-text "captura" --output-dir "$TMPD/out"
  [ "$status" -eq 1 ]
  [ ! -e "$STUB_DIR/proposal-args" ]
}

@test "div: si learning-proposal falla o no existe, el exit code sigue siendo el de la divergencia" {
  mk_div; mkdir -p "$TMPD/out"
  PROPOSAL_EXIT=3 run bash "$D" --claim "xxxx" --graph-text "captura" --propose --output-dir "$TMPD/out"
  [ "$status" -eq 1 ]
  [ -e "$STUB_DIR/proposal-args" ]
  rm "$SB/scripts/learning-proposal.sh"
  run bash "$D" --claim "xxxx" --graph-text "captura" --propose --output-dir "$TMPD/out"
  [ "$status" -eq 1 ]
}

@test "div: argumentos desconocidos se ignoran" {
  mk_div
  run bash "$D" --claim "captura" --graph-text "captura" --nada --json
  [ "$status" -eq 0 ]
  [[ "$output" == '{"divergence":0'* ]]
}

@test "div: SCL_PROPOSALS_DIR es el destino por defecto de las propuestas" {
  mk_div; mkdir -p "$TMPD/envout"
  SCL_PROPOSALS_DIR="$TMPD/envout" run bash "$D" --claim "xxxx" --graph-text "captura" --propose
  grep -qxF -- "$TMPD/envout" "$STUB_DIR/proposal-args"
}
