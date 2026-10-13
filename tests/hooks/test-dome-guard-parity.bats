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
  if [[ -z "$TS_RUNTIME" && "${SAVIA_REQUIRE_TS:-}" == "1" ]]; then
    echo "SAVIA_REQUIRE_TS=1 y no hay runtime TypeScript (bun o node >= 22.6)" >&2
    return 1
  fi
  [[ -n "$TS_RUNTIME" ]] || skip "sin runtime TypeScript (bun o node >= 22.6): la paridad no se puede comprobar aquí"
}

# parity MODE [TS_COMMAND]: ejecuta cada caso de la tabla compartida en el hook bash y en la regla TS, y
# lista las diferencias entre ellos y con la decisión esperada del caso (cada caso, sondas incluidas, la trae).
parity() {
  python3 - "$REPO_ROOT" "$CASES" "$HOOK" "$1" "${2:-$TS_RUNTIME $CLI}" <<'PY'
import json, os, shlex, shutil, subprocess, sys
root, cases_file, hook, mode, ts_cmd = sys.argv[1:6]
sys.path.insert(0, os.path.join(root, "tests/python"))
import test_dome_guard as t

table = json.load(open(cases_file, encoding="utf-8"))
entries = table["cases"]
problems = []
for case in entries:
    ws = t.build_workspace(table, case)
    try:
        env = {k: v for k, v in os.environ.items() if k not in ("SAVIA_SPACE_DOMES_FILE", "SAVIA_DOME_GUARD", "SAVIA_GATES_PIN")}
        env.update({k: t.sub(v, ws) for k, v in case.get("env", {}).items()})
        env["CLAUDE_PROJECT_DIR"] = ws
        data = t.payload_text(case, ws)
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
        else:
            problems += [f"{case['name']}: {e}" for e in t.check(table, case, bash_v)]
    finally:
        t.cleanup(ws)
print(f"entradas={len(entries)} diferencias={len(problems)}")
for p in problems:
    print(p)
sys.exit(1 if problems else 0)
PY
}

# monotonic [TS_COMMAND]: los pares de la sección `monotonic` de la tabla (registros de paridad) en el hook
# bash y en la regla TS. Cada payload da lo mismo en los dos, y en cada par el segundo (más claves, sin cwd o
# sin herramienta) nunca es menos estricto que el primero (deny > ask > pass).
monotonic() {
  python3 - "$REPO_ROOT" "$CASES" "$HOOK" "${1:-$TS_RUNTIME $CLI}" <<'PY'
import json, os, shlex, subprocess, sys
root, cases_file, hook, ts_cmd = sys.argv[1:5]
sys.path.insert(0, os.path.join(root, "tests/python"))
import test_dome_guard as t

table = json.load(open(cases_file, encoding="utf-8"))
spec = table["monotonic"]
pairs = t.monotonic_pairs(spec, spec["parity_registries"])
env = {k: v for k, v in os.environ.items() if k not in ("SAVIA_SPACE_DOMES_FILE", "SAVIA_DOME_GUARD", "SAVIA_GATES_PIN")}
problems, seen, ups, spaces = [], {}, set(), {}


def verdict(reg, payload):
    ws = spaces.setdefault(reg, t.build_workspace(table, {"registry": reg}))
    data = json.dumps(t.sub(payload, ws))
    if (reg, data) not in seen:
        env["CLAUDE_PROJECT_DIR"] = ws
        out = subprocess.run(["bash", hook], input=data, capture_output=True, text=True, env=env, timeout=60).stdout.strip()
        b = json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out else "pass"
        ts_out = subprocess.run(shlex.split(ts_cmd) + ["--root", ws], input=data, capture_output=True, text=True,
                                env=env, timeout=60)
        try:
            ts = json.loads(ts_out.stdout)["decision"]
        except (ValueError, KeyError):
            ts = "error"
        if b != ts:
            problems.append(f"{reg} {data}: bash={b} ts={ts}")
        seen[(reg, data)] = b if b == ts else ts
    return seen[(reg, data)]


try:
    for reg, _ctx, label, weak, strong in pairs:
        a, b = verdict(reg, weak), verdict(reg, strong)
        if t.RANK.get(b, -1) < t.RANK.get(a, -1):
            problems.append(f"{reg} {label}: {a} -> {b}")
        if not label.startswith(("sin herramienta", "herramienta 42")) and b == "pass":
            problems.append(f"{reg} {label}: cwd desconocido y pass")
        if a != b:
            ups.add(f"{a}->{b}")
finally:
    for ws in spaces.values():
        t.cleanup(ws)
print(f"pares={len(pairs)} payloads={len(seen)} subidas={sorted(ups)} problemas={len(problems)}")
for p in problems[:40]:
    print(p)
sys.exit(1 if problems or "ask->deny" not in ups or not any(u.startswith("pass->") for u in ups) else 0)
PY
}

@test "parity: monotonicity, extra keys, a missing cwd or a missing tool never give a looser verdict, and an unknown cwd is never a pass, in both bindings" {
  require_ts
  run monotonic
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"problemas=0"* ]]
  [[ "$output" == *"'pass->"* && "$output" == *"ask->deny"* ]]
}

@test "parity: the monotonicity check fails on a binding that loosens a verdict (mutation: TS passes without a tool)" {
  require_ts
  local fake="$BATS_TEST_TMPDIR/fake-ts.sh"
  {
    echo '#!/bin/sh'
    echo 'in=$(cat)'
    echo 'case "$in" in'
    echo "  *'\"tool_name\"'*) printf '%s' \"\$in\" | $TS_RUNTIME \"$CLI\" \"\$@\" ;;"
    echo "  *) echo '{\"decision\": \"pass\", \"reason\": \"\"}' ;;"
    echo 'esac'
  } > "$fake"
  chmod +x "$fake"
  run monotonic "$fake"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin herramienta"* ]]
}

@test "parity: every shared case, evasion probes included, gives the expected decision and the same reason in the bash hook and in savia-gates" {
  require_ts
  run parity cases
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"diferencias=0"* ]]
  local n
  n=$(jq '.cases | length' "$CASES")
  [ "$n" -ge 310 ]
  [[ "$output" == *"entradas=$n "* ]]
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

@test "parity: an empty or null tool input decides the same in both bindings (null bash input: unknown cwd, asks)" {
  require_ts
  printf '{"version":1,"domes":{"g":{"path":"%s/vaults/g"}}}' "$WS" > "$WS/projects/savia-vaults/savia-vaults.domes.json"
  run both "{\"tool_name\":\"bash\",\"tool_input\":null,\"cwd\":\"$WS\"}"
  [ "$output" = "bash=ask ts=ask" ]
  run both "{\"tool_name\":\"grep\",\"tool_input\":{\"pattern\":\"x\",\"path\":\"src\"},\"cwd\":\"$WS\"}"
  [ "$output" = "bash=pass ts=pass" ]
  run both "{\"tool_name\":\"edit\",\"tool_input\":{},\"cwd\":\"$WS\"}"
  [ "$output" = "bash=ask ts=ask" ]
}

@test "parity: a command over the 32 KiB boundary cannot be analysed and asks in both bindings" {
  require_ts
  printf '{"version":1,"domes":{"g":{"path":"%s/vaults/g"}}}' "$WS" > "$WS/projects/savia-vaults/savia-vaults.domes.json"
  local long
  long=$(head -c 33000 /dev/zero | tr '\0' 'a')
  run both "$(jq -cn --arg c "echo $long" --arg w "$WS" '{tool_name:"bash",tool_input:{command:$c},cwd:$w}')"
  [ "$output" = "bash=ask ts=ask" ]
  long=$(head -c 30000 /dev/zero | tr '\0' 'a')
  run both "$(jq -cn --arg c "echo $long" --arg w "$WS" '{tool_name:"bash",tool_input:{command:$c},cwd:$w}')"
  [ "$output" = "bash=pass ts=pass" ]
}

@test "parity: dome_context with the dome attached or granted lifts the read question in both bindings" {
  require_ts
  printf '{"version":1,"domes":{"g":{"path":"%s/vaults/g"}}}' "$WS" > "$WS/projects/savia-vaults/savia-vaults.domes.json"
  local read="{\"tool_name\":\"read\",\"tool_input\":{\"filePath\":\"$WS/vaults/g/a\"},\"cwd\":\"$WS\""
  run both "$read}"
  [ "$output" = "bash=ask ts=ask" ]
  run both "$read,\"dome_context\":{\"attached\":[\"g\"]}}"
  [ "$output" = "bash=pass ts=pass" ]
  run both "$read,\"dome_context\":{\"granted\":[\"g\"]}}"
  [ "$output" = "bash=pass ts=pass" ]
}
