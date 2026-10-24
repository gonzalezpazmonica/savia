#!/usr/bin/env bats
# SE-379 — cada fixture rompe exactamente una invariante; ok pasa limpio.
SCRIPT="scripts/release-invariants.sh"
FX="tests/fixtures/release-invariants"

@test "SE-379: fixture ok pasa sin fallos" {
  run bash "$SCRIPT" --root "$FX/ok"
  [ "$status" -eq 0 ]
}

@test "SE-379: fixture version-regression detecta VERSION_REGRESSION" {
  run bash "$SCRIPT" --root "$FX/version-regression"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: VERSION_REGRESSION"* ]]
}

@test "SE-379: fixture changelog-mismatch detecta CHANGELOG_VERSION_MISMATCH" {
  run bash "$SCRIPT" --root "$FX/changelog-mismatch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: CHANGELOG_VERSION_MISMATCH"* ]]
}

@test "SE-379: fixture stale-counter detecta CAPABILITY_COUNT_MISMATCH" {
  run bash "$SCRIPT" --root "$FX/stale-counter"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: CAPABILITY_COUNT_MISMATCH"* ]]
}

@test "SE-379: fixture stale-translation detecta STALE_TRANSLATION" {
  run bash "$SCRIPT" --root "$FX/stale-translation"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: STALE_TRANSLATION"* ]]
}

@test "SE-379: fixture roadmap-drift detecta ROADMAP_TIMESTAMP_DRIFT" {
  run bash "$SCRIPT" --root "$FX/roadmap-drift"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: ROADMAP_TIMESTAMP_DRIFT"* ]]
}

@test "SE-379: fixture view-drift detecta GENERATED_VIEW_DRIFT" {
  run bash "$SCRIPT" --root "$FX/view-drift"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: GENERATED_VIEW_DRIFT"* ]]
}

# --- Comportamiento: raíces temporales derivadas de la fixture ok, una rotura por caso ---

mkroot() {
  ROOT_T="$BATS_TEST_TMPDIR/root"
  cp -a "$FX/ok" "$ROOT_T"
}
fails() { grep -c '^FAIL:' <<<"$output"; }

@test "fixture ok: las seis invariantes dan PASS y ninguna FAIL ni SKIP" {
  run bash "$SCRIPT" --root "$FX/ok"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^PASS:' <<<"$output")" -eq 6 ]
  [ "$(fails)" -eq 0 ]
  [[ "$output" == *"todo consistente"* ]]
  [ "$(grep -c '^SKIP' <<<"$output")" -eq 0 ]
}

@test "regresion: GENERATED_VIEW_DRIFT compara contenido real, no falla por no poder copiar al sandbox" {
  run bash "$SCRIPT" --root "$FX/ok"
  [[ "$output" == *"PASS: GENERATED_VIEW_DRIFT"* ]]
  run bash "$SCRIPT" --root "$FX/view-drift"
  [[ "$output" == *"difiere de la regeneración"* ]]
  [[ "$output" != *"no se pudo regenerar"* ]]
}

@test "regresion: con cp -al fallando en algun directorio (otro mount) cae a cp -a y sigue comparando contenido real" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/ln"
  printf '#!/bin/sh\ncase "$1" in -al) exit 1;; esac\nexec /bin/cp "$@"\n' > "$BATS_TEST_TMPDIR/bin/cp"
  chmod +x "$BATS_TEST_TMPDIR/bin/ln" "$BATS_TEST_TMPDIR/bin/cp"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$SCRIPT" --root "$FX/ok"
  [[ "$output" == *"PASS: GENERATED_VIEW_DRIFT"* ]]
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$SCRIPT" --root "$FX/view-drift"
  [[ "$output" == *"difiere de la regeneración"* ]]
  [[ "$output" != *"no se pudo regenerar"* ]]
}

@test "cada fixture rota falla solo su invariante (sin fallos espurios del sandbox)" {
  for f in version-regression changelog-mismatch stale-translation roadmap-drift view-drift; do
    run bash "$SCRIPT" --root "$FX/$f"
    [ "$status" -eq 1 ]
    [ "$(fails)" -eq 1 ]
    [[ "$output" == *"1 invariante(s) rota(s)"* ]]
  done
  # stale-counter rompe el README y por arrastre la traduccion queda distinta: 2, no 3
  run bash "$SCRIPT" --root "$FX/stale-counter"
  [ "$(fails)" -eq 2 ]
  [[ "$output" == *"FAIL: CAPABILITY_COUNT_MISMATCH"* && "$output" == *"FAIL: STALE_TRANSLATION"* ]]
}

@test "VERSION_REGRESSION nombra la version duplicada" {
  run bash "$SCRIPT" --root "$FX/version-regression"
  [[ "$output" == *"FAIL: VERSION_REGRESSION: versiones duplicadas en CHANGELOG: 1.0.1"* ]]
}

@test "CHANGELOG_VERSION_MISMATCH informa ambas versiones" {
  run bash "$SCRIPT" --root "$FX/changelog-mismatch"
  [[ "$output" == *"CHANGELOG=1.0.1 package.json=9.9.9"* ]]
}

@test "package.json sin campo version no falla la comparacion" {
  mkroot
  echo '{}' > "$ROOT_T/package.json"
  run bash "$SCRIPT" --root "$ROOT_T"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: CHANGELOG_VERSION_MISMATCH"* ]]
}

@test "raiz sin ficheros: todo SKIP y exit 0" {
  mkdir -p "$BATS_TEST_TMPDIR/vacia"
  run bash "$SCRIPT" --root "$BATS_TEST_TMPDIR/vacia"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^SKIP' <<<"$output")" -eq 5 ]
  [ "$(fails)" -eq 0 ]
}

@test "README sin linea de contadores canonica falla STALE_COUNTER" {
  mkroot
  echo "sin contadores" > "$ROOT_T/README.md"
  run bash "$SCRIPT" --root "$ROOT_T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: STALE_COUNTER"* ]]
}

@test "contador de hooks se cuenta desde settings.json (2 hooks reales vs README=1)" {
  mkroot
  echo '{"hooks":{"Stop":[{"hooks":[{"command":"a"},{"command":"b"}]}]}}' > "$ROOT_T/.claude/settings.json"
  run bash "$SCRIPT" --root "$ROOT_T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAPABILITY_COUNT_MISMATCH: README=(1 1 1 1) disco=(1 1 1 2)"* ]]
}

@test "contador de comandos, agentes y skills tambien detectan desfase" {
  mkroot
  : > "$ROOT_T/.opencode/commands/b.md"
  run bash "$SCRIPT" --root "$ROOT_T"
  [[ "$output" == *"disco=(2 1 1 1)"* ]]
  : > "$ROOT_T/.opencode/agents/b.md"
  mkdir "$ROOT_T/.claude/skills/b"
  run bash "$SCRIPT" --root "$ROOT_T"
  [[ "$output" == *"disco=(2 2 2 1)"* ]]
}

@test "traduccion desfasada se nombra con sus numeros; traduccion al dia no falla" {
  run bash "$SCRIPT" --root "$FX/stale-translation"
  [[ "$output" == *"FAIL: STALE_TRANSLATION: README."*"(7 1 1 1)"* ]]
  mkroot
  cp "$ROOT_T/README.md" "$ROOT_T/README.pt.md"
  run bash "$SCRIPT" --root "$ROOT_T"
  [[ "$output" == *"PASS: STALE_TRANSLATION"* ]]
}

@test "traduccion gl y pt tambien se vigilan" {
  mkroot
  echo "9 comandos · 1 agentes · 1 skills · 1 hooks" > "$ROOT_T/README.gl.md"
  run bash "$SCRIPT" --root "$ROOT_T"
  [[ "$output" == *"STALE_TRANSLATION: README.gl.md(9 1 1 1)"* ]]
}

@test "ROADMAP menciona el año de la version vigente: PASS; sin el año: FAIL con el año" {
  mkroot
  echo "roadmap 2019" > "$ROOT_T/docs/ROADMAP.md"
  run bash "$SCRIPT" --root "$ROOT_T"
  [[ "$output" == *"FAIL: ROADMAP_TIMESTAMP_DRIFT"*"2026"* ]]
  echo "hito 2026" > "$ROOT_T/docs/ROADMAP.md"
  run bash "$SCRIPT" --root "$ROOT_T"
  [[ "$output" == *"PASS: ROADMAP_TIMESTAMP_DRIFT"* ]]
}

@test "registry.json desfasado falla GENERATED_VIEW_DRIFT aunque INDEX.scm coincida" {
  mkroot
  echo '{"a":1}' > "$ROOT_T/.scm/registry.json"
  run bash "$SCRIPT" --root "$ROOT_T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"registry.json difiere"* ]]
}

@test "generador que no produce INDEX.scm falla con no se pudo regenerar" {
  mkroot
  printf '#!/usr/bin/env python3\n' > "$ROOT_T/scripts/generate-capability-map.py"
  run bash "$SCRIPT" --root "$ROOT_T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se pudo regenerar en sandbox"* ]]
}

@test "traduccion pt desfasada tambien falla" {
  mkroot
  echo "3 comandos · 1 agentes · 1 skills · 1 hooks" > "$ROOT_T/README.pt.md"
  run bash "$SCRIPT" --root "$ROOT_T"
  [[ "$output" == *"STALE_TRANSLATION: README.pt.md(3 1 1 1)"* ]]
}

@test "un fichero suelto en .claude/skills no cuenta como skill (solo directorios)" {
  mkroot
  : > "$ROOT_T/.claude/skills/README.md"
  run bash "$SCRIPT" --root "$ROOT_T"
  [ "$status" -eq 0 ]
}

@test "ficheros no .md en commands y agents no cuentan" {
  mkroot
  : > "$ROOT_T/.opencode/commands/notas.txt"
  : > "$ROOT_T/.opencode/agents/notas.txt"
  run bash "$SCRIPT" --root "$ROOT_T"
  [ "$status" -eq 0 ]
}
