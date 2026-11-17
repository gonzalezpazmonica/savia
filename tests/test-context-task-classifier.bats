#!/usr/bin/env bats
# SE-376 S03 — context-task-classifier: el clasificador decide qué turnos no se pueden comprimir
# (decision/spec congelados) y el medidor de distorsión decide si una compactación es aceptable.
# Aquí se fijan los límites exactos (empates, 8/15 palabras, D=0.15 y D=0.30) y los fallos
# de entrada; cada aserción cae si se muta el umbral o el orden de prioridad del script real.
# Ref: SE-029 · .claude/skills/context-task-classifier/SKILL.md · scripts/context-task-classify.sh · scripts/context-distortion-measure.sh
set -uo pipefail

CLS="scripts/context-task-classify.sh"
DIS="scripts/context-distortion-measure.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  C="$ROOT/$CLS"; D="$ROOT/$DIS"
  W="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
}

teardown() { cd /; }

cls() { printf '%s' "$1" | bash "$C" --stdin; }
# Valor tal cual aparece en el JSON (los decimales conservan sus ceros: 0.5000, no 0.5).
field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"?([^\",}]*)\"?.*/\1/"; }

# ── Clasificador: prioridad y empates ────────────────────────────────────────

@test "empate decision/spec (3 vs 3) lo gana la clase más estricta: decision" {
  [ "$(cls 'approved SPEC-12 for the rollout plan of the new module')" = "decision" ]
}

@test "empate spec/code (3 vs 3) lo gana spec, no code" {
  [ "$(cls 'SPEC-5 hit a Traceback during the nightly run of the suite')" = "spec" ]
}

@test "empate code/review (3 vs 3) lo gana code, no review" {
  [ "$(cls 'Error: the import failed and PASS: nothing else happened in the build today')" = "code" ]
}

@test "un saludo con una aprobación dentro NO baja a chitchat: la decisión se congela" {
  out="$(cls 'hola, APPROVED merge')"
  [ "$out" = "decision" ]
  js="$(printf '%s' 'hola, APPROVED merge' | bash "$C" --stdin --json)"
  [ "$(field "$js" frozen)" = "true" ]
}

# ── Clasificador: tabla clase → ratio y frozen ───────────────────────────────

@test "tabla de ratios y frozen por clase (JSON): decision 5/true, spec 3/true, code 10/partial, review 15/false" {
  js="$(printf '%s' 'APPROVED and merged today' | bash "$C" --stdin --json)"
  [ "$(field "$js" class)" = "decision" ]; [ "$(field "$js" max_ratio)" = "5" ]; [ "$(field "$js" frozen)" = "true" ]
  js="$(printf '%s' 'SE-376 AC-4 acceptance criteria listed here' | bash "$C" --stdin --json)"
  [ "$(field "$js" class)" = "spec" ]; [ "$(field "$js" max_ratio)" = "3" ]; [ "$(field "$js" frozen)" = "true" ]
  js="$(printf '%s' 'Traceback (most recent call last) in module' | bash "$C" --stdin --json)"
  [ "$(field "$js" class)" = "code" ]; [ "$(field "$js" max_ratio)" = "10" ]; [ "$(field "$js" frozen)" = "partial" ]
  js="$(printf '%s' 'VERDICT: PASS for the judge panel on this review' | bash "$C" --stdin --json)"
  [ "$(field "$js" class)" = "review" ]; [ "$(field "$js" max_ratio)" = "15" ]; [ "$(field "$js" frozen)" = "false" ]
}

@test "context 25/false y chitchat 80/false" {
  texto="$(printf 'Notas largas\n'; for i in $(seq 1 12); do printf -- '- punto número %s con bastante texto de relleno para superar las palabras\n' "$i"; done)"
  js="$(printf '%s' "$texto" | bash "$C" --stdin --json)"
  [ "$(field "$js" class)" = "context" ]; [ "$(field "$js" max_ratio)" = "25" ]; [ "$(field "$js" frozen)" = "false" ]
  js="$(printf '%s' 'gracias' | bash "$C" --stdin --json)"
  [ "$(field "$js" class)" = "chitchat" ]; [ "$(field "$js" max_ratio)" = "80" ]
}

# ── Clasificador: límites de palabras ────────────────────────────────────────

@test "boundary sin señales: 15 palabras → chitchat; 16 palabras → context" {
  quince="uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince"
  [ "$(cls "$quince")" = "chitchat" ]
  [ "$(cls "$quince dieciseis")" = "context" ]
}

@test "boundary de chitchat por longitud: 8 palabras puntúan chitchat; 9 sin señales caen al fallback" {
  ocho="uno dos tres cuatro cinco seis siete ocho"
  js="$(printf '%s' "$ocho" | bash "$C" --stdin --json)"
  [ "$(field "$js" class)" = "chitchat" ]
  [ "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["scores"]["chitchat"])')" = "3" ]
  js="$(printf '%s' "$ocho nueve" | bash "$C" --stdin --json)"
  [ "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["scores"]["chitchat"])')" = "0" ]
}

@test "boundary de context por tamaño: 101 palabras suman 2 puntos de context; 100 no" {
  cien="$(printf 'palabra %.0s' $(seq 1 100))"
  js="$(printf '%s' "$cien" | bash "$C" --stdin --json)"
  [ "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["scores"]["context"])')" = "0" ]
  js="$(printf '%s' "$cien palabra" | bash "$C" --stdin --json)"
  [ "$(printf '%s' "$js" | python3 -c 'import json,sys; print(json.load(sys.stdin)["scores"]["context"])')" = "2" ]
}

# ── Clasificador: entrada ────────────────────────────────────────────────────

@test "--input y --stdin dan la misma clase para el mismo texto" {
  printf 'APPROVED and merged today\n' > "$W/turno.txt"
  a="$(bash "$C" --input "$W/turno.txt")"
  b="$(cls 'APPROVED and merged today')"
  [ "$a" = "$b" ]
  [ "$a" = "decision" ]
}

@test "error: fichero de entrada inexistente (nonexistent) → exit 2 sin clase en stdout" {
  run bash "$C" --input "$W/no-existe.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"input file not found"* ]]
}

@test "error: sin argumentos o con flag desconocido → exit 2" {
  run bash "$C"
  [ "$status" -eq 2 ]
  run bash "$C" --bogus
  [ "$status" -eq 2 ]
}

@test "caso límite: entrada vacía (empty) por stdin cae a chitchat, no rompe" {
  run bash -c "printf '' | bash '$C' --stdin"
  [ "$status" -eq 0 ]
  [ "$output" = "chitchat" ]
}

# ── Medidor de distorsión: números exactos y umbrales ───────────────────────

dist() { # dist <original> <compactado> [anchors] → JSON
  printf '%s\n' "$1" > "$W/orig.txt"; printf '%s\n' "$2" > "$W/comp.txt"
  if [ -n "${3:-}" ]; then bash "$D" --original "$W/orig.txt" --compacted "$W/comp.txt" --task-anchors "$3" --json
  else bash "$D" --original "$W/orig.txt" --compacted "$W/comp.txt" --json; fi
}

@test "fórmula: D = 1 - (0.4·recall + 0.6·anchors); sin anclas el coverage es 1.0" {
  js="$(dist 'alpha beta gamma delta' 'alpha beta')"
  [ "$(field "$js" token_recall)" = "0.5000" ]
  [ "$(field "$js" anchor_coverage)" = "1.0000" ]
  [ "$(field "$js" distortion)" = "0.2000" ]
  [ "$(field "$js" verdict)" = "ACCEPTABLE" ]
}

@test "las anclas pesan más que el recall: perder una de dos anclas con recall total da D=0.30 → ACCEPTABLE" {
  js="$(dist 'alpha beta gamma' 'alpha beta gamma' 'alpha,zzzz')"
  [ "$(field "$js" anchor_coverage)" = "0.5000" ]
  [ "$(field "$js" distortion)" = "0.3000" ]
  [ "$(field "$js" verdict)" = "ACCEPTABLE" ]
}

@test "boundary D=0.15 es HIGH_QUALITY (≤) y D=0.20 deja de serlo" {
  js="$(dist 'aaa bbb ccc ddd eee fff ggg hhh' 'aaa bbb ccc ddd eee')"
  [ "$(field "$js" distortion)" = "0.1500" ]
  [ "$(field "$js" verdict)" = "HIGH_QUALITY" ]
  js="$(dist 'aaa bbb ccc ddd eee fff ggg hhh' 'aaa bbb ccc ddd')"
  [ "$(field "$js" distortion)" = "0.2000" ]
  [ "$(field "$js" verdict)" = "ACCEPTABLE" ]
}

@test "boundary D=0.30 es ACCEPTABLE y D=0.35 es UNACCEPTABLE" {
  js="$(dist 'aaa bbb ccc ddd eee fff ggg hhh' 'aaa bbb')"
  [ "$(field "$js" distortion)" = "0.3000" ]
  [ "$(field "$js" verdict)" = "ACCEPTABLE" ]
  js="$(dist 'aaa bbb ccc ddd eee fff ggg hhh' 'aaa')"
  [ "$(field "$js" distortion)" = "0.3500" ]
  [ "$(field "$js" verdict)" = "UNACCEPTABLE" ]
}

@test "compactación que conserva todo (identidad) → D=0.0000 HIGH_QUALITY con ratio 1.00" {
  js="$(dist 'alpha beta gamma' 'alpha beta gamma' 'alpha,gamma')"
  [ "$(field "$js" distortion)" = "0.0000" ]
  [ "$(field "$js" verdict)" = "HIGH_QUALITY" ]
  [ "$(field "$js" ratio)" = "1.00" ]
}

@test "las anclas se buscan sin distinguir mayúsculas; los tokens de menos de 3 letras no cuentan" {
  js="$(dist 'alpha beta no si' 'ALPHA beta' 'AlPhA')"
  [ "$(field "$js" anchor_coverage)" = "1.0000" ]
  [ "$(field "$js" token_recall)" = "1.0000" ]
}

@test "caso límite: compactado empty (zero bytes) → ratio 0.00, recall 0 y UNACCEPTABLE" {
  : > "$W/orig.txt"; printf 'alpha beta gamma\n' > "$W/orig.txt"; : > "$W/comp.txt"
  js="$(bash "$D" --original "$W/orig.txt" --compacted "$W/comp.txt" --json)"
  [ "$(field "$js" ratio)" = "0.00" ]
  [ "$(field "$js" token_recall)" = "0.0000" ]
  [ "$(field "$js" verdict)" = "UNACCEPTABLE" ]
}

@test "error: faltan argumentos o un fichero no existe → exit 2 sin veredicto" {
  run bash "$D" --original "$W/orig.txt"
  [ "$status" -eq 2 ]
  run bash "$D" --original "$W/no-existe.txt" --compacted "$W/no-existe2.txt"
  [ "$status" -eq 2 ]
  [[ "$output" != *"Verdict"* && "$output" != *"verdict"* ]]
}
