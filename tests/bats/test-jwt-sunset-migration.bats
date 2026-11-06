#!/usr/bin/env bats
# test-jwt-sunset-migration.bats — SPEC-SE-036 Slice 3: JWT sunset + PAT migration tools
# Ref: docs/propuestas/savia-enterprise/SPEC-SE-036-api-key-jwt-mint.md
# Tests: block-pat-file-write.sh hook, agent-jwt-mint.md doc, block-credential-leak.sh pattern

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.opencode/hooks/block-pat-file-write.sh"
  CRED_HOOK="$REPO_ROOT/.opencode/hooks/block-credential-leak.sh"
  DOC="$REPO_ROOT/docs/rules/domain/savia-enterprise/agent-jwt-mint.md"
  export REPO_ROOT HOOK CRED_HOOK DOC
}

# ─────────────────────────────────────────────────────────────────
# T1: Hook exists and is executable
# ─────────────────────────────────────────────────────────────────

@test "block-pat-file-write.sh exists and is executable" {
  [[ -x "$HOOK" ]]
}

# ─────────────────────────────────────────────────────────────────
# T2: Write to path with "pat" in name → exit 2 when SAVIA_PAT_BLOCK=on
# ─────────────────────────────────────────────────────────────────

@test "Write to path with 'pat' in name exits 2 when SAVIA_PAT_BLOCK=on" {
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path /tmp/devops-pat
  [[ "$status" -eq 2 ]]
}

# ─────────────────────────────────────────────────────────────────
# T3: SAVIA_PAT_BLOCK=off → exit 0 always
# ─────────────────────────────────────────────────────────────────

@test "SAVIA_PAT_BLOCK=off exits 0 for any path" {
  run env SAVIA_PAT_BLOCK=off bash "$HOOK" --path /tmp/devops-pat
  [[ "$status" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────
# T4: Write to tests/ path with "pat" → exit 0 (exception)
# ─────────────────────────────────────────────────────────────────

@test "Write to tests/test-pat.bats exits 0 (test exception)" {
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path "$REPO_ROOT/tests/bats/test-pat.bats"
  [[ "$status" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────
# T5: Write to docs/ with "pat" in path → exit 0 (exception)
# ─────────────────────────────────────────────────────────────────

@test "Write to docs/ with 'pat' in path exits 0 (docs exception)" {
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" \
    --path "$REPO_ROOT/docs/rules/domain/savia-enterprise/agent-jwt-mint.md"
  [[ "$status" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────
# T6: Hook contains set -uo pipefail
# ─────────────────────────────────────────────────────────────────

@test "block-pat-file-write.sh contains set -uo pipefail" {
  grep -q "set -uo pipefail" "$HOOK"
}

# ─────────────────────────────────────────────────────────────────
# T7: agent-jwt-mint.md exists with "Proceso de migración" section
# ─────────────────────────────────────────────────────────────────

@test "agent-jwt-mint.md exists with Proceso de migración section" {
  [[ -f "$DOC" ]]
  grep -q "Proceso de migración" "$DOC"
}

# ─────────────────────────────────────────────────────────────────
# T8: block-credential-leak.sh contains PAT-shaped 40+ char pattern
# ─────────────────────────────────────────────────────────────────

@test "block-credential-leak.sh contains PAT-shaped 40+ char detection pattern" {
  grep -q 'A-Za-z0-9' "$CRED_HOOK"
  grep -qE '\{40' "$CRED_HOOK"
}

# ─────────────────────────────────────────────────────────────────
# T9: No PAT path is blocked when path is empty (no crash)
# ─────────────────────────────────────────────────────────────────

@test "block-pat-file-write.sh exits 0 when no path provided" {
  run env SAVIA_PAT_BLOCK=on bash "$HOOK"
  [[ "$status" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────
# T10: path with "token" in filename is blocked
# ─────────────────────────────────────────────────────────────────

@test "Write to path with 'token' in filename exits 2 when SAVIA_PAT_BLOCK=on" {
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path /tmp/azure-token
  [[ "$status" -eq 2 ]]
}

# ─────────────────────────────────────────────────────────────────
# T11: agent-jwt-mint.md contains Rollback section
# ─────────────────────────────────────────────────────────────────

@test "agent-jwt-mint.md contains Rollback section" {
  grep -q "Rollback" "$DOC"
}

# ─────────────────────────────────────────────────────────────────
# T12: agent-jwt-mint.md references CLAUDE.md Rule #1
# ─────────────────────────────────────────────────────────────────

@test "agent-jwt-mint.md references CLAUDE.md Rule #1" {
  grep -q "Rule #1" "$DOC"
}

# ── S03o: block-pat-file-write con entrada real por stdin, .gitignore y límites del token ──

# pat_stdin <json>: payload PreToolUse por stdin (como lo entrega el runtime).
pat_stdin() { printf '%s' "$1" | env SAVIA_PAT_BLOCK=on bash "$HOOK"; }

@test "stdin JSON: tool_input.file_path sensible se bloquea con el motivo y la ruta" {
  run pat_stdin '{"tool_name":"Write","tool_input":{"file_path":"/srv/app/devops-pat"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK [SPEC-SE-036 Slice 3]"* ]]
  [[ "$output" == *"Path  : /srv/app/devops-pat"* ]]
}

@test "stdin JSON: filePath (OpenCode) y path también se leen" {
  run pat_stdin '{"tool_input":{"filePath":"/srv/app/api-secret.txt"}}'
  [ "$status" -eq 2 ]
  run pat_stdin '{"tool_input":{"path":"/srv/app/azure_token"}}'
  [ "$status" -eq 2 ]
}

@test "stdin JSON: ruta no sensible pasa; JSON vacío o inválido pasa (empty)" {
  run pat_stdin '{"tool_input":{"file_path":"/srv/app/main.py"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run pat_stdin '{}'
  [ "$status" -eq 0 ]
  run pat_stdin 'no es json'
  [ "$status" -eq 0 ]
}

@test "token pat: límites — pat.txt, my_pat y pat-file bloquean; compat, patched y parallel-dispatch no (boundary)" {
  for p in /srv/pat.txt /srv/my_pat /srv/pat-file.cfg /srv/x.pat; do
    run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path "$p"
    [ "$status" -eq 2 ]
  done
  for p in /srv/compat.sh /srv/patched.sh /srv/parallel-dispatch.sh /srv/path.txt; do
    run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path "$p"
    [ "$status" -eq 0 ]
  done
}

@test "mayúsculas no esquivan: AZURE-TOKEN y Devops-PAT se bloquean" {
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path /srv/AZURE-TOKEN
  [ "$status" -eq 2 ]
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path /srv/Devops-PAT
  [ "$status" -eq 2 ]
}

@test "ruta ignorada por git en el repo destino: permitida; la misma ruta sin ignorar se bloquea" {
  local r; r="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/patrepo.XXXXXX")"
  git init -q "$r"
  printf 'local/\n' > "$r/.gitignore"
  mkdir -p "$r/local" "$r/conf"
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path "$r/local/devops-pat"
  [ "$status" -eq 0 ]
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path "$r/conf/devops-pat"
  [ "$status" -eq 2 ]
}

@test "fuera de git: directorios de credenciales conocidos (.azure, .savia, secrets) se permiten" {
  local d; d="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/nogit.XXXXXX")"
  for p in "$d/.azure/devops-pat" "$d/.savia/token" "$d/secrets/api-secret"; do
    run env GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" SAVIA_PAT_BLOCK=on bash "$HOOK" --path "$p"
    [ "$status" -eq 0 ]
  done
  run env GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" SAVIA_PAT_BLOCK=on bash "$HOOK" --path "$d/conf/devops-pat"
  [ "$status" -eq 2 ]
}

@test "interruptor: valor distinto de on (disabled, ON) desactiva; sin variable bloquea por defecto" {
  run env SAVIA_PAT_BLOCK=ON bash "$HOOK" --path /srv/devops-pat
  [ "$status" -eq 0 ]
  run env -u SAVIA_PAT_BLOCK bash "$HOOK" --path /srv/devops-pat
  [ "$status" -eq 2 ]
}

@test "el mensaje de bloqueo explica la regla, el arreglo y el bypass" {
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path /srv/devops-pat
  [ "$status" -eq 2 ]
  [[ "$output" == *"CLAUDE.md Rule #1"* ]]
  [[ "$output" == *"scripts/jwt-mint.sh --key-stdin"* ]]
  [[ "$output" == *"Bypass: SAVIA_PAT_BLOCK=off"* ]]
}

@test "excepciones por diseño: un nombre sensible bajo docs/ o con extensión .bats se permite" {
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path /srv/proyecto/docs/devops-pat
  [ "$status" -eq 0 ]
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path /srv/proyecto/conf/devops-pat.bats
  [ "$status" -eq 0 ]
  run env SAVIA_PAT_BLOCK=on bash "$HOOK" --path /srv/proyecto/conf/devops-pat
  [ "$status" -eq 2 ]
}

@test "argumentos desconocidos se ignoran sin colgar el hook y --path sigue valiendo" {
  run timeout 5 env SAVIA_PAT_BLOCK=on bash "$HOOK" --otra cosa --path /srv/devops-pat
  [ "$status" -eq 2 ]
  run timeout 5 env SAVIA_PAT_BLOCK=on bash "$HOOK" --otra --path /srv/main.py
  [ "$status" -eq 0 ]
}
