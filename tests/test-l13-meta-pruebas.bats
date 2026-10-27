#!/usr/bin/env bats
# L13 F3 — l13-meta-pruebas (harness determinista pruebas M1-M4)
# Linea: labs/roadmaps/l13-savia-metacognition.md (F3) / protocolo L13

HARNESS="scripts/l13-meta-pruebas.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$FIXDIR"
}

@test "existe, bash -n, sin vendor cloud names, PURE_BASH" {
  [[ -x "$HARNESS" ]]
  bash -n "$HARNESS"
  run grep -niE "api\.openai\.com|api\.anthropic\.com|api\.deepseek\.com|api\.google\.com|api\.mistral\.ai" "$HARNESS"
  [[ "$status" -ne 0 ]]
}

@test "usage sin --pruebas invalido; exit 2" {
  run bash "$HARNESS" --pruebas
  [[ "$status" -eq 2 ]]
}

@test "dependencia ausente → exit 3" {
  # Copiamos el harness a un dir vacío sin las dependencias L13; al ejecutarse
  # desde ahí, la comprobación de dependencias debe abortar con exit 3.
  mkdir -p "$FIXDIR/empty"
  cp "$HARNESS" "$FIXDIR/empty/harness.sh"
  chmod +x "$FIXDIR/empty/harness.sh"
  run bash "$FIXDIR/empty/harness.sh" --pruebas M1
  [[ "$status" -eq 3 ]]
  [[ "$output" == *"falta scripts/meta-monitor.sh"* ]]
}

@test "M1: el tratamiento ajusta el gap de calibración (baseline cruda > ajustada)" {
  run bash "$HARNESS" --pruebas M1 --fixtures "$FIXDIR"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"M1"* ]]
  [[ "$output" == *"PASS"* ]]
  # gap baseline = 15 (confianza cruda 95 vs real 80); el ajuste debe reducirlo
  [[ "$output" == *"baseline=15"* ]]
}

@test "M2: divergence modula la confianza (transiciones monotónicas)" {
  run bash "$HARNESS" --pruebas M2 --fixtures "$FIXDIR"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"M2"* ]]
  [[ "$output" == *"PASS"* ]]
}

@test "M3: autorregulación — POSTPONE evita emitir propuesta errónea" {
  run bash "$HARNESS" --pruebas M3 --fixtures "$FIXDIR"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"M3"* ]]
  [[ "$output" == *"PASS"* ]]
  [[ "$output" == *"POSTPONE"* ]]
}

@test "M4: recalibración — gap decrece entre bloques (curva recalibra)" {
  run bash "$HARNESS" --pruebas M4 --fixtures "$FIXDIR"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"M4"* ]]
  [[ "$output" == *"PASS"* ]]
  [[ "$output" == *"gap bloque2"* ]]
}

@test "suite completa M1-M4: verdict CONFIRMA con >=2 PASS (criterio preregistrado)" {
  run bash "$HARNESS" --fixtures "$FIXDIR"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"CONFIRMA"* ]]
}

@test "CRIT-031 invariante: el harness no modifica CRITERIO.md ni CONSTITUCION.md" {
  local crit_before constit_before crit_after constit_after
  crit_before=$(sha256sum CRITERIO.md 2>/dev/null | cut -d' ' -f1)
  constit_before=$(sha256sum .claude/CONSTITUCION.md 2>/dev/null | cut -d' ' -f1)
  run bash "$HARNESS" --fixtures "$FIXDIR"
  crit_after=$(sha256sum CRITERIO.md 2>/dev/null | cut -d' ' -f1)
  constit_after=$(sha256sum .claude/CONSTITUCION.md 2>/dev/null | cut -d' ' -f1)
  [[ "$crit_before" == "$crit_after" ]]
  [[ "$constit_before" == "$constit_after" ]]
}

@test "reproducibilidad: dos runs idénticos → mismo veredicto y mismas métricas" {
  local r1 r2
  r1=$(bash "$HARNESS" --fixtures "$FIXDIR" 2>/dev/null | grep -E "^\[M[0-9]" | sort)
  r2=$(bash "$HARNESS" --fixtures "$FIXDIR" 2>/dev/null | grep -E "^\[M[0-9]" | sort)
  [[ "$r1" == "$r2" ]]
}
# ── S03k: criterios de veredicto con dependencias sustituidas ──
# El arnés se copia a un árbol con meta-monitor/meta-control/meta-recalibrate
# falsos cuya salida se fija, para ejercitar cada rama PASS/FAIL de M1-M4.

mk_fx() {
  FX="$FIXDIR/fx"; SD="$FIXDIR/stub"
  mkdir -p "$FX/scripts" "$SD"
  cp "$HARNESS" "$FX/scripts/h.sh"
  cat > "$FX/scripts/meta-monitor.sh" <<'EOS'
#!/usr/bin/env bash
n=$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$STUB_DIR/n"
echo "$@" >> "$STUB_DIR/monitor.log"
read -ra seq <<< "$STUB_SEQ"
v=${seq[$((n-1))]:-${seq[-1]}}
echo "{\"confidence_adjusted\": $v}"
EOS
  cat > "$FX/scripts/meta-recalibrate.sh" <<'EOS'
#!/usr/bin/env bash
echo "$@" >> "$STUB_DIR/recal.log"
EOS
  cat > "$FX/scripts/meta-control.sh" <<'EOS'
#!/usr/bin/env bash
echo "$@" >> "$STUB_DIR/control.log"
echo "{\"action\": \"${STUB_ACTION:-PROCEED}\"}"
EOS
  chmod +x "$FX"/scripts/*.sh
  export STUB_DIR="$SD"
}

h() { bash "$FX/scripts/h.sh" --fixtures "$FIXDIR/f" "$@"; }

@test "S03k l13: M1 PASS si la confianza ajustada deja el gap por debajo de 15" {
  mk_fx
  STUB_SEQ="70" run h --pruebas M1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[M1] tratamiento=10 baseline=15 delta=5 → PASS"* ]]
}

@test "S03k l13: M1 en el borde: gap 15 igual a la baseline no es PASS" {
  mk_fx
  STUB_SEQ="65" run h --pruebas M1
  [[ "$output" == *"→ FAIL"* ]]
  [[ "$output" == *"tratamiento=15 "* ]]
}

@test "S03k l13: M1 gap 14 pasa y gap 16 (peor que la baseline) falla" {
  mk_fx
  STUB_SEQ="66" run h --pruebas M1
  [[ "$output" == *"→ PASS"* ]]
  rm -f "$SD/n"
  STUB_SEQ="64" run h --pruebas M1
  [[ "$output" == *"→ FAIL"* ]]
}

@test "S03k l13: M1 sobreestimar mucho (gap 19 > baseline) falla" {
  mk_fx
  STUB_SEQ="99" run h --pruebas M1
  [[ "$output" == *"delta=-4 → FAIL"* ]]
}

@test "S03k l13: M1 entrena la curva con 8 aciertos y 2 fallos, y pide confianza 95 y divergencia 0.2" {
  mk_fx
  STUB_SEQ="70" run h --pruebas M1
  [ "$(grep -c -- '--outcome success' "$SD/recal.log")" -eq 8 ]
  [ "$(grep -c -- '--outcome fail' "$SD/recal.log")" -eq 2 ]
  grep -q -- '--confidence 95 --divergence 0.2 --evidence 1.0' "$SD/monitor.log"
}

@test "S03k l13: M2 con confianza decreciente es PASS 4/4" {
  mk_fx
  STUB_SEQ="80 70 60 50 40" run h --pruebas M2
  [[ "$output" == *"[M2] tratamiento=4 baseline=0 delta=4 → PASS (4/4 transiciones"* ]]
}

@test "S03k l13: M2 barre las divergencias 0.0 0.3 0.5 0.7 0.9 en ese orden" {
  mk_fx
  STUB_SEQ="80 70 60 50 40" run h --pruebas M2
  div=$(sed -E 's/.*--divergence ([0-9.]+).*/\1/' "$SD/monitor.log" | tr '\n' ' ')
  [ "$div" = "0.0 0.3 0.5 0.7 0.9 " ]
}

@test "S03k l13: M2 con 3 transiciones monótonas pasa y con 2 falla" {
  mk_fx
  STUB_SEQ="80 70 60 65 55" run h --pruebas M2
  [[ "$output" == *"tratamiento=3"* ]]
  [[ "$output" == *"→ PASS"* ]]
  rm -f "$SD/n"
  STUB_SEQ="80 70 75 60 65" run h --pruebas M2
  [[ "$output" == *"tratamiento=2"* ]]
  [[ "$output" == *"→ FAIL"* ]]
}

@test "S03k l13: M2 con confianza creciente con la divergencia falla con 0 transiciones" {
  mk_fx
  STUB_SEQ="40 50 60 70 80" run h --pruebas M2
  [[ "$output" == *"tratamiento=0"* ]]
  [[ "$output" == *"→ FAIL"* ]]
}

@test "S03k l13: M3 PASS solo si meta-control responde POSTPONE" {
  mk_fx
  STUB_SEQ="48" STUB_ACTION=POSTPONE run h --pruebas M3
  [[ "$output" == *"[M3]"*"→ PASS (POSTPONE evita emitir con confianza 48"* ]]
  STUB_SEQ="48" STUB_ACTION=PROCEED run h --pruebas M3
  [[ "$output" == *"→ FAIL"* ]]
  STUB_SEQ="48" STUB_ACTION=REPLAN run h --pruebas M3
  [[ "$output" == *"→ FAIL"* ]]
}

@test "S03k l13: M3 pasa a meta-control la confianza ajustada, la divergencia y la acción pedida" {
  mk_fx
  STUB_SEQ="48" STUB_ACTION=POSTPONE run h --pruebas M3
  grep -q -- '--adjusted 48 --divergence 0.3 --calibration 0.6 --requested persist' "$SD/control.log"
}

@test "S03k l13: M3 construye la curva débil con 3 aciertos y 2 fallos" {
  mk_fx
  STUB_SEQ="48" STUB_ACTION=POSTPONE run h --pruebas M3
  [ "$(grep -c -- '--outcome success' "$SD/recal.log")" -eq 3 ]
  [ "$(grep -c -- '--outcome fail' "$SD/recal.log")" -eq 2 ]
}

@test "S03k l13: M4 PASS solo si el gap del bloque 2 es estrictamente menor" {
  mk_fx
  STUB_SEQ="70 85" run h --pruebas M4
  [[ "$output" == *"[M4] tratamiento=5 baseline=20 delta=15 → PASS"* ]]
  rm -f "$SD/n"
  STUB_SEQ="85 85" run h --pruebas M4
  [[ "$output" == *"→ FAIL"* ]]
  rm -f "$SD/n"
  STUB_SEQ="85 70" run h --pruebas M4
  [[ "$output" == *"→ FAIL"* ]]
}

@test "S03k l13: M4 alimenta la segunda curva con 9 aciertos y 1 fallo" {
  mk_fx
  STUB_SEQ="70 85" run h --pruebas M4
  [ "$(grep -c -- '--outcome success' "$SD/recal.log")" -eq 9 ]
  [ "$(grep -c -- '--outcome fail' "$SD/recal.log")" -eq 1 ]
}

@test "S03k l13: con un solo PASS el veredicto es INCONCLUSO (1/1)" {
  mk_fx
  STUB_SEQ="70" run h --pruebas M1
  [[ "$output" == *"VEREDICTO L13: INCONCLUSO (1/1 pruebas"* ]]
}

@test "S03k l13: con dos PASS el veredicto es CONFIRMA y el total cuenta las pruebas pedidas" {
  mk_fx
  STUB_SEQ="70 80 70 60 50 40" run h --pruebas M1,M2
  [[ "$output" == *"VEREDICTO L13: CONFIRMA (2/2 pruebas"* ]]
}

@test "S03k l13: dos de cuatro bastan; uno de cuatro no" {
  mk_fx
  # M1 PASS, M2 FAIL (creciente), M3 PASS, M4 FAIL (sin mejora)
  STUB_SEQ="70 40 50 60 70 80 48 85 85" STUB_ACTION=POSTPONE run h
  [[ "$output" == *"VEREDICTO L13: CONFIRMA (2/4"* ]]
  rm -f "$SD/n"
  STUB_SEQ="70 40 50 60 70 80 48 85 85" STUB_ACTION=PROCEED run h
  [[ "$output" == *"VEREDICTO L13: INCONCLUSO (1/4"* ]]
}

@test "S03k l13: ninguna prueba pasa → INCONCLUSO 0/4" {
  mk_fx
  STUB_SEQ="99 40 50 60 70 80 48 85 85" STUB_ACTION=PROCEED run h
  [[ "$output" == *"INCONCLUSO (0/4"* ]]
}

@test "S03k l13: --pruebas solo ejecuta las pedidas" {
  mk_fx
  STUB_SEQ="70" run h --pruebas M1
  [[ "$output" == *"[M1]"* ]]
  [[ "$output" != *"[M2]"* ]]
  [[ "$output" != *"[M4]"* ]]
}

@test "S03k l13: una prueba desconocida avisa y no suma PASS" {
  mk_fx
  run h --pruebas M9
  [ "$status" -eq 0 ]
  [[ "$output" == *"prueba desconocida: M9"* ]]
  [[ "$output" == *"INCONCLUSO (0/1"* ]]
}

@test "S03k l13: --json antepone la cabecera con las pruebas y el run" {
  mk_fx
  STUB_SEQ="70" run h --pruebas M1 --json
  [ "${lines[0]}" = '{"capa":"l13-meta","pruebas":"M1","run":"run-1"}' ]
}

@test "S03k l13: sin --json no hay cabecera JSON" {
  mk_fx
  STUB_SEQ="70" run h --pruebas M1
  [[ "$output" != *'"capa"'* ]]
}

@test "S03k l13: sin --pruebas se asumen M1,M2,M3,M4" {
  mk_fx
  STUB_SEQ="70" run h --json
  [[ "${lines[0]}" == *'"pruebas":"M1,M2,M3,M4"'* ]]
}

@test "S03k l13: --pruebas o --fixtures sin valor salen con 2" {
  mk_fx
  run bash "$FX/scripts/h.sh" --pruebas
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pruebas requiere valor"* ]]
  run bash "$FX/scripts/h.sh" --fixtures
  [ "$status" -eq 2 ]
  [[ "$output" == *"--fixtures requiere ruta"* ]]
}

@test "S03k l13: argumento desconocido sale con 2 y muestra el uso" {
  mk_fx
  run bash "$FX/scripts/h.sh" --nada
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "S03k l13: cada dependencia ausente sale con 3 y la nombra" {
  mk_fx
  for dep in meta-monitor.sh meta-control.sh meta-recalibrate.sh; do
    cp "$FX/scripts/$dep" "$FIXDIR/$dep.bak"
    unlink "$FX/scripts/$dep"
    run h --pruebas M1
    [ "$status" -eq 3 ]
    [[ "$output" == *"falta scripts/$dep"* ]]
    cp "$FIXDIR/$dep.bak" "$FX/scripts/$dep"
    chmod +x "$FX/scripts/$dep"
  done
}

@test "S03k l13: una dependencia no ejecutable también cuenta como ausente" {
  mk_fx
  chmod -x "$FX/scripts/meta-control.sh"
  run h --pruebas M1
  [ "$status" -eq 3 ]
}

@test "S03k l13: --fixtures crea el directorio indicado" {
  mk_fx
  STUB_SEQ="70" run bash "$FX/scripts/h.sh" --pruebas M1 --fixtures "$FIXDIR/nuevo/sub"
  [ -d "$FIXDIR/nuevo/sub" ]
}

@test "S03k l13: M2 cuenta una confianza igual a la anterior como transición no creciente" {
  mk_fx
  STUB_SEQ="80 80 80 80 80" run h --pruebas M2
  [[ "$output" == *"tratamiento=4"* ]]
  [[ "$output" == *"→ PASS"* ]]
}
