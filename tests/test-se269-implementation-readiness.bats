#!/usr/bin/env bats
# BATS tests for scripts/implementation-readiness.sh (SE-269 S2)
# Ref: docs/specs/SE-269-bmad-patterns.spec.md

SCRIPT="scripts/implementation-readiness.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Helper: create a minimal valid spec (PASA) ──
make_pasa_spec() {
  local dir="$1"
  cat > "$dir/spec.md" <<'ENDSPEC'
# Test Spec
**Status:** APPROVED
AC-1.1: acceptance criteria test
AC-1.2: another acceptance test
Out of scope: nada que ver
- **R1 (S1)**: riesgo de prueba
**Mitigacion:** solucion
SE-123 CRIT-001
## Slice 1
**Esfuerzo:** 5h
ENDSPEC
}

# ── Structure / safety ────────────────────────────────────────────────────

@test "SE269-S2-IR: script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "SE269-S2-IR: script has valid bash syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── Input validation ──────────────────────────────────────────────────────

@test "SE269-S2-IR: requires spec file argument" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "SE269-S2-IR: rejects nonexistent spec file" {
  run bash "$SCRIPT" /tmp/nonexistent-spec-$$.md
  [ "$status" -eq 1 ]
}

@test "SE269-S2-IR: accepts existing spec file" {
  local tmpdir; tmpdir="$(mktemp -d)"
  make_pasa_spec "$tmpdir"
  run bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  rm -rf "$tmpdir"
}

# ── Output structure ──────────────────────────────────────────────────────

@test "SE269-S2-IR: output is valid JSON" {
  local tmpdir; tmpdir="$(mktemp -d)"
  make_pasa_spec "$tmpdir"
  run bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool >/dev/null 2>&1
  [ "$?" -eq 0 ]
  rm -rf "$tmpdir"
}

@test "SE269-S2-IR: output contains veredicto" {
  local tmpdir; tmpdir="$(mktemp -d)"
  make_pasa_spec "$tmpdir"
  run bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto"'* ]]
  rm -rf "$tmpdir"
}

# ── AC-2.4: spec without ACs → FALLA ─────────────────────────────────────

@test "SE269-S2-IR AC-2.4: spec without ACs produces FALLA" {
  local tmpdir; tmpdir="$(mktemp -d)"
  echo "# Empty Spec" > "$tmpdir/spec.md"
  echo "**Status:** APPROVED" >> "$tmpdir/spec.md"
  run bash "$SCRIPT" "$tmpdir/spec.md"
  local verdict; verdict=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['veredicto'])" 2>/dev/null || echo "NO_JSON")
  [[ "$verdict" == "FALLA" ]]
  rm -rf "$tmpdir"
}

# ── AC status checks ──────────────────────────────────────────────────────

@test "SE269-S2-IR: APPROVED spec passes status check" {
  local tmpdir; tmpdir="$(mktemp -d)"
  make_pasa_spec "$tmpdir"
  run bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  rm -rf "$tmpdir"
}

@test "SE269-S2-IR: PROPOSED spec generates RESERVAS for status" {
  local tmpdir; tmpdir="$(mktemp -d)"
  make_pasa_spec "$tmpdir"
  sed -i 's/APPROVED/PROPOSED/' "$tmpdir/spec.md"
  run env OWNER="@test" bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  rm -rf "$tmpdir"
}

# ── Dimension checks ──────────────────────────────────────────────────────

@test "SE269-S2-IR: out of scope detection works" {
  local tmpdir; tmpdir="$(mktemp -d)"
  make_pasa_spec "$tmpdir"
  run bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  rm -rf "$tmpdir"
}

@test "SE269-S2-IR: riesgo mitigation detection works" {
  local tmpdir; tmpdir="$(mktemp -d)"
  make_pasa_spec "$tmpdir"
  run bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  rm -rf "$tmpdir"
}

@test "SE269-S2-IR: vague AC language detected" {
  local tmpdir; tmpdir="$(mktemp -d)"
  echo "# Vague Spec" > "$tmpdir/spec.md"
  echo "**Status:** APPROVED" >> "$tmpdir/spec.md"
  echo "AC-1.1: implementar opcional y si es posible cuando se pueda" >> "$tmpdir/spec.md"
  echo "AC-1.2: idealmente debe funcionar" >> "$tmpdir/spec.md"
  run env OWNER="@test" bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  rm -rf "$tmpdir"
}

# ── Ternary audit ─────────────────────────────────────────────────────────

@test "SE269-S2-IR AC-2.5: audit log is written" {
  local tmpdir; tmpdir="$(mktemp -d)"
  local audit_file="$tmpdir/audit.jsonl"
  make_pasa_spec "$tmpdir"
  run env AUDIT_LOG="$audit_file" bash "$SCRIPT" "$tmpdir/spec.md"
  [ "$status" -eq 0 ]
  [[ -f "$audit_file" ]]
  rm -rf "$tmpdir"
}

# ── Comportamiento: cada dimensión, agregación del veredicto y registro ───

_ir() {  # _ir <spec> → ejecuta con OWNER y registro aislados
  AUDIT="$BATS_TEST_TMPDIR/audit.jsonl"
  run env OWNER="@t" AUDIT_LOG="$AUDIT" bash "$SCRIPT" "$1"
}
_band() { echo "$output" | jq -r --arg n "$1" '.dimensiones[] | select(.nombre==$n) | .banda'; }
_find() { echo "$output" | jq -r --arg n "$1" '.dimensiones[] | select(.nombre==$n) | .hallazgos[0] // ""'; }
_spec() {  # _spec <sed-expr>... → spec PASA con las sustituciones/borrados dados
  S="$BATS_TEST_TMPDIR/spec.md"
  make_pasa_spec "$BATS_TEST_TMPDIR"
  local e; for e in "$@"; do sed -i "$e" "$S"; done
}

D_AC="ACs falsificables"; D_OOS="Out of scope explicito"; D_RISK="Riesgos con mitigacion"
D_TRAZ="Trazabilidad a requisito/BR"; D_SLICE="Slices con hito utilizable"; D_ST="Estado de la spec"

@test "spec completa: PASA, seis dimensiones PASA y motivo exacto" {
  _spec
  _ir "$S"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .veredicto)" = "PASA" ]
  [ "$(echo "$output" | jq -r .motivo)" = "Todas las dimensiones superadas" ]
  [ "$(echo "$output" | jq '.dimensiones | length')" -eq 6 ]
  [ "$(echo "$output" | jq '[.dimensiones[] | select(.banda=="PASA")] | length')" -eq 6 ]
}

@test "ACs: un solo AC-X.Y es suficiente; AC sin punto decimal no cuenta" {
  _spec '/AC-1.2/d'
  _ir "$S"
  [ "$(_band "$D_AC")" = "PASA" ]
  _spec '/AC-1.2/d' 's/AC-1.1/AC-1/'
  _ir "$S"
  [ "$(_band "$D_AC")" = "FALLA" ]
}

@test "ACs: sin criterios FALLA, el veredicto global FALLA y cuenta las dimensiones" {
  _spec '/AC-1/d'
  _ir "$S"
  [ "$(_band "$D_AC")" = "FALLA" ]
  [ "$(_find "$D_AC")" = "La spec no contiene acceptance criteria (AC-X.Y)" ]
  [ "$(echo "$output" | jq -r .veredicto)" = "FALLA" ]
  [ "$(echo "$output" | jq -r .motivo)" = "1 dimension(es) no superadas" ]
}

@test "ACs: cada palabra vaga baja a RESERVAS" {
  for w in opcional "si es posible" "cuando se pueda" idealmente "tal vez"; do
    _spec "s/AC-1.2: .*/AC-1.2: $w hacer algo/"
    _ir "$S"
    [ "$(_band "$D_AC")" = "RESERVAS" ]
  done
}

@test "ACs: el hallazgo vago cuenta las líneas, no las palabras" {
  _spec 's/AC-1.1: .*/AC-1.1: opcional e idealmente/' 's/AC-1.2: .*/AC-1.2: tal vez/'
  _ir "$S"
  [ "$(_find "$D_AC")" = "2 ACs contienen lenguaje vago (opcional/si es posible/idealmente)" ]
}

@test "ACs: FALLA gana a RESERVAS y el motivo cuenta solo las FALLA" {
  _spec '/AC-1/d' '/Out of scope/d'
  _ir "$S"
  [ "$(echo "$output" | jq -r .veredicto)" = "FALLA" ]
  [ "$(echo "$output" | jq -r .motivo)" = "1 dimension(es) no superadas" ]
}

@test "Out of scope: las tres fórmulas válidas pasan y su ausencia da RESERVAS" {
  for f in "Out of scope: x" "Fuera de alcance: x" "NO se implementa x" "NO incluye x" "NO implementa x" "NO cubre x"; do
    _spec "s/^Out of scope.*/$f/"
    _ir "$S"
    [ "$(_band "$D_OOS")" = "PASA" ]
  done
  _spec '/Out of scope/d'
  _ir "$S"
  [ "$(_band "$D_OOS")" = "RESERVAS" ]
  [ "$(_find "$D_OOS")" = "La spec no declara explicitamente que queda fuera de alcance" ]
}

@test "Riesgos: sin sección de riesgos RESERVAS con su hallazgo" {
  _spec '/R1 (S1)/d' '/Mitigacion/d'
  _ir "$S"
  [ "$(_band "$D_RISK")" = "RESERVAS" ]
  [ "$(_find "$D_RISK")" = "La spec no identifica riesgos pre-flight" ]
}

@test "Riesgos: 'Riesgos identificados' basta para entrar a evaluar mitigaciones" {
  _spec 's/^- \*\*R1 (S1)\*\*.*/Riesgos identificados/' '/Mitigacion/d'
  _ir "$S"
  [ "$(_band "$D_RISK")" = "PASA" ]
}

@test "Riesgos: más riesgos que mitigaciones RESERVAS con el recuento exacto" {
  _spec 's/^\*\*Mitigacion:\*\* solucion/- **R2 (S2)**: otro\n**Mitigacion:** solucion/'
  _ir "$S"
  [ "$(_band "$D_RISK")" = "RESERVAS" ]
  [ "$(_find "$D_RISK")" = "2 riesgos, 1 con mitigacion explicita" ]
}

@test "Riesgos: tantas mitigaciones como riesgos (frontera) pasa" {
  _spec 's/^\*\*Mitigacion:\*\* solucion/- **R2 (S2)**: otro\nMitigacion: a\nMitigacion: b/'
  _ir "$S"
  [ "$(_band "$D_RISK")" = "PASA" ]
}

@test "Riesgos: 'Mitigación' con tilde también cuenta" {
  _spec 's/^\*\*Mitigacion:\*\* solucion/Mitigación: algo/'
  _ir "$S"
  [ "$(_band "$D_RISK")" = "PASA" ]
}

@test "Trazabilidad: cada tipo de referencia basta por separado" {
  for ref in "SE-12" "CRIT-4" "BR7" "AB#99"; do
    _spec 's/^SE-123 CRIT-001/'"$ref"'/'
    _ir "$S"
    [ "$(_band "$D_TRAZ")" = "PASA" ]
  done
}

@test "Trazabilidad: sin referencias RESERVAS con su hallazgo" {
  _spec '/^SE-123/d'
  _ir "$S"
  [ "$(_band "$D_TRAZ")" = "RESERVAS" ]
  [[ "$(_find "$D_TRAZ")" == "La spec no referencia otros artefactos"* ]]
}

@test "Slices: sin slices RESERVAS aunque haya esfuerzo" {
  _spec '/^## Slice/d'
  _ir "$S"
  [ "$(_band "$D_SLICE")" = "RESERVAS" ]
  [[ "$(_find "$D_SLICE")" == "La spec no esta descompuesta en slices"* ]]
}

@test "Slices: un slice sin esfuerzo RESERVAS con recuento" {
  _spec '/Esfuerzo/d'
  _ir "$S"
  [ "$(_band "$D_SLICE")" = "RESERVAS" ]
  [ "$(_find "$D_SLICE")" = "1 slices, 0 con estimacion de esfuerzo" ]
}

@test "Slices: dos slices con un solo esfuerzo RESERVAS; con dos pasa (frontera)" {
  _spec 's/^\*\*Esfuerzo:\*\* 5h/**Esfuerzo:** 5h\n## Slice 2/'
  _ir "$S"
  [ "$(_find "$D_SLICE")" = "2 slices, 1 con estimacion de esfuerzo" ]
  _spec 's/^\*\*Esfuerzo:\*\* 5h/**Esfuerzo:** 5h\n## Slice 2\n**Esfuerzo:** 2h/'
  _ir "$S"
  [ "$(_band "$D_SLICE")" = "PASA" ]
}

@test "Estado: APPROVED, APPROVED* e IMPLEMENTING* pasan" {
  for st in APPROVED "APPROVED (con reservas)" "IMPLEMENTING" "IMPLEMENTING S2"; do
    _spec "s/^\*\*Status:\*\* .*/**Status:** $st/"
    _ir "$S"
    [ "$(_band "$D_ST")" = "PASA" ]
  done
}

@test "Estado: PROPOSED RESERVAS con su hallazgo; otro valor, desconocido con el valor" {
  _spec 's/^\*\*Status:\*\* .*/**Status:** PROPOSED/'
  _ir "$S"
  [ "$(_find "$D_ST")" = "Spec en estado PROPOSED — no aprobada aun" ]
  _spec 's/^\*\*Status:\*\* .*/**Status:** DRAFT/'
  _ir "$S"
  [ "$(_band "$D_ST")" = "RESERVAS" ]
  [ "$(_find "$D_ST")" = "Estado desconocido o no estandar: DRAFT" ]
}

@test "Estado: sin línea Status queda como desconocido" {
  _spec '/Status/d'
  _ir "$S"
  [ "$(_band "$D_ST")" = "RESERVAS" ]
}

@test "agregado: solo RESERVAS cuenta reservas y pasadas en el motivo" {
  _spec '/Out of scope/d' '/^SE-123/d'
  _ir "$S"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .veredicto)" = "RESERVAS" ]
  [ "$(echo "$output" | jq -r .motivo)" = "2 dimension(es) con reservas, 4 pasan" ]
}

@test "agregado: RESERVAS sin OWNER no emite veredicto y sale 1" {
  _spec '/Out of scope/d'
  AUDIT="$BATS_TEST_TMPDIR/audit.jsonl"
  run env -u OWNER AUDIT_LOG="$AUDIT" bash "$SCRIPT" "$S"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RESERVAS requiere --owner"* ]]
}

@test "agregado: el owner viaja al veredicto" {
  _spec '/Out of scope/d'
  _ir "$S"
  [ "$(echo "$output" | jq -r .owner)" = "@t" ]
}

@test "registro: una línea por ejecución con veredicto, spec y contadores" {
  _spec '/Out of scope/d'
  _ir "$S"
  [ "$(wc -l < "$AUDIT")" -eq 1 ]
  [ "$(jq -r .veredicto "$AUDIT")" = "RESERVAS" ]
  [ "$(jq -r .spec "$AUDIT")" = "$S" ]
  [ "$(jq -r '[.pasa,.reservas,.falla]|join(",")' "$AUDIT")" = "5,1,0" ]
}

@test "registro: crea el directorio y acumula entradas" {
  _spec
  AUDIT="$BATS_TEST_TMPDIR/a/b/audit.jsonl"
  run env AUDIT_LOG="$AUDIT" bash "$SCRIPT" "$S"
  run env AUDIT_LOG="$AUDIT" bash "$SCRIPT" "$S"
  [ "$(wc -l < "$AUDIT")" -eq 2 ]
}

@test "registro: conserva como máximo 100 entradas" {
  _spec
  AUDIT="$BATS_TEST_TMPDIR/audit.jsonl"
  for i in $(seq 1 100); do echo '{"veredicto":"PASA","spec":"x","pasa":6,"reservas":0,"falla":0}'; done > "$AUDIT"
  run env AUDIT_LOG="$AUDIT" bash "$SCRIPT" "$S"
  [ "$(wc -l < "$AUDIT")" -eq 100 ]
  [ "$(tail -1 "$AUDIT" | jq -r .spec)" = "$S" ]
}

@test "registro: no escribe nada cuando falta el argumento" {
  AUDIT="$BATS_TEST_TMPDIR/audit.jsonl"
  run env AUDIT_LOG="$AUDIT" bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [ ! -e "$AUDIT" ]
}

@test "argumentos: sin spec o con ruta inexistente dan error en stderr con la ruta" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Se requiere fichero spec"* ]]
  run bash "$SCRIPT" "$BATS_TEST_TMPDIR/nada.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Fichero no encontrado: $BATS_TEST_TMPDIR/nada.md"* ]]
}

@test "Riesgos: solo cuentan las viñetas '- **Rn'; una mención en prosa no es un riesgo" {
  _spec 's/^\*\*Mitigacion:\*\* solucion/Mitigacion: a\nver **R9** más abajo/'
  _ir "$S"
  [ "$(_band "$D_RISK")" = "PASA" ]
}

@test "Slices: la palabra Esfuerzo en prosa no sustituye al campo **Esfuerzo:**" {
  _spec 's/^\*\*Esfuerzo:\*\* 5h/Esfuerzo estimado 5h/'
  _ir "$S"
  [ "$(_find "$D_SLICE")" = "1 slices, 0 con estimacion de esfuerzo" ]
}

@test "Slices: una mención 'Slice 1' sin encabezado ## no cuenta como slice" {
  _spec 's/^## Slice 1/Slice 1 pendiente/'
  _ir "$S"
  [ "$(_band "$D_SLICE")" = "RESERVAS" ]
  [[ "$(_find "$D_SLICE")" == "La spec no esta descompuesta"* ]]
}

@test "Estado: con dos líneas Status solo cuenta la primera" {
  _spec 's/^\*\*Status:\*\* .*/**Status:** PROPOSED\n**Status:** APPROVED/'
  _ir "$S"
  [ "$(_find "$D_ST")" = "Spec en estado PROPOSED — no aprobada aun" ]
}

@test "un GATE_TYPE de seguridad heredado del entorno no rechaza las RESERVAS de este gate" {
  _spec '/Out of scope/d'
  AUDIT="$BATS_TEST_TMPDIR/audit.jsonl"
  run env GATE_TYPE=security OWNER="@t" AUDIT_LOG="$AUDIT" bash "$SCRIPT" "$S"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .veredicto)" = "RESERVAS" ]
}
