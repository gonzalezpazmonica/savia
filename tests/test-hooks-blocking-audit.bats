#!/usr/bin/env bats
# tests/test-hooks-blocking-audit.bats — D23-5 / D-T2: guards de seguridad con `blocking: true`
# Ref: docs/rules/domain/hooks-blocking-guards.md
# Ref: docs/HOOKS.md
#
# En modo mediado (Savia Space), un hook `blocking: true` que falla, se cuelga o no
# se puede lanzar bloquea la herramienta (fail-closed). Este test fija qué guards
# llevan la marca y hace fallar la suite si un guard nuevo `block-*` se registra
# sin clasificar en la política.

SCRIPT="scripts/hooks-integrity-check.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  AUDIT="$REPO_ROOT/$SCRIPT"
  SETTINGS="$REPO_ROOT/.claude/settings.json"
  POLICY="$REPO_ROOT/config/hooks-blocking-policy.txt"
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
}

# Fixture mínima: settings con un evento PreToolUse y los hooks pasados como JSON.
write_settings() {
  local hooks_json="$1"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":%s}]}}\n' "$hooks_json" > "$TMPDIR/settings.json"
}

hook() {
  # hook <nombre> [blocking]  → objeto JSON de hook de tipo command
  local name="$1" blocking="${2:-}"
  if [[ -n "$blocking" ]]; then
    printf '{"type":"command","command":"\\"$CLAUDE_PROJECT_DIR\\"/.opencode/hooks/%s.sh","blocking":%s,"timeout":5}' "$name" "$blocking"
  else
    printf '{"type":"command","command":"\\"$CLAUDE_PROJECT_DIR\\"/.opencode/hooks/%s.sh","timeout":5}' "$name"
  fi
}

write_policy() {
  printf '%s\n' "$@" > "$TMPDIR/policy.txt"
}

# ── Estructura del script ─────────────────────────────────────────────────────

@test "script: existe, sintaxis válida y usa set -uo pipefail" {
  [ -f "$AUDIT" ]
  run bash -n "$AUDIT"
  [ "$status" -eq 0 ]
  run grep -c '^set -uo pipefail' "$AUDIT"
  [ "$output" -ge 1 ]
}

# ── Settings reales del repo (positivo) ───────────────────────────────────────

@test "repo: settings.json real cumple la política (exit 0)" {
  run bash "$AUDIT" --blocking
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "repo: los 6 guards de seguridad y adb tienen blocking true en todas sus apariciones" {
  for g in block-credential-leak block-force-push agent-git-discipline \
           block-infra-destructive validate-bash-global android-adb-validate; do
    run python3 - "$SETTINGS" "$g" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1]))
name = sys.argv[2]
hits = [h for gs in s["hooks"].values() for g in gs for h in g.get("hooks", [])
        if f"/{name}.sh" in h.get("command", "")]
print(len(hits), all(h.get("blocking") is True for h in hits))
sys.exit(0 if hits and all(h.get("blocking") is True for h in hits) else 1)
EOF
    [ "$status" -eq 0 ] || { echo "guard sin blocking: $g ($output)"; false; }
  done
}

@test "repo: agent-git-discipline aparece dos veces y ambas son blocking (Space deduplica por comando)" {
  run python3 -c "
import json
s=json.load(open('$SETTINGS'))
hits=[h for g in s['hooks']['PreToolUse'] for h in g.get('hooks',[]) if '/agent-git-discipline.sh' in h.get('command','')]
print(len(hits), sum(1 for h in hits if h.get('blocking') is True))"
  [ "$status" -eq 0 ]
  [ "$output" = "2 2" ]
}

@test "repo: data-sovereignty-gate excluido NO lleva blocking (latencia sin acotar)" {
  run python3 -c "
import json
s=json.load(open('$SETTINGS'))
hits=[h for gs in s['hooks'].values() for g in gs for h in g.get('hooks',[]) if '/data-sovereignty-gate.sh' in h.get('command','')]
print(len(hits), any(h.get('blocking') is True for h in hits))"
  [ "$status" -eq 0 ]
  [ "$output" = "1 False" ]
  run grep -E '^excluded[[:space:]]+data-sovereignty-gate[[:space:]]+.{10,}' "$POLICY"
  [ "$status" -eq 0 ]
}

# ── Regresión: guards futuros (negativos) ─────────────────────────────────────

@test "reject: guard declarado blocking en la política pero sin la clave en settings falla" {
  write_settings "[$(hook block-force-push)]"
  write_policy "blocking block-force-push"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION"*"block-force-push"*"sin blocking"* ]]
}

@test "reject: blocking false explícito en un guard declarado también falla" {
  write_settings "[$(hook block-force-push false)]"
  write_policy "blocking block-force-push"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
}

@test "reject: blocking como cadena \"true\" no cuenta (Space lee as_bool)" {
  write_settings "[$(hook block-force-push '"true"')]"
  write_policy "blocking block-force-push"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
}

@test "reject: duplicado con solo una aparición blocking falla (la otra podría ganar el dedup)" {
  write_settings "[$(hook agent-git-discipline true),$(hook agent-git-discipline)]"
  write_policy "blocking agent-git-discipline"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-git-discipline"* ]]
}

@test "reject: guard nuevo block-* sin clasificar en la política falla" {
  write_settings "[$(hook block-force-push true),$(hook block-new-danger)]"
  write_policy "blocking block-force-push"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"block-new-danger"*"sin clasificar"* ]]
}

@test "reject: hook con blocking true no declarado en la política falla (sin fail-closed implícito)" {
  write_settings "[$(hook some-telemetry true)]"
  write_policy "blocking block-force-push"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"some-telemetry"*"no declarado"* ]]
}

@test "reject: guard excluido que aparece con blocking true falla" {
  write_settings "[$(hook data-sovereignty-gate true)]"
  write_policy "excluded data-sovereignty-gate latencia sin acotar"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
}

@test "reject: guard declarado blocking que ya no está registrado falla (política obsoleta)" {
  write_settings "[$(hook block-force-push true)]"
  write_policy "blocking block-force-push" "blocking block-gone"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"block-gone"*"no registrado"* ]]
}

@test "invalid: exclusión sin motivo es error de política" {
  write_settings "[$(hook data-sovereignty-gate)]"
  write_policy "excluded data-sovereignty-gate"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"motivo"* ]]
}

@test "invalid: verbo desconocido en la política es error (exit 2)" {
  write_settings "[$(hook block-force-push true)]"
  write_policy "maybe block-force-push"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 2 ]
}

@test "error: settings.json inexistente o JSON inválido sale con 2" {
  write_policy "blocking block-force-push"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/no-existe.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 2 ]
  printf '{not json' > "$TMPDIR/bad.json"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/bad.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 2 ]
}

# ── Positivos y límites ───────────────────────────────────────────────────────

@test "pass: guard reviewed (no blocking) con motivo es aceptado" {
  write_settings "[$(hook block-force-push true),$(hook block-branch-switch-dirty)]"
  write_policy "blocking block-force-push" "reviewed block-branch-switch-dirty no es de seguridad"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 0 ]
}

@test "boundary: comentarios y líneas vacías de la política se ignoran" {
  write_settings "[$(hook block-force-push true)]"
  write_policy "# cabecera" "" "   " "blocking block-force-push   # guard"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 0 ]
}

@test "boundary: settings sin hooks (vacío) y política vacía pasan" {
  printf '{"hooks":{}}\n' > "$TMPDIR/settings.json"
  : > "$TMPDIR/policy.txt"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 0 ]
}

@test "boundary: hook con name explícito se identifica por el script, no por el name" {
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash x/.opencode/hooks/android-adb-validate.sh","name":"otro-nombre","blocking":true}]}]}}\n' > "$TMPDIR/settings.json"
  write_policy "blocking android-adb-validate"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 0 ]
}

@test "boundary: varias violaciones se informan todas, no solo la primera" {
  write_settings "[$(hook block-a),$(hook block-b)]"
  write_policy "blocking block-a" "blocking block-b"
  run bash "$AUDIT" --blocking --settings "$TMPDIR/settings.json" --policy "$TMPDIR/policy.txt"
  [ "$status" -eq 1 ]
  [ "$(grep -c VIOLATION <<<"$output")" -eq 2 ]
}
