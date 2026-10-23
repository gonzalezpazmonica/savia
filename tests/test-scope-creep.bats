#!/usr/bin/env bats
# tests/test-scope-creep.bats — SE-315: Scope Creep Gate (S1 + S2).
# Ref: docs/propuestas/SE-315-scope-creep-gate.md (AC-S1, AC-S2)

DECLARE="scripts/scope-declare.sh"
CHECK="scripts/scope-creep-check.sh"
FIXTURES_DIR="tests/fixtures/scope-creep"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

# ── Fixture: spec con tabla de ficheros ────────────────────────────────────
make_spec() {
  cat > "$1" <<'EOF'
# Spec: SE-999 — fixture

## Ficheros a Crear/Modificar

| Fichero | Proposito |
|---|---|
| scripts/alpha.sh | core |
| tests/test-alpha.bats | tests |
EOF
}

ABS_DECLARE="$BATS_TEST_DIRNAME/../scripts/scope-declare.sh"
ABS_CHECK="$BATS_TEST_DIRNAME/../scripts/scope-creep-check.sh"

run_in() { # repo args...
  local repo="$1"; shift
  ( cd "$repo" && bash "$ABS_CHECK" "$@" )
}

# ── S1: scope-declare.sh ───────────────────────────────────────────────────

@test "S1.1: script existe y es ejecutable" {
  [[ -f "$DECLARE" ]]
  [[ -x "$DECLARE" ]]
}

@test "S1.2: usa set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$DECLARE"
  [[ "$output" -ge 1 ]]
}

@test "AC-S1.1: extrae declared_paths de una spec con tabla" {
  local spec="$TMPD/spec.md"
  make_spec "$spec"
  run bash "$DECLARE" "$spec"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['spec_id'] == 'SE-999', d
assert 'scripts/alpha.sh' in d['declared_paths'], d
assert 'tests/test-alpha.bats' in d['declared_paths'], d
assert 'scripts' in d['root_dirs'], d
"
}

@test "AC-S1.2: spec sin ficheros → declared_paths vacío + WARN en salida" {
  local spec="$TMPD/empty.md"
  printf '# Spec vacia\n\nSin declaracion de ficheros.\n' > "$spec"
  run bash "$DECLARE" "$spec"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['declared_paths'] == [], d
"
}

@test "S1.3: spec inexistente → exit 2" {
  run bash "$DECLARE" /no/existe/spec.md
  [[ "$status" -eq 2 ]]
}

@test "S1.4: salida JSON parseable" {
  local spec="$TMPD/spec.md"
  make_spec "$spec"
  run bash "$DECLARE" "$spec"
  echo "$output" | python3 -m json.tool > /dev/null
}

# ── S2: scope-creep-check.sh ───────────────────────────────────────────────
# Se usa un repo git temporal para producir diffs controlados.

make_gitrepo() {
  local dir="$1"
  mkdir -p "$dir/scripts" "$dir/tests"
  cp "$DECLARE" "$CHECK" "$dir/" 2>/dev/null || true
  ( cd "$dir" \
    && git init -q \
    && git config user.email "test@test" \
    && git config user.name "test" \
    && echo "x" > scripts/alpha.sh \
    && echo "x" > tests/test-alpha.bats \
    && echo "x" > scripts/extra.sh \
    && git add -A \
    && git commit -qm base )
}

add_file() { # repo file
  ( cd "$1" && mkdir -p "$(dirname "$2")" && echo "y" > "$2" && git add "$2" && git commit -qm "change $2" )
}

@test "S2.1: script existe y es ejecutable" {
  [[ -f "$CHECK" ]]
  [[ -x "$CHECK" ]]
}

@test "S2.2: usa set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$CHECK"
  [[ "$output" -ge 1 ]]
}

@test "AC-S2.1: diff 100% declared → IN_SCOPE" {
  local repo="$TMPD/repo-in"
  make_gitrepo "$repo"
  local spec="$repo/spec.md"
  cat > "$spec" <<'EOF'
| Fichero | Proposito |
|---|---|
| scripts/alpha.sh | core |
| tests/test-alpha.bats | tests |
EOF
  add_file "$repo" scripts/alpha.sh
  run run_in "$repo" --spec "$spec" --base HEAD~1 --head HEAD --verdict
  [[ "$status" -eq 0 ]]
  [[ "$output" == "IN_SCOPE" ]]
}

@test "AC-S2.2: 1 fichero unrelated → EXTRA_FILES listándolo" {
  local repo="$TMPD/repo-extra"
  make_gitrepo "$repo"
  local spec="$repo/spec.md"
  cat > "$spec" <<'EOF'
| Fichero | Proposito |
|---|---|
| scripts/alpha.sh | core |
EOF
  add_file "$repo" docs/extra.md
  run run_in "$repo" --spec "$spec" --base HEAD~1 --head HEAD --verdict
  [[ "$status" -eq 0 ]]
  [[ "$output" == "EXTRA_FILES" ]]
  run run_in "$repo" --spec "$spec" --base HEAD~1 --head HEAD --files-unrelated
  [[ "$output" == "docs/extra.md" ]]
}

@test "AC-S2.3: declared + unrelated → MIXED_SCOPE con ambos grupos" {
  local repo="$TMPD/repo-mixed"
  make_gitrepo "$repo"
  local spec="$repo/spec.md"
  cat > "$spec" <<'EOF'
| Fichero | Proposito |
|---|---|
| scripts/alpha.sh | core |
EOF
  add_file "$repo" scripts/alpha.sh
  add_file "$repo" docs/extra.md
  run run_in "$repo" --spec "$spec" --base HEAD~2 --head HEAD --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['verdict'] == 'MIXED_SCOPE', d
assert 'scripts/alpha.sh' in d['declared'], d
assert 'docs/extra.md' in d['unrelated'], d
"
}

@test "AC-S2.4: exit 0 incluso con veredicto no-IN_SCOPE (report-only)" {
  local repo="$TMPD/repo-exit"
  make_gitrepo "$repo"
  local spec="$repo/spec.md"
  cat > "$spec" <<'EOF'
| Fichero | Proposito |
|---|---|
| scripts/alpha.sh | core |
EOF
  add_file "$repo" docs/extra.md
  run run_in "$repo" --spec "$spec" --base HEAD~1 --head HEAD --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['verdict'] == 'EXTRA_FILES', d
"
}

@test "S2.5: sin --spec → exit 2 (usage)" {
  run bash "$CHECK"
  [[ "$status" -eq 2 ]]
}

@test "S2.6: spec inexistente → exit 2" {
  local repo="$TMPD/repo-nospec"
  make_gitrepo "$repo"
  run run_in "$repo" --spec /no/existe.md --base HEAD~1 --head HEAD
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"spec no existe: /no/existe.md"* ]]
}

@test "S2.7: whitelist estructural nunca cuenta como unrelated" {
  local repo="$TMPD/repo-wl"
  make_gitrepo "$repo"
  local spec="$repo/spec.md"
  cat > "$spec" <<'EOF'
| Fichero | Proposito |
|---|---|
| scripts/alpha.sh | core |
EOF
  add_file "$repo" CHANGELOG.md
  run run_in "$repo" --spec "$spec" --base HEAD~1 --head HEAD --json
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['verdict'] == 'IN_SCOPE', d
"
}

@test "S2.8: fichero en directorio declarado cuenta como related" {
  local repo="$TMPD/repo-rel"
  make_gitrepo "$repo"
  local spec="$repo/spec.md"
  cat > "$spec" <<'EOF'
| Fichero | Proposito |
|---|---|
| scripts/alpha.sh | core |
EOF
  add_file "$repo" scripts/alpha.sh
  add_file "$repo" scripts/helper.sh
  run run_in "$repo" --spec "$spec" --base HEAD~2 --head HEAD --json
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['verdict'] == 'IN_SCOPE', d
assert 'scripts/helper.sh' in d['related'], d
"
}

# ── S3: Integración ─────────────────────────────────────────────────────────

@test "AC-S3.1: G17 definido en pr-plan-gates.sh y registrado en pr-plan.sh" {
  run grep -c 'g17_scope_creep()' scripts/pr-plan-gates.sh
  [[ "$output" -ge 1 ]]
  run grep -c 'gate "G17"' scripts/pr-plan.sh
  [[ "$output" -ge 1 ]]
}

@test "AC-S3.1b: G17 report-only — nunca bloquea (sin FAIL, solo WARN/PASS)" {
  run grep -A8 'g17_scope_creep()' scripts/pr-plan-gates.sh
  [[ "$output" == *"WARN"* ]]
  # No debe contener "FAIL:" propio (report-only por diseño AC-S2.4)
  local body; body=$(sed -n '/g17_scope_creep()/,/^}/p' scripts/pr-plan-gates.sh)
  [[ "$body" != *'echo "FAIL'* ]]
}

# ── Comportamiento: scope-declare.sh ──────────────────────────────────────────

_declare() { printf '%s\n' "$1" > "$TMPD/s.md"; bash "$ABS_DECLARE" "$TMPD/s.md"; }
_jq_decl() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print($2)"; }

@test "declare: el id es el primer SE-/SPEC- del texto y unknown si no hay" {
  out="$(_declare $'# x\nver SPEC-12 y SE-7')"
  [ "$(_jq_decl "$out" "d['spec_id']")" = "SPEC-12" ]
  out="$(_declare $'# sin identificador')"
  [ "$(_jq_decl "$out" "d['spec_id']")" = "unknown" ]
}

@test "declare: spec_file es el nombre base, sin directorios" {
  out="$(_declare 'SE-1')"
  [ "$(_jq_decl "$out" "d['spec_file']")" = "s.md" ]
}

@test "declare: la tabla acepta rutas con y sin comillas invertidas y descarta la cabecera" {
  out="$(_declare $'SE-1\n| Fichero | Proposito |\n|---|---|\n| `x/a.sh` | x |\n| y/b.md | y |')"
  [ "$(_jq_decl "$out" "d['declared_paths']")" = "['x/a.sh', 'y/b.md']" ]
}

@test "declare: filas de tabla con extensión no admitida o con espacios no cuentan" {
  out="$(_declare $'SE-1\n| a/b.txt | x |\n| mi fichero.md | y |\n| a/b.sh | z |')"
  [ "$(_jq_decl "$out" "d['declared_paths']")" = "['a/b.sh']" ]
}

@test "declare: menciones inline con prefijo conocido se recogen y la puntuación final se limpia" {
  out="$(_declare $'SE-1 toca scripts/a.sh, y también `tests/b.bats`. Además (config/c.yaml); y .opencode/d.ts: fin.')"
  [ "$(_jq_decl "$out" "d['declared_paths']")" = "['.opencode/d.ts', 'config/c.yaml', 'scripts/a.sh', 'tests/b.bats']" ]
}

@test "declare: una mención inline sin prefijo conocido no se considera ruta declarada" {
  out="$(_declare $'SE-1 menciona src/app.py y otro/x.sh')"
  [ "$(_jq_decl "$out" "d['declared_paths']")" = "[]" ]
}

@test "declare: la misma ruta en tabla y en texto aparece una sola vez" {
  out="$(_declare $'SE-1 usa scripts/a.sh\n| scripts/a.sh | x |')"
  [ "$(_jq_decl "$out" "len(d['declared_paths'])")" = "1" ]
}

@test "declare: root_dirs incluye el directorio y el de primer nivel; un fichero suelto se incluye a sí mismo" {
  out="$(_declare $'SE-1\n| a/b/c.sh | x |\n| README.md | y |')"
  [ "$(_jq_decl "$out" "d['root_dirs']")" = "['README.md', 'a', 'a/b']" ]
}

@test "declare: --help sale 0 y sin argumentos sale 2 con uso" {
  run bash "$ABS_DECLARE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  run bash "$ABS_DECLARE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "declare: spec inexistente nombra la ruta en el error" {
  run bash "$ABS_DECLARE" "$TMPD/falta.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"spec no existe: $TMPD/falta.md"* ]]
}

# ── Comportamiento: scope-creep-check.sh ──────────────────────────────────────

# _repo <dir> : repo con un commit base; _commit <dir> <fichero>...
_repo() {
  mkdir -p "$1"
  ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
    && echo base > base.txt && git add -A && git commit -qm base )
}
_commit() { local d="$1"; shift; ( cd "$d" && for f in "$@"; do mkdir -p "$(dirname "$f")"; echo y > "$f"; git add "$f"; done && git commit -qm c ); }
_spec() { printf '| Fichero | P |\n|---|---|\n| scripts/sub/alpha.sh | x |\n' > "$1/spec.md"; }
_verdict() { run_in "$1" --spec "$1/spec.md" --base HEAD~1 --head HEAD --verdict; }

@test "check: spec sin rutas declaradas da NO_DECLARED aunque haya cambios" {
  r="$TMPD/r"; _repo "$r"; printf '# nada\n' > "$r/spec.md"
  _commit "$r" scripts/x.sh
  run _verdict "$r"
  [ "$output" = "NO_DECLARED" ]
}

@test "check: diff vacío con spec que declara rutas es IN_SCOPE con total_changed 0" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  run run_in "$r" --spec "$r/spec.md" --base HEAD --head HEAD --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .verdict)" = "IN_SCOPE" ]
  [ "$(echo "$output" | jq -r .total_changed)" = "0" ]
}

@test "check: un fichero de otro directorio de primer nivel es EXTRA_FILES si no hay nada declarado" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" docs/z.md
  run _verdict "$r"
  [ "$output" = "EXTRA_FILES" ]
}

@test "check: un fichero hermano en el mismo directorio de primer nivel es related" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" scripts/otro/y.sh
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --json
  [ "$(echo "$output" | jq -r .verdict)" = "IN_SCOPE" ]
  [ "$(echo "$output" | jq -r '.related[0]')" = "scripts/otro/y.sh" ]
}

@test "check: un directorio cuyo nombre solo empieza igual (scripts-old) NO es related" {
  r="$TMPD/r"; _repo "$r"; printf '| F | P |\n|---|---|\n| scripts/alpha.sh | x |\n' > "$r/spec.md"
  _commit "$r" scripts-old/x.sh
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --json
  [ "$(echo "$output" | jq -r .verdict)" = "EXTRA_FILES" ]
  [ "$(echo "$output" | jq -r '.unrelated[0]')" = "scripts-old/x.sh" ]
}

@test "check: un fichero en la raíz del repo NO es related de una spec que declara rutas anidadas" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" package.json
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --json
  [ "$(echo "$output" | jq -r .verdict)" = "EXTRA_FILES" ]
  [ "$(echo "$output" | jq -r '.unrelated[0]')" = "package.json" ]
}

@test "check: el directorio padre de una ruta declarada sí es related" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" scripts/top.sh
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --json
  [ "$(echo "$output" | jq -r '.related[0]')" = "scripts/top.sh" ]
}

@test "check: toda la lista blanca estructural cuenta como declared" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" CHANGELOG.md CHANGELOG.d/frag.md .scm/x.json .confidentiality-signature .pr-summary.md AGENTS.md SKILLS.md docs/propuestas/INDEX.md
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --json
  [ "$(echo "$output" | jq -r .verdict)" = "IN_SCOPE" ]
  [ "$(echo "$output" | jq -r '.declared | length')" = "8" ]
  [ "$(echo "$output" | jq -r '.unrelated | length')" = "0" ]
}

@test "check: lista blanca + un fichero ajeno da MIXED_SCOPE (la lista blanca cuenta como declared)" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" CHANGELOG.md docs/z.md
  run _verdict "$r"
  [ "$output" = "MIXED_SCOPE" ]
}

@test "check: la recomendación acompaña al veredicto" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" scripts/sub/alpha.sh
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --json
  [ "$(echo "$output" | jq -r .recommendation)" = "keep — diff alineado con la spec" ]
  [ "$(echo "$output" | jq -r .spec_file)" = "spec.md" ]
  _commit "$r" docs/z.md
  run run_in "$r" --spec "$r/spec.md" --base HEAD~2 --head HEAD --json
  [ "$(echo "$output" | jq -r .recommendation)" = "justify — declarar el extra en .pr-summary.md o split" ]
}

@test "check: --files-unrelated imprime un fichero por línea y nada si no hay" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" docs/a.md docs/b.md
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --files-unrelated
  [ "$output" = $'docs/a.md\ndocs/b.md' ]
  _commit "$r" scripts/sub/alpha.sh
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --files-unrelated
  [ -z "$output" ]
}

@test "check: ref inválida es exit 2 con el mensaje de git diff" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  run run_in "$r" --spec "$r/spec.md" --base no-existe --head HEAD
  [ "$status" -eq 2 ]
  [[ "$output" == *"git diff no-existe..HEAD falló"* ]]
}

@test "check: sin --base el valor por defecto es origin/main (falla si el repo no lo tiene)" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  run run_in "$r" --spec "$r/spec.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"origin/main..HEAD"* ]]
}

@test "check: argumento desconocido y falta de --spec son exit 2; --help sale 0" {
  run bash "$ABS_CHECK" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento desconocido '--bogus'"* ]]
  run bash "$ABS_CHECK" --base HEAD
  [ "$status" -eq 2 ]
  [[ "$output" == *"falta --spec"* ]]
  run bash "$ABS_CHECK" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope-creep-gate"* ]]
}

@test "check: spec inexistente nombra la ruta en el error" {
  run bash "$ABS_CHECK" --spec "$TMPD/falta.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"spec no existe: $TMPD/falta.md"* ]]
}

@test "check: related + unrelated sin ningún declared también es MIXED_SCOPE" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" scripts/otro/y.sh docs/z.md
  run _verdict "$r"
  [ "$output" = "MIXED_SCOPE" ]
}

@test "check: total_changed cuenta todos los ficheros y EXTRA_FILES recomienda separar el commit" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" docs/a.md docs/b.md
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --json
  [ "$(echo "$output" | jq -r .total_changed)" = "2" ]
  [ "$(echo "$output" | jq -r .recommendation)" = "split — mover ficheros ajenos a commit separado" ]
}

@test "check: --verdict gana sobre --json si va después, y al revés" {
  r="$TMPD/r"; _repo "$r"; _spec "$r"
  _commit "$r" docs/a.md
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --json --verdict
  [ "$output" = "EXTRA_FILES" ]
  run run_in "$r" --spec "$r/spec.md" --base HEAD~1 --head HEAD --verdict --json
  [ "$(echo "$output" | jq -r .verdict)" = "EXTRA_FILES" ]
}

@test "check: --help de scope-creep-check sale 0" {
  run bash "$ABS_CHECK" -h
  [ "$status" -eq 0 ]
}
