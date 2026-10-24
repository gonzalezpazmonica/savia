#!/usr/bin/env bats
# tests/bats/test-sdd-research-lane.bats
# SE-370 — SDD Research lane: investigación auditable como fase del flujo SDD
# Ref: docs/specs/SE-370-sdd-research-lane.spec.md
# Cubre AC-0..AC-6. Tests herméticos via SDD_RESEARCH_SPECS_DIR (no tocan docs/specs).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
LANE="$REPO_ROOT/scripts/sdd-research-lane.sh"

setup() {
  LANE_TMP="$(mktemp -d)"
  export SDD_RESEARCH_SPECS_DIR="$LANE_TMP"
}

teardown() {
  rm -rf "$LANE_TMP"
}

open_lane() {
  local change="$1" grant="documentation"
  if [[ "${2:-}" == "--grant" ]]; then
    grant="${3:-documentation}"
  elif [[ -n "${2:-}" ]]; then
    grant="$2"
  fi
  bash "$LANE" select "$change" --grant "$grant" > /dev/null
}

# ── AC-0: select requiere grant registrado (no auto) ─────────────────────────
@test "SE-370 AC-0: select sin --grant falla (el grant no es automático)" {
  run bash "$LANE" select SE-900
  [ "$status" -ne 0 ]
  [[ ! -f "$LANE_TMP/SE-900/research.md" ]]
}

@test "SE-370 AC-0: select con grant inválido falla" {
  run bash "$LANE" select SE-900 --grant full-internet
  [ "$status" -ne 0 ]
}

@test "SE-370 AC-0: select con grant registrado (documentation|open-web) abre la lane" {
  run bash "$LANE" select SE-900 --grant documentation
  [ "$status" -eq 0 ]
  grep -q -- '- scope: documentation' "$LANE_TMP/SE-900/research.md"
  grep -q -- '- granted_by: human' "$LANE_TMP/SE-900/research.md"
  run bash "$LANE" select SE-901 --grant open-web
  [ "$status" -eq 0 ]
  grep -q -- '- scope: open-web' "$LANE_TMP/SE-901/research.md"
}

# ── AC-1: log añade claim→source; sin source → PENDIENTE ─────────────────────
@test "SE-370 AC-1: log añade claim con source al artefacto" {
  open_lane SE-900
  run bash "$LANE" log SE-900 --claim "X es la vía estándar" --source "docs/specs/SE-370-sdd-research-lane.spec.md" --fetched "2026-09-01"
  [ "$status" -eq 0 ]
  grep -q -- '- Claim: "X es la vía estándar" → Source: docs/specs/SE-370-sdd-research-lane.spec.md · fetched: 2026-09-01' "$LANE_TMP/SE-900/research.md"
}

@test "SE-370 AC-1: log sin --source marca el claim PENDIENTE" {
  open_lane SE-900
  run bash "$LANE" log SE-900 --claim "afirmación sin verificar"
  [ "$status" -eq 0 ]
  grep -q -- '→ Source: PENDIENTE' "$LANE_TMP/SE-900/research.md"
}

# ── AC-2: contradict registra la contradicción ───────────────────────────────
@test "SE-370 AC-2: contradict registra la contradicción en el artefacto" {
  open_lane SE-900
  run bash "$LANE" contradict SE-900 --a "docs/A.md" --b "docs/B.md"
  [ "$status" -eq 0 ]
  grep -q 'docs/A.md' "$LANE_TMP/SE-900/research.md"
  grep -q 'docs/B.md' "$LANE_TMP/SE-900/research.md"
  grep -q '→ abierta' "$LANE_TMP/SE-900/research.md"
  # la contradicción cae en su sección, no en Claims
  run awk '/^## Contradicciones/{f=1;next} /^## /{f=0} f && /docs\/A.md/' "$LANE_TMP/SE-900/research.md"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# ── AC-3: close falla con claims sin fuente y sin marcar ─────────────────────
@test "SE-370 AC-3: close pasa con claims con fuente" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim "con fuente" --source "README.md" > /dev/null
  run bash "$LANE" close SE-900
  [ "$status" -eq 0 ]
  grep -q -- '- cerrado:' "$LANE_TMP/SE-900/research.md"
}

@test "SE-370 AC-3: close pasa con claim PENDIENTE (incertidumbre explícita, no oculta)" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim "sin verificar" > /dev/null
  run bash "$LANE" close SE-900
  [ "$status" -eq 0 ]
}

@test "SE-370 AC-3: close falla si hay claim sin fuente y sin marcar" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim "con fuente" --source "README.md" > /dev/null
  # simula edición manual: claim sin source y sin marca PENDIENTE
  sed -i 's|_Sin incertidumbre registrada_|_Sin incertidumbre registrada_\n- Claim: "editado a mano sin fuente"|' "$LANE_TMP/SE-900/research.md"
  run bash "$LANE" close SE-900
  [ "$status" -ne 0 ]
  [[ ! -f "$LANE_TMP/SE-900/research.md" ]] || ! grep -q -- '- cerrado:' "$LANE_TMP/SE-900/research.md"
}

@test "SE-370: log tras close falla (el gate bloquea la implementación sin re-apertura)" {
  open_lane SE-900
  bash "$LANE" close SE-900 > /dev/null
  run bash "$LANE" log SE-900 --claim "tarde" --source "README.md"
  [ "$status" -ne 0 ]
}

# ── AC-4: freshness presente en cada claim ────────────────────────────────────
@test "SE-370 AC-4: log sin --fetched estampa freshness (hoy UTC)" {
  open_lane SE-900
  run bash "$LANE" log SE-900 --claim "claim fresco" --source "README.md"
  [ "$status" -eq 0 ]
  local today
  today="$(date -u +%F)"
  grep -q "fetched: $today" "$LANE_TMP/SE-900/research.md"
}

@test "SE-370 AC-4: validate falla si un claim no tiene fetched" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim "ok" --source "README.md" > /dev/null
  sed -i 's/ · fetched: [0-9-]*//' "$LANE_TMP/SE-900/research.md"
  run bash "$LANE" validate SE-900
  [ "$status" -ne 0 ]
}

# ── AC-5: artefacto persistido bajo docs/specs/<change>/research.md ──────────
@test "SE-370 AC-5: el artefacto persiste en <specs>/<change>/research.md" {
  open_lane SE-900 --grant open-web
  [ -f "$LANE_TMP/SE-900/research.md" ]
  # el layout por defecto es docs/specs/<change>/research.md
  grep -q 'docs/specs' "$LANE"
  grep -q '^# Research — SE-900' "$LANE_TMP/SE-900/research.md"
}

@test "SE-370 AC-5: el artefacto sigue el formato de la spec (secciones)" {
  open_lane SE-900
  local art="$LANE_TMP/SE-900/research.md"
  grep -q '^## Preguntas' "$art"
  grep -q '^## Grant' "$art"
  grep -q '^## Claims → Sources' "$art"
  grep -q '^## Contradicciones' "$art"
  grep -q '^## Incertidumbre' "$art"
  grep -q '^## Freshness' "$art"
}

# ── AC-6: CRIT-001 — filtro por nivel, N3+ jamás se registra ─────────────────
@test "SE-370 AC-6: log con nivel N3 es rechazado (CRIT-001)" {
  open_lane SE-900
  run bash "$LANE" log SE-900 --claim "dato personal del usuario" --source "local.md" --level N3
  [ "$status" -ne 0 ]
  [[ ! -f "$LANE_TMP/SE-900/research.md" ]] || ! grep -q 'dato personal del usuario' "$LANE_TMP/SE-900/research.md"
}

@test "SE-370 AC-6: log con niveles N4 y N4b es rechazado" {
  open_lane SE-900
  run bash "$LANE" log SE-900 --claim "dato de cliente" --source "local.md" --level N4
  [ "$status" -ne 0 ]
  run bash "$LANE" log SE-900 --claim "dato de equipo" --source "local.md" --level N4b
  [ "$status" -ne 0 ]
  [[ ! -f "$LANE_TMP/SE-900/research.md" ]] || ! grep -qE 'dato de cliente|dato de equipo' "$LANE_TMP/SE-900/research.md"
}

@test "SE-370 AC-6: niveles N1 y N2 sí se registran" {
  open_lane SE-900
  run bash "$LANE" log SE-900 --claim "dato público" --source "README.md" --level N1
  [ "$status" -eq 0 ]
  run bash "$LANE" log SE-900 --claim "dato de org" --source "interno.md" --level N2
  [ "$status" -eq 0 ]
  grep -q '· level: N1' "$LANE_TMP/SE-900/research.md"
  grep -q '· level: N2' "$LANE_TMP/SE-900/research.md"
}

# ── validate: coherencia (grant, refs locales, freshness) ────────────────────
@test "SE-370: validate pasa en artefacto coherente y falla con ref local inexistente (grant documentation)" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim "c1" --source "README.md" > /dev/null
  run bash "$LANE" validate SE-900
  [ "$status" -eq 0 ]
  bash "$LANE" log SE-900 --claim "c2" --source "no/existe/ref.md" > /dev/null
  run bash "$LANE" validate SE-900
  [ "$status" -ne 0 ]
}

@test "SE-370: validate no exige existencia de refs URL (grant open-web)" {
  open_lane SE-900 --grant open-web
  bash "$LANE" log SE-900 --claim "web" --source "https://example.com/doc" > /dev/null
  run bash "$LANE" validate SE-900
  [ "$status" -eq 0 ]
}

@test "SE-370: --validate es alias de validate" {
  open_lane SE-900
  run bash "$LANE" --validate SE-900
  [ "$status" -eq 0 ]
}

# ── Comportamiento: formato exacto, orden, frescura, gate y validación ───────

art() { echo "$LANE_TMP/${1:-SE-900}/research.md"; }

@test "select: el artefacto nace con placeholders, grant humano con sello ISO y salida con la ruta" {
  run bash "$LANE" select SE-900 --grant documentation
  [ "$status" -eq 0 ]
  [ "$output" = "OK: lane abierta para SE-900 (grant: documentation) → $LANE_TMP/SE-900/research.md" ]
  [ "$(sed -n 1p "$(art)")" = "# Research — SE-900" ]
  grep -qx '_Sin preguntas registradas_' "$(art)"
  grep -qx '_Sin claims_' "$(art)"
  grep -qx '_Sin contradicciones_' "$(art)"
  grep -qx '_Sin incertidumbre registrada_' "$(art)"
  grep -qE '^- granted_at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$(art)"
  grep -qE '^- Última consulta: [0-9TZ:-]+ · fuente\(s\) más antiguas: -$' "$(art)"
}

@test "select: repetir con el mismo grant es idempotente (no reescribe); con otro grant exige nuevo grant humano" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim "c" --source README.md > /dev/null
  local antes; antes="$(cat "$(art)")"
  run bash "$LANE" select SE-900 --grant documentation
  [ "$status" -eq 0 ]
  [[ "$output" == "OK: lane ya abierta para SE-900 (grant: documentation)"* ]]
  [ "$(cat "$(art)")" = "$antes" ]
  run bash "$LANE" select SE-900 --grant open-web
  [ "$status" -eq 1 ]
  [[ "$output" == *"lane abierta con grant 'documentation'; ampliar scope exige nuevo grant humano"* ]]
  grep -q -- '- scope: documentation' "$(art)"
}

@test "select: argumento desconocido y --grant vacío fallan nombrando el motivo" {
  run bash "$LANE" select SE-900 --otra x
  [ "$status" -eq 1 ]
  [[ "$output" == *"opción desconocida '--otra'"* ]]
  run timeout 10 bash "$LANE" select SE-900 --grant
  [ "$status" -eq 1 ]
  [[ "$output" == *"--grant requerido"* ]]
  run bash "$LANE" select SE-900 --grant full-internet
  [[ "$output" == *"grant inválido 'full-internet'"* ]]
}

@test "log: el primer claim sustituye el placeholder y los siguientes se añaden en orden" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim "uno" --source README.md --fetched 2026-01-01 > /dev/null
  bash "$LANE" log SE-900 --claim "dos" --source README.md --fetched 2026-02-01 > /dev/null
  bash "$LANE" log SE-900 --claim "tres" > /dev/null
  ! grep -q '_Sin claims_' "$(art)"
  local n1 n2 n3
  n1=$(grep -n 'Claim: "uno"' "$(art)" | cut -d: -f1)
  n2=$(grep -n 'Claim: "dos"' "$(art)" | cut -d: -f1)
  n3=$(grep -n 'Claim: "tres"' "$(art)" | cut -d: -f1)
  [ "$n1" -lt "$n2" ] && [ "$n2" -lt "$n3" ]
  # los claims quedan en su sección, antes de Contradicciones
  local nc; nc=$(grep -n '^## Contradicciones' "$(art)" | cut -d: -f1)
  [ "$n3" -lt "$nc" ]
  grep -qx -- '- Claim: "uno" → Source: README.md · fetched: 2026-01-01 · level: N1' "$(art)"
}

@test "log: nivel por defecto N1; salida confirma la ruta" {
  open_lane SE-900
  run bash "$LANE" log SE-900 --claim "x" --source README.md
  [ "$output" = "OK: claim registrado en $(art)" ]
  grep -q '· level: N1$' "$(art)"
}

@test "log: nivel inválido (N9, minúsculas, vacío) se rechaza y no escribe" {
  open_lane SE-900
  local l
  for l in N9 n1 N5 X; do
    run bash "$LANE" log SE-900 --claim "malo-$l" --source README.md --level "$l"
    [ "$status" -eq 1 ]
    [[ "$output" == *"nivel inválido '$l'"* ]]
  done
  ! grep -q 'malo-' "$(art)"
}

@test "log: sin claim, sin lane abierta, lane cerrada y opción desconocida fallan con su mensaje" {
  run bash "$LANE" log SE-900 --claim "x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lane no abierta para SE-900 (ejecuta select primero)"* ]]
  open_lane SE-900
  run bash "$LANE" log SE-900 --source README.md
  [[ "$output" == *"--claim requerido"* ]]
  run bash "$LANE" log SE-900 --claim x --bogus
  [[ "$output" == *"opción desconocida '--bogus'"* ]]
  bash "$LANE" close SE-900 > /dev/null
  run bash "$LANE" log SE-900 --claim "tarde" --source README.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"lane cerrada para SE-900"* ]]
}

@test "freshness: la sección refleja la fuente más antigua y una consulta de ahora" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim a --source README.md --fetched 2026-03-05 > /dev/null
  bash "$LANE" log SE-900 --claim b --source README.md --fetched 2025-12-31 > /dev/null
  bash "$LANE" log SE-900 --claim c --source README.md --fetched 2026-07-01 > /dev/null
  grep -qE '^- Última consulta: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z · fuente\(s\) más antiguas: 2025-12-31$' "$(art)"
}

@test "freshness: contradict también refresca la consulta pero no inventa fuente antigua" {
  open_lane SE-900
  bash "$LANE" contradict SE-900 --a A --b B > /dev/null
  grep -q 'fuente(s) más antiguas: -$' "$(art)"
}

@test "contradict: línea exacta en su sección, placeholder retirado, orden de varias" {
  open_lane SE-900
  run bash "$LANE" contradict SE-900 --a docs/A.md --b docs/B.md
  [ "$output" = "OK: contradicción registrada en $(art)" ]
  bash "$LANE" contradict SE-900 --a C --b D > /dev/null
  ! grep -q '_Sin contradicciones_' "$(art)"
  grep -qx -- '- Fuente docs/A.md dice una cosa; fuente docs/B.md dice ¬esa → abierta (contradicción entre docs/A.md y docs/B.md)' "$(art)"
  local n1 n2
  n1=$(grep -n 'entre docs/A.md' "$(art)" | cut -d: -f1); n2=$(grep -n 'entre C y D' "$(art)" | cut -d: -f1)
  [ "$n1" -lt "$n2" ]
  # sigue habiendo placeholder en las demás secciones
  grep -qx '_Sin claims_' "$(art)"
}

@test "contradict: requiere --a y --b, lane abierta y no cerrada" {
  open_lane SE-900
  run bash "$LANE" contradict SE-900 --a solo
  [ "$status" -eq 1 ]
  [[ "$output" == *"--a y --b requeridos"* ]]
  run timeout 10 bash "$LANE" contradict SE-900 --a A --b
  [ "$status" -eq 1 ]
  run bash "$LANE" contradict SE-777 --a A --b B
  [[ "$output" == *"lane no abierta para SE-777"* ]]
  bash "$LANE" close SE-900 > /dev/null
  run bash "$LANE" contradict SE-900 --a A --b B
  [[ "$output" == *"lane cerrada para SE-900"* ]]
}

@test "close: línea final '- cerrado: <ISO> · gate-ok · claims: N' y mensaje con el recuento" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim a --source README.md > /dev/null
  bash "$LANE" log SE-900 --claim b > /dev/null
  run bash "$LANE" close SE-900
  [ "$status" -eq 0 ]
  [[ "$output" == "GATE OK: research de SE-900 cerrada — 2 claim(s)"* ]]
  tail -1 "$(art)" | grep -qE '^- cerrado: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z · gate-ok · claims: 2$'
}

@test "close: lane sin claims se cierra con 0; cerrar dos veces o sin artefacto falla" {
  open_lane SE-900
  run bash "$LANE" close SE-900
  [ "$status" -eq 0 ]
  tail -1 "$(art)" | grep -q 'claims: 0$'
  run bash "$LANE" close SE-900
  [ "$status" -eq 1 ]
  [[ "$output" == *"lane ya cerrada"* ]]
  run bash "$LANE" close SE-555
  [ "$status" -eq 1 ]
  [[ "$output" == *"no hay artefacto de research para SE-555"* ]]
}

@test "close: informa cuántos claims de cuántos están sin fuente y los lista; Source vacío también cuenta" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim ok --source README.md > /dev/null
  sed -i 's|^- Claim: "ok".*|&\n- Claim: "huérfano uno"\n- Claim: "vacío" → Source:  · fetched: 2026-01-01 · level: N1|' "$(art)"
  run bash "$LANE" close SE-900
  [ "$status" -eq 1 ]
  [[ "$output" == *"SIN FUENTE Y SIN MARCAR: - Claim: \"huérfano uno\""* ]]
  [[ "$output" == *"close: 2 claim(s) de 3 sin fuente y sin marcar PENDIENTE"* ]]
  ! grep -q -- '- cerrado:' "$(art)"
}

@test "validate: informa del recuento de errores y de cada fallo (grant, granted_at, granted_by, Freshness)" {
  open_lane SE-900
  sed -i '/^- scope:/d;/^- granted_at:/d;/^- granted_by:/d;/^## Freshness/d' "$(art)"
  run bash "$LANE" validate SE-900
  [ "$status" -eq 1 ]
  [[ "$output" == *"grant scope ausente o inválido"* ]]
  [[ "$output" == *"granted_at ausente"* ]]
  [[ "$output" == *"granted_by ausente"* ]]
  [[ "$output" == *"sección Freshness ausente"* ]]
  [[ "$output" == *"incoherente (4 error(es))"* ]]
}

@test "validate: claim sin fetched se nombra; con PENDIENTE y con URL no exige referencia local" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim pend > /dev/null
  bash "$LANE" log SE-900 --claim web --source https://example.com/x > /dev/null
  run bash "$LANE" validate SE-900
  [ "$status" -eq 0 ]
  [ "$output" = "OK: artefacto de SE-900 coherente (grant, refs, freshness)" ]
  sed -i 's| · fetched: [0-9-]*||' "$(art)"
  run bash "$LANE" validate SE-900
  [[ "$output" == *"claim sin freshness: - Claim: \"pend\""* ]]
}

@test "validate: la referencia local puede ser relativa al repo, a la carpeta del change o llevar #ancla" {
  open_lane SE-900
  echo hola > "$LANE_TMP/SE-900/nota.md"
  bash "$LANE" log SE-900 --claim repo --source "README.md#seccion" > /dev/null
  bash "$LANE" log SE-900 --claim local --source "nota.md" > /dev/null
  run bash "$LANE" validate SE-900
  [ "$status" -eq 0 ]
  bash "$LANE" log SE-900 --claim roto --source "no/existe.md#x" > /dev/null
  run bash "$LANE" validate SE-900
  [ "$status" -eq 1 ]
  [[ "$output" == *"ref local inexistente: no/existe.md"* ]]
}

@test "validate: con grant open-web las referencias locales inexistentes no cuentan" {
  open_lane SE-900 --grant open-web
  bash "$LANE" log SE-900 --claim roto --source "no/existe.md" > /dev/null
  run bash "$LANE" validate SE-900
  [ "$status" -eq 0 ]
}

@test "validate sin artefacto falla con mensaje; falta de <change> se detecta en cada comando" {
  run bash "$LANE" validate SE-404
  [ "$status" -eq 1 ]
  [[ "$output" == *"validate: no hay artefacto de research para SE-404"* ]]
  local c
  for c in select log contradict close validate; do
    run bash "$LANE" "$c"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$c: falta <change>"* ]]
  done
}

@test "uso: sin argumentos y comando desconocido salen con 1; --help con 0" {
  run bash "$LANE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso:"* ]]
  run bash "$LANE" inventado
  [ "$status" -eq 1 ]
  [[ "$output" == *"comando desconocido 'inventado'"* ]]
  run bash "$LANE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"SDD Research lane"* ]]
}

@test "un claim con comillas y & se conserva literal y la frescura no se corrompe" {
  open_lane SE-900
  bash "$LANE" log SE-900 --claim 'dice "A & B" | C' --source README.md --fetched '2026-05-05' > /dev/null
  grep -qF 'Claim: "dice "A & B" | C" → Source: README.md' "$(art)"
  grep -q 'fuente(s) más antiguas: 2026-05-05$' "$(art)"
}

@test "una opción sin valor al final (--claim, --source, --level, --fetched) termina con error, no se cuelga" {
  open_lane SE-900
  local o
  for o in --claim --source --level --fetched; do
    run timeout 10 bash "$LANE" log SE-900 --claim x "$o"
    [ "$status" -ne 124 ]
  done
  run timeout 10 bash "$LANE" log SE-900 --claim
  [ "$status" -eq 1 ]
  [[ "$output" == *"--claim requerido"* ]]
}
