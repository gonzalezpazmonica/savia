#!/usr/bin/env bash
# context-fixed-measure.sh — SE-511 S1: mide el contexto fijo que viaja en cada turno.
#
# Modos (uno por ejecución):
#   --versioned   CLAUDE.md + @imports recursivos versionados. Idéntico en CI y en cualquier máquina.
#   --hooks       additionalContext/stdout de los hooks de SessionStart y UserPromptSubmit,
#                 ejecutados con la fixture tests/fixtures/context-fixed/turn.json, HOME vacío,
#                 entorno mínimo y reloj fijo. Se corre dos veces; si difiere, sale con error.
#   --local       versionado + ficheros locales gitignored (perfil activo, memoria externa).
#                 Solo cifras por pieza: ni rutas ni contenido. Aviso (sin gate) por encima de 6000.
# Opciones:
#   --entry claude|opencode   punto de entrada (opencode suma .opencode/CLAUDE.md). Por defecto claude.
#   --check       compara con .ci-baseline/context-fixed-*.count; falla (exit 1) si la cifra sube.
#   --json        salida JSON.
#
# Método de tokens: caracteres / 4 (el de scripts/token-estimator.sh), entero hacia abajo, sobre el total.
# Fail-closed: un @import inexistente (y no gitignored), un ciclo, un fichero ilegible o un hook no
# determinista salen con exit 1; nunca se imprime un total parcial como válido.
#
# Env: CONTEXT_FIXED_ROOT (raíz a medir), CI_BASELINE_DIR (baselines), CONTEXT_FIXED_FIXTURE.
# Exit: 0 OK · 1 fallo de medición o regresión del trinquete · 2 uso.
set -uo pipefail

ROOT="${CONTEXT_FIXED_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASELINE_DIR="${CI_BASELINE_DIR:-$ROOT/.ci-baseline}"
FIXTURE="${CONTEXT_FIXED_FIXTURE:-$ROOT/tests/fixtures/context-fixed/turn.json}"

MODE=""; ENTRY="claude"; CHECK=0; JSON=0
usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --versioned|--hooks|--local) [[ -n "$MODE" ]] && { echo "ERROR: un solo modo por ejecución" >&2; exit 2; }; MODE="${1#--}"; shift ;;
    --entry) ENTRY="${2:-}"; [[ "$ENTRY" == claude || "$ENTRY" == opencode ]] || { echo "ERROR: --entry claude|opencode" >&2; exit 2; }; shift 2 ;;
    --check) CHECK=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: opción desconocida: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$MODE" ]] || { echo "ERROR: falta modo (--versioned|--hooks|--local)" >&2; usage >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 no disponible" >&2; exit 1; }

export ROOT BASELINE_DIR FIXTURE MODE ENTRY CHECK JSON
exec python3 -I - <<'PY'
import json, os, re, subprocess, sys, tempfile

ROOT = os.environ["ROOT"]; BASE = os.environ["BASELINE_DIR"]; FIX = os.environ["FIXTURE"]
MODE = os.environ["MODE"]; ENTRY = os.environ["ENTRY"]; CHECK = os.environ["CHECK"] == "1"
AS_JSON = os.environ["JSON"] == "1"
LOCAL_WARN = 6000

def die(msg):
    print("ERROR: " + msg, file=sys.stderr); sys.exit(1)

def tok(chars): return chars // 4

def is_ignored(rel):
    r = subprocess.run(["git", "-C", ROOT, "check-ignore", "-q", "--", rel],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode == 0

# `@ruta` fuera de bloques de código y de código en línea; exige `/` o extensión para no confundir
# con prosa como «@imports».
IMPORT = re.compile(r'(?:(?<=\s)|^)@([\w./~-]+)')
def imports_of(text):
    out, fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence; continue
        if fence: continue
        line = re.sub(r'`[^`]*`', '', line)
        for m in IMPORT.finditer(line):
            p = m.group(1).rstrip(".,;:")
            if "/" in p or re.search(r'\.\w{1,5}$', p): out.append(p)
    return out

def read(path):
    try:
        with open(path, "rb") as f: raw = f.read()
        return raw, raw.decode("utf-8")
    except (OSError, UnicodeDecodeError) as e:
        die("fichero ilegible: %s (%s)" % (os.path.relpath(path, ROOT), type(e).__name__))

def resolve(entry_rel):
    """Devuelve (versionadas, locales_presentes, locales_ausentes). Ciclo o import roto -> die()."""
    versioned, local, absent, seen = [], [], 0, set()
    def walk(rel, stack):
        nonlocal absent
        path = os.path.normpath(os.path.join(ROOT, rel))
        real = os.path.realpath(path)
        if real in stack:
            die("ciclo de @imports: " + " -> ".join(os.path.relpath(s, ROOT) for s in stack + [real]))
        if not os.path.exists(path):
            if is_ignored(rel): absent += 1; return
            die("@import a fichero inexistente: " + rel)
        if real in seen: return
        seen.add(real)
        raw, text = read(path)
        (local if is_ignored(rel) else versioned).append((rel, len(raw), len(text)))
        for imp in imports_of(text):
            walk(os.path.normpath(imp), stack + [real])
    walk(entry_rel, [])
    return versioned, local, absent

def entries():
    if ENTRY == "claude": return ["CLAUDE.md"]
    return [".opencode/CLAUDE.md", "CLAUDE.md"]

def measure_files():
    v, l, a = [], [], 0
    seen = set()
    for e in entries():
        if not os.path.exists(os.path.join(ROOT, e)): die("entrada ausente: " + e)
        vv, ll, aa = resolve(e)
        for x in vv:
            if x[0] not in seen: seen.add(x[0]); v.append(x)
        for x in ll:
            if x[0] not in seen: seen.add(x[0]); l.append(x)
        a += aa
    return v, l, a

# --- hooks -----------------------------------------------------------------
# Excluidos con motivo: escriben en el repo (no medibles sin efectos).
EXCLUDED = ("windows-links.sh",)
def hook_commands():
    try:
        with open(os.path.join(ROOT, ".claude/settings.json"), encoding="utf-8") as f: s = json.load(f)
        res = []
        for ev in ("SessionStart", "UserPromptSubmit"):
            for g in s["hooks"][ev]:
                for h in g["hooks"]:
                    if h.get("type", "command") == "command": res.append((ev, h["command"], h.get("timeout")))
        return res
    except (OSError, KeyError, ValueError, TypeError) as e:
        die("no se pudo leer .claude/settings.json: " + type(e).__name__)

def run_hooks_once():
    try:
        with open(FIX, "rb") as f: stdin = f.read()
        json.loads(stdin)
    except (OSError, ValueError): die("fixture ausente o inválida: " + os.path.relpath(FIX, ROOT))
    rows = []
    for i, (ev, cmd, to) in enumerate(hook_commands()):
        if any(x in cmd for x in EXCLUDED):
            rows.append((i, ev, "excluido", 0, 0)); continue
        with tempfile.TemporaryDirectory() as home:
            env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "TZ": "UTC",
                   "LC_ALL": "C.UTF-8", "CLAUDE_PROJECT_DIR": ROOT, "SOURCE_DATE_EPOCH": "1760000000",
                   "SAVIA_FIXED_CLOCK": "1760000000", "no_proxy": "*"}
            try:
                r = subprocess.run(["bash", "-c", cmd], input=stdin, capture_output=True, env=env,
                                   cwd=ROOT, timeout=min(30, max(5, (to or 10) if (to or 10) < 100 else 30)))
            except subprocess.TimeoutExpired:
                die("hook sin respuesta a tiempo: #%d %s" % (i, ev))
        out = r.stdout.decode("utf-8", "replace")
        ctx = out
        try:
            j = json.loads(out)
            ctx = j.get("hookSpecificOutput", {}).get("additionalContext", "") if isinstance(j, dict) else out
        except ValueError: pass
        rows.append((i, ev, "medido", len(ctx.encode()), len(ctx)))
    return rows

# --- salida ----------------------------------------------------------------
def baseline(name):
    p = os.path.join(BASE, name)
    try:
        with open(p) as f: return int(f.read().strip())
    except (OSError, ValueError): die("baseline ausente o ilegible: " + name)

def ratchet(label, current, name):
    b = baseline(name)
    if current > b:
        print("FAIL: %s %d tokens > baseline %d (%s)" % (label, current, b, name)); return False
    print("OK: %s %d tokens <= baseline %d%s" % (label, current, b, " (baseline holgado, bájalo)" if current < b else ""))
    return True

result = {"mode": MODE, "entry": ENTRY}
ok = True
if MODE in ("versioned", "local"):
    v, l, absent = measure_files()
    pieces = [(rel, b, c, "versionado") for rel, b, c in v]
    if MODE == "local":
        # Sin rutas ni contenido: etiqueta genérica por pieza.
        pieces += [("local-%d" % (i + 1), b, c, "local") for i, (rel, b, c) in enumerate(l)]
    tb = sum(p[1] for p in pieces); tc = sum(p[2] for p in pieces)
    result.update(pieces=[dict(name=p[0], bytes=p[1], chars=p[2], tokens=tok(p[2]), kind=p[3]) for p in pieces],
                  bytes=tb, chars=tc, tokens=tok(tc), local_absent=absent if MODE == "local" else None)
    if not AS_JSON:
        print("# context-fixed (%s, entry=%s)" % (MODE, ENTRY))
        print("%-52s %8s %8s %7s" % ("pieza", "bytes", "chars", "tokens"))
        for p in pieces: print("%-52s %8d %8d %7d" % (p[0], p[1], p[2], tok(p[2])))
        print("%-52s %8d %8d %7d" % ("TOTAL", tb, tc, tok(tc)))
        if MODE == "local" and absent: print("locales ausentes (gitignored, no cuentan): %d" % absent)
    if MODE == "local" and tok(tc) > LOCAL_WARN: print("AVISO: contexto local %d tokens > %d (sin gate)" % (tok(tc), LOCAL_WARN))
    if CHECK and MODE == "versioned" and ENTRY == "claude":
        ok = ratchet("versionado", tok(tc), "context-fixed-tokens.count")
elif MODE == "hooks":
    a = run_hooks_once(); b = run_hooks_once()
    if [(x[2], x[3], x[4]) for x in a] != [(x[2], x[3], x[4]) for x in b]:
        die("--hooks no determinista: dos ejecuciones difieren (%s vs %s caracteres); corrige o excluye el hook con motivo"
            % (sum(x[4] for x in a), sum(x[4] for x in b)))
    tb = sum(x[3] for x in a); tc = sum(x[4] for x in a)
    result.update(hooks=[dict(index=x[0], event=x[1], status=x[2], bytes=x[3], chars=x[4], tokens=tok(x[4])) for x in a],
                  bytes=tb, chars=tc, tokens=tok(tc))
    if not AS_JSON:
        print("# context-fixed (hooks, fixture fija, 2 ejecuciones idénticas)")
        print("%-4s %-18s %-9s %8s %8s" % ("#", "evento", "estado", "bytes", "chars"))
        for x in a: print("%-4d %-18s %-9s %8d %8d" % (x[0], x[1], x[2], x[3], x[4]))
        print("TOTAL bytes=%d chars=%d tokens=%d" % (tb, tc, tok(tc)))
    if CHECK:
        ok = ratchet("hooks", tok(tc), "context-fixed-hooks-tokens.count")
if AS_JSON: print(json.dumps(result, ensure_ascii=False, indent=1))
sys.exit(0 if ok else 1)
PY
