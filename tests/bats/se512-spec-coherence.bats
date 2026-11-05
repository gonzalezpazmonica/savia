#!/usr/bin/env bats
# SE-512 — coherencia interna de la spec (hallazgos de la revisión de la PR #1485).
# Ref: docs/specs/SE-512-grant-de-politica-nocturno.spec.md
# Comprobador: tests/se512_spec_check.py. Cada regla tiene caso positivo
# (la spec real pasa) y caso negativo (una copia mutada falla con su motivo).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-512-grant-de-politica-nocturno.spec.md"
CHECK="$REPO_ROOT/tests/se512_spec_check.py"

setup() {
  set -uo pipefail
  MUT="$BATS_TEST_TMPDIR/spec.md"
  cp "$SPEC" "$MUT"
}

check() { python3 -I "$CHECK" "$1"; }

# Muta el fichero con Python (sustitución literal, una vez) y exige que haya cambiado:
# una mutación que no encuentra su texto no puede dar un falso negativo.
mutate() {
  python3 -I - "$MUT" "$1" "$2" <<'EOF'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if old not in s:
    sys.exit("mutación sin efecto: " + old[:60])
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
EOF
}

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

@test "R-FORCED (P1-1): sin lista propia del ejecutor en R1 falla" {
  mutate '**El ejecutor aplica (a), (b) y (c) por sí mismo desde S2**' 'S3 las añade'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-FORCED: R1 no dice"* ]]
}

@test "R-FORCED (P1-1): AC-11 que llama «ya existente» a .claude/hooks falla" {
  mutate 'en una ruta de exclusión forzosa, no' 'en una ruta de exclusión forzosa ya existente, no'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-11 llama «ya existente»"* ]]
}

@test "R-FORCED (P1-1): AC-11 sin caso de .claude/agents falla" {
  mutate '`.claude/agents/revisora.md` y ' ''
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-11 no prueba la ruta .claude/agents/"* ]]
}

@test "R-ACDEF (P2-1): AC-8b citado sin viñeta propia falla" {
  mutate '- **AC-8b (S2, ampliar en `run`)**' '  Ampliar en `run`:'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-ACDEF: AC-8b se cita pero no tiene viñeta propia"* ]]
}

@test "R-PLAN: AC definido fuera del plan falla" {
  mutate ', AC-16, AC-17 |' ', AC-16 |'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PLAN: AC-17 no aparece en el plan"* ]]
}

@test "R-RUNAC (P2-2): sin AC de revocación en S2 falla" {
  mutate 'Tras `merge-sprint.sh revoke` entre dos pasadas' 'Tras borrar el grant entre dos pasadas'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ningún AC de S2 prueba \`revoke\`"* ]]
}

@test "R-RUNAC (P2-2): sin AC de universe frozen en run falla" {
  mutate 'Con `universe: frozen` y lista' 'Con universo congelado y lista'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ningún AC de S2 prueba \`universe: frozen\`"* ]]
}

@test "R-PENDING (P2-3): plazo de 30 min frente al sondeo de 20 falla" {
  mutate 'la pasada espera hasta `main_pending_timeout` (20 min' 'la pasada espera hasta 30 min (20 min'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plazo de 30 min"* ]]
}

@test "R-PENDING (P2-3): AC-6 sin action_required falla" {
  mutate 'Con un check-run en `action_required` o
  `stale`' 'Con un check-run raro'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-6 no prueba action_required"* ]]
}

@test "R-NOCHECKS (P2-4): AC-6 sin el caso sin check-runs falla" {
  mutate 'sigue sin ninguno, STOP `main_sin_checks` sin fusión' 'sigue sin ninguno, no fusiona'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-6 no prueba main_sin_checks"* ]]
}

@test "R-GLOB (seg. P2-1): fnmatch sobre la ruta entera falla" {
  mutate 'Los globs se evalúan en Python, sin expansión de shell, **por segmentos**' 'Los globs se evalúan con `fnmatch.fnmatchcase` sobre la ruta relativa'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-GLOB: los globs se evalúan con fnmatch"* ]]
}

@test "R-GLOB (seg. P2-1): AC-11c sin negativo docs/x/y falla" {
  mutate 'toca `docs/x/y.md` (`*` no cruza `/`' 'toca otra ruta (`*` no cruza `/`'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-11c no tiene el negativo"* ]]
}

@test "R-KEY (seg. P2-2): sin requisito de la clave ed25519 falla" {
  mutate '**Requisito de la clave ed25519.**' 'Sobre la clave:'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-KEY"* ]]
}

@test "R-GUARD (seg. P2-3): rollback con la condición antigua falla" {
  mutate 'El
guard nocturno se activa con cualquiera' 'El guard nocturno se desactiva quitando `SAVIA_NIGHT_MODE`; sin grant de política vigente no actúa. Se activa con cualquiera'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"el rollback contradice la condición OR"* ]]
}

@test "R-GUARD (seg. P2-3): AC-13 sin el caso de grant sin SAVIA_NIGHT_MODE falla" {
  mutate '(condición OR de R6)' '(R6)'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-13 no prueba el guard"* ]]
}

@test "R-HOLDEQ (nota): equivalencia que no hereda HOLD falla" {
  mutate 'hereda **todas** las revisiones' 'hereda las APPROVE'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-HOLDEQ"* ]]
}
