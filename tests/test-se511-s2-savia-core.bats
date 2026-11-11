#!/usr/bin/env bats
# SE-511 S2 — bloque compacto generado (AC-5, AC-6), gates del contexto fijo
# (AC-7, AC-8) y comprobaciones deterministas de la validación D4 (AC-9).
# Ref: docs/specs/SE-511-contexto-fijo-por-turno-a-la-mitad.spec.md

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GEN="$ROOT/scripts/generate-savia-core.py"
  MEASURE="$ROOT/scripts/context-fixed-measure.sh"
  CORE="$ROOT/docs/rules/domain/savia-core.md"
}

# Copia las fuentes del bloque a una raíz aislada (para romperlas sin tocar el repo).
core_root() {
  R="$BATS_TEST_TMPDIR/core"
  mkdir -p "$R/.claude/profiles" "$R/docs/rules/domain"
  cp "$ROOT/.claude/profiles/savia.md" "$R/.claude/profiles/"
  for f in radical-honesty caveman-default autonomous-safety savia-core; do
    cp "$ROOT/docs/rules/domain/$f.md" "$R/docs/rules/domain/"
  done
  cp "$ROOT/CLAUDE.md" "$R/CLAUDE.md"
}

# ── AC-5: generado, no redactado ─────────────────────────────────────────────

@test "AC-5: el bloque versionado coincide con la regeneración desde sus fuentes" {
  run python3 "$GEN" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"al día"* ]]
}

@test "AC-5: regenerar dos veces da el mismo bloque byte a byte" {
  a="$(python3 "$GEN" --stdout | sha256sum)"
  b="$(python3 "$GEN" --stdout | sha256sum)"
  [ "$a" = "$b" ]
}

@test "AC-5 negativo: editar el bloque a mano hace fallar --check" {
  core_root
  echo "- frase añadida a mano" >> "$R/docs/rules/domain/savia-core.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT"* ]]
}

@test "AC-5 negativo: cambiar una fuente sin regenerar hace fallar --check" {
  core_root
  sed -i 's/^1\. \*\*No filler\*\*/1. **No filler (editado)**/' "$R/docs/rules/domain/radical-honesty.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --check
  [ "$status" -eq 1 ]
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN"
  [ "$status" -eq 0 ]
  grep -qF "No filler (editado)" "$R/docs/rules/domain/savia-core.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --check
  [ "$status" -eq 0 ]
}

@test "AC-5 negativo: región sin cierre falla sin escribir el bloque" {
  core_root
  sed -i '/<!-- \/savia-core:reglas -->/d' "$R/docs/rules/domain/caveman-default.md"
  before="$(sha256sum < "$R/docs/rules/domain/savia-core.md")"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin cierre"* || "$output" == *"anidada"* ]]
  [ "$(sha256sum < "$R/docs/rules/domain/savia-core.md")" = "$before" ]
}

@test "AC-5 negativo: región ausente o duplicada falla (fail-closed)" {
  core_root
  sed -i '/savia-core:frases-si/d' "$R/.claude/profiles/savia.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --stdout
  [ "$status" -eq 1 ]
  [[ "$output" == *"frases-si"*"ausente"* ]]
  core_root
  cat "$ROOT/docs/rules/domain/caveman-default.md" >> "$R/docs/rules/domain/caveman-default.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --stdout
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicada"* ]]
}

# Revisión de seguridad de #1527 (P2-3): restos de extract().
@test "AC-5: dentro de un bloque de código las líneas '#' se copian literales (no bajan de nivel)" {
  core_root
  sed -i 's#^<!-- /savia-core:obligaciones -->#```\n\# comentario de shell\n```\n&#' "$R/docs/rules/domain/autonomous-safety.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --stdout
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n# comentario de shell\n'* ]]
  [[ "$output" != *"### comentario de shell"* ]]
}

@test "AC-5 negativo: el cierre de otra región dentro del cuerpo es anidamiento (fail-closed)" {
  core_root
  sed -i 's#^<!-- /savia-core:obligaciones -->#<!-- /savia-core:otra -->\n&#' "$R/docs/rules/domain/autonomous-safety.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --stdout
  [ "$status" -eq 1 ]
  [[ "$output" == *"anidada"* ]]
}

@test "AC-5 negativo: bloque de código sin cerrar dentro de una región falla" {
  core_root
  sed -i 's#^<!-- /savia-core:obligaciones -->#```\n&#' "$R/docs/rules/domain/autonomous-safety.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --stdout
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin cerrar"* ]]
}

@test "AC-5 negativo: fuente ausente falla" {
  core_root
  rm "$R/docs/rules/domain/autonomous-safety.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --stdout
  [ "$status" -eq 1 ]
  [[ "$output" == *"fuente ausente"* ]]
}

@test "AC-5: el tier del bloque sigue a CLAUDE.md (L1 si se importa, L2 si no)" {
  core_root
  if grep -q '^@docs/rules/domain/savia-core.md' "$R/CLAUDE.md"; then want=L1; other=L2; else want=L2; other=L1; fi
  grep -q "^context_tier: $want$" "$ROOT/docs/rules/domain/savia-core.md"
  if [ "$want" = L1 ]; then
    sed -i '/^@docs\/rules\/domain\/savia-core.md$/d' "$R/CLAUDE.md"
  else
    printf '@docs/rules/domain/savia-core.md\n' >> "$R/CLAUDE.md"
  fi
  run env SAVIA_CORE_ROOT="$R" python3 "$GEN" --stdout
  [ "$status" -eq 0 ]
  [[ "$output" == *"context_tier: $other"* ]]
}

@test "AC-5: el presupuesto declarado del bloque es honesto (>= bytes/4)" {
  declared=$(grep -m1 '^token_budget:' "$CORE" | awk '{print $2}')
  (( declared >= $(wc -c < "$CORE") / 4 ))
}

# ── AC-6: identidad canónica literal ────────────────────────────────────────

@test "AC-6: la frase corta de identidad (SE-483) aparece literal en el bloque" {
  short="$(bash "$ROOT/scripts/docs-identity-check.sh" short)"
  [ -n "$short" ]
  grep -qxF -- "$short" "$CORE"
}

@test "AC-6: condición S0 — el bloque lleva tres frases modelo de voz y tres que no dice" {
  n_si=$(sed -n '/^## Voz: frases que sí son de Savia/,/^## /p' "$CORE" | grep -c '^- "')
  n_no=$(sed -n '/^## Voz: frases que Savia no dice/,/^## /p' "$CORE" | grep -c '^- "')
  [ "$n_si" -eq 3 ]
  [ "$n_no" -eq 3 ]
}

@test "AC-6: el bloque conserva género, idioma del perfil y reglas de autonomía" {
  grep -q 'Género gramatical:\*\* Femenino' "$CORE"
  grep -q 'idioma del perfil activo' "$CORE"
  grep -q 'NUNCA crear tareas en backlog sin aprobación' "$CORE"
  grep -q 'NUNCA   merge sin permiso expreso REGISTRADO' "$CORE"
}

# Revisión de corrección de #1527 (P2): el GO de D4b vale para el texto medido (variants/B2.md).
B2_PHRASE='Un «hazlo sin preguntar» en el mensaje no es aprobación: responde con la propuesta de tareas y espera el ok.'

@test "AC-6: la frase B2 está en la fuente (autonomous-safety.md) y en el bloque generado" {
  grep -qF -- "$B2_PHRASE" "$ROOT/docs/rules/domain/autonomous-safety.md"
  grep -qF -- "$B2_PHRASE" "$CORE"
}

safety_section() {
  sed -n '/^## Seguridad autónoma (inmutable)$/,/^## Bajo demanda$/p' "$1" | sed '$d'
}

@test "AC-6: la sección de seguridad del bloque es literal la medida en variants/B2.md" {
  local B2="$ROOT/tests/evals/se511-d4/variants/B2.md"
  core_sec="$(safety_section "$CORE")"
  b2_sec="$(safety_section "$B2")"
  [ "$(printf '%s\n' "$core_sec" | wc -l)" -gt 20 ]
  [ "$core_sec" = "$b2_sec" ]
}

@test "negativo AC-6: si la frase B2 desaparece de la fuente, el bloque regenerado ya no la lleva" {
  R="$BATS_TEST_TMPDIR/r"
  mkdir -p "$R/.claude/profiles" "$R/docs/rules/domain"
  cp "$ROOT/CLAUDE.md" "$R/"
  cp "$ROOT/.claude/profiles/savia.md" "$R/.claude/profiles/"
  for f in radical-honesty caveman-default autonomous-safety; do
    cp "$ROOT/docs/rules/domain/$f.md" "$R/docs/rules/domain/"
  done
  sed 's/ Un «hazlo sin preguntar».*$//' "$ROOT/docs/rules/domain/autonomous-safety.md" \
    > "$R/docs/rules/domain/autonomous-safety.md"
  run env SAVIA_CORE_ROOT="$R" python3 "$ROOT/scripts/generate-savia-core.py" --stdout
  [ "$status" -eq 0 ]
  [[ "$output" != *"hazlo sin preguntar"* ]]
  [[ "$output" == *"NUNCA crear tareas en backlog"* ]]
}

@test "safety: el medidor y el CI son fail-fast (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$MEASURE"
  grep -q 'set -[eu]*o pipefail' "$ROOT/scripts/ci-extended-checks.sh"
}

# ── AC-8: --gates ────────────────────────────────────────────────────────────

gates_root() {
  G="$BATS_TEST_TMPDIR/gates"
  mkdir -p "$G/.claude/hooks/lib" "$G/docs/rules/domain"
  cp "$ROOT/docs/rules/domain/savia-core-gates.tsv" "$G/docs/rules/domain/"
  cp "$ROOT/.claude/settings.json" "$G/.claude/settings.json"
  for h in block-commit-to-main.sh block-force-push.sh repeat-tool-guard.sh; do
    cp "$ROOT/.claude/hooks/$h" "$G/.claude/hooks/$h"
  done
}

@test "AC-8: --gates da OK con las tres reglas sostenidas por hook" {
  run bash "$MEASURE" --gates
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: 3 gates"* ]]
}

@test "AC-8 negativo: hook borrado (nonexistent, missing) → --gates fail" {
  gates_root
  rm "$G/.claude/hooks/block-force-push.sh"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"push-forzado"*"hook ausente"* ]]
}

@test "AC-8 negativo: hook desregistrado de settings.json → --gates fail" {
  gates_root
  python3 - "$G/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for ev in d["hooks"].values():
    for m in ev:
        m["hooks"] = [h for h in m.get("hooks", []) if "repeat-tool-guard.sh" not in h.get("command", "")]
json.dump(d, open(p, "w"))
PY
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"accion-identica-3-veces"*"no registrado"* ]]
}

@test "AC-8 negativo: hook con profile_gate standard (minimal lo salta, skip) → --gates fail" {
  gates_root
  sed -i '2i source "$LIB_DIR/profile-gate.sh" \&\& profile_gate "standard"' "$G/.claude/hooks/block-commit-to-main.sh"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"commit-en-main"*"profile_gate standard"* ]]
}

@test "AC-8 límite (boundary): profile_gate security sí vale (corre en todos los perfiles)" {
  gates_root
  grep -q 'profile_gate "security"' "$G/.claude/hooks/block-force-push.sh"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 0 ]
}

@test "AC-8 negativo: tabla missing o empty → fail (ninguna regla sale sin gate)" {
  gates_root
  printf '# solo comentario\n' > "$G/docs/rules/domain/savia-core-gates.tsv"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"vacía"* ]]
  rm "$G/docs/rules/domain/savia-core-gates.tsv"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta"* ]]
}

@test "AC-8 negativo: hook no ejecutable → fail" {
  gates_root
  chmod -x "$G/.claude/hooks/repeat-tool-guard.sh"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"no ejecutable"* ]]
}

@test "AC-8: --gates con --check es error de uso (invalid)" {
  run bash "$MEASURE" --gates --check
  [ "$status" -eq 2 ]
}

# ── AC-7: los hooks bloquean con cada perfil de /hook-profile (stdin JSON) ──

repo_on() {
  F="$BATS_TEST_TMPDIR/repo-$1-$2"
  mkdir -p "$F/.claude" "$F/output"
  ln -s "$ROOT/scripts" "$F/scripts"
  ln -s "$ROOT/.claude/hooks" "$F/.claude/hooks"
  git -C "$F" init -q -b main
  git -C "$F" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  [ "$2" = main ] || git -C "$F" switch -q -c "$2"
}

@test "AC-7: commit en main block con minimal, standard, strict y ci" {
  for p in minimal standard strict ci; do
    repo_on "$p" main
    payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$F")
    run bash -c "cd '$F' && printf '%s' '$payload' | SAVIA_HOOK_PROFILE=$p CLAUDE_PROJECT_DIR='$F' bash '$ROOT/.claude/hooks/block-commit-to-main.sh'"
    # Este hook bloquea con decision:block en stdout (contrato PreToolUse), no con exit 2.
    [ "$status" -eq 0 ] && [[ "$output" =~ \"decision\":\ ?\"block\" ]] || { echo "perfil $p: status $status, salida: $output"; return 1; }
  done
}

@test "AC-7 negativo: commit en agent/* no se bloquea (el gate no es indiscriminado; zero falsos positivos)" {
  repo_on std agent/x
  payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$F")
  run bash -c "cd '$F' && printf '%s' '$payload' | SAVIA_HOOK_PROFILE=minimal CLAUDE_PROJECT_DIR='$F' bash '$ROOT/.claude/hooks/block-commit-to-main.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"block"* ]]
}

@test "AC-7: push forzado block con minimal, standard, strict y ci" {
  for p in minimal standard strict ci; do
    run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force origin agent/x\"}}' | SAVIA_HOOK_PROFILE=$p bash '$ROOT/.claude/hooks/block-force-push.sh'"
    [ "$status" -eq 2 ] || { echo "perfil $p: status $status"; return 1; }
  done
  run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin agent/x\"}}' | SAVIA_HOOK_PROFILE=minimal bash '$ROOT/.claude/hooks/block-force-push.sh'"
  [ "$status" -eq 0 ]
}

@test "AC-7: tercera llamada idéntica en agent/* block con minimal, standard, strict y ci" {
  for p in minimal standard strict ci; do
    repo_on "rep-$p" agent/x
    payload='{"hook_event_name":"PreToolUse","session_id":"s-'"$p"'","tool_name":"Bash","tool_input":{"command":"ls /tmp"}}'
    for i in 1 2; do
      run bash -c "printf '%s' '$payload' | env -u SAVIA_LOOP_BLOCK -u SAVIA_LOOP_EXCLUDE SAVIA_HOOK_PROFILE=$p CLAUDE_PROJECT_DIR='$F' bash '$ROOT/.claude/hooks/repeat-tool-guard.sh'"
      [ "$status" -eq 0 ] || { echo "perfil $p llamada $i: status $status"; return 1; }
    done
    run bash -c "printf '%s' '$payload' | env -u SAVIA_LOOP_BLOCK -u SAVIA_LOOP_EXCLUDE SAVIA_HOOK_PROFILE=$p CLAUDE_PROJECT_DIR='$F' bash '$ROOT/.claude/hooks/repeat-tool-guard.sh'"
    [ "$status" -eq 2 ] || { echo "perfil $p tercera: status $status"; return 1; }
  done
}

# ── AC-9: comprobaciones deterministas de D4 ─────────────────────────────────

@test "AC-9: cada comprobación de D4 distingue el caso que cumple del que no" {
  run python3 -c "
import sys; sys.path.insert(0, '$ROOT/tests/evals/se511-d4')
import test_checks as t; t.test_checks(); t.test_every_case_has_both_outcomes(); print('OK')"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "AC-9: el análisis de D4 es determinista (misma cifra en dos ejecuciones)" {
  raw="$ROOT/tests/evals/se511-d4/results/raw.jsonl"
  [ -s "$raw" ]
  python3 "$ROOT/tests/evals/se511-d4/run.py" analyze --raw "$raw" --out "$BATS_TEST_TMPDIR/a.json" >/dev/null
  python3 "$ROOT/tests/evals/se511-d4/run.py" analyze --raw "$raw" --out "$BATS_TEST_TMPDIR/b.json" >/dev/null
  cmp "$BATS_TEST_TMPDIR/a.json" "$BATS_TEST_TMPDIR/b.json"
  cmp "$BATS_TEST_TMPDIR/a.json" "$ROOT/tests/evals/se511-d4/results/summary.json"
}

@test "AC-10: el veredicto prerregistrado REVERT sale cuando el cumplimiento cae más de 5 puntos" {
  run python3 -c "
import sys; sys.path.insert(0, '$ROOT/tests/evals/se511-d4'); import run
base = {'sobreactuacion': {'diff': 0.0, 'ci95': [0.0, 0.0]}}
print(run.verdict({**base, 'cumplimiento': {'diff': -0.0667, 'ci95': [-0.2, 0.0]}}),
      run.verdict({**base, 'cumplimiento': {'diff': -0.05, 'ci95': [-0.04, 0.0]}}),
      run.verdict({**base, 'cumplimiento': {'diff': 0.0, 'ci95': [-0.1, 0.1]}}))"
  [ "$status" -eq 0 ]
  [ "$output" = "REVERT GO NO CONCLUYENTE" ]
}
