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
  mutate "$MP" "op: fullmatch                      # la orden entera; la clase excluye ; & | < > \$ \` \\n \\r" "op: regex"
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

OLD_SEP='[^;&|\n]*'

@test "P1 sustitucion: el unless con la clase vieja (sin dolar ni backtick) falla" {
  mutate "$MP" "--dry-run\\s[^;&|<>\$\`\\n\\r]*'" "--dry-run\\s${OLD_SEP}'"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"admite encadenar o sustituir"* ]]
  [[ "$output" == *"no excluye"* ]]
}

@test "P1 sustitucion: con la clase vieja el caso de sustitucion deja de bloquear (semantica)" {
  mutate "$MP" "--dry-run\\s[^;&|<>\$\`\\n\\r]*'" "--dry-run\\s${OLD_SEP}'"
  run python3 -I "$CHECK" "$MS" "$MP"
  [[ "$output" == *"el caso block no bloquea"* ]]
}

@test "P1 sustitucion: un unless con .* falla" {
  mutate "$MP" "--dry-run\\s[^;&|<>\$\`\\n\\r]*'" "--dry-run\\s.*'"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"casan separadores"* ]]
}

@test "P1 sustitucion: sin el block con sustitucion falla" {
  mutate "$MP" '    - {tool: Bash, input: {command: "git push --dry-run origin main $(git push origin main)"}}   # sustitución' ""
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin block con sustitución"* ]]
}

@test "P2 dolar dentro de una clase no es falso positivo" {
  mutate "$MP" "pattern: 'terraform\\s+destroy'" "pattern: 'terraform\\s+destroy[\\w\$]*'"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 0 ]
}

@test "sec P2-1: sin base_ref fuera de la copia de trabajo falla" {
  mutate "$MS" "ni de la copia de trabajo" "ni de otra cosa"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"base_ref no local"* ]]
}

@test "sec P2-2: sin realpath en la salida de recuperacion falla" {
  mutate "$MS" "resuelta con \`realpath\`" "tal cual"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"realpath"* ]]
}

@test "sec P2-3: sin la restriccion de emit-corpus falla" {
  mutate "$MS" "nunca al corpus versionado" "donde sea"
  run python3 -I "$CHECK" "$MS" "$MP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"emit-corpus"* ]]
}
