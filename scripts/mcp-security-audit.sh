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
#   mcp-security-audit.sh --osv npx pkg@1.2.3  # SE-443 S2: aviso de malware en OSV (0/1/2)
#
# Exit codes:
#   0 — no findings
#   1 — findings present
#   2 — usage error, o auditoría imposible (python3 ausente)
# Con --osv: 0 sin avisos MAL-*, 1 aviso MAL-*, 2 ASK (no se pudo comprobar; nunca 0).
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
  --osv EXEC PKG@VER   SE-443: consulta OSV por avisos MAL-* de un paquete npx (npm) o
                       uvx (PyPI). Exit 0 limpio, 1 malware, 2 ASK (no comprobable).
                       Solo envía {ecosystem,name,version}; recibo en output/mcp-osv-receipts.jsonl

Default: audits .claude/mcp.json + ~/.claude.json mcpServers block.
Ref: SE-058. Rules MCP-01..MCP-11.
EOF
}

# ── SE-443 S2: --osv <npx|uvx> [flags] <paquete@versión> ─────────────────────
# Consulta OSV por avisos de malware (MAL-*) antes de habilitar un MCP. Solo sale a la
# red cuando se pide de forma explícita: ningún arranque invoca este modo.
# Envía únicamente {ecosystem, name, version} (N1, público); el nombre y la versión se
# validan antes, así que una ruta local o un valor raro nunca llega a la red.
# Salida: 0 sin avisos MAL-*; 1 con aviso MAL-* (lo nombra); 2 = ASK (no se pudo comprobar:
# red caída, timeout, HTTP no 200, respuesta no JSON, curl/jq ausentes, sin versión exacta,
# ejecutor desconocido, recibo no escrito). Nunca 0 sin respuesta válida.
# Recibo: una línea JSON por consulta en output/mcp-osv-receipts.jsonl
# (SAVIA_OSV_RECEIPT_FILE lo cambia), mismo formato append-only que unmeasured-gates.jsonl.
OSV_URL="https://api.osv.dev/v1/query"

# Escapa un valor para una cadena JSON sin jq: quita caracteres de control y escapa \ y ".
# Bash puro: la rama sin jq no puede depender de más herramientas externas.
osv_json_str() { local v="$1"; v="${v//[$'\001'-$'\037'$'\177']/}"; v="${v//\\/\\\\}"; printf '"%s"' "${v//\"/\\\"}"; }

# Una línea JSON del recibo. Con jq, todos los campos van por --arg; sin jq (solo en la rama
# «jq ausente»), cada campo pasa por osv_json_str. Ningún camino interpola texto sin escapar.
osv_receipt_line() { # <ts> <result> <exit> <reason> <advisories separados por espacio>
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ts "$1" --arg ex "$OSV_EXEC" --arg eco "$OSV_ECO" --arg n "$OSV_NAME" --arg v "$OSV_VER" \
      --arg r "$2" --argjson c "$3" --arg why "$4" --arg adv "$5" \
      '{ts:$ts,check:"osv",executor:$ex,ecosystem:$eco,name:$n,version:$v,result:$r,exit:$c,reason:$why,advisories:($adv | split(" ") | map(select(length > 0)))}' 2>/dev/null
  else
    local advj="" a
    for a in $5; do advj+="${advj:+,}$(osv_json_str "$a")"; done
    printf '{"ts":%s,"check":"osv","executor":%s,"ecosystem":%s,"name":%s,"version":%s,"result":%s,"exit":%d,"reason":%s,"advisories":[%s]}' \
      "$(osv_json_str "$1")" "$(osv_json_str "$OSV_EXEC")" "$(osv_json_str "$OSV_ECO")" "$(osv_json_str "$OSV_NAME")" \
      "$(osv_json_str "$OSV_VER")" "$(osv_json_str "$2")" "$3" "$(osv_json_str "$4")" "$advj"
  fi
}

osv_finish() { # <result clean|findings|unknown> <exit> <reason> <gap|-> [advisories]
  local result="$1" code="$2" reason="$3" gap="$4" adv="${5:-}" rfile ts
  rfile="${SAVIA_OSV_RECEIPT_FILE:-$PROJECT_ROOT/output/mcp-osv-receipts.jsonl}"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local line
  line="$(osv_receipt_line "$ts" "$result" "$code" "$reason" "$adv")"
  if ! { [[ -n "$line" ]] && mkdir -p "$(dirname "$rfile")" && printf '%s\n' "$line" >> "$rfile"; } 2>/dev/null; then
    echo "ERROR: no se pudo escribir el recibo OSV en $rfile" >&2
    [[ "$code" -eq 0 ]] && { code=2; result=unknown; gap="osv-receipt:unreadable"; reason="recibo no escrito"; }
  fi
  case "$code" in
    0) echo "VERDICT: PASS — $OSV_ECO $OSV_NAME@$OSV_VER sin avisos MAL-* en OSV" ;;
    1) echo "VERDICT: FAIL — $OSV_ECO $OSV_NAME@$OSV_VER tiene aviso de malware: $adv" ;;
    *) echo "VERDICT: ASK — no se pudo comprobar en OSV: $reason" ;;
  esac
  if [[ "$gap" == "-" ]]; then gate_result_emit "$result"; else gate_result_emit "$result" "$gap"; fi
  exit "$code"
}

osv_main() {
  OSV_EXEC="" OSV_ECO="" OSV_NAME="" OSV_VER=""
  local exec="${1:-}" spec="" a
  [[ $# -gt 0 ]] && shift
  case "$exec" in
    npx) OSV_EXEC=npx; OSV_ECO=npm ;;
    uvx) OSV_EXEC=uvx; OSV_ECO=PyPI ;;
    *) osv_finish unknown 2 "ejecutor no soportado (solo npx o uvx)" "osv-executor:not_executed" ;;
  esac
  # Antes del paquete solo se admiten opciones que no cambian qué se instala. Cualquier otra
  # (--package/-p, --from, --with, --registry, --index-url, --) podría hacer que el ejecutor
  # instale un paquete distinto del comprobado: ASK. Lo que va después del paquete son
  # argumentos del propio servidor MCP y no cambian lo instalado.
  for a in "$@"; do
    case "$a" in
      -y|--yes|-q|--quiet) continue ;;
      # El motivo no repite la opción: es entrada cruda (puede llevar rutas o credenciales).
      -*) osv_finish unknown 2 "opción del ejecutor no admitida antes del paquete: podría instalar otro paquete" "osv-package:not_executed" ;;
    esac
    spec="$a"; break
  done
  [[ -n "$spec" ]] || osv_finish unknown 2 "falta el paquete" "osv-package:not_executed"
  local name ver name_re ver_re
  if [[ "$OSV_ECO" == npm ]]; then
    if [[ "$spec" == @*/*@* ]]; then name="@${spec#@}"; name="${name%@*}"; ver="${spec##*@}"
    elif [[ "$spec" == @* || "$spec" != *@* ]]; then name="$spec"; ver=""
    else name="${spec%@*}"; ver="${spec##*@}"; fi
    # Mayúsculas admitidas: npm conserva nombres legacy como JSONStream.
    name_re='^(@[A-Za-z0-9][A-Za-z0-9._~-]*/)?[A-Za-z0-9][A-Za-z0-9._~-]*$'
    # Sin metadatos de build (+x): npm los descarta al resolver y OSV recibiría otra cadena.
    ver_re='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'
  else
    if [[ "$spec" == *==* ]]; then name="${spec%%==*}"; ver="${spec#*==}"
    elif [[ "$spec" == *@* ]]; then name="${spec%%@*}"; ver="${spec#*@}"
    else name="$spec"; ver=""; fi
    name_re='^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$'
    # Solo la forma canónica PEP 440 de una versión pública (sin +local): uv resuelve por
    # equivalencia y OSV recibe la cadena tal cual, así que 1.0.0-RC1 o 1.0+x darían ASK.
    ver_re='^([0-9]+!)?[0-9]+(\.[0-9]+)*((a|b|rc)[0-9]+)?(\.post[0-9]+)?(\.dev[0-9]+)?$'
  fi
  [[ "$name" =~ $name_re ]] || osv_finish unknown 2 "nombre de paquete no válido o local; no se envía" "osv-package:not_executed"
  # PyPI: nombre normalizado según PEP 503 (minúsculas; -, _ y . seguidos → -).
  if [[ "$OSV_ECO" == PyPI ]]; then name="$(printf '%s' "$name" | tr 'A-Z' 'a-z' | sed -E 's/[-_.]+/-/g')"; fi
  OSV_NAME="$name"
  [[ -n "$ver" ]] || osv_finish unknown 2 "sin versión exacta fijada; OSV no puede responder por una versión desconocida" "osv-version:not_executed"
  [[ "$ver" =~ $ver_re ]] || osv_finish unknown 2 "versión no exacta o no válida" "osv-version:not_executed"
  OSV_VER="$ver"
  command -v curl >/dev/null 2>&1 || osv_finish unknown 2 "curl ausente" "curl:missing_tool"
  command -v jq >/dev/null 2>&1 || osv_finish unknown 2 "jq ausente" "jq:missing_tool"
  local body resp rc http payload
  body="$(jq -nc --arg e "$OSV_ECO" --arg n "$OSV_NAME" --arg v "$OSV_VER" '{package:{ecosystem:$e,name:$n},version:$v}')"
  resp="$(printf '%s' "$body" | curl -q -sS --max-time "${SAVIA_OSV_TIMEOUT:-15}" -X POST \
    -H 'Content-Type: application/json' --data-binary @- -w '\n%{http_code}' "$OSV_URL" 2>/dev/null)"
  rc=$?
  [[ $rc -eq 28 ]] && osv_finish unknown 2 "tiempo agotado consultando OSV" "osv:timeout"
  [[ $rc -ne 0 ]] && osv_finish unknown 2 "OSV inaccesible (curl $rc)" "osv:unreadable"
  http="${resp##*$'\n'}"; payload="${resp%$'\n'*}"
  [[ "$http" == 200 ]] || osv_finish unknown 2 "OSV respondió HTTP $http" "osv:unreadable"
  jq -e 'type == "object" and ((.vulns // []) | type == "array")' <<< "$payload" >/dev/null 2>&1 \
    || osv_finish unknown 2 "respuesta de OSV no es JSON válido" "osv:unreadable"
  # Primero se decide si hay malware y después se sanean los IDs para imprimirlos: un aviso
  # MAL-* cuyos IDs no pasan el saneado sigue siendo un hallazgo (con un marcador genérico).
  local mal nmal
  nmal="$(jq -r '[(.vulns // [])[] | select(([.id] + (.aliases // [])) | map(tostring) | any(startswith("MAL-")))] | length' <<< "$payload" 2>/dev/null)" \
    || osv_finish unknown 2 "respuesta de OSV ilegible" "osv:unreadable"
  mal="$(jq -r '[(.vulns // [])[] | select(([.id] + (.aliases // [])) | map(tostring) | any(startswith("MAL-"))) | ([.id] + (.aliases // []))[] | tostring | select(test("^[A-Za-z0-9._:-]+$"))] | unique | join(" ")' <<< "$payload" 2>/dev/null)" \
    || osv_finish unknown 2 "respuesta de OSV ilegible" "osv:unreadable"
  [[ "$nmal" =~ ^[0-9]+$ ]] || osv_finish unknown 2 "respuesta de OSV ilegible" "osv:unreadable"
  if [[ "$nmal" -gt 0 ]]; then osv_finish findings 1 "aviso de malware" "-" "${mal:-MAL-id-no-imprimible}"; fi
  [[ "$(jq -r '.next_page_token // empty' <<< "$payload")" ]] \
    && osv_finish unknown 2 "respuesta de OSV paginada e incompleta" "osv:limit"
  osv_finish clean 0 "sin avisos MAL-*" "-"
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
    --osv) shift; osv_main "$@" ;;
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

# Se prueba que python3 arranque, no solo que exista: un shim de pyenv sin versión o un venv roto
# pasan `command -v` y luego cada config saldría como un falso MCP-00.
if ! python3 -c '' >/dev/null 2>&1; then
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
