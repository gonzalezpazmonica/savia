#!/usr/bin/env bats
# BATS tests for the 2026-09-26 multi-frontend audit fixes (Claude Code, Codex, OpenCode).
# Ref: docs/rules/domain/model-alias-schema.md
SCRIPT="scripts/skill-listing-overrides.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  set -o pipefail
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

@test "settings.json: every command hook uses CLAUDE_PROJECT_DIR and resolves to a runnable script" {
  run python3 - <<'PY'
import json, os, re, sys
d = json.load(open(".claude/settings.json"))
bad = []
for ev, groups in d["hooks"].items():
    for g in groups:
        for h in g["hooks"]:
            c = h.get("command")
            if not c:
                continue
            m = re.search(r'\$CLAUDE_PROJECT_DIR"?/?([^\s"]+)', c)
            if not m or "CLAUDE_PLUGIN_ROOT" in c or "CLAUDE_JSON_INPUT" in c:
                bad.append(c); continue
            p = m.group(1)
            if not os.path.isfile(p) or (not c.startswith("bash") and not os.access(p, os.X_OK)):
                bad.append(p)
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ]
}

@test "settings.json: prompt hooks do not pin vendor models" {
  run python3 -c "
import json; d=json.load(open('.claude/settings.json'))
print([h.get('model') for a in d['hooks'].values() for g in a for h in g['hooks'] if h.get('type')=='prompt' and h.get('model')])"
  [ "$output" = "[]" ]
}

@test "judge-auto-router reads the hook payload from stdin" {
  run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_response\":{\"stdout\":\"ok\"}}' | PROJECT_ROOT='$TMP' bash .claude/hooks/judge-auto-router.sh"
  [ "$status" -eq 0 ]
  run bash -c "printf '' | bash .claude/hooks/judge-auto-router.sh"
  [ "$status" -eq 0 ]
}

@test "judge-trigger-detector: conteo de patrones sin error aritmetico" {
  printf 'v1.2\n2026-09-26\n10 ms\n' > "$TMP/in.txt"
  run env PROJECT_ROOT="$TMP" bash scripts/judge-trigger-detector.sh Bash "$TMP/in.txt"
  [[ "$output" != *"error sintáctico"* && "$output" != *"syntax error"* ]]
}

@test "shield-autostart: opt-in via SAVIA_SHIELD_AUTOSTART=on; never keyed on stdin; headless skips" {
  ! grep -q '\[\[ ! -t 0 \]\]' .claude/hooks/shield-autostart.sh
  run bash -c "echo '{}' | HOME='$TMP' CLAUDE_CODE_ENTRYPOINT=cli bash .claude/hooks/shield-autostart.sh"
  [ "$status" -eq 0 ]
  grep -q 'autostart off (SAVIA_SHIELD_AUTOSTART=off' "$TMP/.savia/shield-autostart.log"
  run bash -c "echo '{}' | HOME='$TMP' SAVIA_SHIELD_AUTOSTART=on CLAUDE_CODE_ENTRYPOINT=sdk-cli bash .claude/hooks/shield-autostart.sh"
  [ "$status" -eq 0 ]
  grep -q 'entrypoint=sdk-cli' "$TMP/.savia/shield-autostart.log"
}

@test "settings.json: no http hooks that fail when the Shield daemon is down" {
  run python3 -c "
import json; d=json.load(open('.claude/settings.json'))
print(sum(1 for a in d['hooks'].values() for g in a for h in g['hooks'] if h.get('type')=='http'))"
  [ "$output" = "0" ]
}

@test "codex hooks.json is valid and points to executable Savia gates" {
  run python3 - <<'PY'
import json, os, re, sys
d = json.load(open(".codex/hooks.json"))
groups = d["hooks"]["PreToolUse"]
assert all(g["matcher"] == "Bash" for g in groups)
paths = [re.search(r"/(\.claude/hooks/[\w.-]+\.sh)", h["command"]).group(1)
         for g in groups for h in g["hooks"]]
missing = [p for p in paths if not os.path.isfile(p)]
print(len(paths), missing); sys.exit(1 if missing or len(paths) < 6 else 0)
PY
  [ "$status" -eq 0 ]
}

@test "Savia Bash gates accept the Codex payload shape (tool_name Bash + tool_input.command)" {
  cmd="rm -rf "/
  payload=$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":"."}))' "$cmd")
  run bash -c "printf '%s' '$payload' | env -u CLAUDE_PROJECT_DIR bash .claude/hooks/validate-bash-global.sh"
  [ "$status" -eq 2 ]
  run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}' | env -u CLAUDE_PROJECT_DIR bash .claude/hooks/validate-bash-global.sh"
  [ "$status" -eq 0 ]
}

@test "codex_profile probes force the C locale" {
  grep -qF 'LC_ALL' scripts/dual-cli/codex_profile.py
  grep -qF 'LANGUAGE' scripts/dual-cli/codex_profile.py
}

@test "generate-critical-facts --check never writes" {
  before=$(sha256sum docs/critical-facts.md)
  run bash scripts/generate-critical-facts.sh --check
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  [ "$(sha256sum docs/critical-facts.md)" = "$before" ]
}

@test "skill listing overrides are in sync with tier: extended commands" {
  run bash scripts/skill-listing-overrides.sh --check
  [ "$status" -eq 0 ]
  run bash scripts/skill-listing-overrides.sh --bogus
  [ "$status" -eq 2 ]
}

@test "command frontmatter parses as strict YAML" {
  run python3 - <<'PY'
import glob, re, sys, yaml
bad = []
for p in glob.glob(".claude/commands/*.md"):
    m = re.match(r"^---\n(.*?)\n---", open(p, errors="ignore").read(), re.S)
    if m:
        try: yaml.safe_load(m.group(1))
        except yaml.YAMLError: bad.append(p)
print(bad); sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ]
}

@test "validate-bash-global: cd into a feature-branch worktree is not treated as main" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/validate-bash-global.sh"
  mkdir -p "$TMP/main/savia" "$TMP/wt"
  git -C "$TMP/main/savia" init -q -b main
  git -C "$TMP/main/savia" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$TMP/main/savia" worktree add -q -b feature "$TMP/wt/savia"
  mk() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"cd \"%s\" && git %s -A" % (sys.argv[1], "add")}}))' "$1"; }
  run bash -c "cd '$TMP/main/savia' && printf '%s' '$(mk "$TMP/wt/savia")' | CLAUDE_PROJECT_DIR='$TMP/main/savia' bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "cd '$TMP/main/savia' && printf '%s' '$(mk "$TMP/main/savia")' | CLAUDE_PROJECT_DIR='$TMP/main/savia' bash '$HOOK'"
  [ "$status" -eq 2 ]
}

@test "safety: new scripts run under set -uo pipefail" {
  grep -q '^set -uo pipefail' scripts/skill-listing-overrides.sh
  grep -q '^set -uo pipefail' scripts/model-tier-lint.sh
  grep -q '^set -uo pipefail' .claude/hooks/judge-auto-router.sh
}

@test "edge: skill-listing-overrides with no args fails with usage" {
  run bash scripts/skill-listing-overrides.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "edge: skill-listing-overrides keeps manual off entries and adds zero stale name-only" {
  mkdir -p "$TMP/p/.claude/commands"
  printf -- '---\nname: a\ntier: extended\n---\n' > "$TMP/p/.claude/commands/a.md"
  printf '{"skillOverrides":{"manual":"off","gone":"name-only"}}' > "$TMP/p/.claude/settings.json"
  PROJECT_ROOT="$TMP/p" run bash scripts/skill-listing-overrides.sh --apply
  [ "$status" -eq 0 ]
  run python3 -c "import json;print(json.load(open('$TMP/p/.claude/settings.json'))['skillOverrides'])"
  [ "$output" = "{'a': 'name-only', 'manual': 'off'}" ]
}

@test "edge: codex gates ignore an empty payload" {
  run bash -c "printf '' | env -u CLAUDE_PROJECT_DIR bash .claude/hooks/block-force-push.sh"
  [ "$status" -eq 0 ]
}
