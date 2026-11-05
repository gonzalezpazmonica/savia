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
  edit "$SPEC" 's.replace("- fecha:\n- respuesta:\n", "- fecha: 2026-11-05\n- respuesta: «Navegado, sigue»\n")'
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
  run python3 "$GATE" --root "$ROOT" --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"DECLARED-FALSE: comprehension-gate SE-900-demo.spec.md"* ]]
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

@test "revisión: iniciativa en ámbito de la vista con spec de nombre no estándar se evalúa por evidence" {
  printf -- '---\nstatus: APPROVED\nhuman_surface: true\n---\n# app\n' > "$ROOT/docs/specs/SE-906-app.md"
  printf '{"initiatives":[{"id":"SE-906","status":"APPROVED","evidence":"docs/specs/SE-906-app.md"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: comprehension-gate SE-906-app.md: falta la sección «## Lo que he entendido»"* ]]
}

@test "revisión: evidence fuera de los globs (prefijo SPEC-, otra carpeta) también se evalúa" {
  mkdir -p "$ROOT/docs/otras"
  printf -- '---\nstatus: APPROVED\nhuman_surface: true\n---\n# app\n' > "$ROOT/docs/otras/SPEC-app.md"
  printf '{"initiatives":[{"id":"SE-906","status":"IMPLEMENTING","evidence":"docs/otras/SPEC-app.md"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: comprehension-gate SPEC-app.md"* ]]
}

@test "revisión: iniciativa en ámbito sin spec localizable falla; fuera de ámbito o PROPOSED no" {
  printf '{"initiatives":[{"id":"SE-907","status":"APPROVED","evidence":"docs/specs/no-existe.md"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-907 está APPROVED en la vista de planificación pero no hay spec localizable"* ]]
  printf '{"initiatives":[{"id":"SE-907","status":"PROPOSED"},{"id":"SE-400","status":"APPROVED"},{"id":"SE-900","status":"APPROVED"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: comprehension-gate"* ]]
}

@test "revisión: spec en un subdirectorio de docs/specs se evalúa" {
  mkdir -p "$ROOT/docs/specs/space"
  printf -- '---\nstatus: APPROVED\nhuman_surface: true\n---\n# sub\n' > "$ROOT/docs/specs/space/SE-908-sub.spec.md"
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-908-sub.spec.md"* ]]
}

@test "revisión: ID con ceros a la izquierda casa con la vista normalizada" {
  mv "$SPEC" "$ROOT/docs/specs/SE-0900-demo.spec.md"
  printf '{"initiatives":[{"id":"SE-900","status":"IMPLEMENTING"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requerida para poner en curso S1"* ]]
}

@test "revisión: roadmap.sh validate muestra EXEMPT en su salida (CI con --quiet)" {
  printf -- '---\nstatus: APPROVED\napproved_at: 2026-11-05\nhuman_surface: false\nhuman_surface_exempt: "informe HTML interno"\n---\nToca `apps/x`.\n' > "$SPEC"
  cat > "$ROOT/docs/propuestas/planning-state.json" <<'JSON'
{"version":2,"tracked_spec_floor":900,"completion_contract_floor":900,"initiatives":[
  {"id":"SE-900","status":"APPROVED","approval":"operadora"}
]}
JSON
  printf '## 2026-11-05 SE-900 APPROVED\n\nfixture\n' > "$ROOT/docs/propuestas/LOG.md"
  run env REPO_ROOT="$ROOT" bash scripts/roadmap.sh validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXEMPT: comprehension-gate SE-900-demo.spec.md: informe HTML interno"* ]]
}

@test "revisión: secciones dentro de un bloque de código cercado no cuentan" {
  edit "$SPEC" 's.replace("## Lo que he entendido", "```markdown\n## Lo que he entendido").replace("## Slice S0", "```\n\n## Slice S0")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta la sección «## Lo que he entendido»"* ]]
}

@test "revisión: current_slice S01, S1a, S1.2 o S2-api cuentan como en curso; S0 no" {
  for sl in S01 S1a S1.2 S2-api s1; do
    write_good "$SPEC"
    edit "$SPEC" "s.replace('human_surface: true', 'human_surface: true\ncurrent_slice: $sl')"
    run python3 "$GATE" --root "$ROOT"
    [ "$status" -eq 1 ] || { echo "no detectado: $sl"; false; }
    [[ "$output" == *"requerida para poner en curso S1"* ]]
  done
  write_good "$SPEC"
  edit "$SPEC" 's.replace("human_surface: true", "human_surface: true\ncurrent_slice: S0-maqueta")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
}

@test "revisión: frontmatter sin cerrar en ámbito falla; comentario YAML tras el estado no lo oculta" {
  edit "$SPEC" 's.replace("human_surface: true\n---\n", "human_surface: true\n", 1)'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"frontmatter sin cerrar"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("status: APPROVED", "status: APPROVED  # nota").replace("## Lo que he entendido", "## Otra")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta la sección «## Lo que he entendido»"* ]]
}

@test "revisión: con claves repetidas manda la primera (como grep -m1 de roadmap.sh)" {
  edit "$SPEC" 's.replace("human_surface: true\n", "human_surface: true\nhuman_surface: false\n").replace("## Lo que he entendido", "## Otra")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta la sección «## Lo que he entendido»"* ]]
}

@test "revisión: confirmación fechada antes de las palabras de la persona falla; el mismo día pasa" {
  edit "$SPEC" 's.replace("- fecha: 2026-11-04", "- fecha: 2026-11-02")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"anterior a las palabras de la persona (2026-11-03)"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("- fecha: 2026-11-04", "- fecha: 2026-11-03")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
}

@test "revisión 2: evidence que no es spec no se evalúa si la spec real está en los globs" {
  mkdir -p "$ROOT/scripts"
  printf 'print(1)\n' > "$ROOT/scripts/foo.py"
  printf '# registro\n' > "$ROOT/docs/propuestas/LOG.md"
  for ev in scripts/foo.py docs/propuestas/LOG.md; do
    printf '{"initiatives":[{"id":"SE-900","status":"IMPLEMENTED","evidence":"%s"}]}' "$ev" > "$ROOT/state.json"
    confirm_s0
    run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
    [ "$status" -eq 0 ] || { echo "evidence=$ev: $output"; false; }
    [[ "$output" == *"PASS: comprehension-gate"* ]]
  done
}

@test "revisión 2: evidence que no es spec y sin spec en los globs falla como no localizable" {
  mkdir -p "$ROOT/scripts"
  printf 'print(1)\n' > "$ROOT/scripts/foo.py"
  printf '{"initiatives":[{"id":"SE-910","status":"APPROVED","evidence":"scripts/foo.py"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-910 está APPROVED en la vista de planificación pero no hay spec localizable"* ]]
}

@test "revisión 3: compartir evidence genérica no oculta una iniciativa que ya inicia S1" {
  mkdir -p "$ROOT/docs/other"
  cp "$SPEC" "$ROOT/docs/other/generic.md"
  rm "$SPEC"
  printf '{"initiatives":[{"id":"SE-900","status":"APPROVED","evidence":"docs/other/generic.md"},{"id":"SE-901","status":"IMPLEMENTING","evidence":"docs/other/generic.md"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"confirmación del prototipo"* ]]
  SPEC="$ROOT/docs/other/generic.md"
  confirm_s0
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: comprehension-gate"* ]]
}

@test "revisión 2: evidence apuntando a la spec de otra iniciativa falla" {
  printf -- '---\nstatus: IMPLEMENTED\n---\n# vieja\n' > "$ROOT/docs/specs/SE-100-viejo.spec.md"
  printf '{"initiatives":[{"id":"SE-911","status":"APPROVED","evidence":"docs/specs/SE-100-viejo.spec.md"}]}' > "$ROOT/state.json"
  run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-911 está APPROVED en la vista y su evidence (docs/specs/SE-100-viejo.spec.md) es la spec de SE-100"* ]]
}

@test "revisión 2: evidence imposible como ruta (byte nulo, nombre larguísimo) no rompe la puerta" {
  long=$(printf 'x%.0s' $(seq 1 300))
  for ev in 'a\u0000b' "$long"; do
    printf '{"initiatives":[{"id":"SE-912","status":"APPROVED","evidence":"%s"}]}' "$ev" > "$ROOT/state.json"
    run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
    [ "$status" -eq 1 ] || { echo "ev=$ev: $output"; false; }
    [[ "$output" == *"SE-912 está APPROVED en la vista de planificación pero no hay spec localizable"* ]]
    [[ "$output" != *"Traceback"* ]]
  done
}

@test "revisión 2: vista con forma inesperada falla cerrado sin traceback" {
  for js in '[1,2]' '{"initiatives":[1]}' '{"initiatives":{"id":"SE-900"}}'; do
    printf '%s' "$js" > "$ROOT/state.json"
    run python3 "$GATE" --root "$ROOT" --state "$ROOT/state.json"
    [ "$status" -eq 1 ] || { echo "js=$js: $output"; false; }
    [[ "$output" == *"FAIL: comprehension-gate: estado ilegible"* ]]
    [[ "$output" != *"Traceback"* ]]
  done
}

@test "revisión 2: un «#» dentro de un valor entrecomillado se conserva" {
  edit "$SPEC" 's.replace("human_surface: true", "human_surface: false\nhuman_surface_exempt: \"informe #3\"  # nota").replace("## Lo que he entendido", "## Otra\n`apps/x/`")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXEMPT: comprehension-gate SE-900-demo.spec.md: informe #3"* ]]
}

@test "revisión 2: fecha de confirmación inexistente o futura falla; hoy pasa" {
  edit "$SPEC" 's.replace("- fecha: 2026-11-04", "- fecha: 2026-99-99")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fecha 2026-99-99 que no existe en el calendario"* ]]
  write_good "$SPEC"
  edit "$SPEC" 's.replace("- fecha: 2026-11-04", "- fecha: 2099-01-01")'
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fecha 2099-01-01 posterior a hoy"* ]]
  write_good "$SPEC"
  today=$(date +%F)
  edit "$SPEC" "s.replace('- fecha: 2026-11-04', '- fecha: $today')"
  run python3 "$GATE" --root "$ROOT"
  [ "$status" -eq 0 ]
}
