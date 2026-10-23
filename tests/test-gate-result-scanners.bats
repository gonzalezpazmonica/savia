#!/usr/bin/env bats
# SE-453 S3 (lote 2): escáneres «por demanda» de la auditoría S0 con exposición real.
# Spec: docs/specs/SE-453-gate-result-contract.spec.md · Contrato: docs/rules/domain/gate-result-contract.md
# - security-audit-all.sh: `$(cmd || echo '{}')` pegaba `{}` tras el JSON de un escáner que salía 1 y el
#   parseo fallaba a 0 hallazgos (un FAIL se leía PASS). Un escáner roto o ausente es hueco, no cero.
# - mcp-security-audit.sh: sin python3 cada config salía como hallazgo MCP-00; ahora es unknown.

setup_file() {
  export NOPY="$BATS_FILE_TMPDIR/nopy"
  mkdir -p "$NOPY"
  local f
  for f in /usr/bin/*; do
    [[ "${f##*/}" == python* ]] && continue
    # Con `&&` como última orden del bucle, un último /usr/bin/* no ejecutable hacía fallar setup_file.
    if [[ -x "$f" ]]; then ln -sf "$f" "$NOPY/${f##*/}"; fi
  done
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  W="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  mkdir -p "$W/scripts" "$W/.claude/hooks/lib"
  cp "$REPO_ROOT/scripts/security-audit-all.sh" "$W/scripts/"
  cp "$REPO_ROOT/scripts/mcp-security-audit.sh" "$W/scripts/mcp-real.sh"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$W/.claude/hooks/lib/"
  # Escáneres falsos limpios; cada test rompe el que necesita.
  for s in mcp-security-audit permissions-wildcard-audit hook-injection-audit; do stub "$s" 0 '{"verdict":"PASS","findings_count":0,"critical":0,"high":0,"medium":0,"low":0}'; done
  printf '#!/usr/bin/env bash\necho "Scanned: 1 files | Findings: 0 | Warnings: 0"\n' > "$W/scripts/prompt-security-scan.sh"
  printf '{"mcpServers":{"ok":{"command":"node","args":["s.js"],"description":"d"}}}' > "$W/clean.json"
  printf '{"mcpServers":{"x":{"command":"npx","args":["-y","pkg"],"autoApprove":true,"description":"d"}}}' > "$W/bad.json"
}

stub() { # stub <scanner> <exit> <stdout>
  printf '#!/usr/bin/env bash\nprintf %%s %q\nexit %s\n' "$3" "$2" > "$W/scripts/$1.sh"
}

json_field() { printf '%s' "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d$1))"; }

# ── mcp-security-audit.sh ───────────────────────────────────────────────────

@test "mcp-audit: sin python3 ⇒ exit 2 y unknown/python3:missing_tool, no un hallazgo MCP-00" {
  run env PATH="$NOPY" /usr/bin/bash "$W/scripts/mcp-real.sh" --config "$W/clean.json"
  [ "$status" -eq 2 ]
  [ "$status" -ne 1 ]
  [[ "$output" != *"MCP-00"* ]]
  [ "$(printf '%s\n' "$output" | tail -1)" = 'gate-result: {"result":"unknown","gaps":[{"check":"python3","reason":"missing_tool"}]}' ]
}

@test "mcp-audit --json sin python3: JSON válido con verdict UNKNOWN, result unknown y su hueco" {
  run env PATH="$NOPY" /usr/bin/bash -c "bash '$W/scripts/mcp-real.sh' --config '$W/clean.json' --json 2>/dev/null"
  [ "$status" -eq 2 ]
  out="$output"; run python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["verdict"]=="UNKNOWN" and d["result"]=="unknown" and d["gaps"]==[{"check":"python3","reason":"missing_tool"}], d' "$out"
  [ "$status" -eq 0 ]
}

@test "mcp-audit con python3: config limpio ⇒ clean, config con autoApprove ⇒ findings" {
  run bash "$W/scripts/mcp-real.sh" --config "$W/clean.json" --json
  [ "$status" -eq 0 ]
  [ "$(json_field '["result"]')" = '"clean"' ]
  run bash "$W/scripts/mcp-real.sh" --config "$W/bad.json" --json
  [ "$status" -eq 1 ]
  [ "$(json_field '["result"]')" = '"findings"' ]
  [ "$(json_field '["critical"]')" = 1 ]
}

# ── security-audit-all.sh ───────────────────────────────────────────────────

@test "agregador: un escáner que sale 1 con hallazgos cuenta sus hallazgos (antes 0 y PASS)" {
  stub mcp-security-audit 1 '{"verdict":"FAIL","findings_count":1,"critical":1,"high":0,"medium":0,"low":0}'
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 1 ]
  [ "$(json_field '["verdict"]')" = '"FAIL"' ]
  [ "$(json_field '["total_critical"]')" = 1 ]
  [ "$(json_field '["result"]')" = '"findings"' ]
}

@test "agregador: escáner que revienta o da salida no JSON ⇒ UNKNOWN exit 2 con hueco unreadable" {
  stub mcp-security-audit 127 'bash: python3: orden no encontrada'
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 2 ]
  [ "$(json_field '["verdict"]')" = '"UNKNOWN"' ]
  [ "$(json_field '["gaps"]')" = '[{"check": "mcp-security-audit", "reason": "unreadable"}]' ]
  [ "$(json_field '["scanners"][0]["critical"]')" = null ]
}

@test "agregador: rc 1 sin ninguna cuenta no se lee como limpio" {
  stub hook-injection-audit 1 '{"verdict":"FAIL","findings_count":0,"critical":0,"high":0,"medium":0,"low":0}'
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 2 ]
  [ "$(json_field '["result"]')" = '"unknown"' ]
}

@test "agregador: rc 0 sin la clave critical (esquema cambiado) ⇒ unreadable, no limpio" {
  stub permissions-wildcard-audit 0 '{"verdict":"PASS","findings_count":0,"crit":3,"high":0,"medium":0}'
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 2 ]
  [ "$(json_field '["gaps"]')" = '[{"check": "permissions-wildcard-audit", "reason": "unreadable"}]' ]
  # Sin low (lo que emiten los escáneres reales) sigue siendo legible.
  stub permissions-wildcard-audit 0 '{"verdict":"PASS","findings_count":0,"critical":0,"high":0,"medium":0}'
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 0 ]
}

@test "agregador: sin python3 ⇒ UNKNOWN con la causa python3:missing_tool, no solo unreadable" {
  run env PATH="$NOPY" /usr/bin/bash "$W/scripts/security-audit-all.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *'"check":"python3","reason":"missing_tool"'* ]]
  [[ "$output" == *'"check":"mcp-security-audit","reason":"unreadable"'* ]]
}

# python3 en PATH pero que no arranca (shim de pyenv sin versión, venv roto): `command -v` lo da por bueno.
broken_python() {
  mkdir -p "$W/brokenpy"
  printf '#!/bin/sh\necho "pyenv: python3: command not found" >&2\nexit 127\n' > "$W/brokenpy/python3"
  chmod +x "$W/brokenpy/python3"
}

@test "mcp-audit: python3 presente pero roto ⇒ exit 2 y unknown, no un MCP-00 por config (revisión #1348 P2-4)" {
  broken_python
  run env PATH="$W/brokenpy:$NOPY" /usr/bin/bash "$W/scripts/mcp-real.sh" --config "$W/clean.json"
  [ "$status" -eq 2 ]
  [[ "$output" != *"MCP-00"* ]]
  [ "$(printf '%s\n' "$output" | tail -1)" = 'gate-result: {"result":"unknown","gaps":[{"check":"python3","reason":"missing_tool"}]}' ]
}

@test "agregador: python3 presente pero roto ⇒ hueco python3:missing_tool, no solo unreadable (P2-4)" {
  broken_python
  run env PATH="$W/brokenpy:$NOPY" /usr/bin/bash "$W/scripts/security-audit-all.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *'"check":"python3","reason":"missing_tool"'* ]]
}

@test "agregador: una cuenta booleana (true) es ilegible, no un entero (revisión #1348 P2-5)" {
  stub hook-injection-audit 1 '{"verdict":"FAIL","findings_count":1,"critical":true,"high":0,"medium":0}'
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 2 ]
  [ "$(json_field '["gaps"]')" = '[{"check": "hook-injection-audit", "reason": "unreadable"}]' ]
  [ "$(json_field '["total_critical"]')" = 0 ]
}

@test "agregador: escáner ausente ⇒ hueco missing_tool; prompt-scan roto ⇒ unreadable" {
  mv "$W/scripts/permissions-wildcard-audit.sh" "$W/gone.sh"
  printf '#!/usr/bin/env bash\necho boom >&2\nexit 2\n' > "$W/scripts/prompt-security-scan.sh"
  run bash "$W/scripts/security-audit-all.sh"
  [ "$status" -eq 2 ]
  [ "$(printf '%s\n' "$output" | tail -1)" = 'gate-result: {"result":"unknown","gaps":[{"check":"permissions-wildcard-audit","reason":"missing_tool"},{"check":"prompt-security-scan","reason":"unreadable"}]}' ]
}

@test "agregador: todo limpio ⇒ PASS, exit 0 y result clean sin huecos" {
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 0 ]
  [ "$(json_field '["verdict"]')" = '"PASS"' ]
  [ "$(json_field '["result"]')" = '"clean"' ]
  [ "$(json_field '["gaps"]')" = '[]' ]
}

@test "mcp-audit: sin python3 y sin --config (autodescubrimiento) ⇒ exit 2, nunca un 0 sin auditar" {
  printf '{"mcpServers":{}}' > "$W/.claude/mcp.json"
  run env HOME="$W" PATH="$NOPY" /usr/bin/bash "$W/scripts/mcp-real.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *'"result":"unknown"'* ]]
}

@test "agregador: hallazgo bajo el umbral + hueco ⇒ result unknown, UNKNOWN y exit 2 (antes result findings)" {
  stub hook-injection-audit 0 '{"verdict":"PASS","findings_count":1,"critical":0,"high":0,"medium":0,"low":1}'
  mv "$W/scripts/permissions-wildcard-audit.sh" "$W/gone.sh"
  run bash "$W/scripts/security-audit-all.sh" --json --fail-on HIGH
  [ "$status" -eq 2 ]
  [ "$(json_field '["verdict"]')" = '"UNKNOWN"' ]
  [ "$(json_field '["result"]')" = '"unknown"' ]
  [ "$(json_field '["total_low"]')" = 1 ]
}

@test "agregador: hallazgo bajo el umbral sin huecos ⇒ result clean, PASS y exit 0" {
  stub hook-injection-audit 0 '{"verdict":"PASS","findings_count":1,"critical":0,"high":0,"medium":0,"low":1}'
  run bash "$W/scripts/security-audit-all.sh" --json --fail-on HIGH
  [ "$status" -eq 0 ]
  [ "$(json_field '["verdict"]')" = '"PASS"' ]
  [ "$(json_field '["result"]')" = '"clean"' ]
  [ "$(json_field '["total_low"]')" = 1 ]
}

@test "agregador: hallazgo sobre el umbral + hueco ⇒ findings, FAIL y exit 1 con el hueco en gaps" {
  stub mcp-security-audit 1 '{"verdict":"FAIL","findings_count":1,"critical":1,"high":0,"medium":0,"low":0}'
  mv "$W/scripts/permissions-wildcard-audit.sh" "$W/gone.sh"
  run bash "$W/scripts/security-audit-all.sh" --json --fail-on HIGH
  [ "$status" -eq 1 ]
  [ "$(json_field '["verdict"]')" = '"FAIL"' ]
  [ "$(json_field '["result"]')" = '"findings"' ]
  [ "$(json_field '["gaps"]')" = '[{"check": "permissions-wildcard-audit", "reason": "missing_tool"}]' ]
}

@test "agregador: prompt-scan rc 0 con Findings: 3 cuenta 3 HIGH; rc 1 con Findings: 0 es unreadable" {
  printf '#!/usr/bin/env bash\necho "Scanned: 1 files | Findings: 3 | Warnings: 0"\n' > "$W/scripts/prompt-security-scan.sh"
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 1 ]
  [ "$(json_field '["total_high"]')" = 3 ]
  printf '#!/usr/bin/env bash\necho "Scanned: 1 files | Findings: 0 | Warnings: 0"\nexit 1\n' > "$W/scripts/prompt-security-scan.sh"
  run bash "$W/scripts/security-audit-all.sh" --json
  [ "$status" -eq 2 ]
  [ "$(json_field '["gaps"]')" = '[{"check": "prompt-security-scan", "reason": "unreadable"}]' ]
}
