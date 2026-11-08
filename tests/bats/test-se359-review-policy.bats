#!/usr/bin/env bats
# test-se359-review-policy.bats — BATS tests for SE-359 REVIEW.md policy
# Ref: SE-359 — política canónica de review con vocab cerrado y cap de nits

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PARSE="$REPO_ROOT/scripts/review-policy-parse.py"
  REVIEW="$REPO_ROOT/REVIEW.md"
  export REPO_ROOT PARSE REVIEW
}

@test "REVIEW.md existe en la raíz" {
  [[ -f "$REVIEW" ]]
}

@test "parser extrae los 3 passes canónicos" {
  run python3 "$PARSE" --file "$REVIEW" --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'Bugs' in d['passes'], f'faltan Bugs: {d}'
assert 'Security' in d['passes']
assert 'Compliance' in d['passes']
"
}

@test "parser extrae nit_cap = 5" {
  run python3 "$PARSE" --file "$REVIEW" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['nit_cap'] == 5, f'nit_cap={d[\"nit_cap\"]}'
"
}

@test "parser extrae exclusiones" {
  run python3 "$PARSE" --file "$REVIEW" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert len(d['exclusions']) > 0
assert any('gen' in e for e in d['exclusions'])
"
}

@test "parser fail-soft con REVIEW.md ausente" {
  run python3 "$PARSE" --file "/no/existe/REVIEW.md" --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['exists'] is False
assert d['nit_cap'] == 5
"
}

@test "REVIEW.md usa vocabulario cerrado (Important|Nit)" {
  # todas las menciones de severidad son Important o Nit
  run grep -iE "important|nit" "$REVIEW"
  [[ "$status" -eq 0 ]]
  # no hay severidades inventadas
  run grep -iE "\b(critical|high|medium|low)\b" "$REVIEW"
  [[ "$status" -ne 0 ]]
}

@test "REVIEW.md menciona cap de nits" {
  grep -qi "at most" "$REVIEW"
  grep -qi "5" "$REVIEW"
}

# ── S03q (SE-376): comportamiento discriminante del parser ──────────────────
# Cada caso falla contra el parser anterior (truncado de REVIEW.md real).

pol() {  # pol <fichero> <expr python sobre d>
  python3 "$PARSE" --file "$1" --json | python3 -c "
import sys, json
d = json.load(sys.stdin)
print($2)
"
}

mkreview() {  # mkreview <contenido> → ruta
  local f="$BATS_TEST_TMPDIR/REVIEW.md"
  printf '%s\n' "$1" > "$f"
  echo "$f"
}

@test "important de REVIEW.md real no se trunca en el salto de línea" {
  run pol "$REVIEW" "d['important']"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"breach a policy."* ]]
  [[ "$output" == *"leak data or breach"* ]]
}

@test "important solo toma el primer párrafo (límite)" {
  f="$(mkreview '## What Important means here

Primera linea
segunda linea.

Parrafo ajeno.
## Otra')"
  run pol "$f" "d['important']"
  [[ "$output" == "Primera linea segunda linea." ]]
}

@test "exclusiones de REVIEW.md real: 3 elementos con continuaciones unidas" {
  run pol "$REVIEW" "len(d['exclusions'])"
  [[ "$output" == "3" ]]
  run pol "$REVIEW" "d['exclusions'][1]"
  [[ "$output" == *"docs/rules/INDEX.md"*"already validated by CI)."* ]]
}

@test "exclusión: línea sin sangría ni viñeta es elemento propio (negativo)" {
  f="$(mkreview '## Do not report
- uno
  sigue uno
dos suelto')"
  run pol "$f" "d['exclusions']"
  [[ "$output" == "['uno sigue uno', 'dos suelto']" ]]
}

@test "nit_cap con N en negrita se lee (7, no el default 5)" {
  f="$(mkreview 'Report at most **7** nits per review.')"
  run pol "$f" "d['nit_cap']"
  [[ "$output" == "7" ]]
}

@test "nit_cap con N en cursiva y límite 0" {
  f="$(mkreview 'Report at most _0_ nits.')"
  run pol "$f" "d['nit_cap']"
  [[ "$output" == "0" ]]
}

@test "nit_cap sin número cae al default 5 (negativo)" {
  f="$(mkreview 'Report at most many nits.')"
  run pol "$f" "d['nit_cap']"
  [[ "$output" == "5" ]]
}

@test "passes: la prosa del bloque no se cuenta como pass" {
  f="$(mkreview '## Passes

Use these checks in order:

- **Perf**: slow paths
- Docs: stale docs
## Next')"
  run pol "$f" "d['passes']"
  [[ "$output" == "['Perf', 'Docs']" ]]
}

@test "passes: bloque sin viñetas cae a los defaults (negativo)" {
  f="$(mkreview '## Passes
Just prose here
## Next')"
  run pol "$f" "d['passes']"
  [[ "$output" == "['Bugs', 'Security', 'Compliance']" ]]
}

@test "passes: duplicado sin distinguir mayúsculas se cuenta una vez (límite)" {
  f="$(mkreview '## Passes
- Bugs: uno
- bugs: otro')"
  run pol "$f" "d['passes']"
  [[ "$output" == "['Bugs']" ]]
}
