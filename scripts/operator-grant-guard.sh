#!/usr/bin/env bash
set -uo pipefail
# operator-grant-guard.sh — PreToolUse: el grant de merge lo concede una persona (LAW-HUMAN-002)
# Ref: SE-343, SE-433 D7, patrón Yema F4. Registro: PreToolUse con matcher
# "Bash|Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob" en .claude/settings.json.
#
# 1. `operator-grant.sh grant --scope merge` nunca se permite en silencio:
#    - modos que no preguntan (bypassPermissions, dontAsk): deniega (exit 2);
#    - si no: deja un ticket de un solo uso (5 min) ligado a scope+contexto y
#      responde «ask», el diálogo nativo del arnés que el modelo no puede pulsar.
#      El script solo emite el grant si encuentra ese ticket (o una terminal).
# 2. Veta a las herramientas la clave HMAC y los tickets: rutas, carpetas que
#    los contienen y las variables que los redirigen.
#
# Límite: ve el texto de la orden, no lo que ejecuta un script escrito antes.
# Sin entrada evaluable: exit 2 (SE-453), nunca 0 sin evaluar.

INPUT=""
if [[ ! -t 0 ]]; then INPUT=$(timeout 3 cat 2>/dev/null) || true; fi
[[ -z "$INPUT" ]] && { echo "BLOQUEADO [operator-grant-guard]: sin entrada del hook" >&2; exit 2; }

export GUARD_KEY_FILE="${SAVIA_GRANT_KEY_FILE:-$HOME/.savia/grant-keys/operator-grant.key}"
export GUARD_TICKETS_DIR="${SAVIA_GRANT_TICKETS_DIR:-$HOME/.savia/grant-tickets}"

printf '%s' "$INPUT" | python3 -c '
import hashlib, json, os, shlex, sys, time
try:
    ev = json.load(sys.stdin)
except ValueError:
    print("BLOQUEADO [operator-grant-guard]: entrada no es JSON", file=sys.stderr); sys.exit(2)
tool = ev.get("tool_name", "")
ti = ev.get("tool_input") or {}
key_file = os.path.realpath(os.path.expanduser(os.environ["GUARD_KEY_FILE"]))
tickets = os.path.realpath(os.path.expanduser(os.environ["GUARD_TICKETS_DIR"]))
protected = [os.path.dirname(key_file), tickets]
markers = [os.path.basename(p) for p in protected] + [os.path.basename(key_file),
           "SAVIA_GRANT_KEY_FILE", "SAVIA_GRANT_TICKETS_DIR"]
VETO = "la clave de grants y los tickets de aprobación no son accesibles a las herramientas"

def deny(why):
    print("BLOQUEADO [operator-grant-guard]: " + why, file=sys.stderr); sys.exit(2)

def touches(path):
    if not isinstance(path, str) or not path:
        return False
    if any(m in path for m in markers):
        return True
    rp = os.path.realpath(os.path.expanduser(path))
    # La ruta protegida o una carpeta que la contenga (Grep/Glob la leerían entera).
    return any(rp == p or p.startswith(rp.rstrip("/") + "/") for p in protected)

if tool != "Bash":
    for f in ("file_path", "path", "notebook_path"):
        if touches(ti.get(f)):
            deny(VETO)
    if tool == "Glob" and touches(ti.get("pattern")):
        deny(VETO)
    sys.exit(0)

cmd = ti.get("command") or ""
if any(m in cmd for m in markers):
    deny(VETO)
if "operator-grant" not in cmd:
    sys.exit(0)

def merge_grant(cmd):
    """(es grant de merge, contexto; None si no se lee con certeza)."""
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()")
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        return True, None
    found, res = False, None
    for i, t in enumerate(toks):
        if "operator-grant" not in t or os.path.basename(t).startswith("operator-grant-guard"):
            continue
        seg = []
        for u in toks[i + 1:]:
            if u and all(c in ";&|()" for c in u):
                break
            seg.append(u)
        scope = ctx = None
        j = 0
        while j < len(seg):
            a = seg[j]
            if a in ("--scope", "--context") and j + 1 < len(seg):
                if a == "--scope":
                    scope = seg[j + 1]
                else:
                    ctx = seg[j + 1]
                j += 2
                continue
            if a.startswith("--scope="):
                scope = a.split("=", 1)[1]
            if a.startswith("--context="):
                ctx = a.split("=", 1)[1]
            j += 1
        if "grant" in seg and scope in ("merge", None):
            if found:
                return True, None   # dos emisiones en una orden: sin ticket
            found, res = True, (ctx if scope == "merge" else None)
    if found:
        return True, res
    # Mención sin invocación legible (eval, base64, variables): se pregunta sin ticket.
    return ("grant" in cmd.replace("=", " ").split() and "merge" in cmd), None

is_merge, ctx = merge_grant(cmd)
if not is_merge:
    sys.exit(0)
mode = ev.get("permission_mode", "")
if mode in ("bypassPermissions", "dontAsk"):
    deny("el grant de merge lo concede una persona y el modo " + mode + " no pregunta. Cambia a modo normal o usa tu terminal.")
if ctx:
    h = hashlib.sha256(("merge\n" + ctx).encode()).hexdigest()[:16]
    os.makedirs(tickets, mode=0o700, exist_ok=True)
    with open(os.path.join(tickets, "merge-" + h + ".json"), "w") as f:
        json.dump({"ts": int(time.time())}, f)
reason = "Grant de merge (LAW-HUMAN-002): solo la operadora lo concede. Contexto: " + (ctx or "(no legible: el grant se rechazará)")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
      "permissionDecision": "ask", "permissionDecisionReason": reason}}, ensure_ascii=False))
'
