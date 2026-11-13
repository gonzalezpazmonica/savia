#!/usr/bin/env bash
set -uo pipefail
# mcp-effect-guard.sh — Guard previo de efectos para tools MCP, WebFetch y WebSearch (SE-508 S1). PreToolUse.
# Matcher: mcp__.*|WebFetch|WebSearch
#
# Clasifica la tool con config/mcp-effect-catalog.yaml (lo más estricto entre el árbol y el `main` de la URL
# canónica): read_only pasa, write pregunta con destino y efecto, merge se rechaza (SE-343), una tool sin
# clasificar pregunta. WebFetch: host de config/webfetch-allow-hosts, https, sin query ni fragmento y ruta
# corta; WebSearch: se registra. Ambos en observación (solo registro) hasta OBSERVE_UNTIL en sesiones con
# persona; en un run sin persona (SAVIA_RUN_ID o SAVIA_AUTONOMOUS_RUN=1) todo ask pasa a deny.
#
# DUAL_BINDING: la misma decisión la toma savia-gates en OpenCode
# (scripts/opencode-plugin/savia-gates/lib/mcp-effect-guard.ts) llamando al mismo núcleo, lib/mcp_effect_guard.py.
# Paridad: tests/hooks/test-se508-mcp-guard-parity.bats.
#
# Sin interruptor: ninguna variable lo apaga ni lo delega en Claude Code (SAVIA_GATES_PIN y SAVIA_MCP_GUARD
# no cuentan aquí; Space no lanza Claude Code). Tampoco pasa por profile-gate: un perfil de hooks mínimo no lo
# quita. Fallo del núcleo o de python3 → ask (deny sin persona); nunca deja pasar.

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
ROOT="${CLAUDE_PROJECT_DIR:-${SAVIA_WORKSPACE_DIR:-$(pwd)}}"

fail_closed() {
  local decision="ask" reason="Guard de efectos: $1"
  if [[ -n "${SAVIA_RUN_ID:-}" || "${SAVIA_AUTONOMOUS_RUN:-}" == "1" ]]; then decision="deny"; fi
  reason="${reason//\\/\\\\}"; reason="${reason//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
    "$decision" "$reason"
  exit 0
}

# La inyección de remoto y reloj (SAVIA_MCP_GUARD_TEST*) es solo de tests: fuera de bats (que exporta BATS_VERSION)
# se quita, igual que productionEnv en el binding de OpenCode. Un `env` en la configuración del frontend no puede
# cambiar el remoto de referencia ni la fecha del guard.
if [[ -z "${BATS_VERSION:-}" ]]; then
  for _v in $(compgen -e); do [[ "$_v" == SAVIA_MCP_GUARD_TEST* ]] && unset "$_v"; done
  unset BATS_TEST_FILENAME _v
fi

command -v python3 >/dev/null 2>&1 || fail_closed "python3 no disponible; no se puede comprobar qué hace la llamada"
[[ -f "$LIB_DIR/mcp_effect_guard.py" ]] || fail_closed "falta el núcleo del guard; no se puede comprobar qué hace la llamada"
# El núcleo lee el payload directamente de stdin. Su tiempo máximo (3 s ls-remote + 2×6 s fetch) cabe en el de
# este timeout, y este en el del registro: un timeout del frontend dejaría pasar la llamada.
if ! OUT=$(timeout 20 python3 "$LIB_DIR/mcp_effect_guard.py" --root "$ROOT" --frontend claude --hook 2>/dev/null); then
  fail_closed "el guard falló; no se puede comprobar qué hace la llamada"
fi
[[ -n "$OUT" ]] && printf '%s\n' "$OUT"
exit 0
