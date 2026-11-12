#!/usr/bin/env bats
# SE-520 — coherencia de la spec y del prototipo (hallazgos de la revisión de la PR #1539).
# Comprobador: tests/se520_spec_check.py. Caso positivo (los reales pasan) y
# casos negativos (copias mutadas fallan con su motivo).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-520-reglas-de-guarda-en-texto.spec.md"
PROTO="$REPO_ROOT/docs/specs/assets/prototipo-SE-520.md"
CHECK="$REPO_ROOT/tests/se520_spec_check.py"

setup() {
  set -uo pipefail
  MS="$BATS_TEST_TMPDIR/spec.md"
  MP="$BATS_TEST_TMPDIR/proto.md"
  cp "$SPEC" "$MS"
  cp "$PROTO" "$MP"
}

# mutate <fichero> <viejo> <nuevo>: sustitución literal; falla si no encuentra el texto.
mutate() {
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s:
    sys.exit("mutación sin efecto: " + old[:60])
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

WHEN_NEW="pattern: 'git\\s+push\\b[^;&|\\n]*\\s(\\+|HEAD:|refs/heads/)?main\\b'"

@test "reales: coherentes" {
  run python3 -I "$CHECK" "$SPEC" "$PROTO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uso: sin argumentos sale 2" {
  run python3 -I "$CHECK"
  [ "$status" -eq 2 ]
}

@test "fichero ausente sale 2" {
  run python3 -I "$CHECK" /nonexistent/a.md "$PROTO"
  [ "$status" -eq 2 ]
}

@test "P1-2: el patron anterior (con \\S+) deja el allow sin ejercer el unless" {
  mutate "$MP" "$WHEN_NEW" "pattern: 'git\\s+push\\s+\\S+\\s+(HEAD:)?main\\b'"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin allow que case con when"* ]]
}

@test "P1-2: unless con op regex en la orden falla" {
  mutate "$MP" "op: fullmatch                      # la orden entera, sin separadores: no admite encadenar" "op: regex"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin op fullmatch"* ]]
}

@test "sec P2-1: sin el block encadenado falla" {
  mutate "$MP" '    - {tool: Bash, input: {command: "git push --dry-run origin main; git push origin main"}}   # encadenado' ""
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin block encadenado"* ]]
}

@test "sec P2-2: un patron con huecos (no bloquea -f ni +main) falla" {
  mutate "$MP" "$WHEN_NEW" "pattern: 'git\\s+push\\s+origin\\s+main\\b'"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"el caso block no bloquea"* ]]
}

@test "P2-2: dolar en un patron falla" {
  mutate "$MP" "pattern: 'terraform\\s+destroy'" "pattern: 'terraform\\s+destroy\$'"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"prohibidos"* ]]
}

@test "P1-1: sin la exclusion de ids de la PR falla" {
  mutate "$MS" "la base **excluye los \`id\` que esa PR modifica" "la base incluye todo"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1-1 exclusión"* ]]
}

@test "P1-3: sin salida de recuperacion falla" {
  mutate "$MS" "**Salida de recuperación.**" "**Sin salida.**"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1-3 salida"* ]]
}

@test "P1-4: sin canal de warn falla" {
  python3 -I - "$MS" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("`additionalContext`", "`stderr`"))
PY
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1-4 canal"* ]]
}

@test "P2-5: sin el motor en tier 3 falla" {
  mutate "$MS" "\`scripts/guard_rules.py\`, \`config/guard-rules.yaml\`" "\`otro\`"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P2-5 motor"* ]]
}
