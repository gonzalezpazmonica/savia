#!/usr/bin/env bats
# SE-376 S03 — tech-research-agent: comportamiento del gate de arranque (doble opt-in, SPEC-186) que la skill
# invoca antes de actuar. Cada caso ejecuta el script real; ninguno comprueba solo que exista.
# Ref: .claude/skills/tech-research-agent/SKILL.md · scripts/savia-double-optin-check.sh
set -uo pipefail

SCRIPT="scripts/savia-double-optin-check.sh"
SKILL="tech-research-agent"
ENVVAR="TECH_RESEARCH_AGENT_ENABLED"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # El bypass de pruebas del script exige SAVIA_TESTING=1; aquí NO se activa: se prueba el gate real.
  unset SAVIA_TESTING OVERNIGHT_SPRINT_ENABLED CODE_IMPROVEMENT_LOOP_ENABLED ADVERSARIAL_SECURITY_ENABLED \
        TECH_RESEARCH_AGENT_ENABLED SAVIA_DUAL_FAILOVER_ENABLED
  export SAVIA_GRANTS_DIR="$BATS_TEST_TMPDIR/grants-vacio"; mkdir -p "$SAVIA_GRANTS_DIR"
  export SAVIA_OPTIN_AUDIT_LOG="$BATS_TEST_TMPDIR/audit/optin.log"
}

# bats borra BATS_TEST_TMPDIR; aquí solo se retira lo exportado para que no se herede.
teardown() { unset "$ENVVAR" SAVIA_GRANTS_DIR SAVIA_OPTIN_AUDIT_LOG; }

run_gate() { cd "$ROOT" && bash "$SCRIPT" --skill "$SKILL" "$@"; }

@test "positivo: variable de entorno y --confirm-autonomous juntos → exit 0 y registro ok" {
  export "$ENVVAR=true"
  run run_gate --confirm-autonomous
  [ "$status" -eq 0 ]
  grep -q "verdict=ok" "$SAVIA_OPTIN_AUDIT_LOG"
  grep -q "$SKILL" "$SAVIA_OPTIN_AUDIT_LOG"
}

@test "negativo: solo el flag, sin variable de entorno → bloquea y nombra la variable que falta" {
  run run_gate --confirm-autonomous
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno: $ENVVAR=true"* ]]
  [[ "$output" == *"[OK]    Flag explicito"* ]]
  grep -q "verdict=denied" "$SAVIA_OPTIN_AUDIT_LOG"
}

@test "negativo: solo la variable, sin el flag → bloquea y nombra el flag que falta" {
  export "$ENVVAR=true"
  run run_gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Flag explicito: --confirm-autonomous"* ]]
  [[ "$output" == *"[OK]    Variable de entorno: $ENVVAR=true"* ]]
}

@test "negativo: sin ningún factor → bloquea con ambos faltantes" {
  run run_gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno"* ]]
  [[ "$output" == *"[FALTA] Flag explicito"* ]]
}

@test "limite boundary: la variable debe valer exactamente true; 1, TRUE, false y empty no activan" {
  for v in 1 TRUE yes false ""; do
    export "$ENVVAR=$v"
    run run_gate --confirm-autonomous
    [ "$status" -eq 1 ] || { echo "valor '$v' activó el gate"; false; }
  done
}

@test "aislamiento: la variable de otra skill autónoma no desbloquea esta" {
  export OVERNIGHT_SPRINT_ENABLED=true CODE_IMPROVEMENT_LOOP_ENABLED=true SAVIA_DUAL_FAILOVER_ENABLED=true
  [ "$ENVVAR" != "ADVERSARIAL_SECURITY_ENABLED" ] && export ADVERSARIAL_SECURITY_ENABLED=true
  [ "$ENVVAR" != "TECH_RESEARCH_AGENT_ENABLED" ] && export TECH_RESEARCH_AGENT_ENABLED=true
  run run_gate --confirm-autonomous
  [ "$status" -eq 1 ]
}

@test "seguridad: el bypass de pruebas no actúa con SAVIA_TESTING=1 fuera de bats ni sin él" {
  # Con SAVIA_TESTING=1 pero sin BATS_TEST_NAME el script debe seguir exigiendo los dos factores.
  run env -u BATS_TEST_NAME SAVIA_TESTING=1 bash "$ROOT/$SCRIPT" --skill "$SKILL" --confirm-autonomous
  [ "$status" -eq 1 ]
}

@test "error nonexistent: skill desconocida y --skill ausente → exit 2 sin escribir registro" {
  run bash "$ROOT/$SCRIPT" --skill no-existe --confirm-autonomous
  [ "$status" -eq 2 ]
  run bash "$ROOT/$SCRIPT" --confirm-autonomous
  [ "$status" -eq 2 ]
  [ ! -f "$SAVIA_OPTIN_AUDIT_LOG" ]
}

@test "error: un fallo al escribir el registro no abre el gate cerrado ni cierra el abierto" {
  export SAVIA_OPTIN_AUDIT_LOG="/proc/no-existe/optin.log"
  run run_gate --confirm-autonomous
  [ "$status" -eq 1 ]
  export "$ENVVAR=true"
  run run_gate --confirm-autonomous
  [ "$status" -eq 0 ]
}

@test "limite zero args: --skill sin valor al final no activa nada y el registro no se crea" {
  export "$ENVVAR=true"
  run bash "$ROOT/$SCRIPT" --confirm-autonomous --skill
  [ "$status" -eq 2 ]
  [ ! -f "$SAVIA_OPTIN_AUDIT_LOG" ]
}

@test "ayuda: --help imprime el uso y la lista de skills cubiertas sin evaluar el gate (usage)" {
  run bash "$ROOT/$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--confirm-autonomous"* ]]
  [[ "$output" == *"$SKILL"* ]]
  [ ! -f "$SAVIA_OPTIN_AUDIT_LOG" ]
}

@test "mapeo env_var_for_skill: cada skill lee su propia variable; la de esta no abre a otra skill" {
  export "$ENVVAR=true"
  run bash "$ROOT/$SCRIPT" --skill overnight-sprint --confirm-autonomous
  [ "$status" -eq 1 ]
  run bash "$ROOT/$SCRIPT" --skill "$SKILL" --confirm-autonomous
  [ "$status" -eq 0 ]
}

@test "registro log_attempt: cada intento deja una línea con skill, factores y veredicto" {
  run run_gate --confirm-autonomous
  [ "$status" -eq 1 ]
  export "$ENVVAR=true"
  run run_gate --confirm-autonomous
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$SAVIA_OPTIN_AUDIT_LOG")" -eq 2 ]
  grep -q "env=0.flag=1.verdict=denied" "$SAVIA_OPTIN_AUDIT_LOG"
  grep -q "env=1.flag=1.verdict=ok" "$SAVIA_OPTIN_AUDIT_LOG"
}
