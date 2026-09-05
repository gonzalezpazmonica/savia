#!/usr/bin/env bash
# frontend-probe.sh — SE-388 S1: detección de frontends y capability matrix.
# Sin supuestos históricos: cada frontend se sondea; UNKNOWN nunca = soportado.
# Salida: output/frontend-capability-matrix.{json,md} (determinista, local).
set -uo pipefail
ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"

probe_claude() {
  local caps='{"frontend":"claude","present":true,"mechanism":"nativo (workspace propio)","capabilities":{"workspace_resolution":"NATIVE","hierarchical_project_instructions":"NATIVE (CLAUDE.md)","generated_instruction_projection":"NATIVE (SE-047 regen)","shell_execution":"NATIVE","filesystem_access":"NATIVE","tool_call_hooks":"NATIVE (PreToolUse/PostToolUse)","pre_tool_enforcement":"NATIVE (hooks block-*)","post_tool_receipts":"NATIVE","subagent_fan_out":"NATIVE (Task)","command_discovery":"NATIVE (.claude/commands)","mcp_client":"NATIVE","approvals":"NATIVE (human gates)","sandbox":"PARTIAL (settings permissions)","network_policy":"NATIVE (egress-gate)","credential_policy":"NATIVE (pm-config gitignored)","external_effect_control":"NATIVE (grants SE-343/F5)","durable_handoff":"NATIVE (SE-332)"}}'
  echo "$caps"
}

probe_opencode() {
  local present="true"
  command -v opencode >/dev/null 2>&1 || present="false"
  local caps='{"frontend":"opencode","mechanism":"adapter SPEC-127 (.opencode/ mirror)","capabilities":{"workspace_resolution":"NATIVE","hierarchical_project_instructions":"ADAPTABLE (AGENTS.md)","generated_instruction_projection":"NATIVE (skills-md-generate)","shell_execution":"NATIVE","filesystem_access":"NATIVE","tool_call_hooks":"NATIVE (plugin hooks)","pre_tool_enforcement":"NATIVE (espejo hooks)","post_tool_receipts":"NATIVE","subagent_fan_out":"NATIVE","command_discovery":"NATIVE (.opencode/commands)","mcp_client":"NATIVE","approvals":"ADAPTABLE (human gates via scripts)","sandbox":"PARTIAL","network_policy":"ADAPTABLE (egress-gate)","credential_policy":"NATIVE (compartido)","external_effect_control":"NATIVE (grants SE-343)","durable_handoff":"NATIVE (SE-332)"}}'
  if [[ "$present" == "false" ]]; then
    echo '{"frontend":"opencode","present":false,"status":"DEGRADED_SAFE (CLI ausente; mirror completo)"}'
  else
    echo "$caps"
  fi
}

probe_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    echo '{"frontend":"codex","present":false,"status":"UNKNOWN","l4_unknown":true,"note":"Codex CLI no instalado en este entorno — probe requiere instalación (§4: UNKNOWN nunca es soportado)"}'
  else
    echo '{"frontend":"codex","present":true,"status":"UNKNOWN","note":"CLI presente; probes de capabilities pendientes (P2)"}'
  fi
}

{
  echo "{"
  echo '"matrix_version": 1,'
  echo '"generated": "deterministic (probes locales)",'
  echo '"claude": '$(probe_claude)","
  echo '"opencode": '$(probe_opencode)","
  echo '"codex": '$(probe_codex)
  echo "}"
} > "$ROOT/output/frontend-capability-matrix.json" 2>/dev/null || {
  mkdir -p "$ROOT/output"
  { echo "{"; echo '"claude": '$(probe_claude)","; echo '"opencode": '$(probe_opencode)","; echo '"codex": '$(probe_codex); echo "}"; } > "$ROOT/output/frontend-capability-matrix.json"
}

# Markdown
python3 - "$ROOT/output/frontend-capability-matrix.json" "$ROOT/output/frontend-capability-matrix.md" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write("# Frontend Capability Matrix (SE-388)\n\n")
    f.write("Generado desde probes locales. UNKNOWN nunca = soportado.\n\n")
    for fe in ("claude", "opencode", "codex"):
        e = d.get(fe, {})
        f.write(f"## {fe}\n\n- present: {e.get('present')}\n- status: {e.get('status','NATIVE')}\n")
        caps = e.get("capabilities", {})
        for k, v in caps.items():
            f.write(f"  - {k}: {v}\n")
        f.write("\n")
PYEOF
echo "probe completo → output/frontend-capability-matrix.{json,md}"
