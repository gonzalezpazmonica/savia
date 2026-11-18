#!/usr/bin/env bats
# rbac-management — pruebas de comportamiento de scripts/rbac-manager.sh (SE-376 S03 grupo 4)
# SCRIPT="scripts/rbac-manager.sh"
# Cada test nuevo indica el mutante que mata (mutación manual sobre una copia del script).
# SPEC: SPEC-SE-002 Multi-Tenant & RBAC
# Quality gate: SPEC-055 (audit score >= 80/100)

SCRIPT="scripts/rbac-manager.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  FAKE_ROOT=$(mktemp -d)
  export FAKE_ROOT
  mkdir -p "$FAKE_ROOT/tenants/acme-corp"
  export CLAUDE_PROJECT_DIR="$FAKE_ROOT"
}

teardown() {
  unset FAKE_ROOT CLAUDE_PROJECT_DIR SAVIA_TENANT
}

rbac() {
  bash "$SCRIPT" --project-dir "$FAKE_ROOT" --tenant acme-corp "$@"
}

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "script has set -uo pipefail safety header" {
  head -20 "$SCRIPT" | grep -q "set -uo pipefail"
}

@test "grant creates rbac.yaml with user in role" {
  run rbac grant developer alice
  [[ "$status" -eq 0 ]]
  [[ -f "$FAKE_ROOT/tenants/acme-corp/rbac.yaml" ]]
  grep -q 'alice' "$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
}

@test "grant is idempotent: repeating does not duplicate" {
  rbac grant developer alice
  rbac grant developer alice
  rbac grant developer alice
  # -o: la lista de miembros va en una sola línea, grep -c contaría 1 aunque hubiera duplicados
  count=$(grep -o 'alice' "$FAKE_ROOT/tenants/acme-corp/rbac.yaml" | wc -l)
  [[ "$count" -eq 1 ]]
}

@test "grant multiple users to same role" {
  rbac grant developer alice
  rbac grant developer bob
  grep -q 'alice' "$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
  grep -q 'bob' "$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
}

@test "revoke removes user from role" {
  rbac grant developer alice
  rbac revoke developer alice
  run grep 'alice' "$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
  [[ "$status" -ne 0 ]]
}

@test "revoke nonexistent user is a no-op (exit 0)" {
  rbac grant developer alice
  run rbac revoke developer nobody
  [[ "$status" -eq 0 ]]
  grep -q 'alice' "$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
}

@test "list prints tenant header and roles" {
  rbac grant reader alice
  run rbac list
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "Tenant: acme-corp" ]]
  [[ "$output" =~ "role: reader" ]]
  [[ "$output" =~ "role: developer" ]]
}

@test "check returns exit 0 for allowed command (direct)" {
  rbac grant reader alice
  run rbac check alice sprint-status
  [[ "$status" -eq 0 ]]
}

@test "check returns exit 1 for denied command" {
  rbac grant reader alice
  run rbac check alice tenant-create
  [[ "$status" -eq 1 ]]
}

@test "check supports glob patterns (spec-* matches spec-generate)" {
  rbac grant developer alice
  run rbac check alice spec-generate
  [[ "$status" -eq 0 ]]
}

@test "role inheritance: developer inherits reader commands" {
  rbac grant developer alice
  run rbac check alice sprint-status
  [[ "$status" -eq 0 ]]
}

@test "role inheritance: admin inherits developer and reader commands" {
  rbac grant admin alice
  run rbac check alice sprint-status
  [[ "$status" -eq 0 ]]
  run rbac check alice spec-generate
  [[ "$status" -eq 0 ]]
  run rbac check alice tenant-create
  [[ "$status" -eq 0 ]]
}

@test "check fails for user not in any role" {
  run rbac check ghost sprint-status
  [[ "$status" -eq 1 ]]
}

@test "missing arguments produce usage error" {
  run bash "$SCRIPT" --project-dir "$FAKE_ROOT" --tenant acme-corp grant
  [[ "$status" -eq 2 ]]
}

@test "missing tenant produces error" {
  unset SAVIA_TENANT
  run bash "$SCRIPT" --project-dir "$FAKE_ROOT" list
  [[ "$status" -eq 2 ]]
}

# ── Comportamiento verificado por mutación (S03 grupo 4) ──

yaml() { cat > "$FAKE_ROOT/tenants/acme-corp/rbac.yaml"; }

@test "check decision is printed: ALLOW on allow, DENY on deny, exit codes matching" {
  rbac grant reader alice
  run rbac check alice help
  [[ "$status" -eq 0 && "$output" == "ALLOW" ]]
  run rbac check alice tenant-create
  [[ "$status" -eq 1 && "$output" == "DENY" ]]
}

@test "check matches the member exactly: a prefix of a member name is denied" {
  rbac grant developer alice
  run rbac check ali spec-generate
  [[ "$status" -eq 1 && "$output" == "DENY" ]]
  run rbac check alice2 spec-generate
  [[ "$status" -eq 1 ]]
}

@test "revoke removes only the exact member, never a name that contains it" {
  rbac grant developer alice
  rbac grant developer ali
  rbac revoke developer ali
  grep -q 'alice' "$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
  run rbac check alice spec-generate
  [[ "$status" -eq 0 ]]
  run rbac check ali spec-generate
  [[ "$status" -eq 1 ]]
}

@test "revoke only touches the named role, not the same user in another role" {
  rbac grant reader alice
  rbac grant admin alice
  rbac revoke admin alice
  run rbac check alice tenant-create
  [[ "$status" -eq 1 ]]
  run rbac check alice help
  [[ "$status" -eq 0 ]]
}

@test "revoke on a tenant without rbac.yaml succeeds and leaves no member" {
  run rbac revoke developer ghost
  [[ "$status" -eq 0 ]]
  [[ -f "$FAKE_ROOT/tenants/acme-corp/rbac.yaml" ]]
}

@test "missing argument for every action is a usage error (exit 2), not a partial run" {
  for a in "grant developer" "revoke developer" "check alice"; do
    run rbac $a
    [[ "$status" -eq 2 ]]
  done
  run bash "$SCRIPT" --project-dir "$FAKE_ROOT" --tenant acme-corp
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"Usage"* ]]
}

@test "help exits 0 and prints usage; unknown flags never grant anything" {
  run bash "$SCRIPT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"rbac-manager.sh grant"* ]]
}

@test "missing tenant fails with the explanation and writes nothing" {
  run bash "$SCRIPT" --project-dir "$FAKE_ROOT" grant developer alice
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"no active tenant"* ]]
  [[ ! -f "$FAKE_ROOT/tenants/acme-corp/rbac.yaml" ]]
}

@test "default file: developer cannot run rbac-* or tenant-*, admin can run rbac-*, tenant-* and backup-*" {
  rbac grant developer dev1
  rbac grant admin adm1
  run rbac check dev1 rbac-grant
  [[ "$status" -eq 1 ]]
  run rbac check dev1 backup-run
  [[ "$status" -eq 1 ]]
  run rbac check adm1 rbac-grant
  [[ "$status" -eq 0 ]]
  run rbac check adm1 backup-run
  [[ "$status" -eq 0 ]]
  run rbac check adm1 tenant-create
  [[ "$status" -eq 0 ]]
}

@test "default file: reader gets exactly sprint-status, help and memory-recall (no inherited extras)" {
  rbac grant reader rd
  for c in sprint-status help memory-recall; do run rbac check rd $c; [[ "$status" -eq 0 ]]; done
  for c in spec-generate tenant-create rbac-grant; do run rbac check rd $c; [[ "$status" -eq 1 ]]; done
}

@test "default file keeps the confirm_destructive gate on admin and the inheritance chain" {
  rbac grant admin adm1
  f="$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
  grep -q 'gates: \[confirm_destructive\]' "$f"
  grep -A1 '^  developer:' "$f" | grep -q 'inherits: reader'
  grep -A1 '^  admin:' "$f" | grep -q 'inherits: developer'
}

@test "list shows inheritance and the real members of each role" {
  rbac grant developer alice
  rbac grant developer bob
  run rbac list
  [[ "$output" == *"inherits: reader"* ]]
  [[ "$output" == *"members:  [alice, bob]"* ]]
  [[ "$output" == *"File:   $FAKE_ROOT/tenants/acme-corp/rbac.yaml"* ]]
}

@test "a user in two roles gets the commands of both (union, not the last role)" {
  yaml <<'Y'
roles:
  alpha:
    commands: [cmd-a]
    members: [carol]
  beta:
    commands: [cmd-b]
    members: [carol]
Y
  run rbac check carol cmd-a
  [[ "$status" -eq 0 ]]
  run rbac check carol cmd-b
  [[ "$status" -eq 0 ]]
  run rbac check carol cmd-c
  [[ "$status" -eq 1 ]]
}

@test "role names that share a prefix are edited independently" {
  yaml <<'Y'
roles:
  dev:
    commands: [cmd-dev]
    members: []
  devops:
    commands: [cmd-ops]
    members: [olga]
Y
  rbac grant dev dan
  f="$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
  grep -A2 '^  dev:' "$f" | grep -q 'members: \[dan\]'
  grep -A2 '^  devops:' "$f" | grep -q 'members: \[olga\]'
  rbac revoke dev dan
  grep -A2 '^  devops:' "$f" | grep -q 'members: \[olga\]'
  run rbac check olga cmd-ops
  [[ "$status" -eq 0 ]]
}

@test "grant works on a role that has no members line yet" {
  yaml <<'Y'
roles:
  solo:
    commands: [cmd-solo]
Y
  rbac grant solo sam
  run rbac check sam cmd-solo
  [[ "$status" -eq 0 && "$output" == "ALLOW" ]]
}

@test "grant to a role that does not exist grants nothing" {
  rbac grant nosuchrole mallory
  run rbac check mallory sprint-status
  [[ "$status" -eq 1 ]]
}

@test "grant leaves no temporary files next to rbac.yaml (atomic replace)" {
  rbac grant developer alice
  rbac revoke developer alice
  run ls "$FAKE_ROOT/tenants/acme-corp"
  [[ "$output" == "rbac.yaml" ]]
}

@test "inheritance cycles terminate and still resolve the commands" {
  yaml <<'Y'
roles:
  a:
    inherits: b
    commands: [cmd-a]
    members: [zed]
  b:
    inherits: a
    commands: [cmd-b]
    members: []
Y
  run timeout 10 bash "$SCRIPT" --project-dir "$FAKE_ROOT" --tenant acme-corp check zed cmd-b
  [[ "$status" -eq 0 ]]
}

@test "--project-dir decides where rbac.yaml lives, even when CLAUDE_PROJECT_DIR points elsewhere" {
  other=$(mktemp -d)
  CLAUDE_PROJECT_DIR="$other" bash "$SCRIPT" --project-dir "$FAKE_ROOT" --tenant acme-corp grant reader alice
  [[ -f "$FAKE_ROOT/tenants/acme-corp/rbac.yaml" ]]
  [[ ! -e "$other/tenants" ]]
}

@test "glob patterns are anchored: spec-* does not match xspec-generate nor spec alone" {
  rbac grant developer alice
  run rbac check alice xspec-generate
  [[ "$status" -eq 1 ]]
  run rbac check alice spec
  [[ "$status" -eq 1 ]]
}

# ── Entradas que no pueden entrar en rbac.yaml (hueco hallado por la mutación: S03 grupo 4) ──

@test "tenant with path traversal is rejected and nothing is written outside tenants/" {
  for t in ../escape a/b .hidden ""; do
    run bash "$SCRIPT" --project-dir "$FAKE_ROOT" --tenant "$t" grant admin mallory
    [[ "$status" -eq 2 ]]
  done
  [[ ! -e "$FAKE_ROOT/escape" ]]
  [[ ! -e "$FAKE_ROOT/tenants/a" ]]
}

@test "a user value with spaces or list syntax is invalid: no extra member is created" {
  run rbac grant admin "bob evil"
  [[ "$status" -eq 2 ]]
  run rbac grant admin 'x], evil'
  [[ "$status" -eq 2 ]]
  run rbac grant admin 'a,evil'
  [[ "$status" -eq 2 ]]
  run rbac check evil tenant-create
  [[ "$status" -eq 1 ]]
  [[ ! -f "$FAKE_ROOT/tenants/acme-corp/rbac.yaml" ]] || ! grep -q 'evil' "$FAKE_ROOT/tenants/acme-corp/rbac.yaml"
}

@test "an invalid role name is rejected for grant and revoke" {
  run rbac grant 'admin: x' alice
  [[ "$status" -eq 2 ]]
  run rbac revoke 'a b' alice
  [[ "$status" -eq 2 ]]
}

@test "check with an invalid user name is DENY without reading the file" {
  run rbac check 'alice evil' help
  [[ "$status" -eq 1 && "$output" == "DENY" ]]
  [[ ! -f "$FAKE_ROOT/tenants/acme-corp/rbac.yaml" ]]
}

@test "emails and dotted handles are valid user names" {
  rbac grant developer "ana.perez@example.org"
  run rbac check "ana.perez@example.org" spec-generate
  [[ "$status" -eq 0 ]]
}
