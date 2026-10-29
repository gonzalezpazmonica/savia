#!/usr/bin/env bats
# SE-376 — overnight-sprint: comportamiento de las salvaguardas que la skill ejecuta.
# Doble opt-in (SPEC-186, SE-343), clasificación de fallos (SE-250) y estado del bucle (SE-228).
# Ref: .claude/skills/overnight-sprint/SKILL.md · docs/rules/domain/autonomous-safety.md
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OPTIN="$REPO_ROOT/scripts/savia-double-optin-check.sh"
  TOKENS="$REPO_ROOT/scripts/detect-token-exhaustion.sh"
  # cwd aislado: el gate busca scripts/operator-grant.sh en el cwd; aquí no hay grant real.
  WORK="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  cd "$WORK" || return 1
  export SAVIA_OPTIN_AUDIT_LOG="$WORK/optin-audit.log"
  unset SAVIA_TESTING OVERNIGHT_SPRINT_ENABLED
}

teardown() { cd "$REPO_ROOT" || true; }

optin() { run bash "$OPTIN" --skill overnight-sprint "$@"; }

@test "safety: los tres scripts de la skill declaran set -uo pipefail" {
  for s in savia-double-optin-check.sh detect-token-exhaustion.sh loop-state-init.sh; do
    grep -q "set -uo pipefail" "$REPO_ROOT/scripts/$s"
  done
}

# ── Doble opt-in: hacen falta los dos factores ──────────────────────────────

@test "opt-in: variable y flag ⇒ exit 0 y queda auditado como ok" {
  OVERNIGHT_SPRINT_ENABLED=true optin --confirm-autonomous
  [ "$status" -eq 0 ]
  grep -qP 'overnight-sprint\tenv=1\tflag=1\tverdict=ok' "$SAVIA_OPTIN_AUDIT_LOG"
}

@test "opt-in: solo la variable heredada (sin flag) ⇒ exit 1, nombra el flag que falta y audita denied" {
  OVERNIGHT_SPRINT_ENABLED=true optin
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Flag explicito: --confirm-autonomous"* ]]
  [[ "$output" == *"[OK]    Variable de entorno: OVERNIGHT_SPRINT_ENABLED=true"* ]]
  grep -qP 'overnight-sprint\tenv=1\tflag=0\tverdict=denied' "$SAVIA_OPTIN_AUDIT_LOG"
}

@test "opt-in: solo el flag (sin variable ni grant) ⇒ exit 1 y nombra la variable que falta" {
  optin --confirm-autonomous
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno: OVERNIGHT_SPRINT_ENABLED=true"* ]]
}

@test "opt-in edge: variable empty (definida pero vacía) cuenta como ausente" {
  OVERNIGHT_SPRINT_ENABLED="" optin --confirm-autonomous
  [ "$status" -eq 1 ]
}

@test "opt-in: la variable debe valer exactamente 'true' (TRUE, 1 o yes no cuentan)" {
  for v in TRUE 1 yes; do
    OVERNIGHT_SPRINT_ENABLED="$v" optin --confirm-autonomous
    [ "$status" -eq 1 ]
  done
}

@test "opt-in: un grant autonomy:overnight-sprint vigente sustituye a la variable (SE-343), no al flag" {
  # El gate ancla el grant a la raíz de SU repo (#1281): se ejecuta una copia
  # dentro de un repo falso cuyo scripts/operator-grant.sh concede el scope.
  mkdir -p fake/scripts
  cp "$OPTIN" fake/scripts/
  printf '#!/usr/bin/env bash\n[ "$3" = "autonomy:overnight-sprint" ]\n' > fake/scripts/operator-grant.sh
  run bash fake/scripts/savia-double-optin-check.sh --skill overnight-sprint --confirm-autonomous
  [ "$status" -eq 0 ]
  run bash fake/scripts/savia-double-optin-check.sh --skill overnight-sprint
  [ "$status" -eq 1 ]
}

@test "opt-in: un operator-grant.sh plantado en el cwd NO concede el factor (#1281)" {
  mkdir -p scripts
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/operator-grant.sh
  optin --confirm-autonomous
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno: OVERNIGHT_SPRINT_ENABLED=true"* ]]
}

@test "opt-in: el bypass de tests exige SAVIA_TESTING=1 dentro de BATS; fuera de BATS no abre" {
  SAVIA_TESTING=1 optin
  [ "$status" -eq 0 ]
  run env -u BATS_TEST_NAME SAVIA_TESTING=1 bash "$OPTIN" --skill overnight-sprint
  [ "$status" -eq 1 ]
}

@test "opt-in: skill desconocida o sin --skill ⇒ exit 2" {
  run bash "$OPTIN" --skill overnight-sprintx --confirm-autonomous
  [ "$status" -eq 2 ]
  run bash "$OPTIN" --confirm-autonomous
  [ "$status" -eq 2 ]
}

# ── SE-250: causa del fallo antes de contar el intento ─────────────────────

@test "fallos: agotar el contexto ⇒ token_exhaustion (se puede escalar de tier)" {
  printf 'API error: context_length_exceeded (prompt is too long)\n' > it.log
  run bash "$TOKENS" --log it.log
  [ "$status" -eq 0 ]
  [ "$output" = "CAUSE=token_exhaustion" ]
}

@test "fallos: un error de código ⇒ logic_error (no se escala)" {
  printf 'not ok 3 parser\nTypeError: x is undefined\n' > it.log
  run bash "$TOKENS" --log it.log
  [ "$status" -eq 0 ]
  [ "$output" = "CAUSE=logic_error" ]
}

@test "fallos: si aparecen ambas señales gana token_exhaustion" {
  printf 'TypeError: a\nMaximum context length reached\n' > it.log
  run bash "$TOKENS" --log it.log
  [ "$output" = "CAUSE=token_exhaustion" ]
}

@test "fallos boundary: sin señales ⇒ unknown y exit 2 (conservador: no escalar)" {
  printf 'iteración interrumpida\n' > it.log
  run bash "$TOKENS" --log it.log
  [ "$status" -eq 2 ]
  [ "$output" = "CAUSE=unknown" ]
}

@test "fallos edge: log nonexistent o empty ⇒ exit 1" {
  run bash "$TOKENS" --log no-existe.log
  [ "$status" -eq 1 ]
  : > vacio.log
  run bash "$TOKENS" --log vacio.log
  [ "$status" -eq 1 ]
}

# ── SE-228: STATE.md del bucle ──────────────────────────────────────────────

@test "estado: --dry-run no escribe; init crea STATE.md y no lo pisa sin --force" {
  mkdir -p proj/scripts
  cp "$REPO_ROOT/scripts/loop-state-init.sh" proj/scripts/
  run bash proj/scripts/loop-state-init.sh --skill overnight-sprint --dry-run
  [ "$status" -eq 0 ]
  [ ! -e proj/output/loop-state/overnight-sprint/STATE.md ]
  run bash proj/scripts/loop-state-init.sh --skill overnight-sprint
  [ "$status" -eq 0 ]
  state=proj/output/loop-state/overnight-sprint/STATE.md
  [ -s "$state" ]
  echo "marca-de-progreso" >> "$state"
  run bash proj/scripts/loop-state-init.sh --skill overnight-sprint
  [ "$status" -eq 0 ]
  grep -q "marca-de-progreso" "$state"
  run bash proj/scripts/loop-state-init.sh --skill overnight-sprint --force
  [ "$status" -eq 0 ]
  run grep -q "marca-de-progreso" "$state"
  [ "$status" -ne 0 ]
}

@test "estado: invalid, sin --skill ⇒ exit 1" {
  mkdir -p proj/scripts
  cp "$REPO_ROOT/scripts/loop-state-init.sh" proj/scripts/
  run bash proj/scripts/loop-state-init.sh
  [ "$status" -eq 1 ]
}
