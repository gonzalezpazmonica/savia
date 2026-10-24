#!/usr/bin/env bats
# test-se251-pre-tribunal-gates.bats — SE-251: deterministic pre-tribunal gates tests
#
# Acceptance criteria from SE-251:
# 1. Script exists and is executable
# 2. set -uo pipefail present
# 3. --help exits 0
# 4. --decision missing exits 1
# 5. spec_status=PROPOSED -> G1 BLOCK (exit 1)
# 6. spec_status=APPROVED -> no G1 block
# 7. risk_score=0.9 -> G3 BLOCK (exit 1) with RISK_GATE_THRESHOLD=0.8
# 8. risk_score=0.5 -> no G3 block
# 9. source_branch=feature/foo target=main -> G4 BLOCK (exit 1)
# 10. source_branch=nido/se248 target=main -> no G4 block
# 11. PRETRIBUNAL_GATES_ENABLED=false -> always exit 0
# 12. Unknown decision type -> SKIP (exit 2)
# 13. JSON output has "gate" and "verdict" fields
# 14. PASS output has verdict=PASS

SCRIPT="scripts/pre-tribunal-gates.sh"

setup() {
  cd "${BATS_TEST_DIRNAME}/.."
}

# ── Structure tests ──────────────────────────────────────────────────────────

@test "SE-251-T01: script exists and is executable" {
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

@test "SE-251-T02: set -uo pipefail is present" {
  grep -q "set -uo pipefail" "$SCRIPT"
}

# ── Invocation tests ─────────────────────────────────────────────────────────

@test "SE-251-T03: --help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
}

@test "SE-251-T04: --decision missing exits 1" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# ── G1: Spec Approval Gate ───────────────────────────────────────────────────

@test "SE-251-T05: spec_status=PROPOSED -> G1 BLOCK" {
  run bash "$SCRIPT" --decision merge \
    --context '{"spec_status":"PROPOSED","source_branch":"nido/test","target_branch":"main"}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"G1"* ]]
  [[ "$output" == *"BLOCK"* ]]
}

@test "SE-251-T06: spec_status=APPROVED -> no G1 block" {
  run bash "$SCRIPT" --decision merge \
    --context '{"spec_status":"APPROVED","source_branch":"nido/test","target_branch":"main"}'
  # Must not produce a G1 BLOCK (may still PASS or block on other gates)
  [[ "$output" != *'"gate":"G1"'* ]] || [[ "$output" != *"BLOCK"* ]]
}

# ── G3: Risk Score Gate ──────────────────────────────────────────────────────

@test "SE-251-T07: risk_score=0.9 -> G3 BLOCK with threshold=0.8" {
  run env RISK_GATE_THRESHOLD=0.8 bash "$SCRIPT" --decision deploy \
    --context '{"risk_score":0.9}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"G3"* ]]
  [[ "$output" == *"BLOCK"* ]]
}

@test "SE-251-T08: risk_score=0.5 -> no G3 block" {
  run env RISK_GATE_THRESHOLD=0.8 bash "$SCRIPT" --decision deploy \
    --context '{"risk_score":0.5}'
  # Must not block on G3
  [[ "$output" != *'"gate":"G3"'* ]] || [[ "$output" != *"BLOCK"* ]]
  [ "$status" -ne 1 ] || [[ "$output" != *"G3"* ]]
}

# ── G4: Branch Safety Gate ───────────────────────────────────────────────────

@test "SE-251-T09: source_branch=feature/foo target=main -> G4 BLOCK" {
  run bash "$SCRIPT" --decision merge \
    --context '{"source_branch":"feature/foo","target_branch":"main"}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"G4"* ]]
  [[ "$output" == *"BLOCK"* ]]
}

@test "SE-251-T10: source_branch=nido/se248 target=main -> no G4 block" {
  run bash "$SCRIPT" --decision merge \
    --context '{"spec_status":"APPROVED","source_branch":"nido/se248","target_branch":"main"}'
  # Must not produce a G4 BLOCK
  if [ "$status" -eq 1 ]; then
    [[ "$output" != *'"gate":"G4"'* ]]
  fi
}

# ── Environment gates ────────────────────────────────────────────────────────

@test "SE-251-T11: PRETRIBUNAL_GATES_ENABLED=false -> always exit 0" {
  run env PRETRIBUNAL_GATES_ENABLED=false bash "$SCRIPT" --decision merge \
    --context '{"spec_status":"PROPOSED","risk_score":0.99,"source_branch":"feature/x","target_branch":"main"}'
  [ "$status" -eq 0 ]
}

@test "SE-251-T12: unknown decision type -> SKIP exit 2" {
  run bash "$SCRIPT" --decision unknown-type
  [ "$status" -eq 2 ]
  [[ "$output" == *"SKIP"* ]]
}

# ── JSON output structure ────────────────────────────────────────────────────

@test "SE-251-T13: JSON output contains 'gate' and 'verdict' fields" {
  run bash "$SCRIPT" --decision deploy \
    --context '{"risk_score":0.9}'
  [[ "$output" == *'"gate"'* ]]
  [[ "$output" == *'"verdict"'* ]]
}

@test "SE-251-T14: PASS output has verdict=PASS" {
  run bash "$SCRIPT" --decision deploy \
    --context '{"risk_score":0.1}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"PASS"'* ]]
}

# ── Comportamiento: precedencia de gates, fronteras y JSON exacto ─────────
# Se ejecuta desde un directorio temporal: los gates leen scripts/savia-env.sh
# relativo al cwd, así que cada test controla el revisor con un stub.

_w() {  # _w [reviewer]  → crea cwd aislado; con argumento instala stub de savia-env
  W="$BATS_TEST_TMPDIR/w"; rm -rf "$W"; mkdir -p "$W/scripts"; cd "$W"
  if [[ $# -gt 0 ]]; then
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$1" > "$W/scripts/savia-env.sh"
  fi
  ABS="${BATS_TEST_DIRNAME}/../$SCRIPT"
}

_g() { bash "$ABS" "$@"; }
_gate() { echo "$output" | jq -r .gate; }
_verd() { echo "$output" | jq -r .verdict; }

@test "args: bandera desconocida sale 1 con 'Unknown arg' en stderr" {
  _w
  run _g --raro
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown arg: --raro"* ]]
}

@test "args: --help muestra uso y sale 0 sin exigir --decision" {
  _w
  run _g -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: pre-tribunal-gates.sh"* ]]
}

@test "args: sin --decision el error es explícito" {
  _w
  run _g --context '{}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"--decision is required"* ]]
}

@test "salida PASS: JSON exacto con escalate_to none" {
  _w
  run _g --decision deploy --context '{"risk_score":0.1}'
  [ "$status" -eq 0 ]
  [ "$output" = '{"gate":"ALL","verdict":"PASS","reason":"all gates passed","escalate_to":"none"}' ]
}

@test "salida BLOCK: escalate_to human" {
  _w
  run _g --decision deploy --context '{"risk_score":0.95}'
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r .escalate_to)" = "human" ]
}

@test "decisión desconocida: SKIP con verdict y escalate_to none, aun con contexto malo" {
  _w
  run _g --decision release --context '{"risk_score":0.99}'
  [ "$status" -eq 2 ]
  [ "$(_gate)" = "SKIP" ]
  [ "$(_verd)" = "SKIP" ]
  [ "$(echo "$output" | jq -r .escalate_to)" = "none" ]
  [[ "$output" == *"'release' not classified"* ]]
}

@test "las tres decisiones críticas se evalúan (merge, deploy, devops)" {
  _w
  for d in merge deploy devops; do
    run _g --decision "$d" --context '{"risk_score":0.99}'
    [ "$status" -eq 1 ]
    [ "$(_gate)" = "G3" ]
  done
}

@test "deshabilitado: PASS con gate ALL y razón, aunque la decisión sea desconocida" {
  _w
  PRETRIBUNAL_GATES_ENABLED=false run _g --decision cualquiera
  [ "$status" -eq 0 ]
  [ "$(_gate)" = "ALL" ]
  [[ "$output" == *"disabled via PRETRIBUNAL_GATES_ENABLED=false"* ]]
}

@test "G1: DRAFT, NONE y PROPOSED bloquean un merge; la razón cita el estado" {
  _w
  for st in DRAFT NONE PROPOSED; do
    run _g --decision merge --context "{\"spec_status\":\"$st\"}"
    [ "$status" -eq 1 ]
    [ "$(_gate)" = "G1" ]
    [[ "$output" == *"spec_status=$st"* ]]
  done
}

@test "G1: APPROVED e IMPLEMENTED pasan" {
  _w
  for st in APPROVED IMPLEMENTED; do
    run _g --decision merge --context "{\"spec_status\":\"$st\"}"
    [ "$status" -eq 0 ]
  done
}

@test "G1: un estado desconocido no bloquea (solo los listados)" {
  _w
  run _g --decision merge --context '{"spec_status":"WEIRD"}'
  [ "$status" -eq 0 ]
}

@test "G1: solo aplica a merge, no a deploy" {
  _w
  run _g --decision deploy --context '{"spec_status":"PROPOSED"}'
  [ "$status" -eq 0 ]
}

@test "G1: SPEC_GATE_ENABLED=false lo desactiva" {
  _w
  SPEC_GATE_ENABLED=false run _g --decision merge --context '{"spec_status":"PROPOSED"}'
  [ "$status" -eq 0 ]
}

@test "G1: sin spec_status en el contexto no bloquea" {
  _w
  run _g --decision merge --context '{}'
  [ "$status" -eq 0 ]
}

@test "G2: stub con revisor válido deja pasar" {
  _w "alguien"
  run _g --decision deploy --context '{}'
  [ "$status" -eq 0 ]
}

@test "G2: revisor vacío o con comillas vacías bloquea" {
  for r in "" '""' "''"; do
    _w "$r"
    run _g --decision deploy --context '{}'
    [ "$status" -eq 1 ]
    [ "$(_gate)" = "G2" ]
    [[ "$output" == *"AUTONOMOUS_REVIEWER unresolvable"* ]]
  done
}

@test "G2: sin savia-env.sh el gate no se evalúa" {
  _w
  run _g --decision deploy --context '{}'
  [ "$status" -eq 0 ]
}

@test "orden de gates: G1 antes que G2, G2 antes que G3, G3 antes que G4" {
  _w '""'
  run _g --decision merge --context '{"spec_status":"DRAFT","risk_score":0.99,"source_branch":"x","target_branch":"main"}'
  [ "$(_gate)" = "G1" ]
  run _g --decision merge --context '{"spec_status":"APPROVED","risk_score":0.99,"source_branch":"x","target_branch":"main"}'
  [ "$(_gate)" = "G2" ]
  _w "ok"
  run _g --decision merge --context '{"spec_status":"APPROVED","risk_score":0.99,"source_branch":"x","target_branch":"main"}'
  [ "$(_gate)" = "G3" ]
  run _g --decision merge --context '{"spec_status":"APPROVED","risk_score":0.1,"source_branch":"x","target_branch":"main"}'
  [ "$(_gate)" = "G4" ]
}

@test "G3: frontera estricta, igual al umbral pasa y justo por encima bloquea" {
  _w
  run _g --decision deploy --context '{"risk_score":0.8}'
  [ "$status" -eq 0 ]
  run _g --decision deploy --context '{"risk_score":0.81}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"risk_score=0.81 > threshold=0.8"* ]]
}

@test "G3: RISK_GATE_THRESHOLD se respeta" {
  _w
  RISK_GATE_THRESHOLD=0.3 run _g --decision deploy --context '{"risk_score":0.5}'
  [ "$status" -eq 1 ]
  RISK_GATE_THRESHOLD=0.95 run _g --decision deploy --context '{"risk_score":0.9}'
  [ "$status" -eq 0 ]
}

@test "G3: risk_score como cadena entre comillas también se evalúa" {
  _w
  run _g --decision deploy --context '{"risk_score":"0.99"}'
  [ "$status" -eq 1 ]
  [ "$(_gate)" = "G3" ]
}

@test "G3: sin risk_score no bloquea; aplica también a merge y devops" {
  _w
  run _g --decision devops --context '{}'
  [ "$status" -eq 0 ]
  run _g --decision devops --context '{"risk_score":0.9}'
  [ "$status" -eq 1 ]
}

@test "G4: ramas agent/, nido/ y hotfix/ pueden ir a main, develop y master" {
  _w
  for src in agent/x nido/y hotfix/z; do
    for tgt in main develop master; do
      run _g --decision merge --context "{\"source_branch\":\"$src\",\"target_branch\":\"$tgt\"}"
      [ "$status" -eq 0 ]
    done
  done
}

@test "G4: rama humana a main, develop o master bloquea y la razón cita ambas" {
  _w
  for tgt in main develop master; do
    run _g --decision merge --context "{\"source_branch\":\"feature/x\",\"target_branch\":\"$tgt\"}"
    [ "$status" -eq 1 ]
    [ "$(_gate)" = "G4" ]
    [[ "$output" == *"source_branch=feature/x"* ]]
    [[ "$output" == *"unsafe merge to $tgt"* ]]
  done
}

@test "G4: el prefijo se ancla al inicio (xagent/ no vale)" {
  _w
  run _g --decision merge --context '{"source_branch":"xagent/a","target_branch":"main"}'
  [ "$status" -eq 1 ]
}

@test "G4: destino que no es principal no bloquea" {
  _w
  run _g --decision merge --context '{"source_branch":"feature/x","target_branch":"release"}'
  [ "$status" -eq 0 ]
}

@test "G4: sin una de las dos ramas no se evalúa; y no aplica a deploy" {
  _w
  run _g --decision merge --context '{"target_branch":"main"}'
  [ "$status" -eq 0 ]
  run _g --decision merge --context '{"source_branch":"feature/x"}'
  [ "$status" -eq 0 ]
  run _g --decision deploy --context '{"source_branch":"feature/x","target_branch":"main"}'
  [ "$status" -eq 0 ]
}
