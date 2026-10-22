#!/usr/bin/env bats
# tests/bats/test-standards-compliance-gate.bats — SE-311 S2: compuerta de estandares

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/standards-compliance-gate.sh"
  TESTDIR=$(mktemp -d)
  export SLDC_GATE_ROOT="$TESTDIR"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "S2: file-size FAIL con fichero >150 lineas" {
  mkdir -p "$TESTDIR/.opencode/agents"
  python3 -c "print('\n'.join(['# line']*160))" > "$TESTDIR/.opencode/agents/big.md"
  run bash "$SCRIPT" --check file-size
  [[ "$output" == *FAIL* ]]
  [ "$status" -eq 1 ]
}

@test "S2: file-size PASS sin ficheros grandes" {
  mkdir -p "$TESTDIR/.opencode/agents"
  python3 -c "print('\n'.join(['# line']*50))" > "$TESTDIR/.opencode/agents/small.md"
  run bash "$SCRIPT" --check file-size
  [[ "$output" == *PASS* ]]
  [ "$status" -eq 0 ]
}

@test "S2: --check con nombre invalido sale con error (exit 2)" {
  run bash "$SCRIPT" --check no-existe
  [ "$status" -eq 2 ]
}

@test "S2: --json emite JSON con verdict y checks" {
  run bash "$SCRIPT" --json
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['verdict'] in ('PASS', 'FAIL')
assert isinstance(d['checks'], dict)
assert isinstance(d['details'], dict)
assert 'file-size' in d['checks']
"
}

@test "S2: --report genera fichero con secciones" {
  run bash "$SCRIPT" --report "$TESTDIR/report.md"
  [ -f "$TESTDIR/report.md" ]
  grep -q "Standards Compliance Gate" "$TESTDIR/report.md"
  grep -q "VERDICT" "$TESTDIR/report.md"
}

@test "S2: el set de checks incluye los 6 esperados" {
  run bash "$SCRIPT" --json
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for c in ['file-size','skill-audit','agent-schema','drift','rules','confid']:
    assert c in d['checks'], f'falta {c}'
"
}

@test "S2: regla de exencion cross-frontend-coverage.md" {
  mkdir -p "$TESTDIR/docs/rules/domain"
  python3 -c "print('\n'.join(['# x']*200))" > "$TESTDIR/docs/rules/domain/cross-frontend-coverage.md"
  run bash "$SCRIPT" --check file-size
  [[ "$output" == *PASS* ]]
}

# ── Comportamiento discriminante con dependencias simuladas (S03 calidad) ────
# El gate resuelve sus checks hermanos desde su propio directorio: se copia a
# un scripts/ temporal con stubs para controlar cada veredicto.

mk_gate() {
  GD="$(mktemp -d)"
  mkdir -p "$GD/scripts" "$GD/docs/rules/domain" "$GD/.opencode/agents" "$GD/.opencode/commands"
  cp "$SCRIPT" "$GD/scripts/gate.sh"
  stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$GD/scripts/$1"; chmod +x "$GD/scripts/$1"; }
  stub skill-catalog-audit.sh 'echo "{\"fail\": 0}"'
  stub agents-opencode-convert.sh 'echo "agents in sync"'
  stub claude-md-drift-check.sh 'exit 0'
  stub confidentiality-scan.sh 'exit 0'
  touch "$GD/docs/rules/domain/critical-rules-extended.md" "$GD/docs/rules/domain/pm-config.md"
  export SLDC_GATE_ROOT="$GD"
}

gate() { bash "$GD/scripts/gate.sh" "$@"; }

lines_file() { python3 -c "print('\n'.join(['x']*$1))" > "$2"; }

@test "S2: usa modo estricto de bash (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$SCRIPT"
}

@test "S2: file-size boundary: 150 líneas pasa, 151 falla y nombra el fichero con su tamaño" {
  mk_gate
  lines_file 150 "$GD/.opencode/agents/justo.md"
  run gate --check file-size
  [ "$status" -eq 0 ]
  lines_file 151 "$GD/.opencode/agents/pasado.md"
  run gate --check file-size
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 fichero(s) >150 lineas: pasado.md(151)"* ]]
  [[ "$output" != *"justo.md"* ]]
}

@test "S2: file-size cuenta los ficheros grandes de commands, agents y rules" {
  mk_gate
  lines_file 200 "$GD/.opencode/agents/a.md"
  lines_file 200 "$GD/.opencode/commands/c.md"
  lines_file 200 "$GD/docs/rules/domain/r.md"
  run gate --check file-size
  [[ "$output" == *"3 fichero(s)"* ]]
}

@test "S2: file-size ignora ficheros grandes fuera de los directorios vigilados y las exenciones" {
  mk_gate
  mkdir -p "$GD/docs/otros"
  lines_file 500 "$GD/docs/otros/enorme.md"
  lines_file 500 "$GD/docs/rules/domain/INDEX.md"
  lines_file 500 "$GD/docs/rules/domain/savia-ethical-principles.md"
  run gate --check file-size
  [ "$status" -eq 0 ]
  [[ "$output" == *"file-size: PASS"* ]]
}

@test "S2: file-size con directorios vacíos (empty tree) pasa" {
  mk_gate
  run gate --check file-size
  [ "$status" -eq 0 ]
}

@test "S2: rules FAIL nombra el fichero que falta y PASS cuando están ambos" {
  mk_gate
  run gate --check rules
  [ "$status" -eq 0 ]
  unlink "$GD/docs/rules/domain/pm-config.md"
  run gate --check rules
  [ "$status" -eq 1 ]
  [[ "$output" == *"rules: FAIL: pm-config"* && "$output" != *"critical-rules"* ]]
  unlink "$GD/docs/rules/domain/critical-rules-extended.md"
  run gate --check rules
  [[ "$output" == *"critical-rules"* && "$output" == *"pm-config"* ]]
}

@test "S2: skill-audit PASS con fail=0, FAIL con el recuento si fail>0" {
  mk_gate
  run gate --check skill-audit
  [ "$status" -eq 0 ]
  printf '#!/usr/bin/env bash\necho "{\\"fail\\": 3}"\n' > "$GD/scripts/skill-catalog-audit.sh"
  run gate --check skill-audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"reporta 3 FAIL"* ]]
}

@test "S2: skill-audit trata una salida no JSON como FAIL (fail por defecto = 1)" {
  mk_gate
  printf '#!/usr/bin/env bash\necho "roto"\n' > "$GD/scripts/skill-catalog-audit.sh"
  run gate --check skill-audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"reporta 1 FAIL"* ]]
}

@test "S2: agent-schema PASS solo si el conversor dice in sync; si no, FAIL con la primera línea" {
  mk_gate
  run gate --check agent-schema
  [ "$status" -eq 0 ]
  printf '#!/usr/bin/env bash\necho "agent x out of sync"\necho "segunda linea"\nexit 1\n' > "$GD/scripts/agents-opencode-convert.sh"
  run gate --check agent-schema
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: agent x out of sync"* && "$output" != *"segunda linea"* ]]
}

@test "S2: drift FAIL incluye el nombre del check que falla y su mensaje" {
  mk_gate
  printf '#!/usr/bin/env bash\necho "contadores desfasados"\nexit 1\n' > "$GD/scripts/claude-md-drift-check.sh"
  run gate --check drift
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude-md: contadores desfasados"* ]]
}

@test "S2: drift ejecuta readme y spec-status solo si existen, y reporta cada uno" {
  mk_gate
  run gate --check drift
  [ "$status" -eq 0 ]
  printf '#!/usr/bin/env bash\nexit 1\n' > "$GD/scripts/readme-drift-check.sh"
  printf '#!/usr/bin/env bash\necho "estado"\nexit 1\n' > "$GD/scripts/spec-status-drift-audit.sh"
  chmod +x "$GD/scripts/readme-drift-check.sh" "$GD/scripts/spec-status-drift-audit.sh"
  run gate --check drift
  [ "$status" -eq 1 ]
  [[ "$output" == *"readme:"* && "$output" == *"spec-status: estado"* ]]
}

@test "S2: confid PASS con exit 0 del scan; exit 1 y exit 2 son FAIL" {
  mk_gate
  run gate --check confid
  [ "$status" -eq 0 ]
  for rc in 1 2; do
    printf '#!/usr/bin/env bash\nexit %s\n' "$rc" > "$GD/scripts/confidentiality-scan.sh"
    run gate --check confid
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL: scan de confidencialidad"* ]]
  done
}

@test "S2: sin --check ejecuta los 6 checks y un solo fallo da VERDICT FAIL con su nombre" {
  mk_gate
  run gate
  [ "$status" -eq 0 ]
  [ "$(grep -c '^[a-z-]*: PASS' <<< "$output")" -eq 6 ]
  [[ "$output" == *"VERDICT: PASS"* ]]
  unlink "$GD/docs/rules/domain/pm-config.md"
  run gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERDICT: FAIL ( rules)"* ]]
  [ "$(grep -c '^[a-z-]*: PASS' <<< "$output")" -eq 5 ]
}

@test "S2: --check ejecuta únicamente ese check" {
  mk_gate
  run gate --check rules
  [ "$(grep -c '^[a-z-]*: ' <<< "$output")" -eq 1 ]
  [[ "$output" == rules:* ]]
}

@test "S2: --json con un fallo da verdict FAIL, failed y details del check" {
  mk_gate
  lines_file 300 "$GD/.opencode/agents/grande.md"
  run gate --json --check file-size
  [ "$status" -eq 1 ]
  run jq -e '.verdict == "FAIL" and .failed == ["file-size"] and .checks["file-size"] == "FAIL" and (.details["file-size"] | contains("grande.md(300)"))' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "S2: --json con todo PASS da failed vacío y details vacío" {
  mk_gate
  run gate --json
  [ "$status" -eq 0 ]
  run jq -e '.verdict == "PASS" and .failed == [] and .details == {} and (.checks | length) == 6' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "S2: --report refleja el veredicto FAIL y el detalle del check que falló" {
  mk_gate
  unlink "$GD/docs/rules/domain/pm-config.md"
  run gate --report "$GD/rep.md"
  [ "$status" -eq 1 ]
  grep -q '^rules: FAIL: pm-config' "$GD/rep.md"
  grep -q '^VERDICT: FAIL' "$GD/rep.md"
}

@test "S2: --report con todo PASS termina en VERDICT: PASS" {
  mk_gate
  run gate --report "$GD/rep.md"
  grep -q '^VERDICT: PASS$' "$GD/rep.md"
}

@test "S2: opción desconocida y --help salen 2 con el uso; check desconocido lista los válidos" {
  mk_gate
  run gate --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"error: --nope"* && "$output" == *"Usage:"* ]]
  run gate --help
  [ "$status" -eq 2 ]
  [[ "$output" == *"Checks (default todos)"* ]]
  run gate --check zzz
  [ "$status" -eq 2 ]
  [[ "$output" == *"validos: file-size skill-audit agent-schema drift rules confid"* ]]
}
