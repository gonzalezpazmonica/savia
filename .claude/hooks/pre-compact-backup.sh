#!/bin/bash
set -uo pipefail
# pre-compact-backup.sh — SPEC-026 + SPEC-016 + SE-529 S1: guarda contexto antes de /compact.
# La entrada (stdin) es metadatos; la conversación está en `transcript_path`. Se abre solo si es seguro
# (realpath dentro de ~/.claude/projects, fichero regular, dueño = quien ejecuta), se lee como máximo el
# final (S0.5: 589824 B), solo turnos de texto de persona/asistente, redact_private (S5) y extracción.
# Nunca bloquea la compactación (exit 0 siempre). Dice la verdad: si no pudo leer o guardar, lo dice.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh" 2>/dev/null || true
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${SAVIA_WORKSPACE_DIR:-$(pwd)}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORE_SCRIPT="$SCRIPT_DIR/../../scripts/memory-store.sh"
MAX_READ_BYTES=589824

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROJ_SLUG=$(echo "$PROJ_DIR" | sed 's|[/:\\]|-|g; s|^-||')
SESSION_HOT_DIR="$HOME/.claude/projects/$PROJ_SLUG/memory"
SESSION_HOT="$SESSION_HOT_DIR/session-hot.md"

INPUT=$(head -c 1048576 2>/dev/null | tr -d '\000' || true)

say_unread() {
    echo "No he podido leer la conversación antes de compactar: $1. Solo uso lo que ya estaba guardado."
}

detect_project() {
    local p=""
    if [[ -f "CLAUDE.local.md" ]]; then
        p=$(grep -i "^project:" "CLAUDE.local.md" | head -1 | cut -d':' -f2- | xargs || true)
    elif git rev-parse --git-dir >/dev/null 2>&1; then
        p=$(git config --get remote.origin.url 2>/dev/null | sed 's|/*$||; s|.*[/:]||; s|\.git$||' || true)
    else
        p=$(basename "$(pwd)")
    fi
    case "$p" in ""|"/"|"null") p="" ;; esac
    printf '%s' "$p"
}

PYCODE=$(cat <<'PY'
import json, os, re, stat, subprocess, sys

STORE_SCRIPT, MAX_BYTES = sys.argv[1], int(sys.argv[2])
SEP = "\n\x1e\n"


def out(k, v=""):
    v = re.sub(r"[\t\r\n\x1e]+", " ", str(v)).strip()
    sys.stdout.write("%s\t%s\n" % (k, v))


def unread(reason):
    out("STATUS", "unread")
    out("REASON", reason)
    sys.exit(0)


raw = sys.stdin.read()
try:
    payload = json.loads(raw)
except Exception:
    payload = None
if not isinstance(payload, dict):
    unread("la entrada del hook no es un JSON de metadatos")
tp = payload.get("transcript_path")
if not isinstance(tp, str) or not tp:
    unread("la carga no trae transcript_path (el frontend no entrega la conversación)")
if isinstance(payload.get("cwd"), str):
    out("CWD", payload["cwd"])

base = os.path.realpath(os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or
                                     os.path.join(os.path.expanduser("~"), ".claude"), "projects"))
real = os.path.realpath(tp)
if os.path.commonpath([base, real]) != base:
    unread("la ruta está fuera de la carpeta de datos del frontend")
try:
    fd = os.open(real, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
except FileNotFoundError:
    unread("el fichero de la conversación no existe")
except OSError:
    unread("el fichero de la conversación no se puede abrir")
try:
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode):
        unread("la ruta no es un fichero regular")
    if st.st_uid != os.getuid():
        unread("el fichero no es de la persona que ejecuta el hook")
    size = st.st_size
    start = max(0, size - MAX_BYTES)
    os.lseek(fd, start, os.SEEK_SET)
    data = b""
    while len(data) < size - start:
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        data += chunk
except OSError:
    unread("el fichero de la conversación no se puede leer")
finally:
    try:
        os.close(fd)
    except OSError:
        pass

truncated = start > 0
lines = data.split(b"\n")
if truncated:
    lines = lines[1:]

TAG = re.compile(r"<system-reminder>.*?</system-reminder>", re.S | re.I)
turns = []
for ln in lines:
    ln = ln.strip()
    if not ln:
        continue
    try:
        o = json.loads(ln)
    except Exception:
        continue
    if not isinstance(o, dict) or o.get("type") not in ("user", "assistant"):
        continue
    if o.get("isCompactSummary") or o.get("isMeta") or o.get("isSidechain"):
        continue
    msg = o.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        text = "\n".join(b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") == "text"
                         and isinstance(b.get("text"), str))
    else:
        continue
    text = TAG.sub("", text).strip()
    if text and not text.startswith("<local-command"):
        turns.append((o["type"], text))

out("TRUNCATED", "1" if truncated else "0")
out("TURNS", len(turns))
if not turns:
    out("STATUS", "ok")
    sys.exit(0)

if not os.path.isfile(STORE_SCRIPT):
    unread("no hay forma de redactar bloques privados (falta memory-store.sh)")
try:
    r = subprocess.run(["bash", "-c", 'source "$1" >/dev/null 2>&1 && redact_private', "_", STORE_SCRIPT],
                       input=SEP.join(t for _, t in turns).encode("utf-8"),
                       capture_output=True, timeout=6)
except Exception:
    unread("falló la redacción de bloques privados")
if r.returncode != 0:
    unread("falló la redacción de bloques privados")
red = r.stdout.decode("utf-8", "replace").split(SEP)
if len(red) != len(turns):
    unread("la redacción de bloques privados no conservó los turnos")
pairs = [(turns[i][0], red[i]) for i in range(len(turns))]

PAT = {
    "D": (re.compile(r"(decid|chose|will use|switched to|went with|vamos con|elegimos|usaremos)[^\n\"]{5,80}", re.I), 5, ("user", "assistant")),
    "C": (re.compile(r"(no[, ]+not that|wrong|cambia|change to|eso no|incorrecto)[^\n\"]{5,80}", re.I), 3, ("user",)),
    "T": (re.compile(r"(working on|implementando|step [0-9]|slice [0-9]|fase [0-9])[^\n\"]{5,60}", re.I), 2, ("user", "assistant")),
    "P": (re.compile(r"(always|siempre|never|nunca|convention|patron|regla)[^\n\"]{10,80}", re.I), 3, ("user",)),
}
for key, (rx, keep, roles) in PAT.items():
    seen, items = set(), []
    for role, text in pairs:
        if role not in roles:
            continue
        for m in rx.finditer(text):
            s = " ".join(m.group(0).split())
            if s.lower() not in seen:
                seen.add(s.lower())
                items.append(s)
    for s in items[-keep:]:
        out(key, s)

files, seen = [], set()
FRX = re.compile(r"[a-zA-Z0-9/_-]+\.(?:ts|js|py|sh|cs|md|json|yaml|yml)\b")
for _, text in pairs:
    for m in FRX.finditer(text):
        if m.group(0) not in seen:
            seen.add(m.group(0))
            files.append(m.group(0))
for f in files[-10:]:
    out("F", f)
out("STATUS", "ok")
PY
)

STATUS="unread"; REASON="no se pudo ejecutar el extractor"; TRUNC=0; CWD_IN=""
declare -a D=() C=() T=() P=() F=()
if command -v python3 >/dev/null 2>&1; then
    RESULT=$(printf '%s' "$INPUT" | timeout 8 python3 -I -c "$PYCODE" "$STORE_SCRIPT" "$MAX_READ_BYTES" 2>/dev/null)
    rc=$?
    if [[ $rc -eq 124 ]]; then
        STATUS="unread"; REASON="se agotó el tiempo al leer la conversación"
    elif [[ $rc -eq 0 && -n "$RESULT" ]]; then
        STATUS=""; REASON=""
        while IFS=$'\t' read -r k v; do
            case "$k" in
                STATUS) STATUS="$v" ;; REASON) REASON="$v" ;; TRUNCATED) TRUNC="$v" ;;
                CWD) CWD_IN="$v" ;;
                D) D+=("$v") ;; C) C+=("$v") ;; T) T+=("$v") ;; P) P+=("$v") ;; F) F+=("$v") ;;
            esac
        done <<< "$RESULT"
        [[ -z "$STATUS" ]] && { STATUS="unread"; REASON="el extractor no devolvió resultado"; }
    fi
else
    REASON="falta python3"
fi

join_items() { local IFS='; '; printf '%s' "$*"; }

N=0; WROTE_B=0; WROTE_C=0
if [[ "$STATUS" == "ok" ]]; then
    decisions=$(join_items "${D[@]+"${D[@]}"}")
    corrections=$(join_items "${C[@]+"${C[@]}"}")
    task_state=$(join_items "${T[@]+"${T[@]}"}")
    patterns=$(join_items "${P[@]+"${P[@]}"}")
    files=$(IFS=','; printf '%s' "${F[*]+"${F[*]}"}")
    nB=$(( ${#D[@]} + ${#C[@]} + ${#T[@]} )); nP=${#P[@]}

    tier_b=""
    [[ -n "$decisions" ]] && tier_b="Decisions: $decisions"
    [[ -n "$corrections" ]] && tier_b="${tier_b:+$tier_b | }Corrections: $corrections"
    [[ -n "$task_state" ]] && tier_b="${tier_b:+$tier_b | }Task: $task_state"

    if [[ -n "$tier_b" ]]; then
        if mkdir -p "$SESSION_HOT_DIR" 2>/dev/null && {
            echo "## Session Context ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
            echo "$tier_b"
            [[ -n "$files" ]] && echo "Files: $files"
            echo ""
        } >> "$SESSION_HOT" 2>/dev/null; then
            WROTE_B=1
            if [[ $(wc -l < "$SESSION_HOT") -gt 80 ]]; then
                tail -40 "$SESSION_HOT" > "$SESSION_HOT.tmp" && mv "$SESSION_HOT.tmp" "$SESSION_HOT"
            fi
        fi
    fi

    tier_c=""
    [[ -n "$patterns" ]] && tier_c="Patterns: $patterns"
    [[ -n "$decisions" ]] && tier_c="${tier_c:+$tier_c | }Decisions: $decisions"
    if [[ -n "$tier_c" && -f "$STORE_SCRIPT" ]]; then
        proj=$( [[ -n "$CWD_IN" && -d "$CWD_IN" ]] && cd "$CWD_IN" 2>/dev/null; detect_project )
        if timeout 6 bash "$STORE_SCRIPT" session-summary \
            --accomplished "$tier_c" \
            ${files:+--files "$files"} \
            ${proj:+--project "$proj"} \
            --source "tool:pre-compact-hook" --origin untrusted \
            --goal "pre-compact auto-save" >/dev/null 2>&1; then
            WROTE_C=1
        fi
    fi

    if [[ $WROTE_B -eq 1 ]]; then N=$((N + nB)); [[ $WROTE_C -eq 1 ]] && N=$((N + nP)); fi
    if [[ $WROTE_B -eq 0 && $WROTE_C -eq 1 ]]; then N=$((N + ${#D[@]} + nP)); fi

    donde=""
    [[ $WROTE_B -eq 1 ]] && donde="session-hot"
    [[ $WROTE_C -eq 1 ]] && donde="${donde:+$donde + }memory-store"
    found=$((nB + nP))
    if [[ $N -gt 0 ]]; then
        msg="Pre-compact: $N elementos guardados ($donde)."
        [[ "$TRUNC" == "1" ]] && msg="$msg Solo se leyeron los últimos $MAX_READ_BYTES bytes de la conversación."
        [[ -n "$tier_c" && $WROTE_C -eq 0 ]] && msg="$msg Memoria permanente: no confirmado."
        echo "$msg"
    elif [[ $found -gt 0 ]]; then
        echo "Pre-compact: no confirmado. Se extrajeron $found elementos pero no se pudo escribir en session-hot ni en memory-store; comprueba antes de reintentar."
    else
        say_unread "no había decisiones, correcciones ni estado de tarea en la parte leída"
    fi
else
    say_unread "$REASON"
fi

COMPACT_SCRIPT="$SCRIPT_DIR/../../scripts/semantic-compact.sh"
if [[ -f "$COMPACT_SCRIPT" ]]; then
    bash "$COMPACT_SCRIPT" 2>/dev/null || true
fi

exit 0
