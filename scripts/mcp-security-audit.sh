#!/usr/bin/env bash
# mcp-security-audit.sh — SE-058 Slice 1 MCP supply-chain + config audit.
#
# Audita MCP server declarations en:
#   - .claude/mcp.json (repo-level)
#   - ~/.claude.json (user-level, mcpServers block)
#
# Detecta 11 patrones MCP-01..MCP-11 inspirados en agentshield (MIT):
# supply chain (npx -y sin pin), auto-approve, hardcoded secrets,
# shell transport, remote sin auth, metacaracteres, path traversal, etc.
#
# Usage:
#   mcp-security-audit.sh                    # audit default configs
#   mcp-security-audit.sh --config PATH      # specific file
#   mcp-security-audit.sh --json
#   mcp-security-audit.sh --severity high    # filter findings
#
# Exit codes:
#   0 — no findings
#   1 — findings present
#   2 — usage error, o auditoría imposible (python3 ausente)
#
# SE-453: resultado clean|findings|unknown. En texto, la última línea de stdout es
# `gate-result: {...}`; con --json, los campos `result` y `gaps` del propio JSON.
# python3 ausente ⇒ unknown/python3:missing_tool y exit 2 (antes salía 1 con un falso MCP-00).
# --config a un fichero que no existe o no se puede leer, o ninguna config por defecto ⇒
# unknown/config:unreadable (exit 0, registrado; SAVIA_GATE_UNKNOWN=block ⇒ exit 2).
#
# Ref: SE-058, research/agentshield-20260420.md
# Safety: read-only. set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh"
GAPS=()
add_gap() { [[ " ${GAPS[*]} " == *" $1 "* ]] || GAPS+=("$1"); }

CONFIGS=()
JSON=0
MIN_SEVERITY="LOW"
SEVERITIES=(LOW MEDIUM HIGH CRITICAL)

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  --config PATH        Audit specific config (can be repeated)
  --severity LEVEL     Report findings >= LEVEL (LOW/MEDIUM/HIGH/CRITICAL, default LOW)
  --json               JSON output

Default: audits .claude/mcp.json + ~/.claude.json mcpServers block.
Ref: SE-058. Rules MCP-01..MCP-11.
EOF
}

sev_rank() {
  case "$1" in
    LOW) echo 1 ;;
    MEDIUM) echo 2 ;;
    HIGH) echo 3 ;;
    CRITICAL) echo 4 ;;
    *) echo 0 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIGS+=("$2"); shift 2 ;;
    --severity) MIN_SEVERITY="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Validate severity
if [[ "$(sev_rank "$MIN_SEVERITY")" -eq 0 ]]; then
  echo "ERROR: invalid severity '$MIN_SEVERITY'" >&2; exit 2
fi
MIN_RANK=$(sev_rank "$MIN_SEVERITY")

# Default configs if none specified
if [[ ${#CONFIGS[@]} -eq 0 ]]; then
  [[ -f "$PROJECT_ROOT/.claude/mcp.json" ]] && CONFIGS+=("$PROJECT_ROOT/.claude/mcp.json")
  [[ -f "$HOME/.claude.json" ]] && CONFIGS+=("$HOME/.claude.json")
  # Sin ninguna config que leer no hay evidencia de «limpio» (mismo criterio que --config inexistente).
  [[ ${#CONFIGS[@]} -eq 0 ]] && add_gap "config:unreadable"
fi

FINDINGS=()
total_servers=0

# emit_result <result> — salida del contrato SE-453 en el formato pedido (texto o --json).
emit_result() {
  local result="$1"
  if [[ "$JSON" -eq 1 ]]; then
    gate_result_emit "$result" "${GAPS[@]}" | sed 's/^gate-result: //'
  else
    gate_result_emit "$result" "${GAPS[@]}"
  fi
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 no disponible; no se puede auditar ninguna configuración MCP." >&2
  add_gap "python3:missing_tool"
  GATE_UNMEASURED_ROOT="$PROJECT_ROOT" gate_unmeasured_record "mcp-security-audit" missing_tool
  emit_result unknown
  exit 2
fi

# Emit finding
add_finding() {
  local rule="$1" sev="$2" server="$3" detail="$4" config="$5"
  local rank
  rank=$(sev_rank "$sev")
  [[ "$rank" -lt "$MIN_RANK" ]] && return 0
  FINDINGS+=("$rule|$sev|$server|$detail|$config")
}

# Process a single config file
audit_config() {
  local cfg="$1"
  if [[ ! -f "$cfg" || ! -r "$cfg" ]]; then
    add_gap "config:unreadable"
    return 0
  fi

  # Check if valid JSON
  if ! python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$cfg" 2>/dev/null; then
    add_finding "MCP-00" "HIGH" "_global" "Invalid JSON in $cfg" "$cfg"
    return 0
  fi

  # Extract mcpServers entries
  local servers_json
  servers_json=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
servers = d.get('mcpServers', {})
for name, cfg in servers.items():
    if isinstance(cfg, dict):
        print(json.dumps({'name': name, 'cfg': cfg}))
" "$cfg" 2>/dev/null)

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    total_servers=$((total_servers + 1))

    local server cmd_str args_str env_str auto_approve transport descr
    server=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
    cmd_str=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['cfg'].get('command',''))")
    args_str=$(echo "$line" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['cfg'].get('args',[])))")
    env_str=$(echo "$line" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['cfg'].get('env',{})))")
    auto_approve=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['cfg'].get('autoApprove', False))")
    transport=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['cfg'].get('transport',''))")
    descr=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['cfg'].get('description',''))")

    # MCP-01: npx -y without version pin
    if [[ "$cmd_str" == "npx" && "$args_str" == *"-y "* ]]; then
      if ! echo "$args_str" | grep -qE '@[0-9]+\.[0-9]+'; then
        add_finding "MCP-01" "HIGH" "$server" "npx -y without version pin (RCE via typosquatting)" "$cfg"
      fi
    fi

    # MCP-02: autoApprove true
    if [[ "$auto_approve" == "True" ]]; then
      add_finding "MCP-02" "CRITICAL" "$server" "autoApprove=true bypasses user consent" "$cfg"
    fi

    # MCP-03: hardcoded secrets in env (match key-name + long value)
    if echo "$env_str" | grep -qiE '"(api[_-]?key|token|secret|password|access[_-]?key)"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_.-]{16,}"'; then
      add_finding "MCP-03" "CRITICAL" "$server" "Hardcoded secret pattern in env" "$cfg"
    fi

    # MCP-04: shell transport
    if [[ "$transport" == "shell" || "$transport" == "bash" ]]; then
      add_finding "MCP-04" "HIGH" "$server" "Shell transport without sandbox" "$cfg"
    fi

    # MCP-05: remote endpoint
    if echo "$args_str" | grep -qE 'https?://' && ! echo "$env_str" | grep -qiE 'authorization|bearer'; then
      add_finding "MCP-05" "HIGH" "$server" "Remote endpoint without auth header" "$cfg"
    fi

    # MCP-06: shell metacharacters in args
    if echo "$args_str" | grep -qE '[;|`$(){}]'; then
      add_finding "MCP-06" "HIGH" "$server" "Shell metacharacters in args" "$cfg"
    fi

    # MCP-07: sensitive paths
    if echo "$args_str" | grep -qE '\.ssh|\.aws|\.azure|\.gnupg'; then
      add_finding "MCP-07" "HIGH" "$server" "Args reference sensitive credential dirs" "$cfg"
    fi

    # MCP-08: path traversal in name
    if [[ "$server" == *".."* ]]; then
      add_finding "MCP-08" "CRITICAL" "$server" "Path traversal in server name" "$cfg"
    fi

    # MCP-09: command bash/sh without whitelist
    if [[ "$cmd_str" == "bash" || "$cmd_str" == "sh" || "$cmd_str" == "/bin/sh" ]]; then
      add_finding "MCP-09" "HIGH" "$server" "Raw bash/sh command without whitelist" "$cfg"
    fi

    # MCP-10: PATH override in env
    if echo "$env_str" | grep -q '"PATH"'; then
      add_finding "MCP-10" "MEDIUM" "$server" "env overrides PATH" "$cfg"
    fi

    # MCP-11: missing description
    if [[ -z "$descr" ]]; then
      add_finding "MCP-11" "LOW" "$server" "Missing description/metadata" "$cfg"
    fi
  done <<< "$servers_json"
}

for c in "${CONFIGS[@]}"; do
  audit_config "$c"
done

EXIT_CODE=0
[[ ${#FINDINGS[@]} -gt 0 ]] && EXIT_CODE=1

# Count by severity
count_sev() {
  local s="$1" c=0
  for f in "${FINDINGS[@]}"; do
    [[ "$f" == *"|$s|"* ]] && c=$((c + 1))
  done
  echo "$c"
}

CRIT=$(count_sev "CRITICAL")
HIGH=$(count_sev "HIGH")
MED=$(count_sev "MEDIUM")
LOW=$(count_sev "LOW")

RESULT="clean"
if [[ ${#FINDINGS[@]} -gt 0 ]]; then RESULT="findings"; elif [[ ${#GAPS[@]} -gt 0 ]]; then RESULT="unknown"; fi
if [[ "$RESULT" == "unknown" ]]; then
  GATE_UNMEASURED_ROOT="$PROJECT_ROOT" gate_unmeasured_record "mcp-security-audit" "${GAPS[0]#*:}"
  [[ "${SAVIA_GATE_UNKNOWN:-warn}" == "block" ]] && EXIT_CODE=2
fi
GATE_JSON="$(gate_result_emit "$RESULT" "${GAPS[@]}" | sed 's/^gate-result: {//; s/}$//')"

if [[ "$JSON" -eq 1 ]]; then
  findings_json=""
  for f in "${FINDINGS[@]}"; do
    IFS='|' read -r rule sev server detail cfg <<< "$f"
    detail_esc=$(echo "$detail" | sed 's/"/\\"/g')
    cfg_esc=$(echo "$cfg" | sed 's/"/\\"/g')
    findings_json+="{\"rule\":\"$rule\",\"severity\":\"$sev\",\"server\":\"$server\",\"detail\":\"$detail_esc\",\"config\":\"$cfg_esc\"},"
  done
  findings_json="[${findings_json%,}]"
  cat <<JSON
{"verdict":"$([ $EXIT_CODE -eq 0 ] && echo PASS || echo FAIL)","configs_audited":${#CONFIGS[@]},"servers_audited":$total_servers,"findings_count":${#FINDINGS[@]},"critical":$CRIT,"high":$HIGH,"medium":$MED,"low":$LOW,"findings":$findings_json,$GATE_JSON}
JSON
else
  echo "=== SE-058 MCP Security Audit ==="
  echo ""
  echo "Configs audited:   ${#CONFIGS[@]}"
  echo "Servers audited:   $total_servers"
  echo "Findings:          ${#FINDINGS[@]} (crit=$CRIT high=$HIGH med=$MED low=$LOW)"
  echo ""
  if [[ ${#FINDINGS[@]} -gt 0 ]]; then
    echo "Findings:"
    for f in "${FINDINGS[@]}"; do
      IFS='|' read -r rule sev server detail cfg <<< "$f"
      printf "  [%s] %-9s %-30s %s\n" "$rule" "$sev" "$server" "$detail"
    done
    echo ""
  fi
  echo "VERDICT: $([ $EXIT_CODE -eq 0 ] && echo PASS || echo FAIL)"
  emit_result "$RESULT"
fi

exit $EXIT_CODE
