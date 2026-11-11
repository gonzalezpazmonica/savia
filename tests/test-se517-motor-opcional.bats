#!/usr/bin/env bats
# SE-517 D9: coherencia de la spec aprobada con motor opcional por persona.
# Fallos que cubre (revisión #1530): AC-21/escena 6 exigían «perfiles» que el
# diseño (una configuración y una credencial por instalación) no admite; el texto
# de S1 sonaba a autorización saltándose el prototipo S0.
# Ref: docs/specs/SE-517-space-motor-suscripcion-chatgpt-oauth.spec.md

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  SPEC="docs/specs/SE-517-space-motor-suscripcion-chatgpt-oauth.spec.md"
  [ -f "$SPEC" ]
}

@test "AC-21 habla de instalaciones, no de perfiles" {
  line=$(grep -F '**AC-21**' "$SPEC")
  [ -n "$line" ]
  [[ "$line" == *"dos instalaciones independientes"* ]]
  [[ "${line,,}" != *"perfil"* ]]
}

@test "la única mención de perfiles es D9, que los descarta" {
  n=$(grep -ci 'perfil' "$SPEC")
  [ "$n" -eq 1 ]
  grep -i 'perfil' "$SPEC" | grep -q 'no tiene perfiles dentro de una misma instalación'
}

@test "D9 define «cada persona» como «cada instalación»" {
  grep -q '«Cada persona» significa «cada instalación»' "$SPEC"
}

@test "AC-21 tiene caso negativo: sin elección no se usa la sesión ajena" {
  grep -F '**AC-21**' "$SPEC" | grep -q 'elige un motor en Ajustes > Motor'
}

@test "S1 sigue bloqueado por la confirmación de S0 y no dice «puede empezar»" {
  run grep -c 'S1 puede empezar' "$SPEC"
  [ "$output" = "0" ]
  grep -q 'sigue bloqueado por la confirmación del prototipo S0' "$SPEC"
}

@test "el gate de comprensión exige de verdad S0 para poner S1 en curso" {
  grep -q 'requerida para poner en curso S1 o posteriores' scripts/comprehension-gate.py
}

@test "S1 y Riesgos reconocen un posible valor por defecto previo (AC-20)" {
  grep -F '| S1 |' "$SPEC" | grep -q 'lo retira'
  grep -q 'ya trae hoy un proveedor o modelo por defecto' "$SPEC"
}

@test "planning no promete formalizar una aprobación ya escrita" {
  run grep -c 'se formaliza al fusionar' docs/propuestas/planning.d/SE-517.json
  [ "$output" = "0" ]
}
