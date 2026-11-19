#!/usr/bin/env bash
# dispatch-pretooluse.sh — SE-253 Slice 4, contrato de fallo cerrado de SE-510 D3
set -uo pipefail
# Único punto de entrada PreToolUse. Lee routing-pretooluse.tsv (generada desde settings.json
# por scripts/dispatch-table.py) y despacha.
#
# Input  : JSON de Claude Code / OpenCode en stdin (se parsea una vez; cada hook lo recibe por stdin)
# Exit   : 0 (permitir), 2 (bloquear)
# Stdout : como mucho UN objeto JSON con las decisiones fusionadas de los hooks bloqueantes
#          (ask/allow, updatedInput, additionalContext, systemMessage), o nada.
#
# FALLO CERRADO: tabla ausente, ilegible, vacía o truncada, JSON roto, herramienta desconocida,
# fila mal formada, ruta de hook fuera del repo, hook ausente, exit distinto de 0/2 en un hook
# bloqueante, tiempo agotado, decisión `deny`/`block`/`continue:false` en stdout, stdout JSON
# ilegible o decisiones incompatibles, o fallo del propio despachador => exit 2 con el motivo.
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

# Cualquier salida distinta de 0 y 2 (error del propio bash con `-u`, señal, fallo no previsto)
# se normaliza a 2: Claude Code trata el exit 1 como no bloqueante y eso sería fallar abierto.
WORK="" INPUT_FILE="" HOOK_OUT="" DECISIONS=""
on_exit() {
    local rc=$?
    if [[ -n "$WORK" ]]; then
        rm -f -- "$INPUT_FILE" "$HOOK_OUT" "$DECISIONS"
        rmdir -- "$WORK" 2>/dev/null
    fi
    # Si al despachador lo matan con un hook en marcha, el grupo del hook no queda huérfano.
    [[ -n "${hook_pid:-}" ]] && kill -KILL -- "-$hook_pid" 2>/dev/null
    if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
        echo "[dispatch-pretooluse] BLOQUEO (POLÍTICA): fallo interno del despachador (rc $rc)" >&2
        exit 2
    fi
    exit "$rc"
}
trap on_exit EXIT
# Muerto por señal, bash conservaría el 128+N aunque el trap EXIT haga `exit 2`: se sale a mano.
trap 'exit 143' TERM; trap 'exit 130' INT; trap 'exit 129' HUP
# `declare -A` necesita bash >= 4; en bash 3, DONE[...] sería un índice aritmético.
[[ "${BASH_VERSINFO[0]:-0}" -ge 4 ]] || block "bash ${BASH_VERSION:-?} no soportado (hace falta >= 4)"

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
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-pretooluse.XXXXXX") || block "no se pudo crear el directorio de trabajo"
INPUT_FILE="$WORK/input" HOOK_OUT="$WORK/out" DECISIONS="$WORK/decisions.jsonl"
printf '%s' "$INPUT" > "$INPUT_FILE" || block "no se pudo escribir el fichero de entrada"
: > "$DECISIONS" || block "no se pudo crear el registro de decisiones"

# ── Decisiones por stdout (exit 0 + JSON), como las lee Claude Code ───────────
# Un hook puede bloquear con exit 0 y `permissionDecision:"deny"`, `decision:"block"` o
# `continue:false` (p. ej. mcp-effect-guard, block-commit-to-main). Si el despachador solo mirase el
# código de salida, ese bloqueo se perdería. exit 0 = sin decisión o decisión registrada;
# 10 = bloqueo (motivo en stdout); 11 = stdout JSON ilegible o decisión desconocida.
PARSE_PY='
import json, sys
out, acc, script = sys.argv[1:4]
text = open(out, encoding="utf-8", errors="replace").read().strip()
if not text:
    sys.exit(0)
if not text.startswith("{"):
    sys.stderr.write(text + "\n")   # texto libre: Claude Code no lo lee como decisión
    sys.exit(0)
try:
    d = json.loads(text)
except ValueError as exc:
    print(f"stdout JSON ilegible ({exc})"); sys.exit(11)
if not isinstance(d, dict):
    print("stdout JSON no es un objeto"); sys.exit(11)
hso = d.get("hookSpecificOutput") or {}
if not isinstance(hso, dict):
    print("hookSpecificOutput no es un objeto"); sys.exit(11)
pd, legacy = hso.get("permissionDecision"), d.get("decision")
reason = hso.get("permissionDecisionReason") or d.get("reason") or d.get("stopReason") or "(sin motivo)"
if pd == "deny" or legacy == "block" or d.get("continue") is False:
    print(reason); sys.exit(10)
if pd not in (None, "ask", "allow") or legacy not in (None, "approve"):
    print(f"decisión desconocida: permissionDecision={pd!r} decision={legacy!r}"); sys.exit(11)
rec = {"script": script}
if pd or legacy:
    rec["decision"] = pd or "allow"
    rec["reason"] = hso.get("permissionDecisionReason") or d.get("reason")
for k in ("updatedInput", "additionalContext"):
    if k in hso:
        rec[k] = hso[k]
if d.get("systemMessage"):
    rec["systemMessage"] = d["systemMessage"]
with open(acc, "a", encoding="utf-8") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
'
# Fusión: ask > allow (deny ya cortó); dos updatedInput distintos son incompatibles => exit 11.
MERGE_PY='
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
if not recs:
    sys.exit(0)
hso = {"hookEventName": "PreToolUse"}
decs = [r for r in recs if r.get("decision")]
for want in ("ask", "allow"):
    hit = [r for r in decs if r["decision"] == want]
    if hit:
        hso["permissionDecision"] = want
        reasons = [r["reason"] for r in hit if r.get("reason")]
        if reasons:
            hso["permissionDecisionReason"] = " | ".join(reasons)
        break
upd = [r for r in recs if "updatedInput" in r]
if len({json.dumps(r["updatedInput"], sort_keys=True) for r in upd}) > 1:
    print("updatedInput incompatibles de " + ", ".join(r["script"] for r in upd)); sys.exit(11)
if upd:
    hso["updatedInput"] = upd[0]["updatedInput"]
ctx = [str(r["additionalContext"]) for r in recs if r.get("additionalContext")]
if ctx:
    hso["additionalContext"] = "\n".join(ctx)
msgs = [str(r["systemMessage"]) for r in recs if r.get("systemMessage")]
out = {"hookSpecificOutput": hso}
if msgs:
    out["systemMessage"] = "\n".join(msgs)
if len(hso) > 1 or msgs:
    print(json.dumps(out, ensure_ascii=False))
'

# ── Lee y valida la tabla entera antes de ejecutar nada ───────────────────────
# `|| [[ -n "$matcher" ]]`: la última fila cuenta aunque no acabe en salto de línea.
# La línea de control `# filas=N` (la última que escribe el generador) detecta una tabla vacía,
# truncada o con filas añadidas a mano: sin ella, o si N no coincide, se bloquea. N es decimal
# canónico de hasta 6 cifras: `08` no se lee como octal y un número enorme no desborda hasta
# coincidir con el recuento. Una línea `# filas=` con otra forma es un control inválido.
ROW_MATCH=() ROW_SPEC=() ROW_BLOCK=() EXPECTED_ROWS=""
while IFS=$'\t' read -r matcher script_spec mode blocking desc || [[ -n "$matcher" ]]; do
    [[ -z "$matcher" ]] && continue
    if [[ "$matcher" == "# filas="* ]]; then
        [[ "$matcher" =~ ^#\ filas=(0|[1-9][0-9]{0,5})$ ]] \
            || block "línea de control inválida en la tabla: $matcher"
        [[ -z "$EXPECTED_ROWS" ]] || block "línea de control '# filas=' repetida en la tabla"
        EXPECTED_ROWS="${BASH_REMATCH[1]}"; continue
    fi
    [[ "$matcher" =~ ^[[:space:]]*# ]] && continue
    [[ -n "$script_spec" && ( "$mode" == "spawn" || "$mode" == "source" ) \
        && ( "$blocking" == "yes" || "$blocking" == "no" ) ]] \
        || block "fila mal formada en la tabla (matcher=$matcher)"
    # `source` no se puede acotar con timeout y un `exit` interno escapa al contrato.
    [[ "$mode" == "spawn" ]] || block "modo $mode no soportado (solo spawn): $script_spec"
    # Defensa en profundidad (el generador ya lo rechaza): el hook vive dentro del repo.
    first="${script_spec%% *}"
    [[ "$first" != /* && "/$first/" != */../* ]] || block "ruta de hook fuera del repo: $first"
    ROW_MATCH+=("$matcher"); ROW_SPEC+=("$script_spec"); ROW_BLOCK+=("$blocking")
done < "$ROUTING" || block "fallo leyendo la tabla de despacho"
[[ -n "$EXPECTED_ROWS" ]] || block "tabla sin línea de control '# filas=N' (truncada o escrita a mano)"
[[ "${#ROW_SPEC[@]}" -gt 0 ]] || block "tabla de despacho sin filas"
[[ "$EXPECTED_ROWS" -eq "${#ROW_SPEC[@]}" ]] \
    || block "la tabla tiene ${#ROW_SPEC[@]} filas y su control dice $EXPECTED_ROWS (truncada o editada)"

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
        # stdout del bloqueante: a un fichero, para leer su decisión. El de un no bloqueante (async
        # en Claude Code) no decide nada: se descarta para no mezclarlo con el JSON fusionado.
        out_target="$HOOK_OUT"; [[ "$pass" == "yes" ]] || out_target=/dev/null
        timeout -k "$HOOK_KILL_GRACE" "$HOOK_TIMEOUT" bash "$script_path" "${parts[@]:1}" \
            < "$INPUT_FILE" > "$out_target" &
        hook_pid=$!
        wait "$hook_pid" || exit_code=$?
        if [[ "$exit_code" -eq 124 || "$exit_code" -eq 137 ]]; then
            kill -KILL -- "-$hook_pid" 2>/dev/null
        fi
        hook_pid=""   # el pid puede reutilizarse: on_exit solo mata un grupo aún en marcha
        if [[ "$exit_code" -eq 0 ]]; then
            [[ "$pass" == "yes" && -s "$HOOK_OUT" ]] || continue   # sin stdout: sin decisión
            parse_rc=0
            verdict=$(python3 -c "$PARSE_PY" "$HOOK_OUT" "$DECISIONS" "$script") || parse_rc=$?
            case "$parse_rc" in
                0) continue ;;
                10) echo "[dispatch-pretooluse] bloqueado por $script: $verdict" >&2; exit 2 ;;
                *) block "$script: ${verdict:-no se pudo leer su stdout (rc $parse_rc)}" ;;
            esac
        fi

        if [[ "$pass" == "yes" ]]; then
            if [[ "$exit_code" -eq 2 ]]; then
                echo "[dispatch-pretooluse] bloqueado por $script" >&2
                exit 2
            fi
            [[ "$exit_code" -eq 124 || "$exit_code" -eq 137 ]] \
                && block "tiempo agotado (${HOOK_TIMEOUT}s) o señal KILL en $script (exit $exit_code)"
            block "$script salió con exit $exit_code (solo 0 o 2 son válidos en un hook bloqueante)"
        fi
        echo "[dispatch-pretooluse] WARNING: hook no bloqueante $script salió con exit $exit_code" >&2
    done
done

# Un único JSON con lo que decidieron los bloqueantes (o nada). Incompatibles => bloqueo.
merged_rc=0 merged=""
[[ -s "$DECISIONS" ]] && { merged=$(python3 -c "$MERGE_PY" "$DECISIONS") || merged_rc=$?; }
[[ "$merged_rc" -eq 0 ]] || block "decisiones de hooks incompatibles: ${merged:-rc $merged_rc}"
[[ -z "$merged" ]] || printf '%s\n' "$merged"
exit 0
