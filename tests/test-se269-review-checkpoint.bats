#!/usr/bin/env bats
# BATS tests for scripts/review-checkpoint.sh (SE-269 S3)
# Ref: docs/specs/SE-269-bmad-patterns.spec.md

SCRIPT="scripts/review-checkpoint.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Structure / safety ────────────────────────────────────────────────────

@test "SE269-S3: script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "SE269-S3: script has valid bash syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── Input validation ──────────────────────────────────────────────────────

@test "SE269-S3: requires --branch or --pr" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "SE269-S3: --branch with valid name succeeds" {
  run bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
}

@test "SE269-S3: --pr with number succeeds" {
  run bash "$SCRIPT" --pr 123
  [ "$status" -eq 0 ]
}

# ── Output structure ──────────────────────────────────────────────────────

@test "SE269-S3: output is valid JSON" {
  run bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool >/dev/null 2>&1
  [ "$?" -eq 0 ]
}

@test "SE269-S3: output contains checkpoint_id" {
  run bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"checkpoint_id"'* ]]
}

@test "SE269-S3: output contains file path" {
  run bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"file"'* ]]
}

@test "SE269-S3: output contains timestamp" {
  run bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"timestamp"'* ]]
}

# ── Package file generation ───────────────────────────────────────────────

@test "SE269-S3: generates markdown package file" {
  local output_dir; output_dir="$(mktemp -d)/review-checkpoints"
  mkdir -p "$output_dir"
  run env REVIEW_CHECKPOINT_OUTPUT_DIR="$output_dir" bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  local pkg_file; pkg_file=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])" 2>/dev/null)
  [[ -f "$pkg_file" ]]
  rm -rf "$(dirname "$output_dir")"
}

@test "SE269-S3 AC-3.2: package has 5 sections" {
  local output_dir; output_dir="$(mktemp -d)/review-checkpoints"
  mkdir -p "$output_dir"
  run env REVIEW_CHECKPOINT_OUTPUT_DIR="$output_dir" bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  local pkg_file; pkg_file=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])" 2>/dev/null)
  run grep -c "^## " "$pkg_file"
  # Should have at least 5 sections (header + 5 numbered sections)
  [[ "$output" -ge 5 ]]
  rm -rf "$(dirname "$output_dir")"
}

@test "SE269-S3: package contains section 1 (Que cambio)" {
  local output_dir; output_dir="$(mktemp -d)/review-checkpoints"
  mkdir -p "$output_dir"
  run env REVIEW_CHECKPOINT_OUTPUT_DIR="$output_dir" bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  local pkg_file; pkg_file=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])" 2>/dev/null)
  run grep -q "Que cambio" "$pkg_file"
  [ "$status" -eq 0 ]
  rm -rf "$(dirname "$output_dir")"
}

@test "SE269-S3: package contains section 2 (Orden de lectura)" {
  local output_dir; output_dir="$(mktemp -d)/review-checkpoints"
  mkdir -p "$output_dir"
  run env REVIEW_CHECKPOINT_OUTPUT_DIR="$output_dir" bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  local pkg_file; pkg_file=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])" 2>/dev/null)
  run grep -q "Orden de lectura" "$pkg_file"
  [ "$status" -eq 0 ]
  rm -rf "$(dirname "$output_dir")"
}

@test "SE269-S3: package contains section 3 (Hallazgos)" {
  local output_dir; output_dir="$(mktemp -d)/review-checkpoints"
  mkdir -p "$output_dir"
  run env REVIEW_CHECKPOINT_OUTPUT_DIR="$output_dir" bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  local pkg_file; pkg_file=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])" 2>/dev/null)
  run grep -q "Hallazgos" "$pkg_file"
  [ "$status" -eq 0 ]
  rm -rf "$(dirname "$output_dir")"
}

@test "SE269-S3: package contains section 4 (Verificacion manual)" {
  local output_dir; output_dir="$(mktemp -d)/review-checkpoints"
  mkdir -p "$output_dir"
  run env REVIEW_CHECKPOINT_OUTPUT_DIR="$output_dir" bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  local pkg_file; pkg_file=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])" 2>/dev/null)
  run grep -q "Verificacion manual" "$pkg_file"
  [ "$status" -eq 0 ]
  rm -rf "$(dirname "$output_dir")"
}

@test "SE269-S3: package contains section 5 (Cierre)" {
  local output_dir; output_dir="$(mktemp -d)/review-checkpoints"
  mkdir -p "$output_dir"
  run env REVIEW_CHECKPOINT_OUTPUT_DIR="$output_dir" bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  local pkg_file; pkg_file=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])" 2>/dev/null)
  run grep -q "Cierre" "$pkg_file"
  [ "$status" -eq 0 ]
  rm -rf "$(dirname "$output_dir")"
}

# ── Spec integration ──────────────────────────────────────────────────────

@test "SE269-S3: --spec flag is accepted" {
  run bash "$SCRIPT" --branch "agent/se269-test" --spec "docs/specs/SE-269-bmad-patterns.spec.md"
  [ "$status" -eq 0 ]
}

# ── Cierre options ────────────────────────────────────────────────────────

@test "SE269-S3: cierre section contains decision options" {
  local output_dir; output_dir="$(mktemp -d)/review-checkpoints"
  mkdir -p "$output_dir"
  run env REVIEW_CHECKPOINT_OUTPUT_DIR="$output_dir" bash "$SCRIPT" --branch "agent/se269-test"
  [ "$status" -eq 0 ]
  local pkg_file; pkg_file=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['file'])" 2>/dev/null)
  run grep -q "APROBAR\|REHACER\|SEGUIR DISCUTIENDO" "$pkg_file"
  [ "$status" -eq 0 ]
  rm -rf "$(dirname "$output_dir")"
}

# ── Comportamiento: contenido del paquete sobre un repositorio aislado ────
# El script lee `git diff HEAD~1` y escribe bajo REVIEW_CHECKPOINT_OUTPUT_DIR relativo al cwd,
# así que cada test trabaja en un repo temporal con los cambios que necesita.

_repo() {  # _repo fichero... → repo con un commit base y esos ficheros modificados sin commitear
  R="$BATS_TEST_TMPDIR/repo"; rm -rf "$R"; mkdir -p "$R"; cd "$R"
  git init -q; git config user.email t@e.invalid; git config user.name T
  echo base > base.txt; git add .; git commit -qm base
  echo base2 >> base.txt; git commit -qam base2
  local f
  for f in "$@"; do mkdir -p "$(dirname "$f")"; echo x > "$f"; done
  ABS="$BATS_TEST_DIRNAME/../scripts/review-checkpoint.sh"
}

# `! cmd` no hace fallar un test de bats (errexit lo ignora): estos helpers sí.
_absent() { if grep -q "$@"; then return 1; fi; }
_absent_in() { if printf '%s\n' "$1" | grep -q "${@:2}"; then return 1; fi; }

_gen() {  # _gen args... → ejecuta y deja PKG con el contenido del paquete
  run bash "$ABS" "$@"
  [ "$status" -eq 0 ]
  PKG=$(echo "$output" | jq -r .file)
  [ -f "$PKG" ]
}

@test "JSON de salida: id con formato ckpt-fecha, fichero bajo la carpeta por defecto y timestamp UTC" {
  _repo
  _gen --branch agent/x
  [[ "$(echo "$output" | jq -r .checkpoint_id)" =~ ^ckpt-[0-9]{8}-[0-9]{6}$ ]]
  [[ "$PKG" == output/review-checkpoints/ckpt-*.md ]]
  [[ "$(echo "$output" | jq -r .timestamp)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
}

@test "REVIEW_CHECKPOINT_OUTPUT_DIR del entorno decide dónde se escribe el paquete" {
  _repo
  REVIEW_CHECKPOINT_OUTPUT_DIR="$BATS_TEST_TMPDIR/otra/dir" _gen --branch agent/x
  [[ "$PKG" == "$BATS_TEST_TMPDIR/otra/dir/ckpt-"*.md ]]
  [ ! -d output ]
}

@test "un OUTPUT_DIR genérico heredado del entorno no redirige el paquete" {
  _repo
  OUTPUT_DIR="$BATS_TEST_TMPDIR/ajeno" _gen --branch agent/x
  [[ "$PKG" == "output/review-checkpoints/ckpt-"*.md || "$PKG" == *"/output/review-checkpoints/ckpt-"*.md ]]
  [ ! -d "$BATS_TEST_TMPDIR/ajeno" ]
}

@test "cabecera: origen es la rama o 'PR #n'; spec 'No especificada' por defecto" {
  _repo
  _gen --branch agent/mi-rama
  grep -q '^\*\*Origen:\*\* agent/mi-rama$' "$PKG"
  grep -q '^\*\*Spec:\*\* No especificada$' "$PKG"
  _gen --pr 321
  grep -q '^\*\*Origen:\*\* PR #321$' "$PKG"
}

@test "las cinco secciones aparecen numeradas y en orden" {
  _repo
  _gen --branch b
  grep -n '^## ' "$PKG" | sed 's/^[0-9]*://' > "$BATS_TEST_TMPDIR/secs"
  [ "$(cat "$BATS_TEST_TMPDIR/secs")" = "$(printf '%s\n' '## 1. Que cambio y por que' '## 2. Orden de lectura sugerido' '## 3. Hallazgos ordenados por preocupacion' '## 4. Verificacion manual' '## 5. Cierre')" ]
}

@test "sin spec: sección 1 lista el origen y los últimos commits" {
  _repo
  _gen --branch agent/x
  grep -q 'Cambio detectado desde rama: agent/x' "$PKG"
  grep -q 'base2' "$PKG"
}

@test "con --pr sin rama: sección 1 dice PR #n" {
  _repo
  _gen --pr 55
  grep -q 'Cambio detectado desde rama: PR #55' "$PKG"
}

@test "con spec: título, requisito AB# y cabecera Spec" {
  _repo
  printf '# Mi spec\n\nVinculado a AB#1234 y más\n' > s.md
  _gen --branch b --spec s.md
  grep -q 'Cambio ligado a spec: Mi spec' "$PKG"
  grep -q 'Requisito de negocio: .*AB#1234' "$PKG"
  grep -q '^\*\*Spec:\*\* s.md$' "$PKG"
  _absent 'Ultimos commits' "$PKG"
}

@test "con spec: requisito BR numérico se detecta; sin requisito no hay línea" {
  _repo
  printf '# T\nafecta a BR17\n' > s.md
  _gen --branch b --spec s.md
  grep -q 'Requisito de negocio: .*BR17' "$PKG"
  printf '# T\nsin referencias\n' > s2.md
  _gen --branch b --spec s2.md
  _absent 'Requisito de negocio' "$PKG"
}

@test "spec inexistente cae al modo sin spec" {
  _repo
  _gen --branch b --spec no-existe.md
  grep -q 'Ultimos commits' "$PKG"
}

@test "orden declarado por el autor: se copia y no se genera del diff" {
  _repo scripts/a.sh
  printf '# S\n\nOrden de lectura\n1. primero.md\n2. segundo.md\nrelleno\n' > s.md
  _gen --branch b --spec s.md
  grep -q 'ORDEN_DECLARADO_POR_AUTOR' "$PKG"
  grep -q '^1\. primero.md' "$PKG"
  grep -q '^2\. segundo.md' "$PKG"
  _absent 'ORDEN_GENERADO_DEL_DIFF' "$PKG"
}

@test "spec sin 'Orden de lectura' genera el orden del diff" {
  _repo
  printf '# S\n' > s.md
  _gen --branch b --spec s.md
  grep -q 'ORDEN_GENERADO_DEL_DIFF' "$PKG"
}

@test "orden generado: prioritarios primero, luego normales, tests al final, con numeración continua" {
  _repo docs/SPEC-9.md src/app.py tests/test-app.bats
  git add -A
  _gen --branch b
  sec=$(sed -n '/^## 2\./,/^## 3\./p' "$PKG")
  l1=$(echo "$sec" | grep -n 'SPEC-9.md' | cut -d: -f1)
  l2=$(echo "$sec" | grep -n 'src/app.py' | cut -d: -f1)
  l3=$(echo "$sec" | grep -n 'test-app.bats' | cut -d: -f1)
  [ "$l1" -lt "$l2" ]
  [ "$l2" -lt "$l3" ]
  echo "$sec" | grep -q '1\. docs/SPEC-9.md (prioritario: define el contrato)'
  echo "$sec" | grep -q '2\. base.txt$'
  echo "$sec" | grep -q '3\. src/app.py$'
  echo "$sec" | grep -q '4\. tests/test-app.bats (tests: verifica despues de entender el cambio)'
}

@test "orden generado: incluye la nota de que es automático" {
  _repo
  _gen --branch b
  grep -q 'NOTA: Este orden es generado automaticamente' "$PKG"
}

@test "hallazgos: sin ficheros de entrada dice que no hay hallazgos de seguridad ni de lógica" {
  _repo
  _gen --branch b
  grep -q 'No se encontraron hallazgos de seguridad' "$PKG"
  grep -q 'No se encontraron hallazgos de logica' "$PKG"
  grep -q '### Seguridad' "$PKG"
  grep -q '### Rendimiento' "$PKG"
  grep -q '### Logica' "$PKG"
  grep -q '### Estilo' "$PKG"
}

@test "hallazgos: output/security-findings.json se vuelca (máximo 5)" {
  _repo
  mkdir -p output
  echo '["a1","a2","a3","a4","a5","a6","a7"]' > output/security-findings.json
  _gen --branch b
  [ "$(grep -c '^  - a[0-9]' "$PKG")" -eq 5 ]
  grep -q '  - a1' "$PKG"
  _absent '  - a6' "$PKG"
}

@test "hallazgos: court-review.json solo vuelca la categoría logic" {
  _repo
  mkdir -p output
  echo '{"findings":[{"category":"logic","message":"bucle infinito"},{"category":"style","message":"espacios"}]}' > output/court-review.json
  _gen --branch b
  grep -q '  - bucle infinito' "$PKG"
  _absent 'espacios' "$PKG"
}

@test "verificación manual: sin cambios observables lo declara explícitamente" {
  _repo notas.txt; git add -A
  _gen --branch b
  grep -q 'SIN_COMPORTAMIENTO_OBSERVABLE' "$PKG"
  grep -q 'AC-3.3: prohibido inventar trabajo' "$PKG"
}

@test "verificación manual: un script .sh añade la comprobación 1 y no la declaración de vacío" {
  _repo scripts/nuevo.sh
  git add -A
  _gen --branch b
  grep -q '^1\. Ejecutar el script modificado' "$PKG"
  _absent 'SIN_COMPORTAMIENTO_OBSERVABLE' "$PKG"
}

@test "verificación manual: comando .md, config y spec activan las comprobaciones 2, 3 y 4" {
  _repo .claude/commands/x.md cfg/app.yaml docs/specs/algo.spec.md
  git add -A
  _gen --branch b
  grep -q '^2\. Invocar el comando' "$PKG"
  grep -q '^3\. Validar sintaxis del fichero de configuracion' "$PKG"
  grep -q '^4\. Leer la spec desde el principio' "$PKG"
  _absent '^1\. Ejecutar' "$PKG"
}

@test "verificación manual: json y toml también cuentan como configuración" {
  _repo a.json
  git add -A
  _gen --branch b
  grep -q '^3\. Validar sintaxis' "$PKG"
  _repo b.toml
  git add -A
  _gen --branch b
  grep -q '^3\. Validar sintaxis' "$PKG"
}

@test "verificación manual: un .sh fuera de scripts/ no cuenta como script" {
  _repo otra/cosa.sh
  git add -A
  _gen --branch b
  _absent '^1\. Ejecutar' "$PKG"
}

@test "cierre: opciones de decisión y línea de firma" {
  _repo
  _gen --branch b
  grep -q 'Opciones: \[ \] APROBAR  \[ \] REHACER  \[ \] SEGUIR DISCUTIENDO' "$PKG"
  grep -q 'Decision: ________________  Firma: ________________  Fecha: ________________' "$PKG"
}

@test "argumentos: sin origen sale 1 con mensaje y sin escribir nada" {
  _repo
  run bash "$ABS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--branch o --pr requerido"* ]]
  [ ! -d output ]
}

@test "argumentos: opción desconocida sale 1 citándola" {
  _repo
  run bash "$ABS" --raro
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: --raro"* ]]
}

@test "argumentos: --help muestra las cinco secciones y sale 1" {
  _repo
  run bash "$ABS" --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"5 secciones"* ]]
  [[ "$output" == *"5. Cierre"* ]]
}

@test "sección 1 lista hasta 5 commits recientes (no solo el último)" {
  _repo
  for i in 1 2 3 4 5 6; do git commit --allow-empty -qm "c$i"; done
  _gen --branch b
  grep -q ' c6$' "$PKG"
  grep -q ' c2$' "$PKG"
  _absent ' c1$' "$PKG"
}

@test "sin commit anterior (comportamiento actual conocido, no deseado): el orden dice 'Sin diff disponible'" {
  R="$BATS_TEST_TMPDIR/uno"; mkdir -p "$R"; cd "$R"
  git init -q; git config user.email t@e.invalid; git config user.name T
  echo a > a.txt; git add .; git commit -qm solo
  ABS="$BATS_TEST_DIRNAME/../scripts/review-checkpoint.sh"
  _gen --branch b
  sec=$(sed -n '/^## 2\./,/^## 3\./p' "$PKG")
  echo "$sec" | grep -q 'Sin diff disponible'
}

@test "diff vacío (commit sin cambios y árbol limpio): ninguna entrada numerada" {
  R="$BATS_TEST_TMPDIR/vacio"; mkdir -p "$R"; cd "$R"
  git init -q; git config user.email t@e.invalid; git config user.name T
  echo a > a.txt; git add .; git commit -qm uno; git commit --allow-empty -qm dos
  ABS="$BATS_TEST_DIRNAME/../scripts/review-checkpoint.sh"
  _gen --branch b
  sec=$(sed -n '/^## 2\./,/^## 3\./p' "$PKG")
  _absent_in "$sec" -E '^  [0-9]+\. '
}

@test "prioritarios por nombre: CRITERIO.md, *.rules.yaml y specs en minúsculas" {
  _repo CRITERIO.md reglas/a.rules.yaml docs/specs/algo.md
  git add -A
  _gen --branch b
  sec=$(sed -n '/^## 2\./,/^## 3\./p' "$PKG")
  echo "$sec" | grep -q 'CRITERIO.md (prioritario'
  echo "$sec" | grep -q 'reglas/a.rules.yaml (prioritario'
  echo "$sec" | grep -q 'docs/specs/algo.md (prioritario'
}

@test "tests por nombre: *test*, *.bats y *spec* fuera de markdown van al final" {
  _repo lib/test_helper.sh check.bats lib/spec_helper.rb
  git add -A
  _gen --branch b
  sec=$(sed -n '/^## 2\./,/^## 3\./p' "$PKG")
  echo "$sec" | grep -q 'lib/test_helper.sh (tests'
  echo "$sec" | grep -q 'check.bats (tests'
  echo "$sec" | grep -q 'lib/spec_helper.rb (tests'
}

@test "hallazgos de lógica: máximo 5 de la categoría logic" {
  _repo
  mkdir -p output
  python3 -c "
import json
print(json.dumps({'findings': [{'category': 'logic', 'message': f'hallazgo-{i}'} for i in range(1, 8)]}))" > output/court-review.json
  _gen --branch b
  [ "$(grep -c '  - hallazgo-' "$PKG")" -eq 5 ]
  _absent 'hallazgo-6' "$PKG"
}

@test "verificación manual: un .md fuera de commands/ no activa la comprobación 2" {
  _repo docs/guia.md
  git add -A
  _gen --branch b
  _absent '^2\. Invocar el comando' "$PKG"
  grep -q 'SIN_COMPORTAMIENTO_OBSERVABLE' "$PKG"
}

@test "verificación manual: cada categoría por separado evita la declaración de vacío" {
  for f in .claude/commands/x.md cfg/app.yaml docs/specs/algo.md; do
    _repo "$f"
    git add -A
    _gen --branch b
    _absent 'SIN_COMPORTAMIENTO_OBSERVABLE' "$PKG"
  done
}

@test "verificación manual: una spec en carpeta specs/ activa la comprobación 4 sin ser .spec.md" {
  _repo docs/specs/algo.md
  git add -A
  _gen --branch b
  grep -q '^4\. Leer la spec' "$PKG"
}

@test "verificación manual: una extensión que solo empieza por .md en commands/ no cuenta" {
  _repo .claude/commands/x.mdx
  git add -A
  _gen --branch b
  _absent '^2\. Invocar el comando' "$PKG"
}
