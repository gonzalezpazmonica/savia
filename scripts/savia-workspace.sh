#!/usr/bin/env bash
# savia-workspace.sh — SE-373: composicion de repos multi-repo para agentes.
#
# Dado un directorio-padre (workspace) con repos git hermanos, genera en la
# raiz un AGENTS.md de composicion: inventario de repos (path, remote),
# mapa de relaciones (heuristica por nombre + overrides manuales) e instruccion
# de lazy-load (los repos se cargan bajo demanda — no leer todos: coste de
# contexto + prompt cache SE-371). Registra el workspace en el estado de Savia.
#
# CRIT-001: solo lectura de los repos hijos; solo escribe en la raiz del
# workspace (AGENTS.md) y en ~/.savia/savia-setup.json. Sin egress.
#
# Uso:
#   savia-workspace.sh <dir> [--dry-run] [--answers FILE]
# Entorno: SAVIA_HOME_OVERRIDE (estado, default ~/.savia)
# Exit: 0 ok · 2 uso/error (sin repos hermanos → error claro)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHOME="${SAVIA_HOME_OVERRIDE:-$HOME/.savia}"
STATE_FILE="$SHOME/savia-setup.json"
WROOT="" DRY=0 ANSWERS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --answers) ANSWERS="$2"; shift 2 ;;
    --help|-h) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "uso invalido: $1" >&2; exit 2 ;;
    *) WROOT="$1"; shift ;;
  esac
done
[[ -n "$WROOT" ]] || { echo "uso: savia-workspace.sh <dir> [--dry-run] [--answers FILE]" >&2; exit 2; }
WROOT="$(cd "$WROOT" 2>/dev/null && pwd)" || { echo "✗ directorio no existe: $WROOT" >&2; exit 2; }
mkdir -p "$SHOME"

OUT="$WROOT/AGENTS.md"
# salida del motor: primera linea = ruta del AGENTS.md, resto = contenido; si exit 2 → sin repos
RESULT="$(python3 - "$WROOT" "$ANSWERS" "$STATE_FILE" "$OUT" <<'PY'
import json, os, re, subprocess, sys
root, ans_path, state_path, out = sys.argv[1:5]

def load_manual():
    manual = {}
    for p in (ans_path, state_path):
        if not p or not os.path.exists(p): continue
        try: d = json.load(open(p))
        except Exception: continue
        src = (d.get("workspace") or {}) if isinstance(d.get("workspace"), dict) else {}
        if isinstance(src.get("relations_manual"), dict):
            manual.update(src["relations_manual"])
        for k, v in (d.get("workspaces") or {}).items():
            m = v.get("relations_manual") or {}
            if m: manual.update(m)
    return manual

manual = load_manual()
repos = []
for name in sorted(os.listdir(root)):
    d = os.path.join(root, name)
    if os.path.isdir(d) and not name.startswith(".") and \
       (os.path.isdir(os.path.join(d, ".git")) or os.path.isfile(os.path.join(d, ".git"))):
        repos.append(name)
if not repos:
    print("", flush=True)
    sys.exit(2)

def norm(n): return re.sub(r'[^a-z0-9]+', '', n.lower())
providers = {}
for r in repos:
    if re.match(r'^.+[-_](api|backend|server|service|srv)$', r.lower()):
        providers[r] = norm(re.sub(r'[-_](api|backend|server|service|srv)$', '', r.lower()))
relations = {}   # proveedor -> [consumidores]
for r in repos:
    base = re.sub(r'(api|backend|server|service|srv)$', '', norm(r))
    for p, prov in providers.items():
        if p != r and (base == prov or base.startswith(prov) or prov.startswith(base)):
            relations.setdefault(p, []).append(r)
for k, v in manual.items():
    # override manual: {"provider": ["consumidor1", ...]}
    if k in providers and isinstance(v, list):
        relations.setdefault(k, []).extend(x for x in v if x not in relations.get(k, []) and x != k)
    elif k in repos and isinstance(v, list):
        # forma tolerante: {"consumer": ["provider"]} se invierte
        for x in v:
            if x in providers and k not in relations.get(x, []):
                relations.setdefault(x, []).append(k)

meta = {}
for r in repos:
    rem = ""
    try:
        rr = subprocess.run(["git", "-C", os.path.join(root, r), "remote", "get-url", "origin"],
                            capture_output=True, text=True)
        rem = rr.stdout.strip()
    except Exception: pass
    meta[r] = rem

name = os.path.basename(root) or "workspace"
L = []
L.append(f"# Workspace — {name} (multi-repo)")
L.append("")
L.append("> Generado por savia-workspace (SE-373). Instrucción para agentes:")
L.append("> **Los repos hermanos se cargan BAJO DEMANDA (lazy load). No leas todos los repos en cada turno**:")
L.append("> carga solo el repo del trabajo actual (coste de contexto y prompt cache).")
L.append("")
L.append("## Repos (inventario)")
L.append("")
L.append("| Repo | Remote |")
L.append("|---|---|")
for r in repos:
    L.append(f"| `{r}` | `{meta[r] or '—'}` |")
L.append("")
L.append("## Mapa de relaciones")
L.append("")
L.append("| Repo | Sirve a |")
L.append("|---|---|")
for r in repos:
    t = ", ".join(f"`{x}`" for x in relations.get(r, [])) or "—"
    L.append(f"| `{r}` | {t} |")
L.append("")
L.append("## Reglas por repo")
L.append("")
L.append("Al trabajar en un repo: carga `<repo>/CLAUDE.md` si existe; si no, `README.md`.")
L.append("Cruza dependencias con el mapa de relaciones antes de tocar contratos entre repos.")
L.append("")
body = "\n".join(L)

persist = {"path": out, "repos": repos, "relations": [{"repo": r, "served_by": relations.get(r, [])} for r in repos],
           "manual": {k: v for k, v in manual.items() if k in repos}}
print("__OK__", flush=True)
print(json.dumps(persist), flush=True)
print("__BODY__", flush=True)
print(body, flush=True)
PY
)"
RC=$?
if [[ "$RC" == "2" ]]; then
  echo "✗ no hay repos git hermanos en $WROOT (subdirectorios con .git)" >&2
  exit 2
elif [[ "$RC" != "0" ]]; then
  echo "✗ error del motor workspace (exit $RC)" >&2
  exit $RC
fi

PERSIST="$(echo "$RESULT" | sed -n '2p')"
BODY="$(echo "$RESULT" | sed -n '/^__BODY__$/,$p' | sed '1d')"

if [[ "$DRY" == "1" ]]; then
  echo "--- dry-run: se escribiria $OUT ---"
  echo "$BODY"
  exit 0
fi

echo "$BODY" > "$OUT"
echo "✓ composicion: $OUT"

python3 - "$STATE_FILE" "$WROOT" "$PERSIST" <<'PY'
import datetime, json, os, sys
st, wdir, persist_s = sys.argv[1:4]
persist = json.loads(persist_s)
state = {}
if os.path.exists(st):
    try: state = json.load(open(st))
    except Exception: state = {}
ws = state.setdefault("workspaces", {})
ws[wdir] = {"repos": persist["repos"], "relations": persist["relations"],
            "relations_manual": persist["manual"], "updated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
state["version"] = 1
open(st, "w").write(json.dumps(state, indent=2, ensure_ascii=False) + "\n")
print("✓ estado registrado: workspaces[" + os.path.basename(wdir) + "]")
PY
echo "repos: $(echo "$PERSIST" | python3 -c "import json,sys; print(', '.join(json.load(sys.stdin)['repos']))")"
