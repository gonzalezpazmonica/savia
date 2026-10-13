#!/usr/bin/env bats
# Paridad del guard de cúpulas (SE-436 S5, DUAL_BINDING): la misma entrada da la misma decisión y el
# mismo motivo en el hook de Claude Code (.claude/hooks/dome-guard.sh) y en la regla de savia-gates
# para OpenCode (scripts/opencode-plugin/savia-gates/lib/dome-guard.ts).
# Ref: docs/specs/SE-436-savia-space-projects-and-domes.spec.md (Verification protocol, DUAL_BINDING)
# Las dos implementaciones son puertos de dome_guard.rs de Savia Space; un guard TS que diverge de su
# gemelo bash ya dejó huecos (PR #1237, #1238): por eso se comparan las salidas, caso a caso.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.claude/hooks/dome-guard.sh"
  CLI="$REPO_ROOT/scripts/opencode-plugin/savia-gates/__tests__/dome-guard-cli.ts"
  CASES="$REPO_ROOT/tests/hooks/fixtures/dome-guard-cases.json"
  TS_RUNTIME=""
  if command -v bun >/dev/null 2>&1; then
    TS_RUNTIME="bun"
  elif [[ -x "$HOME/.bun/bin/bun" ]]; then
    TS_RUNTIME="$HOME/.bun/bin/bun"
  elif node --experimental-strip-types --no-warnings -e '' >/dev/null 2>&1; then
    TS_RUNTIME="node --experimental-strip-types --no-warnings"
  fi
  unset SAVIA_DOME_GUARD SAVIA_GATES_PIN SAVIA_SPACE_DOMES_FILE SAVIA_HOOK_PROFILE
  WS="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$WS/projects/savia-vaults" "$WS/vaults/g" "$WS/src"
}

teardown() {
  [[ -n "${WS:-}" && -d "$WS" ]] && find "$WS" -mindepth 1 -delete 2>/dev/null; rmdir "$WS" 2>/dev/null || true
}

# both PAYLOAD [ENV=VAL]: decisión del hook bash y de la regla TS, como "bash=<d> ts=<d>".
both() {
  local payload="$1" extra="${2:-SAVIA_PARITY=1}" out bash_d ts_d
  out=$(printf '%s' "$payload" | env "$extra" CLAUDE_PROJECT_DIR="$WS" bash "$HOOK")
  bash_d=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  ts_d=$(printf '%s' "$payload" | env "$extra" $TS_RUNTIME "$CLI" --root "$WS" | jq -r '.decision')
  echo "bash=${bash_d:-pass} ts=$ts_d"
}

require_ts() {
  [[ -n "$TS_RUNTIME" ]] || skip "sin runtime TypeScript (bun o node >= 22.6): la paridad no se puede comprobar aquí"
}

# parity MODE [TS_COMMAND]: ejecuta cada entrada en el hook bash y en la regla TS y lista las diferencias.
# MODE=cases usa la tabla compartida (y comprueba además lo esperado); MODE=probes, variantes de evasión.
parity() {
  python3 - "$REPO_ROOT" "$CASES" "$HOOK" "$1" "${2:-$TS_RUNTIME $CLI}" <<'PY'
import json, os, shlex, shutil, subprocess, sys
root, cases_file, hook, mode, ts_cmd = sys.argv[1:6]
sys.path.insert(0, os.path.join(root, "tests/python"))
import test_dome_guard as t

table = json.load(open(cases_file, encoding="utf-8"))
PROBES = [
    ("edit", {"filePath": "./vaults/./gallinero/a.md"}), ("edit", {"filePath": "src//../vaults/gallinero/a.md"}),
    ("Write", {"file_path": "@WS@/VAULTS/GALLINERO/x"}), ("edit", {"filePath": "/@WS@/vaults/gallinero/x"}),
    ("read", {"filePath": "vaults/otra/../gallinero/a.md"}), ("read", {"filePath": "vaults/gallinero"}),
    ("bash", {"command": "LANG=C git -C vaults/gallinero commit -m x"}),
    ("bash", {"command": "bwrap --ro-bind / / -- bash -c 'echo x > vaults/gallinero/a.md'"}),
    ("bash", {"command": "cat vaults/gallinero/a.md 2>/dev/null"}), ("bash", {"command": "cat < vaults/gallinero/a.md"}),
    ("bash", {"command": "echo $(cat vaults/secreta/a.md)"}), ("bash", {"command": "x=vaults/gallinero; cat $x/a"}),
    ("bash", {"command": "cat ~/vaults/gallinero/a"}), ("bash", {"command": "tar czf /tmp/x.tgz vaults"}),
    ("bash", {"command": "rsync -a src/ /tmp/y"}), ("bash", {"command": "grep -R --include=*.md x"}),
    ("bash", {"command": "ls vaults/*/"}), ("bash", {"command": "cat vaults/g?llinero/a.md"}),
    ("bash", {"command": "echo \"$(echo vaults/gallinero)\" >&2"}), ("bash", {"command": "echo ok # vaults/gallinero"}),
    ("bash", {"command": "cat <<EOF > vaults/gallinero/a\n$(id)\nEOF"}), ("bash", {"command": "echo ${X:-vaults/gallinero}"}),
    ("bash", {"command": "echo $((1+2)) > src/n"}), ("bash", {"command": "printf %s\\\\n a | tee -a vaults/otra/x"}),
    ("bash", {"command": "cd vaults; cat gallinero/a"}), ("bash", {"command": "f() { cat vaults/gallinero/a; }; f"}),
    ("bash", {"command": "echo 'unterminated"}), ("bash", {"command": "cat vaults/abierta/a vaults/secreta/b"}),
    ("grep", {"pattern": "x", "path": "@WS@"}), ("glob", {"pattern": "vaults/gall*/**"}),
    ("glob", {"pattern": "/etc/*"}), ("list", {"path": "@WS@/vaults/abierta"}), ("LS", {"path": "/"}),
    ("apply_patch", {"patchText": "*** Begin Patch\n*** Move to: vaults/gallinero/b\n*** End Patch"}),
    ("NotebookEdit", {"notebook_path": "src/n.ipynb"}), ("Edit", {"file_path": 42}), ("bash", {"command": ["ls"]}),
]
if mode == "cases":
    entries = table["cases"]
else:
    ctxs = [None, {"cloud": False}, {"attached": ["gallinero"]}, {"granted": ["otra"], "cloud": True}]
    entries = [{"name": f"sonda {i}/{n}", "registry": "std", "links": [["src/atajo", "@WS@/vaults/gallinero"]],
                "tool": tool, "input": inp, **({"ctx": ctx} if ctx is not None else {})}
               for i, (tool, inp) in enumerate(PROBES) for n, ctx in enumerate(ctxs)]
problems = []
for case in entries:
    ws = t.build_workspace(table, case)
    try:
        payload = {"hook_event_name": "PreToolUse", "tool_name": case["tool"], "tool_input": t.sub(case["input"], ws),
                   "session_id": "s1", "cwd": ws}
        if "ctx" in case:
            payload["dome_context"] = case["ctx"]
        env = {k: v for k, v in os.environ.items() if k not in ("SAVIA_SPACE_DOMES_FILE", "SAVIA_DOME_GUARD", "SAVIA_GATES_PIN")}
        env.update({k: t.sub(v, ws) for k, v in case.get("env", {}).items()})
        env["CLAUDE_PROJECT_DIR"] = ws
        data = json.dumps(payload)
        out = subprocess.run(["bash", hook], input=data, capture_output=True, text=True, env=env, timeout=60).stdout.strip()
        if out:
            spec = json.loads(out)["hookSpecificOutput"]
            bash_v = {"decision": spec["permissionDecision"],
                      "reason": spec["permissionDecisionReason"].removeprefix("Guard de cúpulas: ")}
        else:
            bash_v = {"decision": "pass", "reason": ""}
        ts_out = subprocess.run(shlex.split(ts_cmd) + ["--root", ws], input=data, capture_output=True, text=True,
                                env=env, timeout=60)
        try:
            ts_v = json.loads(ts_out.stdout)
        except ValueError:
            ts_v = {"decision": "error", "reason": ts_out.stderr.strip()[:200]}
        if bash_v != ts_v:
            problems.append(f"{case['name']}: bash={bash_v} ts={ts_v}")
        elif "expect" in case:
            problems += [f"{case['name']}: {e}" for e in t.check(table, case, bash_v)]
    finally:
        shutil.rmtree(ws, ignore_errors=True)
print(f"entradas={len(entries)} diferencias={len(problems)}")
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
}

@test "parity: every shared case gives the same decision and reason in the bash hook and in savia-gates" {
  require_ts
  run parity cases
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"diferencias=0"* ]]
  local n
  n=$(jq '.cases | length' "$CASES")
  [ "$n" -ge 100 ]
  [[ "$output" == *"entradas=$n "* ]]
}

@test "parity: boundary and evasion probes (.., case, sandbox wrapper, quoting, substitutions) agree in both bindings" {
  require_ts
  run parity probes
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"diferencias=0"* ]]
}

@test "parity: the comparison fails when a binding diverges (mutation of the TS side)" {
  require_ts
  local fake="$BATS_TEST_TMPDIR/fake-ts.sh"
  printf '#!/bin/sh\ncat >/dev/null\necho %s\n' "'{\"decision\": \"pass\", \"reason\": \"\"}'" > "$fake"
  chmod +x "$fake"
  run parity cases "$fake"
  [ "$status" -eq 1 ]
  [[ "$output" != *"diferencias=0"* ]]
  [[ "$output" == *"AC17 edit en una cúpula pregunta con el aviso de propuesta: bash="* ]]
}

@test "parity: delegation to Savia Space and mediated mode silence both bindings" {
  require_ts
  printf '{"version":1,"domes":{"g":{"path":"%s/vaults/g"}}}' "$WS" > "$WS/projects/savia-vaults/savia-vaults.domes.json"
  local payload="{\"tool_name\":\"edit\",\"tool_input\":{\"filePath\":\"$WS/vaults/g/a\"},\"cwd\":\"$WS\"}"
  run both "$payload"
  [ "$output" = "bash=ask ts=ask" ]
  run both "$payload" SAVIA_DOME_GUARD=space
  [ "$output" = "bash=pass ts=pass" ]
  run both "$payload" SAVIA_GATES_PIN=1
  [ "$output" = "bash=pass ts=pass" ]
}

@test "parity: an invalid or nonexistent registry fails closed (ask) in both bindings" {
  require_ts
  grep -q "set -uo pipefail" "$HOOK"
  local payload="{\"tool_name\":\"read\",\"tool_input\":{\"filePath\":\"$WS/src/a\"},\"cwd\":\"$WS\"}"
  printf '{"version":1,"domes":{"g":{"path":"%s/vaults/g","confidentiality":"N7"}}}' "$WS" > "$WS/projects/savia-vaults/savia-vaults.domes.json"
  run both "$payload"
  [ "$output" = "bash=ask ts=ask" ]
  printf '[' > "$WS/projects/savia-vaults/savia-vaults.domes.local.json"
  run both "$payload"
  [ "$output" = "bash=ask ts=ask" ]
  run both "$payload" SAVIA_SPACE_DOMES_FILE="$WS/nonexistent.json"
  [ "$output" = "bash=ask ts=ask" ]
}

@test "parity: an empty or null tool input passes in both bindings" {
  require_ts
  printf '{"version":1,"domes":{"g":{"path":"%s/vaults/g"}}}' "$WS" > "$WS/projects/savia-vaults/savia-vaults.domes.json"
  run both "{\"tool_name\":\"bash\",\"tool_input\":null,\"cwd\":\"$WS\"}"
  [ "$output" = "bash=pass ts=pass" ]
  run both "{\"tool_name\":\"grep\",\"tool_input\":{\"pattern\":\"x\",\"path\":\"src\"},\"cwd\":\"$WS\"}"
  [ "$output" = "bash=pass ts=pass" ]
  run both "{\"tool_name\":\"edit\",\"tool_input\":{},\"cwd\":\"$WS\"}"
  [ "$output" = "bash=ask ts=ask" ]
}
