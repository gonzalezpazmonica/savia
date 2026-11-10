#!/usr/bin/env bats
# SE-511 S2 — gates del contexto fijo (AC-7, AC-8) y validación D4 (AC-9, AC-10).
# El bloque compacto (AC-5, AC-6) se revirtió por el veredicto REVERT de D4
# (docs/evidence/SE-511-D4-validacion.md); sus tests viven en el historial de la rama.
# Ref: docs/specs/SE-511-contexto-fijo-por-turno-a-la-mitad.spec.md

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MEASURE="$ROOT/scripts/context-fixed-measure.sh"
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

@test "AC-8 negativo: hook borrado hace fallar --gates" {
  gates_root
  rm "$G/.claude/hooks/block-force-push.sh"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"push-forzado"*"hook ausente"* ]]
}

@test "AC-8 negativo: hook desregistrado de settings.json hace fallar --gates" {
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

@test "AC-8 negativo: hook con profile_gate standard (minimal lo salta) hace fallar --gates" {
  gates_root
  sed -i '2i source "$LIB_DIR/profile-gate.sh" \&\& profile_gate "standard"' "$G/.claude/hooks/block-commit-to-main.sh"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"commit-en-main"*"profile_gate standard"* ]]
}

@test "AC-8 límite: profile_gate security sí vale (corre en todos los perfiles)" {
  gates_root
  grep -q 'profile_gate "security"' "$G/.claude/hooks/block-force-push.sh"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 0 ]
}

@test "AC-8 negativo: tabla ausente o vacía falla (ninguna regla sale sin gate)" {
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

@test "AC-8 negativo: hook no ejecutable falla" {
  gates_root
  chmod -x "$G/.claude/hooks/repeat-tool-guard.sh"
  run env CONTEXT_FIXED_ROOT="$G" bash "$MEASURE" --gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"no ejecutable"* ]]
}

@test "AC-8: --gates con --check es error de uso" {
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

@test "AC-7: commit en main bloqueado con minimal, standard, strict y ci" {
  for p in minimal standard strict ci; do
    repo_on "$p" main
    payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$F")
    run bash -c "cd '$F' && printf '%s' '$payload' | SAVIA_HOOK_PROFILE=$p CLAUDE_PROJECT_DIR='$F' bash '$ROOT/.claude/hooks/block-commit-to-main.sh'"
    # Este hook bloquea con decision:block en stdout (contrato PreToolUse), no con exit 2.
    [ "$status" -eq 0 ] && [[ "$output" =~ \"decision\":\ ?\"block\" ]] || { echo "perfil $p: status $status, salida: $output"; return 1; }
  done
}

@test "AC-7 negativo: commit en agent/* no se bloquea (el gate no es indiscriminado)" {
  repo_on std agent/x
  payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$F")
  run bash -c "cd '$F' && printf '%s' '$payload' | SAVIA_HOOK_PROFILE=minimal CLAUDE_PROJECT_DIR='$F' bash '$ROOT/.claude/hooks/block-commit-to-main.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"block"* ]]
}

@test "AC-7: push forzado bloqueado con minimal, standard, strict y ci" {
  for p in minimal standard strict ci; do
    run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force origin agent/x\"}}' | SAVIA_HOOK_PROFILE=$p bash '$ROOT/.claude/hooks/block-force-push.sh'"
    [ "$status" -eq 2 ] || { echo "perfil $p: status $status"; return 1; }
  done
  run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin agent/x\"}}' | SAVIA_HOOK_PROFILE=minimal bash '$ROOT/.claude/hooks/block-force-push.sh'"
  [ "$status" -eq 0 ]
}

@test "AC-7: tercera llamada idéntica en agent/* bloqueada con minimal, standard, strict y ci" {
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
