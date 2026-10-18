#!/usr/bin/env bash
# opencode-health-check.sh — SPEC-OC2-03
#
# Gate de solo lectura para la ejecución de Savia en OpenCode.
# No modifica configuración, no escribe estado y no llama al modelo.
#
# Uso: bash scripts/opencode-health-check.sh [--repo DIR]
# Exit: 0 PASS (puede incluir WARN), 1 FAIL.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift ;;
    --help|-h) sed -n '2,9p' "$0"; exit 0 ;;
  esac
  shift
done

FAILS=0
WARNS=0
pass() { printf 'PASS %s\n' "$1"; }
warn() { printf 'WARN %s\n' "$1"; WARNS=$((WARNS+1)); }
fail() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS+1)); }

command -v opencode >/dev/null 2>&1 || { fail "opencode no está en PATH"; exit 1; }

VER=$(opencode --version 2>/dev/null || echo "?")
MAJOR=${VER%%.*}
pass "opencode $VER"

# 1. Plugin local descubierto
if opencode plugin list 2>/dev/null | grep -q "savia-foundation"; then
  pass "plugin savia-foundation descubierto"
else
  fail "plugin savia-foundation no descubierto"
fi

# 2. Config efectiva sin fugas y con controles V2
CFG=$(opencode debug config 2>/dev/null)
if [[ -z "$CFG" ]]; then
  fail "opencode debug config no devuelve configuración"
else
  if printf '%s' "$CFG" | grep -q '"model_tier"'; then
    fail "model_tier presente en la config efectiva (fuga a request.body)"
  else
    pass "sin model_tier en la config efectiva"
  fi
  if printf '%s' "$CFG" | grep -q '"external_directory"'; then
    pass "permission external_directory definido"
  else
    warn "external_directory no definido (V2 permite acceso externo por defecto)"
  fi
  if printf '%s' "$CFG" | grep -q '"subagent_depth": 2'; then
    pass "subagent_depth=2"
  else
    warn "subagent_depth distinto de 2 (orquestación SDD limitada)"
  fi
  if printf '%s' "$CFG" | grep -q '"policies"'; then
    pass "policies presentes"
  else
    warn "policies ausentes (solo aplican en OpenCode 2)"
  fi
fi

# 3. MCP: los desactivados no deben intentar arrancar
MCP=$(opencode mcp list 2>&1 || true)
if printf '%s' "$MCP" | grep -q "savia-vaults"; then
  if printf '%s' "$MCP" | grep -qE "✗ savia-vaults|savia-vaults.*failed"; then
    fail "savia-vaults no conecta"
  else
    pass "savia-vaults sin fallo reportado"
  fi
else
  warn "savia-vaults no aparece en mcp list"
fi
if printf '%s' "$MCP" | grep -qE "✗ (codegraph|codebase-memory-mcp)"; then
  fail "servidores marcados desactivados siguen intentando arrancar"
else
  pass "servidores desactivados no arrancan"
fi

# 4. Contrato dual del plugin (sin bun)
SMOKE="$REPO/.opencode/plugins/__tests__/v2-compat.smoke.ts"
if [[ -f "$SMOKE" ]]; then
  if timeout 120 node --experimental-strip-types "$SMOKE" >/dev/null 2>&1; then
    pass "smoke dual V1/V2"
  else
    fail "smoke dual V1/V2"
  fi
else
  warn "smoke dual no encontrado ($SMOKE)"
fi

printf -- '---\n'
if [[ "$FAILS" -gt 0 ]]; then
  printf 'RESULT FAIL (%d fallos, %d warnings)\n' "$FAILS" "$WARNS"
  exit 1
fi
printf 'RESULT PASS (%d warnings)\n' "$WARNS"
exit 0
