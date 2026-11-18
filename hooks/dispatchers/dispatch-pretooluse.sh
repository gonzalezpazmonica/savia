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
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$REPO_ROOT}"

# Motivo ambiguo = POLÍTICA (decisión de la operadora, SE-510 S0).
block() {
    echo "[dispatch-pretooluse] BLOQUEO (POLÍTICA): $1" >&2
    exit 2
}

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

# ── Despacha hooks cuyo matcher coincide con TOOL, en el orden de la tabla ────
while IFS=$'\t' read -r matcher script_spec mode blocking desc; do
    [[ -z "$matcher" ]] && continue
    [[ "$matcher" =~ ^[[:space:]]*# ]] && continue

    [[ -n "$script_spec" && ( "$mode" == "spawn" || "$mode" == "source" ) \
        && ( "$blocking" == "yes" || "$blocking" == "no" ) ]] \
        || block "fila mal formada en la tabla (matcher=$matcher)"

    if [[ "$matcher" != ".*" ]]; then
        regex="^(${matcher//\./\\.})$"
        [[ ! "$TOOL" =~ $regex ]] && continue
    fi

    script="${script_spec%% *}"
    script_args=""
    [[ "$script_spec" == *" "* ]] && script_args="${script_spec#* }"

    script_path="$REPO_ROOT/$script"
    if [[ ! -f "$script_path" ]]; then
        [[ "$blocking" == "yes" ]] && block "hook registrado que falta: $script"
        echo "[dispatch-pretooluse] WARNING: hook no bloqueante ausente: $script" >&2
        continue
    fi

    # ── Ejecuta el hook ───────────────────────────────────────────────────────
    exit_code=0
    if [[ "$mode" == "source" ]]; then
        (source "$script_path" <<< "$INPUT") && exit_code=$? || exit_code=$?
    else
        # shellcheck disable=SC2086 — script_args son literales de la tabla generada
        printf '%s' "$INPUT" | timeout "$HOOK_TIMEOUT" bash "$script_path" $script_args && exit_code=$? || exit_code=$?
    fi

    [[ "$exit_code" -eq 0 ]] && continue

    if [[ "$blocking" == "yes" ]]; then
        if [[ "$exit_code" -eq 2 ]]; then
            echo "[dispatch-pretooluse] bloqueado por $script" >&2
            exit 2
        fi
        if [[ "$exit_code" -eq 124 ]]; then
            block "tiempo agotado (${HOOK_TIMEOUT}s) en $script"
        fi
        block "$script salió con exit $exit_code (solo 0 o 2 son válidos en un hook bloqueante)"
    fi
    echo "[dispatch-pretooluse] WARNING: hook no bloqueante $script salió con exit $exit_code" >&2

done < "$ROUTING" || block "fallo leyendo la tabla de despacho"

exit 0
