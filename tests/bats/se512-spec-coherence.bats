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
  mutate '**El ejecutor aplica (a), (b), (c) y (d) por sí mismo desde S2**' 'S3 las añade'
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

@test "R-PENDING: sin convertir minutos a segundos el contrato falla" {
  mutate 'ceil(main_pending_timeout * 60 / MERGE_SPRINT_POLL_S)' 'ceil(main_pending_timeout / MERGE_SPRINT_POLL_S)'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no convierte minutos a segundos"* ]]
}

@test "R-KEY: quitar la prohibición de clave local rompe el contrato" {
  mutate 'La clave privada nunca reside en el equipo de los agentes' 'La clave puede residir en el equipo'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-KEY: la clave privada debe quedar fuera"* ]]
}

@test "R-KEY: sin declarar que no enmienda LAW-HUMAN-002 falla" {
  mutate 'Esta spec no enmienda LAW-HUMAN-002.' 'La spec relaja LAW-HUMAN-002.'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-KEY: R1 no declara que la spec no enmienda LAW-HUMAN-002"* ]]
}

@test "R-WFEXEC (seg. P1-1): R1 sin (d) falla" {
  mutate '**El ejecutor aplica (a), (b), (c) y (d) por sí mismo desde S2**' '**El ejecutor aplica (a), (b) y (c) por sí mismo desde S2**'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-WFEXEC: R1 no aplica (d)"* ]]
}

@test "R-WFEXEC (seg. P1-1): derivar (d) sin cierre transitivo falla" {
  mutate 'Después, el **cierre transitivo** sobre' 'Después, el recorrido sobre'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-WFEXEC: R2.3 no deriva (d)"* ]]
}

@test "R-WFEXEC (seg. P1-1): error al derivar (d) sin STOP en R3 falla" {
  mutate '| Error al derivar `WORKFLOW_EXEC_PATHS` (R2.3) | STOP `forced_exclude_error`;' '| Error al derivar `WORKFLOW_EXEC_PATHS` (R2.3) | se sigue con la lista parcial;'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-WFEXEC: un error al derivar (d) no es STOP"* ]]
}

@test "R-WFEXEC (seg. P1-1): AC-11 sin el caso de scripts/changelog-consolidate.sh falla" {
  mutate '`scripts/changelog-consolidate.sh` (citado por un' '`scripts/otro.sh` (citado por un'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-WFEXEC: AC-11 no prueba scripts/changelog-consolidate.sh"* ]]
}

@test "R-WFEXEC (seg. P1-1): AC-11 sin el caso solo transitivo falla" {
  mutate '`scripts/generate-capability-map.py` (solo por cierre transitivo)' '`scripts/x.py` (solo por cierre transitivo)'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-WFEXEC: AC-11 no prueba scripts/generate-capability-map.py"* ]]
}

@test "R-ACTIVATION: sin enmienda humana previa no se puede activar" {
  mutate 'Activación bloqueada hasta la enmienda humana de S4' 'Activación inmediata desde S2'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-ACTIVATION"* ]]
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

# --- Quinta ronda (revisiones sobre 66ee1659) ---

@test "R-WFEXEC (corr. P2-3): R2.3 sin forced_exclude_error falla" {
  mutate 'derivación da error, STOP `forced_exclude_error` sin' 'derivación da error, se sigue sin'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es STOP en R2.3"* ]]
}

@test "R-WFEXEC (corr. P2-3): AC-11 sin forced_exclude_error falla" {
  mutate 'workflow ilegible (fixture), STOP `forced_exclude_error` sin fusión.' 'workflow ilegible (fixture), se sigue.'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-WFEXEC: AC-11 no prueba forced_exclude_error"* ]]
}

@test "R-ACTIVATION (corr. P2-3): la frase fuera de Dependencias no basta" {
  mutate '- **Activación bloqueada hasta la enmienda humana de S4.**' '- **Activación libre.**'
  printf '\nNota: Activación bloqueada hasta la enmienda humana de S4.\n' >> "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-ACTIVATION"* ]]
}

@test "R-WFIMPORT (seg. P1-1): cierre sin imports de Python falla" {
  mutate 'en Python, cada `import x` y `from x import ...`' 'en Python, nada'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no sigue los imports de Python"* ]]
}

@test "R-WFIMPORT (seg. P1-1): cierre sin source de bash falla" {
  mutate 'en bash, `source` y `.` de un fichero' 'en bash, nada'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no sigue source/. de bash"* ]]
}

@test "R-WFIMPORT (seg. P1-1): lo no resoluble sin excluir el directorio falla" {
  mutate 'se excluye **todo el' 'se ignora **el'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no excluye el directorio entero"* ]]
}

@test "R-WFIMPORT (seg. P1-1): AC-11 sin el caso solo por import falla" {
  mutate '`scripts/sam_model.py`
  (solo por import de Python' '`scripts/x_model.py`
  (solo por import de Python'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-11 no prueba scripts/sam_model.py"* ]]
}

@test "R-WFIMPORT (seg. P2-1): semillas con lista de prefijos falla" {
  mutate '**sin lista de prefijos**' 'con la lista de prefijos de siempre'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lista de prefijos"* ]]
}

@test "R-WFIMPORT (seg. P2-1): AC-11 sin la ruta raíz mcp.json falla" {
  mutate '`mcp.json` (raíz, citado por `ci.yml`' '`scripts/y.json` (citado por `ci.yml`'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-11 no prueba \`mcp.json\`"* ]]
}

@test "R-WFIMPORT (seg. P2-1): (b) sin manifiestos de dependencias falla" {
  mutate 'los manifiestos de dependencias en cualquier directorio' 'los ficheros de siempre'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"manifiestos de dependencias"* ]]
}

@test "R-WFIMPORT (corr. P2-2): sin definir los filtros on.paths falla" {
  mutate 'filtros `paths`/`paths-ignore` disparan, no ejecutan' 'filtros cuentan igual'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"filtros on.paths"* ]]
}

@test "R-WFIMPORT (corr. P2-2): AC-11 sin fixture on.push.paths falla" {
  mutate 'un workflow con `on.push.paths:' 'un workflow con `jobs:'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC-11 no prueba on.push.paths"* ]]
}

@test "R-GUARDVIAS (seg. P2-2): R6 sin la vía gh api merge falla" {
  mutate 'una llamada `gh api` a `/pulls/<n>/merge`' 'una llamada `gh api` cualquiera'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-GUARDVIAS: R6"* ]]
}

@test "R-GUARDVIAS (seg. P2-2): AC-13 sin el caso de push a main falla" {
  mutate 'un `git push` con refspec `HEAD:` hacia `main`' 'otra orden'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-GUARDVIAS: AC-13"* ]]
}

@test "R-AUTHOR (corr. P2-5): sin identidad de la autora falla" {
  mutate '**Identidad de la autora.**' 'Autora:'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-AUTHOR: R2.5"* ]]
}

@test "R-C3WIN (corr. P2-2): C3 sin acotar a la ventana falla" {
  mutate 'registrada dentro de `[not_before, not_after)`' 'registrada'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C3 no dice qué filas cuenta"* ]]
}

@test "R-C3WIN (corr. P2-3): R2.5 «reutiliza sin cambios» falla" {
  mutate 'La política lo reutiliza y le' 'La política lo reutiliza sin cambios y le'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin cambios"* ]]
}

@test "R-C3WIN (seg. P2-1): sin declarar el límite del orquestador comprometido falla" {
  mutate '**C1-C3 no protegen frente a un orquestador comprometido**' '**C1-C3 bastan**'
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"orquestador"* ]]
}
