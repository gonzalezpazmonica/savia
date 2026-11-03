#!/usr/bin/env bats
# SE-496 — coherencia interna de la spec (hallazgos de la revisión de la PR #1452).
# Ref: docs/specs/SE-496-governed-operational-ontology-authority.spec.md
# Comprobador: tests/se496_spec_check.py. Cada regla tiene caso positivo
# (la spec real pasa) y caso negativo (una copia mutada falla con su motivo).
# Vive en tests/bats/ para que ci-select-bats lo elija cuando cambian la spec
# o el comprobador (rutas con "$REPO_ROOT/..." para el mapa de dependencias).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-496-governed-operational-ontology-authority.spec.md"
CHECK="$REPO_ROOT/tests/se496_spec_check.py"

setup() {
  set -uo pipefail
  MUT="$BATS_TEST_TMPDIR/spec.md"
  cp "$SPEC" "$MUT"
}

check() { python3 -I "$CHECK" "$1"; }

@test "spec real: coherente" {
  run check "$SPEC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uso: sin argumentos sale 2" {
  run python3 -I "$CHECK"
  [ "$status" -eq 2 ]
}

@test "fichero inexistente: sale 2, nunca 0" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -eq 2 ]
}

@test "R-PHASE (P1-1): F0 sin recheck deja AC-5 (D04) sin componente" {
  sed -i '/^| F0 |/s/`recheck`, //' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PHASE: AC-5 usa recheck pero F0 no lo entrega"* ]]
}

@test "R-PHASE: AC-5 movido a F0 y F2 a la vez se detecta" {
  sed -i '/^| F2 |/s/(AC-11)/(AC-11, AC-5)/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PHASE: AC-5 en 2 fases"* ]]
}

@test "R-PHASE: AC sin fase se detecta" {
  sed -i '/^| F0 |/s/, AC-13)/)/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PHASE: AC-13 en 0 fases"* ]]
}

@test "R-USES (P1-2): sin ledger de usos falla" {
  sed -i 's/^\*\*Ledger de usos/**Contador/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-USES: max_uses sin ledger definido"* ]]
}

@test "R-USES (P1-2): ledger sin creación exclusiva falla" {
  sed -i 's/O_CREAT|O_EXCL/creación normal/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-USES: el ledger no fija creación exclusiva"* ]]
}

@test "R-USES (P1-2): ledger que no dice que evaluate no consume falla" {
  sed -i '/^- `evaluate` cuenta los ficheros/s/\*\*no consume\*\*/consume/' "$MUT"
  sed -i '/^\*\*Ledger de usos/,/^En F2/s/no consume/consume/g' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-USES: el ledger no fija evaluate no consume"* ]]
}

@test "R-CODES (P2-2): código usado en la batería y ausente del orden de R3 falla" {
  sed -i '/^| 11 | Los usos registrados/d' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-CODES: MAX_USES_EXHAUSTED"* ]]
}

@test "R-BATTERY (P2-1): una fila D.. con REQUIRES_APPROVAL falla" {
  sed -i '/^| D01 |/s/`NO_CONTRACT`/`REQUIRES_APPROVAL`/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-BATTERY: fila con REQUIRES_APPROVAL"* ]]
}

@test "R-DIGEST (P2-3): state_digest sin lista de campos falla" {
  sed -i '/^\*\*`state_digest`\.\*\*/,/^El estado que ninguna/{/^- /d}' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-DIGEST: falta el campo facts"* ]]
}

@test "R-DIGEST (rev 2): volver a meter uses en el digest falla" {
  sed -i '/^- `revoked`: booleano/a - `uses`: número de usos registrados del contrato;' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-DIGEST: campo no previsto en state_digest: uses"* ]]
}

@test "R-DIGEST (rev 2): quitar facts del digest falla" {
  sed -i '/^- `facts`: valor de cada atributo/d' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-DIGEST: falta el campo facts en state_digest"* ]]
}

@test "R-DIGEST (rev 2): sin «exactamente estos campos» falla" {
  sed -i 's/con exactamente estos campos, y ningún otro/con estos campos, entre otros/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-DIGEST: state_digest sin lista cerrada de campos"* ]]
}

@test "R-EXIT (P1 rev 2): volver a decir que el JSON malformado da DENY falla" {
  sed -i 's/^- Fail-closed: .*/- Fail-closed: herramienta ausente, `origin\/main` ilegible, JSON malformado, lector que no responde o excepción → `DENY` con su código. Exit 0 solo con `ALLOW`; 1 con `DENY`; 4 con `REQUIRES_APPROVAL`; 2 si no se puede evaluar./' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-EXIT: entrada malformada con DENY"* ]]
}

@test "R-EXIT (P1 rev 2): fuente ilegible con exit 2 en la tabla falla" {
  sed -i 's/^| Una fuente no se puede leer (cualquier paso) | `DENY` | 1 |$/| Una fuente no se puede leer (cualquier paso) | `DENY` | 2 |/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-EXIT: «Una fuente no se puede leer (cualquier paso)» da DENY con exit 2"* ]]
}

@test "R-EXIT (P1 rev 2): UNKNOWN_STATE descrito con exit 2 falla" {
  sed -i 's/`DENY UNKNOWN_STATE` (exit 1)/`DENY UNKNOWN_STATE` (exit 2)/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-EXIT: UNKNOWN_STATE con exit 2"* ]]
}

@test "R-EXIT (P1 rev 2): tabla sin el caso de petición mal formada falla" {
  sed -i '/^| Petición mal formada (paso 0) |/d' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-EXIT: la tabla no fija el caso «mal formada»"* ]]
}

@test "R-EXIT (P1 rev 2): sin tabla de códigos de salida falla" {
  sed -i 's/^\*\*Códigos de salida\.\*\*/**Salidas.**/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-EXIT: falta la tabla «Códigos de salida»"* ]]
}

@test "R-CODES (P2 rev 2): STATE_CHANGED de recheck fuera del orden de R3 falla" {
  sed -i '/^| 18 | Solo `recheck`/d' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-CODES: STATE_CHANGED se usa pero no está en el orden de R3"* ]]
}

@test "R-CODES (rev 2): sección R5 renombrada no pasa en vacío" {
  sed -i 's/^### R5 /### Batería /' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-CODES: falta la sección R5"* ]]
}

@test "R-PHASE (rev 2): AC-5c usa recheck y F0 sin recheck lo detecta" {
  sed -i '/^| F0 |/s/`recheck`, //' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PHASE: AC-5c usa recheck pero F0 no lo entrega"* ]]
}

@test "R-PHASE (rev 2): AC que usa authority-exec.sh en una fase que no lo entrega falla" {
  sed -i '/^| F0 |/s/AC-12, AC-13)/AC-11, AC-12, AC-13)/; /^| F2 |/s/(AC-11)/()/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PHASE: AC-11 usa authority-exec.sh pero F0 no lo entrega"* ]]
}

@test "R-USES (rev 2): ledger en que recheck no consume falla" {
  sed -i '/^- `recheck`, si todo lo demás/s/consume un uso/registra la orden/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-USES: el ledger no fija quién consume"* ]]
}

@test "fichero no UTF-8: sale 2, no 1" {
  printf '\xff\xfe\x00spec' > "$BATS_TEST_TMPDIR/bin.md"
  run check "$BATS_TEST_TMPDIR/bin.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede leer"* ]]
}
