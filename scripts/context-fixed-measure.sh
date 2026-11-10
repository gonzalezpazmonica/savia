#!/usr/bin/env bash
# context-fixed-measure.sh — SE-511 S1: mide el contexto fijo que viaja en cada turno.
#
# Modos (uno por ejecución):
#   --versioned   CLAUDE.md + @imports recursivos versionados. Idéntico en CI y en cualquier máquina.
#   --hooks       additionalContext/stdout de TODOS los hooks de SessionStart y UserPromptSubmit,
#                 ejecutados con la fixture tests/fixtures/context-fixed/turn.json, HOME vacío y
#                 entorno mínimo, en un worktree desechable de HEAD (detached) más los cambios
#                 versionables sin commit. Así la cifra no depende de la rama ni de ficheros locales
#                 y los efectos de los hooks no tocan la raíz. Cada hook corre en su grupo de procesos
#                 y se espera a sus procesos en segundo plano. Se corre dos veces; si difiere, error.
#                 El reloj NO se fija: un hook que dependa de la fecha puede cambiar de un día a otro.
#   --local       versionado + ficheros locales gitignored (perfil activo, memoria externa).
#                 Solo cifras por pieza: ni rutas ni contenido. Aviso (sin gate) por encima de 6000.
# Opciones:
#   --entry claude|opencode   punto de entrada (opencode suma .opencode/CLAUDE.md). Por defecto claude.
#   --check       compara con .ci-baseline/context-fixed-*.count; falla (exit 1) si la cifra sube.
#                 Solo con --versioned (entry claude) o --hooks; en otra combinación sale con 2.
#   --json        salida JSON pura en stdout (veredicto del trinquete y avisos en el JSON y en stderr).
#
# Imports: `@ruta` se resuelve relativo a la RAÍZ (no al fichero importador), igual en todos los
# niveles; es la convención del repo. `~` no se expande. Una ruta absoluta o con `..` que salga de la
# raíz es error. --versioned no lee ni recorre ficheros gitignored: la cifra no depende de la máquina.
#
# Método de tokens: caracteres / 4 (el de scripts/token-estimator.sh), entero hacia abajo, sobre el total.
# Fail-closed: un @import inexistente (y no gitignored), un ciclo, un fichero ilegible, un hook que
# sale con código != 0 o un hook no determinista salen con exit 1; nunca se imprime un total parcial.
# --hooks exige git y un commit en la raíz; registra el worktree temporal y lo retira al terminar.
#
# Env: CONTEXT_FIXED_ROOT (raíz a medir), CI_BASELINE_DIR (baselines), CONTEXT_FIXED_FIXTURE.
# Exit: 0 OK · 1 fallo de medición o regresión del trinquete · 2 uso.
set -uo pipefail

ROOT="${CONTEXT_FIXED_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASELINE_DIR="${CI_BASELINE_DIR:-$ROOT/.ci-baseline}"
FIXTURE="${CONTEXT_FIXED_FIXTURE:-$ROOT/tests/fixtures/context-fixed/turn.json}"

MODE=""; ENTRY="claude"; CHECK=0; JSON=0
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --versioned|--hooks|--local|--gates) [[ -n "$MODE" ]] && { echo "ERROR: un solo modo por ejecución" >&2; exit 2; }; MODE="${1#--}"; shift ;;
    --entry) ENTRY="${2:-}"; [[ "$ENTRY" == claude || "$ENTRY" == opencode ]] || { echo "ERROR: --entry claude|opencode" >&2; exit 2; }; shift 2 ;;
    --check) CHECK=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: opción desconocida: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$MODE" ]] || { echo "ERROR: falta modo (--versioned|--hooks|--local|--gates)" >&2; usage >&2; exit 2; }
if [[ $CHECK -eq 1 ]] && ! [[ "$MODE" == hooks || ( "$MODE" == versioned && "$ENTRY" == claude ) ]]; then
  echo "ERROR: --check solo existe para --versioned (entry claude) y --hooks: no hay baseline para --$MODE --entry $ENTRY" >&2; exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 no disponible" >&2; exit 1; }

export ROOT BASELINE_DIR FIXTURE MODE ENTRY CHECK JSON
exec python3 -I - <<'PY'
import json, os, re, shutil, signal, subprocess, sys, tempfile, time

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

def read(path, hidden=False):
    try:
        with open(path, "rb") as f: raw = f.read()
        return raw, raw.decode("utf-8")
    except (OSError, UnicodeDecodeError) as e:
        die("fichero ilegible: %s (%s)" % (LOCAL_LABEL if hidden else os.path.relpath(path, ROOT),
                                          type(e).__name__))

def inside_root(path):
    root = os.path.normpath(ROOT)
    return path == root or path.startswith(root + os.sep)

LOCAL_LABEL = "<fichero local>"
def resolve(entry_rel):
    """Devuelve (versionadas, locales_presentes, locales_ausentes). Ciclo o import roto -> die().
    En --versioned los ficheros gitignored no se leen ni se recorren. Los mensajes de error nunca
    nombran un fichero local ni lo que importa un fichero local."""
    versioned, local, absent, seen = [], [], 0, set()
    def name(rel, is_local): return LOCAL_LABEL if is_local else rel
    def walk(rel, stack, from_local):
        nonlocal absent
        path = os.path.normpath(os.path.join(ROOT, rel))
        if os.path.isabs(rel) or not inside_root(path):
            die("@import fuera de la raíz: " + name(rel, from_local))
        ignored = is_ignored(rel)
        hidden = from_local or ignored
        real = os.path.realpath(path)
        if not ignored and os.path.exists(path) and not inside_root(real):
            die("@import versionado que sale de la raíz (enlace): " + name(rel, from_local))
        if real in [r for r, _ in stack]:
            chain = [name(r, h) for _, (r, h) in stack] + [name(rel, hidden)]
            die("ciclo de @imports: " + " -> ".join(chain))
        if not os.path.exists(path):
            if ignored: absent += 1; return
            die("@import a fichero inexistente: " + name(rel, from_local))
        if ignored and MODE == "versioned": return
        if real in seen: return
        seen.add(real)
        raw, text = read(path, hidden)
        (local if ignored else versioned).append((rel, len(raw), len(text)))
        for imp in imports_of(text):
            walk(os.path.normpath(imp), stack + [(real, (rel, hidden))], hidden)
    walk(entry_rel, [], False)
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
# Todos los hooks registrados se miden (sin exclusiones): corren en una copia desechable, así que los
# que escriben en el repo no tocan ROOT.
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

def git_z(*args):
    r = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True)
    if r.returncode: die("--hooks necesita que la raíz sea un repositorio git con al menos un commit")
    return [x for x in r.stdout.decode("utf-8", "surrogateescape").split("\0") if x]

def make_sandbox():
    """Copia desechable de la raíz: worktree de HEAD en modo detached más los cambios versionables
    sin commit (modificados, borrados y nuevos no ignorados). Sin ficheros gitignored ni rama: la cifra
    no depende de la máquina, de la rama ni del estado local, y los efectos de los hooks no tocan ROOT."""
    git_z("rev-parse", "-z", "--verify", "HEAD^{commit}")
    changed = git_z("diff", "-z", "--name-only", "HEAD") + git_z("ls-files", "-z", "--others", "--exclude-standard")
    tmp = tempfile.mkdtemp(prefix="context-fixed-")
    wt = os.path.join(tmp, "wt")   # el padre (tmp) está vacío: nada «hermano» del repo se cuela
    r = subprocess.run(["git", "-C", ROOT, "worktree", "add", "-q", "--detach", wt, "HEAD"], capture_output=True)
    if r.returncode:
        shutil.rmtree(tmp, ignore_errors=True); die("no se pudo crear el worktree desechable para --hooks")
    for rel in changed:
        src, dst = os.path.join(ROOT, rel), os.path.join(wt, rel)
        if os.path.islink(dst) or os.path.isfile(dst): os.unlink(dst)   # borrado o reemplazado
        if os.path.islink(src): os.symlink(os.readlink(src), dst)
        elif os.path.isfile(src):
            os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy2(src, dst)
    return tmp, wt

def drop_sandbox(tmp, wt):
    subprocess.run(["git", "-C", ROOT, "worktree", "remove", "--force", wt], capture_output=True)
    shutil.rmtree(tmp, ignore_errors=True)
    subprocess.run(["git", "-C", ROOT, "worktree", "prune"], capture_output=True)

def wait_group(pgid, secs=10):
    """Espera a los procesos en segundo plano que deja el hook (mismo grupo); los mata al agotar el plazo."""
    end = time.time() + secs
    while time.time() < end:
        try: os.killpg(pgid, 0)
        except ProcessLookupError: return
        time.sleep(0.05)
    try: os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError: pass

def run_hooks_once(wt):
    try:
        with open(FIX, "rb") as f: stdin = f.read()
        json.loads(stdin)
    except (OSError, ValueError): die("fixture ausente o inválida: " + os.path.relpath(FIX, ROOT))
    rows = []
    for i, (ev, cmd, to) in enumerate(hook_commands()):
        with tempfile.TemporaryDirectory() as home:
            env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "TZ": "UTC",
                   "LC_ALL": "C.UTF-8", "CLAUDE_PROJECT_DIR": wt, "no_proxy": "*"}
            p = subprocess.Popen(["bash", "-c", cmd], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, env=env, cwd=wt, start_new_session=True)
            try:
                out_b, _ = p.communicate(stdin, timeout=min(30, max(5, (to or 10) if (to or 10) < 100 else 30)))
            except subprocess.TimeoutExpired:
                wait_group(p.pid, 0); p.communicate()
                die("hook sin respuesta a tiempo: #%d %s" % (i, ev))
            wait_group(p.pid)
        r = subprocess.CompletedProcess(p.args, p.returncode, out_b, b"")
        if r.returncode != 0:
            die("hook #%d %s salió con código %d: la medición no vale (corrige o excluye el hook con motivo)"
                % (i, ev, r.returncode))
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

MSG_OUT = sys.stderr if AS_JSON else sys.stdout   # --json: stdout solo lleva el JSON
def ratchet(label, current, name):
    b = baseline(name)
    ok = current <= b
    msg = ("OK: %s %d tokens <= baseline %d%s" % (label, current, b, " (baseline holgado, bájalo)" if current < b else "")
           if ok else "FAIL: %s %d tokens > baseline %d (%s)" % (label, current, b, name))
    print(msg, file=MSG_OUT)
    result["check"] = {"baseline": b, "ok": ok, "message": msg}
    return ok

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
    if MODE == "local" and tok(tc) > LOCAL_WARN:
        result["warning"] = "AVISO: contexto local %d tokens > %d (sin gate)" % (tok(tc), LOCAL_WARN)
        print(result["warning"], file=MSG_OUT)
    if CHECK:   # la combinación ya se validó en bash (solo versioned + claude llega aquí)
        ok = ratchet("versionado", tok(tc), "context-fixed-tokens.count")
elif MODE == "gates":
    table = os.path.join(ROOT, "docs/rules/domain/savia-core-gates.tsv")
    if not os.path.isfile(table): die("falta docs/rules/domain/savia-core-gates.tsv")
    rows = [l.rstrip("\n").split("\t") for l in open(table, encoding="utf-8")
            if l.strip() and not l.startswith("#")]
    if not rows: die("tabla de gates vacía: ninguna regla puede salir del texto fijo sin gate")
    try:
        settings = json.load(open(os.path.join(ROOT, ".claude/settings.json"), encoding="utf-8"))
    except Exception as e:
        die("settings.json ilegible: %s" % type(e).__name__)
    fails = []; out = []
    for r in rows:
        if len(r) != 3: die("fila mal formada en savia-core-gates.tsv: %r" % "\t".join(r))
        rule, hook, event = r
        path = os.path.join(ROOT, ".claude/hooks", hook)
        why = []
        if "/" in hook or not os.path.isfile(path): why.append("hook ausente")
        elif not os.access(path, os.X_OK): why.append("hook no ejecutable")
        cmds = [h.get("command", "") for m in settings.get("hooks", {}).get(event, []) for h in m.get("hooks", [])]
        if not any(re.search(r"/hooks/%s\"?(\s|$)" % re.escape(hook), c) for c in cmds):
            why.append("no registrado en %s" % event)
        if os.path.isfile(path):
            tiers = re.findall(r'profile_gate\s+"?(\w+)', open(path, encoding="utf-8", errors="replace").read())
            bad = sorted(set(t for t in tiers if t != "security"))
            if bad: why.append("profile_gate %s: lo salta algún perfil" % ",".join(bad))
        out.append(dict(rule=rule, hook=hook, event=event, status="FAIL" if why else "OK", why=why))
        if why: fails.append(rule)
    result.update(gates=out)
    if not AS_JSON:
        print("# context-fixed (gates: reglas sostenidas por hook, SE-511 D5)")
        for g in out:
            print("%-4s %-28s %-28s %-12s %s" % (g["status"], g["rule"], g["hook"], g["event"], "; ".join(g["why"])))
    if fails:
        print("FAIL: %d regla(s) sin gate válido: %s" % (len(fails), ", ".join(fails)), file=sys.stderr); ok = False
    else:
        print("OK: %d gates con hook registrado que corre en todos los perfiles" % len(out), file=MSG_OUT)
elif MODE == "hooks":
    tmp, wt = make_sandbox()
    try:
        a = run_hooks_once(wt); b = run_hooks_once(wt)
    finally:
        drop_sandbox(tmp, wt)
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
