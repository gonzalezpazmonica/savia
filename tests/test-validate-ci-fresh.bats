#!/usr/bin/env bats
# SE-407 S1 — frescura de artefactos generados en validate-ci-local.sh (gate G10 de pr-plan).
# Ref: docs/specs/SE-407-consistent-state-predicate.spec.md
set -uo pipefail

SCRIPT="scripts/validate-ci-local.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
}

# Tabla falsa: nombre|comprobación|cómo regenerar (override solo para tests).
fake_table() {
  printf '%s\n' \
    "rule-manifest.json|$1|bash scripts/rule-manifest-generate.sh" \
    "settings-hooks pin|true|bash scripts/contract-pin.sh pin settings-hooks --path .claude/settings.json" \
    ".scm/sam.json|$2 # sam.py check|python3 scripts/sam.py generate" \
    "docs/propuestas/INDEX.md|true|bash scripts/propuestas-index-gen.sh" \
    "planning-state.json|true|bash scripts/roadmap.sh render"
}

@test "safety: el script mantiene set -uo pipefail" {
  grep -q "set -uo pipefail" "$REPO_ROOT/$SCRIPT"
}

@test "AC1: un artefacto desfasado hace fallar el script y nombra el artefacto y su comando" {
  run env SAVIA_FRESH_CHECKS_FOR_TESTS="$(fake_table false true)" bash "$REPO_ROOT/$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL Generado desfasado: rule-manifest.json → regenerar: bash scripts/rule-manifest-generate.sh"* ]]
  [[ "$output" == *"OK Generado al día: docs/propuestas/INDEX.md"* ]]
}

@test "AC1: varios desfasados se informan por separado" {
  run env SAVIA_FRESH_CHECKS_FOR_TESTS="$(fake_table false false)" bash "$REPO_ROOT/$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"desfasado: rule-manifest.json"* ]]
  [[ "$output" == *"desfasado: .scm/sam.json → regenerar: python3 scripts/sam.py generate"* ]]
  [ "$(grep -c '^  FAIL Generado desfasado' <<<"$output")" -eq 2 ]
}

@test "AC2: todo al día ⇒ ninguna línea de desfasado y cinco comprobaciones al día" {
  run env SAVIA_FRESH_CHECKS_FOR_TESTS="$(fake_table true true)" bash "$REPO_ROOT/$SCRIPT"
  [[ "$output" != *"Generado desfasado"* ]]
  [ "$(grep -c 'Generado al día' <<<"$output")" -eq 5 ]
}

@test "AC3: --quick omite solo sam.py check, nunca los otros cuatro" {
  run env SAVIA_FRESH_CHECKS_FOR_TESTS="$(fake_table true false)" bash "$REPO_ROOT/$SCRIPT" --quick
  [[ "$output" != *".scm/sam.json"* ]]
  [ "$(grep -c 'Generado al día' <<<"$output")" -eq 4 ]
  run env SAVIA_FRESH_CHECKS_FOR_TESTS="$(fake_table false true)" bash "$REPO_ROOT/$SCRIPT" --quick
  [ "$status" -ne 0 ]
  [[ "$output" == *"desfasado: rule-manifest.json"* ]]
}

@test "la tabla por defecto ejecuta los cinco --check existentes, sin reimplementarlos" {
  for c in "rule-manifest-generate.sh --check" "contract-pin.sh check settings-hooks" "sam.py check" \
           "propuestas-index-gen.sh --check" "roadmap.sh validate"; do
    grep -qF "$c" "$REPO_ROOT/$SCRIPT"
  done
}

@test "edge: empty override ⇒ cero comprobaciones de frescura, sin error del script" {
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=" " bash "$REPO_ROOT/$SCRIPT" --quick
  [[ "$output" != *"Generado"* ]]
  [[ "$output" == *"Results:"* ]]
}

@test "integración: en un clon con INDEX.md y rule-manifest desfasados, los detecta con las comprobaciones reales" {
  git clone -q --shared --depth 1 "file://$REPO_ROOT" "$TMP/repo"
  # Copia de trabajo: el script y sus dependencias son los del working tree (incluye cambios sin commit).
  cp "$REPO_ROOT/$SCRIPT" "$TMP/repo/$SCRIPT"
  printf '\n<!-- desfase de prueba -->\n' >> "$TMP/repo/docs/propuestas/INDEX.md"
  printf '# Regla de prueba\n\nTexto.\n' > "$TMP/repo/docs/rules/domain/zz-regla-de-prueba.md"
  run bash -c "cd '$TMP/repo' && bash $SCRIPT --quick"
  [ "$status" -ne 0 ]
  [[ "$output" == *"desfasado: docs/propuestas/INDEX.md → regenerar: bash scripts/propuestas-index-gen.sh"* ]]
  [[ "$output" == *"desfasado: rule-manifest.json → regenerar: bash scripts/rule-manifest-generate.sh"* ]]
  [[ "$output" == *"OK Generado al día: settings-hooks pin"* ]]
}

# ── --fresh-only: lo que ejecuta la CI (el hueco de #1401: el --check solo corría en local) ──
@test "fresh-only: un artefacto desfasado sale con 1 y nombra artefacto y comando" {
  run env SAVIA_FRESH_CHECKS_FOR_TESTS="$(fake_table false true)" bash "$REPO_ROOT/$SCRIPT" --fresh-only --quick
  [ "$status" -eq 1 ]
  [[ "$output" != *"Results:"* ]]
  [[ "$output" == *"FAIL Generado desfasado: rule-manifest.json → regenerar: bash scripts/rule-manifest-generate.sh"* ]]
}

@test "fresh-only: todo al día sale con 0 y no ejecuta las demás comprobaciones" {
  run env SAVIA_FRESH_CHECKS_FOR_TESTS="$(fake_table true true)" bash "$REPO_ROOT/$SCRIPT" --fresh-only --quick
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS Generado al día: rule-manifest.json"* ]]
  [[ "$output" != *"Results:"* ]]
}

@test "fresh-only: fail-closed, sin ninguna comprobación no da OK" {
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=" " bash "$REPO_ROOT/$SCRIPT" --fresh-only --quick
  [ "$status" -eq 1 ]
}

@test "fresh-only: en un clon con rule-manifest desfasado falla con la comprobación real" {
  git clone -q --shared --depth 1 "file://$REPO_ROOT" "$TMP/repo"
  cp "$REPO_ROOT/$SCRIPT" "$TMP/repo/$SCRIPT"
  printf '# Regla de prueba\n\nTexto.\n' > "$TMP/repo/docs/rules/domain/zz-regla-de-prueba.md"
  run bash -c "cd '$TMP/repo' && bash $SCRIPT --fresh-only --quick"
  [ "$status" -eq 1 ]
  [[ "$output" != *"Results:"* ]]
  [[ "$output" == *"desfasado: rule-manifest.json"* ]]
}

@test "la CI ejecuta --fresh-only (sin el paso, un artefacto desfasado llega a main)" {
  grep -qE "^[[:space:]]+run: bash scripts/validate-ci-local\.sh --fresh-only" "$REPO_ROOT/.github/workflows/ci.yml"
}

# ── SE-425: lockfiles versionados (scripts/ y projects/savia-vaults/) ─────
# Directorio npm mínimo: package.json y un lock cuya raíz declara `lockdeps` como dependencias.
lock_dir() {
  local d="$TMP/$1" deps="$2" lockdeps="$3"
  mkdir -p "$d"
  printf '{"name":"x","version":"1.0.0","dependencies":%s}\n' "$deps" > "$d/package.json"
  [[ -n "$lockdeps" ]] && printf '{"name":"x","version":"1.0.0","lockfileVersion":3,"packages":{"":{"name":"x","version":"1.0.0","dependencies":%s}}}\n' "$lockdeps" > "$d/package-lock.json"
  echo "$d"
}

@test "SE-425 AC1: lock coherente ⇒ al día; desfasado o ausente ⇒ aviso con el comando, sin bloquear" {
  ok=$(lock_dir ok '{"yargs":"17.7.2"}' '{"yargs":"17.7.2"}')
  drift=$(lock_dir drift '{"yargs":"17.7.1"}' '{"yargs":"17.7.2"}')
  none=$(lock_dir none '{"yargs":"17.7.2"}' '')
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=" " SAVIA_LOCK_DIRS_FOR_TESTS="$ok $drift $none" bash "$REPO_ROOT/$SCRIPT" --quick
  [[ "$output" == *"OK Lockfile al día: $ok"* ]]
  [[ "$output" == *"WARN Lockfile desfasado: $drift/package.json cambió sin su lock → npm install --package-lock-only --prefix $drift"* ]]
  [[ "$output" == *"WARN Lockfile ausente: $none/package-lock.json"* ]]
  [[ "$output" != *"FAIL Lockfile"* ]]
}

@test "SE-425 edge: un directorio sin package.json se ignora; lock ilegible ⇒ desfasado, no error del script" {
  mkdir -p "$TMP/vacio"
  bad=$(lock_dir bad '{"a":"1.0.0"}' '{"a":"1.0.0"}')
  printf 'no es json' > "$bad/package-lock.json"
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=" " SAVIA_LOCK_DIRS_FOR_TESTS="$TMP/vacio $bad" bash "$REPO_ROOT/$SCRIPT" --quick
  [[ "$output" != *"vacio"* ]]
  [[ "$output" == *"WARN Lockfile desfasado: $bad/package.json"* ]]
  [[ "$output" == *"Results:"* ]]
}

@test "SE-425 AC1: los dos lockfiles versionados están al día y fuera del .gitignore" {
  run bash "$REPO_ROOT/$SCRIPT" --quick
  [[ "$output" == *"OK Lockfile al día: scripts"* ]]
  [[ "$output" == *"OK Lockfile al día: projects/savia-vaults"* ]]
  for f in scripts/package-lock.json projects/savia-vaults/package-lock.json; do
    run git -C "$REPO_ROOT" check-ignore -q "$f"
    [ "$status" -ne 0 ]
  done
  run git -C "$REPO_ROOT" check-ignore -q projects/savia-web/package-lock.json
  [ "$status" -eq 0 ] # D2: el resto sigue ignorado hasta que se toque
}

@test "SE-425 AC1: npm ci rechaza un package.json que no coincide con el lock (sin red)" {
  command -v npm >/dev/null || skip "npm no disponible"
  mkdir -p "$TMP/ci"
  cp "$REPO_ROOT/scripts/package-lock.json" "$TMP/ci/"
  sed 's/"yargs": "17.7.2"/"yargs": "17.7.1"/' "$REPO_ROOT/scripts/package.json" > "$TMP/ci/package.json"
  run bash -c "cd '$TMP/ci' && npm ci --offline --ignore-scripts --no-audit --no-fund"
  [ "$status" -ne 0 ]
  [[ "$output" == *"in sync"* ]]
}

@test "SE-425 AC2: la CI instala con npm ci, audita el lock versionado y ejecuta la suite de savia-vaults" {
  ci="$REPO_ROOT/.github/workflows/ci.yml"
  run grep -qE "npm install --prefix scripts|package-lock-only" "$ci"
  [ "$status" -ne 0 ]
  [ "$(grep -c 'npm ci --prefix scripts' "$ci")" -ge 2 ]
  grep -q "npm audit --prefix projects/savia-vaults" "$ci"
  grep -q "savia-vaults:" "$ci"
  grep -q "npx vitest run" "$ci"
}

@test "SE-425 G7: el email público del aviso deprecated de npm no bloquea; cualquier otro email sí" {
  mkdir -p "$TMP/scan/scripts"
  cp "$REPO_ROOT/scripts/confidentiality-scan.sh" "$TMP/scan/scripts/"
  printf '# vacía\n' > "$TMP/scan/scripts/confidentiality-allowlist.txt"
  : > "$TMP/scan/blocklist.txt"
  git -C "$TMP/scan" init -q
  printf '{"deprecated": "contact i@izs.me"}\n' > "$TMP/scan/package-lock.json"
  git -C "$TMP/scan" add package-lock.json
  run bash "$TMP/scan/scripts/confidentiality-scan.sh" --staged --blocklist "$TMP/scan/blocklist.txt"
  [[ "$output" != *"FAIL i@izs.me"* ]]
  printf '{"deprecated": "contact persona@correo-real.es"}\n' >> "$TMP/scan/package-lock.json"
  git -C "$TMP/scan" add package-lock.json
  run bash "$TMP/scan/scripts/confidentiality-scan.sh" --staged --blocklist "$TMP/scan/blocklist.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL persona@correo-real.es"* ]]
}

# ── Revisión independiente de #1421 ──
@test "fresh-only: el veredicto no usa tuberías hacia grep -q (SIGPIPE + pipefail daba falso verde)" {
  run grep -nE '\|[[:space:]]*grep -q' <(sed -n '/^if \$FRESH_ONLY/,/^fi$/p' "$REPO_ROOT/$SCRIPT")
  [ "$status" -eq 1 ]
}

@test "fresh-only: un FAIL entre muchas comprobaciones nunca da OK (50 repeticiones)" {
  table="$(printf 'a|false|regen-a\n'; for n in $(seq 1 30); do printf 'p%s|true|x\n' "$n"; done)"
  for _ in $(seq 1 50); do
    run env SAVIA_FRESH_CHECKS_FOR_TESTS="$table" bash "$REPO_ROOT/$SCRIPT" --fresh-only --quick
    [ "$status" -eq 1 ]
  done
}

@test "fresh-only: una comprobación que muere sin dejar resultado no da OK (fail-closed por recuento)" {
  # El check mata su subshell contenedor: sin fichero 8-fresh-N para esa fila.
  table="$(printf 'ok|true|x\nmuere|kill -9 $PPID|x\n')"
  run env SAVIA_FRESH_CHECKS_FOR_TESTS="$table" bash "$REPO_ROOT/$SCRIPT" --fresh-only --quick
  [ "$status" -eq 1 ]
}

@test "CI: la tabla de comprobaciones no se sobrescribe por entorno fuera de bats" {
  table="fake-artefacto|false|regen-fake"
  run env -u BATS_VERSION CI=true SAVIA_FRESH_CHECKS_FOR_TESTS="$table" bash "$REPO_ROOT/$SCRIPT" --fresh-only --quick
  [[ "$output" != *"fake-artefacto"* ]]
  # Con bats sigue siendo posible (las pruebas dependen de ello).
  run env CI=true BATS_VERSION=1 SAVIA_FRESH_CHECKS_FOR_TESTS="$table" bash "$REPO_ROOT/$SCRIPT" --fresh-only --quick
  [[ "$output" == *"FAIL Generado desfasado: fake-artefacto"* ]]
}

@test "CI: el paso --fresh-only no es opcional (sin continue-on-error ni if) y esta suite se ejecuta en CI" {
  ci="$REPO_ROOT/.github/workflows/ci.yml"
  step="$(awk '/- name: Generated artifacts fresh/{f=1;print;next} f&&/^      - name:/{exit} f' "$ci")"
  [[ "$step" == *"run: bash scripts/validate-ci-local.sh --fresh-only"* ]]
  [[ "$step" != *"continue-on-error"* ]]
  [[ "$step" != *"if:"* ]]
  grep -qE '^[[:space:]]+run: bats .*tests/test-validate-ci-fresh\.bats' "$ci"
}
