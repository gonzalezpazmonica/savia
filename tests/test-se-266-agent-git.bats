#!/usr/bin/env bats
# tests/test-se-266-agent-git.bats — Tests for agent-git-discipline hook (SE-266)
# Extended: git destructive ops + shell safety layer (v2)

HOOK="${BATS_TEST_DIRNAME}/../.opencode/hooks/agent-git-discipline.sh"

setup() {
  [[ -x "$HOOK" ]] || skip "agent-git-discipline.sh not executable at $HOOK"
}

# Helper: pipe a JSON command directly to the hook (no bash -c, no export -f)
run_hook() {
  local cmd="$1"
  printf '{"tool_input":{"command":"%s"}}' "$cmd" | bash "$HOOK"
}

# ═══════════════════════════════════════════════════════════════════════
# Shell destructive operations (v2)
# ═══════════════════════════════════════════════════════════════════════

@test "SE266-T01: blocks rm -rf" {
  run run_hook "rm -rf /tmp/foo"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T02: blocks rm -r" {
  run run_hook "rm -r /tmp/bar"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T03: blocks rm -fr" {
  run run_hook "rm -fr /tmp/baz"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T04: blocks rm --recursive" {
  run run_hook "rm --recursive /tmp/qux"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T05: blocks rm without -i flag" {
  run run_hook "rm file.txt"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T06: blocks rm -f without -i flag" {
  run run_hook "rm -f file.txt"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T07: blocks sudo rm -rf" {
  run run_hook "sudo rm -rf /etc/foo"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T08: allows rm with -i" {
  run run_hook "rm -i file.txt"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T09: allows rm --interactive" {
  run run_hook "rm --interactive file.txt"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T10: allows rm in safe /tmp/opencode path" {
  run run_hook "rm /tmp/opencode/temp.txt"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T11: allows rm in safe /tmp/recovery path" {
  run run_hook "rm /tmp/recovery/test.txt"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T12: blocks dd writing to block device" {
  run run_hook "dd if=/dev/zero of=/dev/sda"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T13: blocks mkfs format" {
  run run_hook "mkfs.ext4 /dev/sdb"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T14: blocks sudo mkfs" {
  run run_hook "sudo mkfs.xfs /dev/sdc"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T15: blocks chown -R on home" {
  run run_hook "sudo chown -R user /home/monica"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T16: blocks truncate of home file" {
  run run_hook "cat /dev/null > /home/monica/.bashrc"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Git destructive operations (original SE-266)
# ═══════════════════════════════════════════════════════════════════════

@test "SE266-T17: blocks git reset --hard" {
  run run_hook "git reset --hard"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T18: blocks git clean -fd" {
  run run_hook "git clean -fd"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T19: blocks git stash" {
  run run_hook "git stash"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T20: blocks git checkout ." {
  run run_hook "git checkout ."
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T21: warns on git add -A" {
  run run_hook "git add -A"
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "WARN" ]]
}

@test "SE266-T22: warns on git add ." {
  run run_hook "git add ."
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "WARN" ]]
}

@test "SE266-T23: allows explicit git add path" {
  run run_hook "git add src/main.sh"
  [[ "$status" -eq 0 ]]
  [[ ! "$output" =~ "BLOCKED" ]]
  [[ ! "$output" =~ "WARN" ]]
}

@test "SE266-T24: passes through non-git non-rm commands" {
  run run_hook "ls -la"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T25: allows git clean dry-run (-fdn)" {
  run run_hook "git clean -fdn"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T26: allows git clean with -n flag" {
  run run_hook "git clean -n"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T27: blocks git clean -f without dry-run" {
  run run_hook "git clean -f"
  [[ "$status" -eq 2 ]]
  [[ "$output" =~ "BLOCKED" ]]
}

@test "SE266-T28: passes through git status" {
  run run_hook "git status"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T29: passes through git diff" {
  run run_hook "git diff"
  [[ "$status" -eq 0 ]]
}

@test "SE266-T30: passes through git log" {
  run run_hook "git log --oneline -5"
  [[ "$status" -eq 0 ]]
}


# ═══════════════════════════════════════════════════════════════════════
# Comportamiento: motivo del bloqueo, anclaje de la orden, exenciones por
# tramo, borrado remoto de ramas, rutas seguras y modo de saneado de entorno.
# El JSON se construye con python para que las comillas lleguen intactas.
# ═══════════════════════════════════════════════════════════════════════

hk() {
  python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" | bash "$HOOK"
}

blocked() { run hk "$1"; [ "$status" -eq 2 ]; [[ "$output" == *"BLOCKED [agent-git-discipline]"* ]]; }
allowed() { run hk "$1"; [ "$status" -eq 0 ]; [[ "$output" != *"BLOCKED"* ]]; }

@test "SE266-B01: rm recursive and rm without -i give different reasons" {
  run hk "rm -rf build"
  [ "$status" -eq 2 ]
  [[ "$output" == *"rm recursivo"* ]]
  run hk "rm build.log"
  [ "$status" -eq 2 ]
  [[ "$output" == *"rm sin confirmación humana"* ]]
}

@test "SE266-B02: rm -R, rm -rfv and --recursive are all recursive" {
  for c in "rm -R dir" "rm -rfv dir" "rm -vr dir" "rm --recursive dir"; do
    run hk "$c"
    [ "$status" -eq 2 ]
    [[ "$output" == *"rm recursivo"* ]]
  done
}

@test "SE266-B03: rm -i exempts only its own command, not the rest of the line" {
  allowed "rm -i a.txt"
  blocked "rm -i a.txt; rm b.txt"
  blocked "rm -i a.txt && rm -rf b"
  blocked "echo ok | rm c"
}

@test "SE266-B04: wrappers before rm do not hide it" {
  blocked "sudo rm x"
  blocked "FOO=1 rm x"
  blocked "env rm x"
  blocked "echo \$(rm x)"
  blocked "(rm x)"
  blocked "true && rm x"
}

@test "SE266-B05: a mention of rm inside a quoted message or echo is not a command" {
  allowed "git commit -m 'never run rm -rf here'"
  allowed "echo \"rm -rf is dangerous\""
  allowed "grep -n 'rm -rf' README.md"
}

@test "SE266-B06: rm of a safe path is allowed" {
  allowed "rm /tmp/opencode/x"
  allowed "rm -f /tmp/recovery/a /tmp/testdisk/b"
  allowed "rm \"/tmp/extundelete/a\""
}

@test "SE266-B07: paths outside the safe list are blocked" {
  blocked "rm /tmp/other/x"
  blocked "rm /home/u/file"
}

@test "SE266-B08: recursive rm is blocked even inside a safe path" {
  run hk "rm -rf /tmp/opencode/cache"
  [ "$status" -eq 2 ]
  [[ "$output" == *"rm recursivo"* ]]
}

@test "SE266-B09: rm with no target is blocked" {
  blocked "rm -f"
}

@test "SE266-B10: dd to a block device is blocked, dd to a file is not" {
  blocked "dd if=/dev/zero of=/dev/sda bs=1M"
  blocked "sudo dd if=x of=/dev/sdb"
  allowed "dd if=/dev/zero of=disk.img bs=1M count=1"
}

@test "SE266-B11: mkfs variants are blocked but the word alone is not" {
  blocked "mkfs.ext4 /dev/sdb1"
  allowed "echo mkfs.ext4 is a formatter"
}

@test "SE266-B12: chown -R on home is blocked, elsewhere is not" {
  blocked "chown -R me:me ~/projects"
  blocked "chown -R me /home/other"
  allowed "chown -R me /var/app"
  allowed "chown me ~/file"
}

@test "SE266-B13: truncating user or system files is blocked, other redirects are not" {
  blocked ": > ~/.bashrc"
  blocked "true > /etc/hosts"
  blocked "cat /dev/null > /root/x"
  allowed "echo hi > /tmp/out.txt"
  allowed "true > ./local.txt"
}

@test "SE266-B14: git reset --hard is blocked, with global options too" {
  blocked "git reset --hard HEAD~1"
  blocked "git -C /repo reset --hard"
  blocked "git -c core.x=1 reset -q --hard"
  allowed "git reset --soft HEAD~1"
  allowed "git reset HEAD file"
}

@test "SE266-B15: git clean is blocked unless a dry run is requested" {
  blocked "git clean -fd"
  blocked "git clean -f"
  allowed "git clean -n"
  allowed "git clean --dry-run -fd"
  allowed "git clean -fdn"
}

@test "SE266-B16: a dry-run clean does not exempt a second real clean" {
  blocked "git clean -n && git clean -fd"
}

@test "SE266-B17: git stash is blocked with its reason" {
  run hk "git stash"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git stash oculta cambios"* ]]
  [[ "$output" == *"commitea a tu rama agent/*"* ]]
}

@test "SE266-B18: git checkout of the working tree is blocked, of a branch or file is not" {
  blocked "git checkout ."
  blocked "git checkout -- ."
  blocked "git checkout . && echo done"
  allowed "git checkout main"
  allowed "git checkout -- file.txt"
  allowed "git checkout ./sub/dir"
  allowed "git checkout -b agent/x"
}

@test "SE266-B19: pushing to a branch is allowed, deleting a foreign branch is blocked" {
  allowed "git push origin main"
  allowed "git push -u origin agent/feature"
  blocked "git push origin --delete main"
  blocked "git push origin :main"
  blocked "git push -d origin feature/x"
}

@test "SE266-B20: push delete names the foreign refs it refuses" {
  run hk "git push origin --delete agent/a feature/b release"
  [ "$status" -eq 2 ]
  [[ "$output" == *"(feature/b release)"* ]]
  [[ "$output" != *"agent/a"* ]]
  [[ "$output" == *"solo borra sus ramas agent/*"* ]]
}

@test "SE266-B21: deleting own agent branches on the remote is allowed" {
  allowed "git push origin --delete agent/s03i-20261023"
  allowed "git push origin :agent/s03i-20261023"
  allowed "git push -d origin agent/a agent/b"
  allowed "git push origin --delete refs/heads/agent/a"
}

@test "SE266-B22: the remote name is never mistaken for a branch" {
  allowed "git push origin --delete agent/a"
  allowed "git push upstream :agent/a"
}

@test "SE266-B23: quoted refs and refs/heads prefixes are normalised" {
  blocked "git push origin --delete 'main'"
  blocked "git push origin \":release\""
  blocked "git push origin --delete refs/heads/main"
  allowed "git push origin --delete \"agent/x\""
}

@test "SE266-B24: a delete in a second push of the same line is still seen" {
  blocked "git push origin agent/a && git push origin --delete main"
}

@test "SE266-B25: git mention inside a commit message does not trigger" {
  allowed "git commit -m 'docs: explain git reset --hard and git stash'"
  allowed "echo \"git push origin --delete main\""
}

@test "SE266-B26: git add -A warns but does not block, git add path is silent" {
  run hk "git add -A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN [agent-git-discipline]: git add -A/. stagea archivos de otros agentes."* ]]
  run hk "git add src/a.sh src/b.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SE266-B27: empty input, input without a command and an empty command are allowed" {
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "echo '{\"tool_input\":{}}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run hk ""
  [ "$status" -eq 0 ]
}

@test "SE266-B28: leading whitespace does not hide a destructive command" {
  blocked "   rm -rf x"
  blocked "	git reset --hard"
}

@test "SE266-B29: SAVIA_SCRUB_ENV=1 runs the env-scrub check and never blocks" {
  proj="$(mktemp -d)"
  mkdir -p "$proj/scripts"
  printf '#!/usr/bin/env bash\necho "SCRUB-CHECK:$1:$2"\nexit 1\n' > "$proj/scripts/env-scrub.sh"
  chmod +x "$proj/scripts/env-scrub.sh"
  run env SAVIA_SCRUB_ENV=1 CLAUDE_PROJECT_DIR="$proj" bash -c "python3 -c 'import json; print(json.dumps({\"tool_input\":{\"command\":\"ls\"}}))' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCRUB-CHECK:check:ls"* ]]
  rm -rf "$proj"
}

@test "SE266-B30: without SAVIA_SCRUB_ENV the env-scrub check is not run" {
  proj="$(mktemp -d)"
  mkdir -p "$proj/scripts"
  printf '#!/usr/bin/env bash\necho "SCRUB-CHECK"\n' > "$proj/scripts/env-scrub.sh"
  chmod +x "$proj/scripts/env-scrub.sh"
  run env -u SAVIA_SCRUB_ENV CLAUDE_PROJECT_DIR="$proj" bash -c "python3 -c 'import json; print(json.dumps({\"tool_input\":{\"command\":\"ls\"}}))' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"SCRUB-CHECK"* ]]
  rm -rf "$proj"
}
