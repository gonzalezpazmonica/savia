#!/usr/bin/env bats
# SE-508 S1 (SPEC-508) — paridad (AC-9, DUAL_BINDING): el binding de OpenCode
# (scripts/opencode-plugin/savia-gates/lib/mcp-effect-guard.ts) toma la misma decisión que el hook de
# Claude Code (.claude/hooks/mcp-effect-guard.sh) ante las mismas entradas de AC-1..8. La delegación con
# pin fijado solo existe en OpenCode: su test está en __tests__/mcp-effect-guard.test.ts y al final de este
# fichero, como diferencia esperada.
# Ref: docs/specs/SE-508-mcp-webfetch-pretooluse-guard.spec.md

load se508-fixture

setup() {
  se508_setup
  CLI="$REPO_ROOT/scripts/opencode-plugin/savia-gates/__tests__/mcp-effect-guard-cli.ts"
  TS_RUNTIME=""
  if command -v bun >/dev/null 2>&1; then
    TS_RUNTIME="bun"
  elif [[ -x "$HOME/.bun/bin/bun" ]]; then
    TS_RUNTIME="$HOME/.bun/bin/bun"
  elif node --experimental-strip-types --no-warnings -e '' >/dev/null 2>&1; then
    TS_RUNTIME="node --experimental-strip-types --no-warnings"
  fi
}
teardown() { se508_teardown; }

require_ts() {
  if [[ -z "$TS_RUNTIME" && "${SAVIA_REQUIRE_TS:-}" == "1" ]]; then
    echo "SAVIA_REQUIRE_TS=1 y no hay runtime TypeScript (bun o node >= 22.6)" >&2
    return 1
  fi
  [[ -n "$TS_RUNTIME" ]] || skip "sin runtime TypeScript (bun o node >= 22.6): la paridad no se puede comprobar aquí"
}

# ts_decision PAYLOAD [--pin-fixed]: el binding corre el núcleo copiado en el árbol de fixture, el mismo
# fichero que usa el hook (SE508_CORE_SRC o el del repo).
ts_decision() {
  printf '%s' "$1" | $TS_RUNTIME "$CLI" --root "$WS" --core-root "$WS" ${2:-} | jq -r '.decision'
}

# both PAYLOAD → "bash=<d> ts=<d>"
both() { echo "bash=$(hook_decision "$1") ts=$(ts_decision "$1")"; }

# check PAYLOAD ESPERADA
check() {
  local got
  got=$(both "$1")
  [[ "$got" == "bash=$2 ts=$2" ]] || { echo "payload=$1 esperado=$2 obtenido=$got" >&2; return 1; }
}

@test "AC-9: misma decisión en MCP (read_only, write, merge, no catalogada)" {
  require_ts
  check "$(se508_payload mcp__claude_ai_Gmail__get_message)" pass
  check "$(se508_payload mcp__claude_ai_Gmail__send_message '{"to":["a@x.test"]}')" ask
  check "$(se508_payload mcp__github__merge_pull_request)" deny
  check "$(se508_payload mcp__claude_ai_Nuevo__x)" ask
}

@test "AC-9: misma decisión con catálogo aflojado en el árbol y con remoto caído" {
  require_ts
  sed -i 's/send_message: write/send_message: read_only/' "$WS/config/mcp-effect-catalog.yaml"
  check "$(se508_payload mcp__claude_ai_Gmail__send_message)" ask
  export SAVIA_MCP_GUARD_TEST_REMOTE="file://$TMPD/no-existe.git"
  check "$(se508_payload mcp__claude_ai_Gmail__get_message)" ask
}

@test "AC-9: misma decisión ante entrada inválida (vacía, malformada, no UTF-8, WebFetch sin URL)" {
  require_ts
  check "" ask
  check '{"tool_name": "mcp__x' ask
  check "$(printf '{"tool_name":"mcp__\xff"}')" ask
  check "$(se508_payload WebFetch '{}')" ask
}

@test "AC-9: misma decisión en WebFetch y WebSearch (observación y enforce)" {
  require_ts
  check "$(se508_payload WebFetch '{"url":"https://otro.test/x?q=1"}')" pass
  check "$(se508_payload WebSearch '{"query":"x"}')" pass
  export SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  check "$(se508_payload WebFetch '{"url":"https://docs.ejemplo.org/guia"}')" pass
  check "$(se508_payload WebFetch '{"url":"https://DOCS.Ejemplo.org./guia"}')" pass
  check "$(se508_payload WebFetch '{"url":"https://docs.ejemplo.org/api?token=abc"}')" ask
  check "$(se508_payload WebFetch '{"url":"https://docs.ejemplo.org@atacante.test/"}')" ask
  check "$(se508_payload WebFetch '{"url":"http://docs.ejemplo.org/"}')" ask
  check "$(se508_payload WebSearch '{"query":"x"}')" ask
}

@test "AC-9: misma decisión sin persona (SAVIA_AUTONOMOUS_RUN=1)" {
  require_ts
  export SAVIA_AUTONOMOUS_RUN=1
  check "$(se508_payload mcp__claude_ai_Gmail__send_message)" deny
  check '{malformado' deny
  check "$(se508_payload WebFetch '{"url":"https://otro.test/"}')" deny
  check "$(se508_payload WebSearch '{"query":"x"}')" pass
}

@test "AC-9: SAVIA_GATES_PIN=1 sin pin fijado no delega en ninguno de los dos" {
  require_ts
  export SAVIA_GATES_PIN=1 SAVIA_MCP_GUARD=space
  check "$(se508_payload mcp__claude_ai_Gmail__send_message)" ask
  check "$(se508_payload mcp__github__merge_pull_request)" deny
}

@test "AC-8 (solo OpenCode): con pin fijado y SAVIA_GATES_PIN=1 el binding delega write; el hook pregunta; merge deny en ambos" {
  require_ts
  export SAVIA_GATES_PIN=1
  [ "$(hook_decision "$(se508_payload mcp__claude_ai_Gmail__send_message)")" = ask ]
  [ "$(ts_decision "$(se508_payload mcp__claude_ai_Gmail__send_message)" --pin-fixed)" = pass ]
  [ "$(jq -r 'select(.frontend=="opencode") | .decision' "$SAVIA_MCP_GUARD_TEST_LOG" | tail -1)" = delegated ]
  [ "$(ts_decision "$(se508_payload mcp__github__merge_pull_request)" --pin-fixed)" = deny ]
}

@test "AC-8b (OpenCode): un run sin persona no delega aunque el pin esté fijado" {
  require_ts
  export SAVIA_GATES_PIN=1 SAVIA_AUTONOMOUS_RUN=1
  [ "$(ts_decision "$(se508_payload mcp__claude_ai_Gmail__send_message)" --pin-fixed)" = deny ]
}

@test "invalid: misma decisión con tool_name numérico, vacío y tool_input null" {
  require_ts
  check '{"hook_event_name":"PreToolUse","tool_name":42,"tool_input":{}}' ask
  check '{"hook_event_name":"PreToolUse","tool_name":"","tool_input":{}}' ask
  check '{"hook_event_name":"PreToolUse","tool_name":"mcp__claude_ai_Gmail__send_message","tool_input":null}' ask
}

@test "reject: merge con tool_input vacío es deny en ambos" {
  require_ts
  check "$(se508_payload mcp__github__merge_pull_request '{}')" deny
}

@test "safety: el binding TS no usa @ts-ignore ni any explícito para la decisión" {
  ! grep -qE '@ts-ignore|: any\b' "$REPO_ROOT/scripts/opencode-plugin/savia-gates/lib/mcp-effect-guard.ts"
}

@test "empty: stdin vacío da ask en ambos y el hook sale con 0 (set -uo pipefail)" {
  run grep -c '^set -uo pipefail' "$REPO_ROOT/.claude/hooks/mcp-effect-guard.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run bash "$HOOK" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"ask"'* || "$output" == *'"permissionDecision": "ask"'* ]]
}

@test "error: JSON malformado y WebFetch sin URL → ask en ambos" {
  require_ts
  check '{"tool_name": "mcp__x' ask
  check "$(se508_payload WebFetch '{}')" ask
}

@test "fail-closed: tool fuera del catálogo y userinfo en la URL → ask, nunca pass" {
  require_ts
  export SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  check "$(se508_payload mcp__claude_ai_Otro__hacer)" ask
  check "$(se508_payload WebFetch '{"url":"https://u:p@docs.ejemplo.org/"}')" ask
}

@test "boundary: ruta de 200 caracteres pasa y 201 pregunta en ambos" {
  require_ts
  export SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  c=$(printf 'c%.0s' $(seq 49))
  path="/$c/$c/$c/$c"
  [ "${#path}" -eq 200 ]
  check "$(se508_payload WebFetch "{\"url\":\"https://docs.ejemplo.org$path\"}")" pass
  check "$(se508_payload WebFetch "{\"url\":\"https://docs.ejemplo.org${path}c\"}")" ask
}

@test "zero: tool_input sin campos en una tool read_only pasa en ambos" {
  require_ts
  check "$(se508_payload mcp__claude_ai_Gmail__get_message '{}')" pass
}

# --- revisión #1525 (seguridad P1): las suites del guard corren en CI con el runtime TS obligatorio
@test "revisión #1525: ci.yml ejecuta las 4 suites del guard con SAVIA_REQUIRE_TS=1 y Bun preparado antes" {
  run python3 - "$REPO_ROOT/.github/workflows/ci.yml" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
need = ["tests/python/test_mcp_effect_guard.py", "tests/hooks/test-se508-mcp-effect-guard.bats",
        "tests/hooks/test-se508-mcp-guard-parity.bats", "bun test __tests__/mcp-effect-guard.test.ts"]
for job in wf["jobs"].values():
    steps = job.get("steps", [])
    for i, st in enumerate(steps):
        # Solo cuentan las órdenes que se ejecutan: ni comentarios ni una línea que oculte su fallo (revisión #1525).
        lines = [l.strip() for l in str(st.get("run", "")).splitlines()]
        live = [l for l in lines if l and not l.startswith("#")]
        if any(n in l for l in live for n in need):
            hidden = [l for l in live if any(n in l for n in need) and any(x in l for x in ("|| true", "|| :", "|| exit 0"))]
            assert not hidden, f"fallo oculto: {hidden}"
            assert not any(l.startswith("set +e") for l in live), "set +e oculta fallos"
        run = "\n".join(live)
        if all(n in run for n in need):
            assert str(st.get("env", {}).get("SAVIA_REQUIRE_TS")) == "1", "sin SAVIA_REQUIRE_TS=1"
            assert any("setup-bun" in str(s.get("uses", "")) for s in steps[:i]), "Bun no está preparado antes"
            print("OK")
            sys.exit(0)
sys.exit("ningún paso de CI ejecuta las suites de SE-508")
PY
  [ "$status" -eq 0 ]
  [ "$output" = OK ]
}
