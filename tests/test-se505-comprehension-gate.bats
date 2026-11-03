#!/usr/bin/env bats
# SE-505 — puerta de comprensión: specs con superficie humana exigen escenas confirmadas
# y prototipo S0 confirmado antes de S1. Cada caso negativo parte de una spec que pasa.

GATE="scripts/comprehension-gate.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$ROOT/docs/specs" "$ROOT/docs/propuestas"
  SPEC="$ROOT/docs/specs/SE-900-demo.spec.md"
  write_good "$SPEC"
}

write_good() {
  cat > "$1" <<'MD'
---
status: APPROVED
approved_at: 2026-11-05
human_surface: true
---
# SE-900 — Demo

## Lo que he entendido

### Escenas
1. Son las 8:30, abres el móvil y Savia te resume lo pendiente.
2. A mediodía le dictas una nota y la archiva en el proyecto.
3. Por la tarde te avisa de un correo que necesita respuesta.

### Palabras de la persona
> «Quiero un agente que viva y trabaje conmigo» — 2026-11-03

### Qué SÍ será
- Un agente que propone y actúa con permiso.

### Qué NO será
- Un panel de consultas por botones.

### Confirmación
- fecha: 2026-11-04
- respuesta: «Sí, eso es lo que quiero»

## Slice S0 — Prototipo navegable
- prototipo: maqueta navegable en el móvil con las tres escenas

### Confirmación del prototipo
- fecha:
- respuesta:

## Slice S1 — Producto
- código
MD
}

edit() { # edit FILE PYEXPR-sobre-s
  python3 - "$1" "$2" <<'PY'
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s = eval(expr)
open(p, "w", encoding="utf-8").write(s)
PY
}

confirm_s0() {
  edit "$SPEC" 's.replace("- fecha:\n- respuesta:\n", "- fecha: 2026-11-06\n- respuesta: «Navegado, sigue»\n")'
}

@test "spec completa y aprobada (S0 sin confirmar) pasa" {
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: comprehension-gate"* ]]
}

@test "AC-1: human_surface true sin «Lo que he entendido» falla" {
  edit "$SPEC" 's.replace("## Lo que he entendido", "## Otra cosa")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta la sección «## Lo que he entendido»"* ]]
}

@test "AC-2: confirmación con respuesta vacía falla" {
  edit "$SPEC" 's.replace("respuesta: «Sí, eso es lo que quiero»", "respuesta:")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"confirmación de las escenas vacía"* ]]
}

@test "AC-2: respuesta vacía no toma la cita de la línea siguiente" {
  edit "$SPEC" 's.replace("- respuesta: «Sí, eso es lo que quiero»", "- respuesta:\n«Sí, eso es lo que quiero»")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"confirmación de las escenas vacía"* ]]
}

@test "AC-2: confirmación de relleno («pendiente», «{…}») o sin fecha falla" {
  edit "$SPEC" 's.replace("«Sí, eso es lo que quiero»", "«pendiente»")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"confirmación de las escenas vacía"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("«Sí, eso es lo que quiero»", "«{texto literal}»")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("- fecha: 2026-11-04", "- fecha: ayer")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin «fecha: AAAA-MM-DD»"* ]]
}

@test "AC-3: dos escenas fallan, seis fallan; tres y cinco pasan (límites)" {
  edit "$SPEC" 's.replace("3. Por la tarde te avisa de un correo que necesita respuesta.\n", "")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"de 3 a 5 escenas (tiene 2)"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("3. Por la tarde", "4. a\n5. b\n6. c\n3. Por la tarde")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(tiene 6)"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("3. Por la tarde", "4. a\n5. b\n3. Por la tarde")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
}

@test "AC-3: palabras sin fecha o sin cita literal fallan" {
  edit "$SPEC" 's.replace(" — 2026-11-03", "")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cita literal «…» con fecha"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("«Quiero un agente que viva y trabaje conmigo»", "Quiere un agente")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
}

@test "AC-3: listas «Qué SÍ será» o «Qué NO será» vacías fallan" {
  edit "$SPEC" 's.replace("- Un panel de consultas por botones.\n", "")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"«### Qué NO será» vacía o ausente"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("### Qué SÍ será", "### Otra")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"«### Qué SÍ será» vacía o ausente"* ]]
}

@test "AC-4: sin human_surface en el frontmatter falla, y avisa si hay rutas" {
  edit "$SPEC" 's.replace("human_surface: true\n", "")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta «human_surface: true|false»"* ]]
  edit "$SPEC" 's + "\nToca `apps/space/main.ts`.\n"'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"hay rutas de superficie humana citadas"* ]]
}

@test "AC-4: human_surface false sin rutas pasa; con rutas exige motivo; con motivo es EXEMPT" {
  printf -- '---\nstatus: APPROVED\napproved_at: 2026-11-05\nhuman_surface: false\n---\n# backend\n' > "$SPEC"
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
  for path in 'apps/x/main.ts' 'ui/panel' 'projects/demo/src/web/index.ts' 'projects/savia-web/src/a.ts' 'projects/demo/android/' 'src/view/Home.tsx:12'; do
    printf -- '---\nstatus: APPROVED\napproved_at: 2026-11-05\nhuman_surface: false\n---\nToca `%s`.\n' "$path" > "$SPEC"
    run python3 "$GATE" --root "$ROOT"
    [ "$status" -eq 1 ] || { echo "no detectada: $path"; false; }
    [[ "$output" == *"human_surface_exempt"* ]]
  done
  printf -- '---\nstatus: APPROVED\napproved_at: 2026-11-05\nhuman_surface: false\nhuman_surface_exempt: "informe HTML interno"\n---\nToca `apps/x`.\n' > "$SPEC"
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXEMPT: comprehension-gate SE-900-demo.spec.md: informe HTML interno"* ]]
}

@test "AC-4: rutas que no son de superficie no se detectan" {
  printf -- '---\nstatus: APPROVED\napproved_at: 2026-11-05\nhuman_surface: false\n---\nToca `scripts/build-apps/x.sh` y `docs/guide.md` y `projects/soul/src/api/server.ts`.\n' > "$SPEC"
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"EXEMPT"* ]]
}

@test "AC-4: valor de human_surface no reconocido falla" {
  edit "$SPEC" 's.replace("human_surface: true", "human_surface: quizá")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"human_surface inválido"* ]]
}

@test "AC-5: falta el slice S0 o su prototipo falla" {
  edit "$SPEC" 's.replace("## Slice S0 — Prototipo navegable", "## Notas")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta «## Slice S0 — Prototipo navegable»"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("- prototipo: maqueta navegable en el móvil con las tres escenas", "- prototipo:")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no dice qué prototipo"* ]]
}

@test "AC-5: IMPLEMENTING en el frontmatter sin confirmar S0 falla; confirmado pasa" {
  edit "$SPEC" 's.replace("status: APPROVED", "status: IMPLEMENTING")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requerida para poner en curso S1"* ]]
  confirm_s0
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
}

@test "AC-5: current_slice S1 sin confirmar S0 falla; current_slice S0 pasa" {
  edit "$SPEC" 's.replace("human_surface: true", "human_surface: true\ncurrent_slice: S1")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requerida para poner en curso S1"* ]]
  edit "$SPEC" 's.replace("current_slice: S1", "current_slice: S0")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
}

@test "AC-5: IMPLEMENTING en la vista de planificación (spec APPROVED) sin confirmar S0 falla" {
  printf '{"initiatives":[{"id":"SE-900","status":"IMPLEMENTING"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requerida para poner en curso S1"* ]]
}

@test "AC-6: fuera de ámbito no se evalúa; en el límite sí" {
  printf -- '---\nstatus: APPROVED\napproved_at: 2026-11-03\nhuman_surface: true\n---\n# legado\n' > "$ROOT/docs/specs/SE-490-legado.spec.md"
  printf -- '---\nstatus: PROPOSED\nhuman_surface: true\n---\n# borrador\n' > "$ROOT/docs/specs/SE-901-borrador.spec.md"
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
  # SE-504 entra por número aunque se aprobase el 2026-11-03.
  printf -- '---\nstatus: APPROVED\napproved_at: 2026-11-03\nhuman_surface: true\n---\n# usable\n' > "$ROOT/docs/specs/SE-504-usable.spec.md"
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-504-usable.spec.md"* ]]
  rm "$ROOT/docs/specs/SE-504-usable.spec.md"
  # Número bajo aprobado desde el corte también entra.
  printf -- '---\nstatus: APPROVED\napproved_at: 2026-11-04\nhuman_surface: true\n---\n# tardía\n' > "$ROOT/docs/specs/SE-400-tardia.spec.md"
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-400-tardia.spec.md"* ]]
}

@test "AC-8: fichero o vista de planificación ilegibles fallan cerrado" {
  run python3 "$GATE" --root "$ROOT" --spec "$ROOT/docs/specs/no-existe.spec.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ilegible"* ]]
  printf 'no es json' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"estado ilegible"* ]]
}

@test "AC-7: roadmap.sh validate falla cuando la puerta falla y pasa cuando no" {
  cat > "$ROOT/docs/propuestas/planning-state.json" <<'JSON'
{"version":2,"tracked_spec_floor":900,"completion_contract_floor":900,"initiatives":[
  {"id":"SE-900","status":"APPROVED","approval":"operadora"}
]}
JSON
  printf '## 2026-11-05 SE-900 APPROVED\n\nfixture\n' > "$ROOT/docs/propuestas/LOG.md"
  run env REPO_ROOT="$ROOT" bash scripts/roadmap.sh validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: planning state consistente"* ]]
  edit "$SPEC" 's.replace("## Lo que he entendido", "## Otra cosa")'
  run env REPO_ROOT="$ROOT" bash scripts/roadmap.sh validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: comprehension-gate SE-900-demo.spec.md"* ]]
  [[ "$output" != *"PASS: planning state consistente"* ]]
}

@test "el repo real pasa la puerta (SE-505 aparece como EXEMPT)" {
  python3 scripts/planning-view.py --root . state > "$BATS_TEST_TMPDIR/state.json"
  run python3 "$GATE" --root . --state "$BATS_TEST_TMPDIR/state.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXEMPT: comprehension-gate SE-505-puerta-de-comprension.spec.md"* ]]
}
