#!/bin/bash
# post-compaction.sh - Reinyección de memoria tras compactar (SE-529 S2).
# Eventos PostCompact / SessionStart(compact): lo que imprime llega al modelo.
#
# Un único bloque acotado:
#   Memoria tras compactar (proyecto: <nombre>)
#   Fijado: <titular> · …
#   Reciente: <titular> · …
#   Esta sesión: <lo extraído antes de compactar>
#   (y N más; consulta con memory-store recall)
#
# - Solo entradas del proyecto activo; las de otro proyecto nunca. Sin proyecto
#   determinable no se inyecta nada del almacén (sí session-hot.md).
# - Entradas sin proyecto ("null"): solo si son fijadas.
# - Fijadas primero (importance_tier A; si A supera el 30 % del almacén, umbral más
#   estricto: A de tipo feedback/correction, sin campo nuevo — Q1), luego las recientes.
# - Tope en bytes: SAVIA_REINJECT_MAX_BYTES (por defecto 4096, S0.5).
# - session-hot.md se vacía SOLO después de emitir el bloque y solo si la emisión terminó bien.
# Nunca bloquea: siempre exit 0.

set -uo pipefail

MAX_BYTES="${SAVIA_REINJECT_MAX_BYTES:-4096}"
[[ "$MAX_BYTES" =~ ^[0-9]+$ ]] || MAX_BYTES=4096

detect_project() {
    local p=""
    if [[ -f "CLAUDE.local.md" ]]; then
        p=$(grep -i "^project:" "CLAUDE.local.md" | head -1 | cut -d':' -f2- | xargs || true)
    elif git rev-parse --git-dir > /dev/null 2>&1; then
        p=$(git config --get remote.origin.url 2>/dev/null | sed 's|/*$||; s|.*[/:]||; s|\.git$||' || true)
    else
        p=$(basename "$(pwd)")
    fi
    case "$p" in ""|"/"|"null") p="" ;; esac
    printf '%s' "$p"
}

store_file="${PROJECT_ROOT:-.}/output/.memory-store.jsonl"

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJ_SLUG=$(echo "$PROJ_DIR" | sed 's|[/:\\]|-|g; s|^-||')
SESSION_HOT="$HOME/.claude/projects/$PROJ_SLUG/memory/session-hot.md"
[[ -f "$SESSION_HOT" && -s "$SESSION_HOT" ]] || SESSION_HOT=""

project=$(detect_project)

command -v python3 >/dev/null 2>&1 || exit 0

block=$(python3 -I - "$store_file" "$project" "$MAX_BYTES" "$SESSION_HOT" <<'PY'
import datetime
import json
import os
import sys

store, project, cap, hot = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
SEP = " · "
TITLE_MAX = 80
SESSION_MAX = 1200


def nbytes(s):
    return len(s.encode("utf-8"))


def clip(s, n):
    s = " ".join(s.split())
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def load_store():
    rows = []
    if not store or not os.path.isfile(store):
        return rows
    now = datetime.datetime.now(datetime.timezone.utc)
    with open(store, "rb") as fh:
        for raw in fh:
            try:
                o = json.loads(raw.decode("utf-8", "replace"))
            except Exception:
                continue
            if not isinstance(o, dict) or not str(o.get("title", "")).strip():
                continue
            exp = o.get("expires_at")
            if exp:
                try:
                    d = datetime.datetime.fromisoformat(str(exp).replace("Z", "+00:00"))
                    if d.tzinfo is None:
                        d = d.replace(tzinfo=datetime.timezone.utc)
                    if d < now:
                        continue
                except Exception:
                    pass
            rows.append(o)
    return rows


def session_line():
    if not hot:
        return ""
    try:
        with open(hot, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return ""
    keep = [x.strip() for x in lines
            if x.strip() and not x.startswith("## ") and not x.startswith("Files:")]
    if not keep:
        return ""
    txt = SEP.join(x.replace(" | ", SEP) for x in keep[-3:])
    return "Esta sesión: " + clip(txt, SESSION_MAX)


def emit(lines):
    text = "\n".join(lines)
    if nbytes(text) <= cap:
        sys.stdout.write(text)


sess = session_line()

if not project:
    lines = ["Memoria tras compactar (proyecto: no determinado)",
             "No he podido determinar el proyecto: no reinyecto memoria del almacén."]
    if sess:
        lines.append(sess)
    emit(lines)
    sys.exit(0)

rows = load_store()
# Fijada: tier A; si A pasa del 30 % del almacén, A de tipo feedback/correction.
n_a = sum(1 for r in rows if r.get("importance_tier") == "A")
strict = bool(rows) and n_a * 100 > 30 * len(rows)


def pinned(r):
    if r.get("importance_tier") != "A":
        return False
    return r.get("type") in ("feedback", "correction") if strict else True


def no_project(r):
    return r.get("project") in (None, "null", "")


eligible = [r for r in rows if r.get("project") == project or (no_project(r) and pinned(r))]
eligible.sort(key=lambda r: str(r.get("ts", "")), reverse=True)
queue = [("Fijado: ", r) for r in eligible if pinned(r)] + \
        [("Reciente: ", r) for r in eligible if not pinned(r)]

if not queue and not sess:
    sys.exit(0)

head = "Memoria tras compactar (proyecto: %s)" % clip(project, 60)


def render(shown):
    lines = [head]
    for label in ("Fijado: ", "Reciente: "):
        ts = [clip(str(r.get("title", "")), TITLE_MAX) for lb, r in shown if lb == label]
        if ts:
            lines.append(label + SEP.join(ts))
    if sess:
        lines.append(sess)
    rest = len(queue) - len(shown)
    if rest > 0:
        lines.append("(y %d más; consulta con memory-store recall)" % rest)
    return lines


shown = []
if nbytes("\n".join(render(queue))) <= cap:
    shown = list(queue)  # todo cabe y entonces no hace falta la línea «y N más»
else:
    for item in queue:
        if nbytes("\n".join(render(shown + [item]))) > cap:
            break  # orden estricto: lo que no cabe corta, no se salta a una menos importante
        shown.append(item)
emit(render(shown))
PY
)
py_rc=$?

if [[ $py_rc -ne 0 || -z "$block" ]]; then
    exit 0   # nada que emitir (o fallo del ayudante): session-hot.md no se vacía
fi

if printf '%s\n' "$block"; then
    # Emitido bien: ahora sí se consume session-hot.md.
    [[ -n "$SESSION_HOT" ]] && : > "$SESSION_HOT"
fi
exit 0
