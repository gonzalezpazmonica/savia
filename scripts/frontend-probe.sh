#!/usr/bin/env bash
# frontend-probe.sh — SE-388 S1: detección de frontends y capability matrix.
# Sin supuestos históricos: cada frontend se sondea; UNKNOWN nunca = soportado.
# Salida: output/frontend-capability-matrix.{json,md} (determinista, local).
#
# Hueco G3: una capacidad de control (red, credenciales, efectos externos,
# handoff, enforcement previo, recibos) solo es NATIVE si su mecanismo está en
# el camino del efecto: hook registrado en .claude/settings.json (Claude) o
# guard importado por el plugin de OpenCode. Si no, DECLARED. Ante settings o
# plugin ausentes o ilegibles, DECLARED (fail-closed).
#
# Uso: frontend-probe.sh                → escribe la matriz
#      frontend-probe.sh --wired <name> → exit 0 si <name> (script o hook) está
#        referenciado por un hook de .claude/settings.json, por el fichero de un
#        hook registrado o por un workflow de CI; exit 1 si no; exit 2 si error.
set -uo pipefail
ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
SETTINGS="${FRONTEND_PROBE_SETTINGS:-$ROOT/.claude/settings.json}"
OC_PLUGIN="${FRONTEND_PROBE_OC_PLUGIN:-$ROOT/.opencode/plugins/savia-foundation.ts}"
WORKFLOWS="${FRONTEND_PROBE_WORKFLOWS:-$ROOT/.github/workflows}"

# Evaluador único de evidencia (también lo usa coherence-gates.sh vía --wired).
effect_eval() { # $1=modo (wired|claude|opencode) [$2=nombre]
  python3 - "$1" "${2:-}" "$SETTINGS" "$OC_PLUGIN" "$WORKFLOWS" "$ROOT" <<'PYEOF'
import json, os, re, sys
mode, name, settings, plugin, workflows, root = sys.argv[1:7]

def load_hooks():
    """[(evento, comando)] registrados; None si settings falta o es ilegible."""
    try:
        d = json.load(open(settings, encoding="utf-8"))
        out = []
        for ev, arr in (d.get("hooks") or {}).items():
            for m in arr or []:
                for h in (m or {}).get("hooks") or []:
                    c = (h or {}).get("command")
                    if isinstance(c, str) and c.strip():
                        out.append((ev, c))
        return out
    except Exception:
        return None

def ref(text, token):
    # nombre exacto: «checkpoint.sh» no casa con «review-checkpoint.sh»
    return re.search(r"(?<![\w.-])" + re.escape(token) + r"(?![\w-])", text) is not None

hooks = load_hooks()

if mode == "wired":
    if not name or hooks is None:
        sys.exit(2)
    texts = [c for _, c in hooks]
    for _, c in hooks:  # contenido de los ficheros de hook registrados (un nivel)
        for p in re.findall(r"[\w$\"{}./-]+\.(?:sh|py)", c):
            p = p.replace('"', "").replace("$CLAUDE_PROJECT_DIR", root).replace("${CLAUDE_PROJECT_DIR}", root)
            if os.path.isfile(p):
                try: texts.append(open(p, encoding="utf-8", errors="replace").read())
                except OSError: pass
    if os.path.isdir(workflows):
        for f in sorted(os.listdir(workflows)):
            if f.endswith((".yml", ".yaml")):
                try: texts.append(open(os.path.join(workflows, f), encoding="utf-8").read())
                except OSError: pass
    sys.exit(0 if any(ref(t, name) for t in texts) else 1)

def pre(rx):
    return hooks is not None and any(ev == "PreToolUse" and re.search(rx, c) for ev, c in hooks)
def post(rx):
    return hooks is not None and any(ev == "PostToolUse" and re.search(rx, c) for ev, c in hooks)
def any_hook(rx):
    return hooks is not None and any(re.search(rx, c) for _, c in hooks)

try:
    plug = open(plugin, encoding="utf-8").read()
except Exception:
    plug = None
def guard(rx):
    return plug is not None and re.search(r"from\s+[\"']\./guards/" + rx, plug) is not None

def st(ok, native, mech, where):
    return native if ok else f"DECLARED ({mech}: sin {where})"

if mode == "claude":
    W = "hook registrado en .claude/settings.json"
    caps = {
        "workspace_resolution": "NATIVE",
        "hierarchical_project_instructions": "NATIVE (CLAUDE.md)",
        "generated_instruction_projection": "NATIVE (SE-047 regen)",
        "shell_execution": "NATIVE",
        "filesystem_access": "NATIVE",
        "tool_call_hooks": st(pre(r".") and post(r"."), "NATIVE (PreToolUse/PostToolUse)", "PreToolUse/PostToolUse", W),
        "pre_tool_enforcement": st(pre(r"block-[\w-]+\.sh"), "NATIVE (hooks block-*)", "hooks block-*", W),
        "post_tool_receipts": st(post(r"edit-ledger-record\.sh"), "NATIVE (edit-ledger-record)", "edit-ledger-record", W),
        "subagent_fan_out": "NATIVE (Task)",
        "command_discovery": "NATIVE (.claude/commands)",
        "mcp_client": "NATIVE",
        "approvals": "NATIVE (human gates)",
        "sandbox": "PARTIAL (settings permissions)",
        "network_policy": st(pre(r"egress-gate\.sh"), "NATIVE (egress-gate)", "egress-gate", W),
        "credential_policy": st(pre(r"block-credential-leak\.sh"), "NATIVE (block-credential-leak)", "block-credential-leak", W),
        "external_effect_control": st(pre(r"operator-grant\.sh\s+guard"), "NATIVE (grants SE-343/F5)", "grants SE-343/F5", W),
        "durable_handoff": st(any_hook(r"validate-handoff[\w-]*\.sh"), "NATIVE (SE-332)", "SE-332 validate-handoff", W),
    }
    print(json.dumps({"frontend": "claude", "present": True, "mechanism": "nativo (workspace propio)",
                      "evidence": os.path.relpath(settings, root) if hooks is not None else "AUSENTE",
                      "capabilities": caps}, ensure_ascii=False))
elif mode == "opencode":
    W = "guard importado por el plugin de OpenCode"
    caps = {
        "workspace_resolution": "NATIVE",
        "hierarchical_project_instructions": "ADAPTABLE (AGENTS.md)",
        "generated_instruction_projection": "NATIVE (skills-md-generate)",
        "shell_execution": "NATIVE",
        "filesystem_access": "NATIVE",
        "tool_call_hooks": st(plug is not None and "tool.execute.before" in plug, "NATIVE (plugin hooks)", "plugin hooks", "tool.execute.before en el plugin"),
        "pre_tool_enforcement": st(guard(r"block-[\w-]+\.ts"), "NATIVE (espejo hooks)", "espejo hooks", W),
        "post_tool_receipts": st(guard(r"edit-ledger-record\.ts"), "NATIVE (edit-ledger-record)", "edit-ledger-record", W),
        "subagent_fan_out": "NATIVE",
        "command_discovery": "NATIVE (.opencode/commands)",
        "mcp_client": "NATIVE",
        "approvals": "ADAPTABLE (human gates via scripts)",
        "sandbox": "PARTIAL",
        "network_policy": st(guard(r"egress[\w-]*\.ts"), "ADAPTABLE (egress-gate)", "egress-gate", W),
        "credential_policy": st(guard(r"block-credential-leak\.ts"), "NATIVE (compartido)", "block-credential-leak", W),
        "external_effect_control": st(guard(r"operator-grant[\w-]*\.ts"), "NATIVE (grants SE-343)", "grants SE-343", W),
        "durable_handoff": st(guard(r"[\w-]*handoff[\w-]*\.ts"), "NATIVE (SE-332)", "SE-332", W),
    }
    print(json.dumps({"frontend": "opencode", "mechanism": "adapter SPEC-127 (.opencode/ mirror)",
                      "evidence": os.path.relpath(plugin, root) if plug is not None else "AUSENTE",
                      "capabilities": caps}, ensure_ascii=False))
else:
    sys.exit(2)
PYEOF
}

if [[ "${1:-}" == "--wired" ]]; then
  [[ -n "${2:-}" ]] || { echo "Uso: $0 --wired <script-o-hook>" >&2; exit 2; }
  effect_eval wired "$2"; exit $?
fi

probe_claude() {
  effect_eval claude
}

probe_opencode() {
  if ! command -v opencode >/dev/null 2>&1; then
    echo '{"frontend":"opencode","present":false,"status":"DEGRADED_SAFE (CLI ausente; mirror completo)"}'
    return
  fi
  effect_eval opencode
}

probe_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    echo '{"frontend":"codex","present":false,"status":"UNKNOWN","l4_unknown":true,"note":"Codex CLI no instalado"}'
    return
  fi
  local ver auth="absent" sandbox_m="?" mcp="?"
  ver=$(codex --version 2>/dev/null | head -1)
  if ls ~/.codex/auth.json >/dev/null 2>&1 && codex login status 2>&1 | grep -qE "Logged in"; then
    auth="authenticated"
  fi
  if timeout 40 codex sandbox echo day1-probe >/dev/null 2>&1; then sandbox_m="native-ok"; else sandbox_m="degraded"; fi
  mcp=$(codex mcp list 2>/dev/null | head -1 | tr -d '"')
  echo "{\"frontend\":\"codex\",\"present\":true,\"cli_version\":\"${ver#codex-cli }\",\"auth\":\"$auth\",\"status\":\"DEGRADED_SAFE\",\"max_verified_risk\":\"L2\",\"l3_l4\":\"BLOCKED_OR_HUMAN_REROUTE\",\"sandbox\":\"$sandbox_m\",\"mcp_client\":\"$mcp\",\"capabilities\":{\"workspace_resolution\":\"NATIVE\",\"hierarchical_project_instructions\":\"NATIVE (AGENTS.md)\",\"generated_instruction_projection\":\"ADAPTABLE\",\"shell_execution\":\"NATIVE (codex exec)\",\"filesystem_access\":\"NATIVE\",\"tool_call_hooks\":\"UNKNOWN (sin PreToolUse equivalente)\",\"pre_tool_enforcement\":\"PARTIAL (sandbox+approvals; L4 requiere reroute)\",\"post_tool_receipts\":\"ADAPTABLE\",\"subagent_fan_out\":\"PARTIAL\",\"command_discovery\":\"UNKNOWN\",\"mcp_client\":\"NATIVE\",\"approvals\":\"NATIVE\",\"sandbox\":\"$sandbox_m\",\"network_policy\":\"PARTIAL\",\"credential_policy\":\"NATIVE\",\"external_effect_control\":\"ADAPTABLE\",\"durable_handoff\":\"ADAPTABLE\"}}"
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
        caps = e.get("capabilities", {})
        declared = sorted(k for k, v in caps.items() if str(v).startswith("DECLARED"))
        default = f"DECLARED_GAPS ({', '.join(declared)})" if declared else "NATIVE"
        f.write(f"## {fe}\n\n- present: {e.get('present')}\n- status: {e.get('status', default)}\n")
        for k, v in caps.items():
            f.write(f"  - {k}: {v}\n")
        f.write("\n")
PYEOF
echo "probe completo → output/frontend-capability-matrix.{json,md}"
