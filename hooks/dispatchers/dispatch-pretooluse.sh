#!/usr/bin/env bash
# dispatch-pretooluse.sh — SE-253 Slice 4, contrato de fallo cerrado de SE-510 D3
set -uo pipefail
# Único punto de entrada PreToolUse. Lee routing-pretooluse.tsv (generada desde settings.json
# por scripts/dispatch-table.py) y despacha.
#
# Input  : JSON de Claude Code / OpenCode en stdin (se parsea una vez; cada hook lo recibe por stdin)
# Exit   : 0 (permitir), 2 (bloquear)
#
# FALLO CERRADO: tabla ausente o ilegible, JSON roto, herramienta desconocida, fila mal formada,
# hook ausente, exit distinto de 0/2 en un hook bloqueante, tiempo agotado o fallo del propio
# despachador => exit 2 con el motivo. Ningún error deja pasar la operación.
# Ref    : docs/rules/domain/se-253-dispatcher-design.md · docs/specs/SE-510-*.md (D3, AC-5)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROUTING="$REPO_ROOT/hooks/routing-pretooluse.tsv"
HOOK_TIMEOUT="${DISPATCH_HOOK_TIMEOUT:-100}"
HOOK_KILL_GRACE=5   # tras el TERM, KILL: un hook que ignora TERM no cuelga la acción
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$REPO_ROOT}"

# Motivo ambiguo = POLÍTICA (decisión de la operadora, SE-510 S0).
block() {
    echo "[dispatch-pretooluse] BLOQUEO (POLÍTICA): $1" >&2
    exit 2
}

# Entero 1..100: `timeout 0` desactivaría el límite y un hook colgado colgaría la sesión.
[[ "$HOOK_TIMEOUT" =~ ^[1-9][0-9]*$ && "$HOOK_TIMEOUT" -le 100 ]] \
    || block "DISPATCH_HOOK_TIMEOUT inválido (entero 1..100): $HOOK_TIMEOUT"

INPUT=$(cat) || block "no se pudo leer stdin"

# ── Parseo único del JSON: herramienta ────────────────────────────────────────
command -v python3 >/dev/null 2>&1 || block "python3 no disponible"
TOOL=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
name = (d.get('tool_use', {}) or {}).get('name', '') or d.get('tool_name', '') or d.get('name', '')
if not isinstance(name, str) or not name:
    sys.exit(3)
print(name)
" 2>/dev/null) || block "entrada JSON malformada o sin nombre de herramienta"

# ── Tabla: debe existir y ser legible ─────────────────────────────────────────
[[ -f "$ROUTING" && -r "$ROUTING" ]] || block "tabla de despacho ausente o ilegible: $ROUTING"
command -v timeout >/dev/null 2>&1 || block "timeout no disponible: no se puede acotar el tiempo de los hooks"

# La entrada va a cada hook desde un fichero, no por tubería: con `pipefail`, un hook que sale 0
# sin leer stdin dejaba a printf con SIGPIPE (141) y el despachador bloqueaba en falso.
INPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/dispatch-pretooluse.XXXXXX") || block "no se pudo crear el fichero de entrada"
trap 'rm -f "$INPUT_FILE"' EXIT
printf '%s' "$INPUT" > "$INPUT_FILE" || block "no se pudo escribir el fichero de entrada"

# ── Lee y valida la tabla entera antes de ejecutar nada ───────────────────────
# `|| [[ -n "$matcher" ]]`: la última fila cuenta aunque no acabe en salto de línea.
ROW_MATCH=() ROW_SPEC=() ROW_BLOCK=()
while IFS=$'\t' read -r matcher script_spec mode blocking desc || [[ -n "$matcher" ]]; do
    [[ -z "$matcher" ]] && continue
    [[ "$matcher" =~ ^[[:space:]]*# ]] && continue
    [[ -n "$script_spec" && ( "$mode" == "spawn" || "$mode" == "source" ) \
        && ( "$blocking" == "yes" || "$blocking" == "no" ) ]] \
        || block "fila mal formada en la tabla (matcher=$matcher)"
    # `source` no se puede acotar con timeout y un `exit` interno escapa al contrato.
    [[ "$mode" == "spawn" ]] || block "modo $mode no soportado (solo spawn): $script_spec"
    ROW_MATCH+=("$matcher"); ROW_SPEC+=("$script_spec"); ROW_BLOCK+=("$blocking")
done < "$ROUTING" || block "fallo leyendo la tabla de despacho"

# El matcher es una regex, como en Claude Code (`mcp__.*` casa con `mcp__github__x`).
# rc 0 = casa, 1 = no casa; cualquier otro (regex inválida) bloquea: nunca se salta mudo.
matches() {
    [[ "$1" == ".*" ]] && return 0
    local regex="^($1)$" rc=0
    [[ "$TOOL" =~ $regex ]] 2>/dev/null || rc=$?
    [[ "$rc" -le 1 ]] || block "matcher inválido en la tabla: $1"
    return "$rc"
}

# ── Despacha: primero los bloqueantes en orden de tabla, después los no bloqueantes ──
# Un mismo comando se ejecuta una vez por acción (Claude Code deduplica comandos idénticos).
declare -A DONE=()
for pass in yes no; do
    for i in "${!ROW_SPEC[@]}"; do
        [[ "${ROW_BLOCK[$i]}" == "$pass" ]] || continue
        matches "${ROW_MATCH[$i]}" || continue
        script_spec="${ROW_SPEC[$i]}"
        [[ -n "${DONE[$script_spec]:-}" ]] && continue
        DONE[$script_spec]=1

        read -r -a parts <<< "$script_spec"   # sin expansión de globs ni eval
        script="${parts[0]}"
        script_path="$REPO_ROOT/$script"
        if [[ ! -f "$script_path" ]]; then
            [[ "$pass" == "yes" ]] && block "hook registrado que falta: $script"
            echo "[dispatch-pretooluse] WARNING: hook no bloqueante ausente: $script" >&2
            continue
        fi

        exit_code=0
        # `timeout` es líder de su grupo de procesos (pgid = su pid). Su KILL final solo alcanza al
        # hook: si vence el tiempo, se mata el grupo entero para que ningún hijo que ignore TERM
        # quede vivo con la salida del despachador abierta (colgaría la acción).
        timeout -k "$HOOK_KILL_GRACE" "$HOOK_TIMEOUT" bash "$script_path" "${parts[@]:1}" < "$INPUT_FILE" &
        hook_pid=$!
        wait "$hook_pid" || exit_code=$?
        if [[ "$exit_code" -eq 124 || "$exit_code" -eq 137 ]]; then
            kill -KILL -- "-$hook_pid" 2>/dev/null
        fi
        [[ "$exit_code" -eq 0 ]] && continue

        if [[ "$pass" == "yes" ]]; then
            if [[ "$exit_code" -eq 2 ]]; then
                echo "[dispatch-pretooluse] bloqueado por $script" >&2
                exit 2
            fi
            [[ "$exit_code" -eq 124 || "$exit_code" -eq 137 ]] && block "tiempo agotado (${HOOK_TIMEOUT}s) en $script"
            block "$script salió con exit $exit_code (solo 0 o 2 son válidos en un hook bloqueante)"
        fi
        echo "[dispatch-pretooluse] WARNING: hook no bloqueante $script salió con exit $exit_code" >&2
    done
done

exit 0
