#!/usr/bin/env bash
# savia-setup.sh — SE-372: inicializador interactivo de configuracion completa.
#
# Configura Savia (pm-workspace) con todas sus funciones actuales, preguntando
# en orden y con defaults seguros (CRIT-001): identidad/frontend, modelos/
# proveedor, MCPs on/off, vaults local/remoto, federacion, backends, autonomia.
#
# Uso:
#   savia-setup.sh --help
#   savia-setup.sh --check                    # estado actual por area
#   savia-setup.sh                            # wizard interactivo (TTY)
#   savia-setup.sh <modulo> --answers FILE    # modulo desde respuestas/estado
#   savia-setup.sh --answers FILE             # aplica todo headless
#
# Entorno: SAVIA_HOME_OVERRIDE (estado/prefs, default ~/.savia) · --root DIR
# CRIT-001: local primero; vault remoto exige infra propia salvo --allow-any-remote.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHOME="${SAVIA_HOME_OVERRIDE:-$HOME/.savia}"
STATE_FILE="$SHOME/savia-setup.json"
PREFS_FILE="$SHOME/preferences.yaml"
ANSWERS="" MODULE="all" PUSH=0 ALLOW_ANY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --answers) ANSWERS="$2"; shift 2 ;;
    --push-remotes) PUSH=1; shift ;;
    --allow-any-remote) ALLOW_ANY=1; shift ;;
    --help|-h) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --check) MODE=check; shift ;;
    identity|models|mcp|vaults|federation|backends|autonomy) MODULE="$1"; shift ;;
    workspace) shift; exec "$SCRIPT_DIR/savia-workspace.sh" "$@" ;;
    all) MODULE=all; shift ;;
    *) echo "uso invalido: $1" >&2; exit 2 ;;
  esac
done

OPENCODE_JSON="$ROOT/opencode.json"
ACTIVE_USER="$ROOT/.claude/profiles/active-user.md"
PM_CONFIG_LOCAL="$ROOT/.claude/rules/pm-config.local.md"
CLAUDE_LOCAL="$ROOT/CLAUDE.local.md"
VAULTS_ROOT="$ROOT/vaults"

info(){ printf '%s\n' "· $*"; }
ok(){ printf '%s\n' "✓ $*"; }
warn(){ printf '%s\n' "! $*"; }
err(){ printf '%s\n' "✗ $*" >&2; }

mkdir -p "$SHOME"
[[ -f "$OPENCODE_JSON" ]] || { err "opencode.json no encontrado en $ROOT"; exit 2; }

state_read() { # clave dot -> valor
  [[ -f "$STATE_FILE" ]] || return 0
  python3 - "$STATE_FILE" "$1" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: raise SystemExit
for k in sys.argv[2].split('.'):
    if isinstance(d,dict) and k in d: d=d[k]
    else: d=None; break
print('' if d is None else (d if isinstance(d,str) else json.dumps(d)))
PY
}

save_state() { # $1=json (se mergea con estado previo)
  python3 - "$STATE_FILE" "$1" <<'PY'
import json,os,sys
p=sys.argv[1]; blob=json.loads(sys.argv[2])
if os.path.exists(p):
    old=json.load(open(p))
    for k in ('profile','frontend','models','mcp','vaults','federation','backends','autonomy'):
        if k in blob and isinstance(blob[k],dict) and isinstance(old.get(k),dict):
            old[k].update(blob[k]); continue
        if k in blob: old[k]=blob[k]
    blob=old
blob["version"]=1
open(p,"w").write(json.dumps(blob,indent=2,ensure_ascii=False)+"\n")
PY
  ok "estado guardado: $STATE_FILE"
}

ask_yn(){ local a; printf '%s [y/N] ' "$1"; read -r a || return 1; [[ "$a" =~ ^[YySs]$ ]]; }
ask_menu(){ # $1 prompt; resto opciones; imprime eleccion
  # El menú va a stderr: quien llama captura stdout con $(...) y solo debe recibir la elección.
  local prompt="$1"; shift; local n=$# i=1 o
  printf '%s\n' "$prompt" >&2
  for o in "$@"; do printf '  %d) %s\n' "$i" "$o" >&2; i=$((i+1)); done
  printf 'Elegir [1-%d]: ' "$n" >&2; read -r a || a=""
  if [[ "$a" =~ ^[0-9]+$ && "$a" -ge 1 && "$a" -le "$n" ]]; then
    eval "printf '%s' \"\${$a}\""
  else printf '%s' "$1"
  fi
}

# ── M0 / check ──────────────────────────────────────────────────────────────
cmd_check(){
  echo "=== Savia setup — estado por area ($ROOT) ==="
  local prefs
  [[ -f "$PREFS_FILE" ]] && prefs="si" || prefs="no"
  printf '%-14s %s\n' "preferences" "$prefs"
  printf '%-14s %s\n' "provider" "$(grep -E '^provider:' "$PREFS_FILE" 2>/dev/null | awk '{print $2}')"
  printf '%-14s %s\n' "frontend" "$(state_read frontend.primary)"
  printf '%-14s %s\n' "mcp" "$(python3 -c "import json;d=json.load(open('$OPENCODE_JSON'));print(','.join(k for k,v in (d.get('mcp') or {}).items() if v.get('enabled')!=False) or 'ninguno')" 2>/dev/null)"
  printf '%-14s %s\n' "vaults" "$(ls "$VAULTS_ROOT" 2>/dev/null | grep -vE '^(INDEX|MAP|\.)' | tr '\n' ' ')"
  printf '%-14s %s\n' "federation" "$([ -f "$VAULTS_ROOT/.federation.json" ] && echo on || echo off)"
  printf '%-14s %s\n' "workspaces" "$(python3 -c "import json,os;d=json.load(open('$STATE_FILE')) if os.path.exists('$STATE_FILE') else {};ws=d.get('workspaces') or {};print(', '.join(os.path.basename(k) for k in ws) or 'ninguno')" 2>/dev/null)"
  exit 0
}

# ── aplicadores (python, args por argv) ─────────────────────────────────────
apply_mcp(){
  python3 - "$OPENCODE_JSON" "$STATE_FILE" <<'PY' || return 1
import json,os,sys
p,st=sys.argv[1],sys.argv[2]
d=json.load(open(p)); mcp=d.setdefault("mcp",{})
enabled=[]; disabled=[]
if os.path.exists(st):
    s=json.load(open(st)) or {}
    enabled=(s.get("mcp") or {}).get("enabled",[])
    disabled=(s.get("mcp") or {}).get("disabled",[])
known=["codegraph","codebase-memory-mcp","savia-vaults"]
for name in known:
    e=mcp.get(name)
    if e is None: e={"type":"local","enabled":False}; mcp[name]=e
    if name in enabled: e["enabled"]=True
    elif name in disabled: e["enabled"]=False
    # no mencionado -> se conserva el estado actual (modulo imperativo no pisa)
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n")
print("opencode.json mcp:", "enabled="+",".join(enabled) if enabled else "ninguno")
PY
}
apply_prefs(){
  python3 - "$PREFS_FILE" "$STATE_FILE" <<'PY' || return 1
import json,os,sys
p,st=sys.argv[1],sys.argv[2]
s=json.load(open(st)) or {}
fr=s.get("frontend") or {}; md=s.get("models") or {}
lines=[]
if os.path.exists(p): lines=[l.rstrip("\n") for l in open(p)]
def setk(k,v):
    global lines
    lines=[l for l in lines if not l.startswith(k+":")]
    lines.insert(1,f"{k}: {v}")
for k,v in {"version":"1","frontend":fr.get("primary","opencode"),
            "provider":md.get("provider","ollama")}.items(): setk(k,v)
for t in ("heavy","mid","fast"):
    if md.get("model_"+t): setk("model_"+t, md["model_"+t])
for k,v in {"has_hooks":"yes","has_task_fan_out":"yes","has_slash_commands":"yes",
            "budget_kind":"none","auth_kind":md.get("auth_kind","api-key")}.items(): setk(k,v)
open(p,"w").write("\n".join(lines)+"\n")
print("preferences.yaml:", p)
PY
}
apply_user(){
  python3 - "$ACTIVE_USER" "$STATE_FILE" <<'PY' || return 0
import datetime,json,os,re,sys
p,st=sys.argv[1],sys.argv[2]
s=json.load(open(st)) or {}
name=(s.get("profile") or {}).get("name") or ""
if not name: raise SystemExit
role=(s.get("profile") or {}).get("role") or "Operadora"
slug=(s.get("profile") or {}).get("slug") or re.sub(r'[^a-z0-9]+','_',name.lower()).strip('_')
os.makedirs(os.path.dirname(p),exist_ok=True)
now=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
open(p,"w").write(f'---\nactive_slug: "{slug}"\nactive_name: "{name}"\nactive_role: "{role}"\nactivated_at: "{now}"\n---\n')
print("perfil activo:", slug)
PY
}
apply_pmc(){
  python3 - "$PM_CONFIG_LOCAL" "$STATE_FILE" <<'PY' || return 0
import json,os,sys
p,st=sys.argv[1],sys.argv[2]
s=json.load(open(st)) or {}; au=s.get("autonomy") or {}
reviewer=au.get("autonomous_reviewer"); notify=au.get("research_notify")
if not reviewer and not notify: raise SystemExit
os.makedirs(os.path.dirname(p),exist_ok=True)
body=""
if os.path.exists(p): body=open(p).read()
def ensure(k,v):
    global body
    import re
    body=re.sub(rf"^{k}=.*$","",body,flags=re.M)
    body=(body+"\n"+f'{k}="{v}"').strip()+"\n"
if reviewer: ensure("AUTONOMOUS_REVIEWER",reviewer)
if notify: ensure("AUTONOMOUS_RESEARCH_NOTIFY",notify)
open(p,"w").write(body)
print("pm-config.local:", p)
PY
}
apply_backend(){
  python3 - "$CLAUDE_LOCAL" "$STATE_FILE" <<'PY' || return 0
import json,os,re,sys
p,st=sys.argv[1],sys.argv[2]
s=json.load(open(st)) or {}; be=(s.get("backends") or {}).get("azure_devops") or {}
if not be.get("enabled") or not be.get("org_url"): raise SystemExit
blk=f"# azure-devops (savia setup)\nAZURE_DEVOPS_ORG_URL=\"{be['org_url']}\""
body=""
if os.path.exists(p):
    body=open(p).read()
    body=re.sub(r"# azure-devops \(savia setup\)\n.*?(?=\n# |\Z)","",body,flags=re.S)
body=(body+"\n"+blk+"\n").strip()+"\n"
open(p,"w").write(body)
print("CLAUDE.local.md backend:", be['org_url'])
PY
}
apply_vaults(){
  python3 - "$VAULTS_ROOT" "$STATE_FILE" "$PUSH" "$ALLOW_ANY" <<'PY' || return 1
import json,os,subprocess,sys
root,st,push,allow=sys.argv[1],sys.argv[2],sys.argv[3]=="1",sys.argv[4]=="1"
s=json.load(open(st)) or {}; domes=(s.get("vaults") or {}).get("domes",[])
for d in domes:
    name=d.get("name"); mode=d.get("mode","local"); url=d.get("remote_url")
    if not name: continue
    lvl=d.get("confidentiality","N2")
    vdir=os.path.join(root,name)
    os.makedirs(vdir,exist_ok=True)
    idx=os.path.join(vdir,"INDEX.md")
    if not os.path.exists(idx):
        open(idx,"w").write(
"---\nentity: {type: cupula, id: cupula-%s}\ntitle: \"Cúpula — %s\"\ndomain: %s\ncategory: Conocimiento\nlifecycle: cupula-creada\nconfidentiality: %s\nsource: \"savia setup (SE-372)\"\n---\n\n# Cúpula — %s\n\nDome configurado por savia setup (SE-372). Nivel: %s.\n"
% (name.lower(), name, name.upper()[:4], lvl, name, lvl))
    if mode=="remote":
        if not url:
            print("WARN dome", name, "en modo remote sin remote_url — se deja local")
            continue
        own = url.startswith("git@") or "github.com/" in url or \
              "localhost" in url or url.startswith("127.") or url.startswith("file://")
        if not own and not allow:
            print("RECHAZADO dome", name, ": remoto", url, "no es infra propia (CRIT-001) — usa --allow-any-remote solo si confirmas")
            continue
        if not os.path.exists(os.path.join(vdir,".git")):
            subprocess.run(["git","-C",vdir,"init","-q"],check=True)
        r=subprocess.run(["git","-C",vdir,"remote","get-url","origin"],capture_output=True,text=True)
        if r.returncode!=0:
            subprocess.run(["git","-C",vdir,"remote","add","origin",url],check=True)
        else:
            subprocess.run(["git","-C",vdir,"remote","set-url","origin",url],check=True)
        if push:
            try:
                subprocess.run(["git","-C",vdir,"add","-A"],check=True)
                subprocess.run(["git","-C",vdir,"commit","-q","--allow-empty","-m","chore: savia setup dome"],check=True)
                subprocess.run(["git","-C",vdir,"push","-u","origin","HEAD"],check=True,capture_output=True)
            except Exception:
                print("WARN push fallo:", name, "(remote configurado, push manual)")
    print("vault:", name, "mode="+mode, "nivel="+lvl, ("remote="+url) if url else "")
PY
}
apply_fed(){
  python3 - "$VAULTS_ROOT" "$STATE_FILE" <<'PY' || return 1
import datetime,json,os,sys
root,st=sys.argv[1],sys.argv[2]
s=json.load(open(st)) or {}; fed=s.get("federation") or {}
if not fed.get("enabled"): raise SystemExit(0)
open(os.path.join(root,".federation.json"),"w").write(
  json.dumps({"enabled":True,"remotes":fed.get("remotes",[]),"updated_at":datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},indent=2)+"\n")
print("federacion:", ", ".join(fed.get("remotes",[])) if fed.get("remotes") else "on (sin remotos)")
PY
}
apply_all(){ apply_mcp && apply_prefs; apply_user; apply_pmc; apply_backend; apply_vaults; apply_fed; }

# ── wizard ──────────────────────────────────────────────────────────────────
wizard(){
  echo "=== Savia setup — configuracion interactiva (SE-372) ==="
  echo "(defaults seguros CRIT-001 · ctrl-c cancela)"
  local name="" role="" prov="" fe=""
  name="$(state_read profile.name)"; [[ -z "$name" ]] && { printf 'Nombre de la operadora: '; read -r name || name=""; }
  role="$(state_read profile.role)";  [[ -z "$role" ]]  && { printf 'Rol: '; read -r role || role=""; }
  prov="$(state_read models.provider)"; [[ -z "$prov" ]] && prov="ollama"
  prov="$(ask_menu "Proveedor de modelos (local primero):" "ollama" "zai-coding-plan" "deepseek" "azure-openai")"
  local heavy="provider/glm-5.3" mid="provider/glm-5" fast="provider/glm-5.3-flash"
  case "$prov" in
    ollama) heavy="ollama/llama3.1:70b"; mid="ollama/llama3.1:8b"; fast="ollama/llama3.1";;
    deepseek) heavy="deepseek/deepseek-v4-flash"; mid="$heavy"; fast="$heavy";;
    zai-coding-plan) heavy="zai-coding-plan/glm-5.3"; mid="zai-coding-plan/glm-5"; fast="zai-coding-plan/glm-5.3-flash";;
  esac
  fe="$(ask_menu "Frontend principal:" "opencode" "claude-code" "ambos")"
  echo; echo "--- Vaults ---"
  local mode rem=""
  mode="$(ask_menu "Modo de vaults por defecto:" "local" "remoto")"
  if [[ "$mode" == "remoto" ]]; then
    printf 'URL git del remoto (infra propia, ej git@host:user/repo): '; read -r rem || rem=""
  fi
  local domes=()
  if ask_yn "¿Crear domes locales (SaviaLearning, SaviaLabs, savia-docs, Fronesia)? (y/N)"; then
    domes=(SaviaLearning SaviaLabs savia-docs Fronesia)
  fi
  echo; echo "--- MCP servers ---"
  local on_v=1 on_cg=1 on_cbm=1
  ask_yn "MCP savia-vaults (local)? (y/N)"        || on_v=0
  ask_yn "MCP codegraph (local)? (y/N)"           || on_cg=0
  ask_yn "MCP codebase-memory-mcp (local)? (y/N)" || on_cbm=0
  local fed=0 rems=()
  if ask_yn "¿Habilitar federacion de domes? (y/N)"; then
    fed=1
    local r0=""
    printf 'Endpoint remoto (infra propia) o vacio: '; read -r r0 || r0=""
    [[ -n "$r0" ]] && rems+=("$r0")
  fi
  # Construir respuestas con python (json correcto)
  local ANSWERS_TMP
  ANSWERS_TMP="$(mktemp)"
  NAME="$name" ROLE="$role" PROVIDER="$prov" HEAVY="$heavy" MID="$mid" FAST="$fast" \
  FE="$fe" MODE_V="${mode/remoto/remote}" REM="$rem" DOMES="${domes[*]:-}" ON_V="$on_v" ON_CG="$on_cg" ON_CBM="$on_cbm" FED="$fed" REMS="${rems[*]:-}" \
  python3 - "$ANSWERS_TMP" <<'PY'
import json,os,sys
p=sys.argv[1]
d={
 "profile":{"name":os.environ.get("NAME",""),"role":os.environ.get("ROLE","Operadora")},
 "frontend":{"primary":os.environ.get("FE","opencode")},
 "models":{"provider":os.environ.get("PROVIDER","ollama"),
           "model_heavy":os.environ.get("HEAVY"),"model_mid":os.environ.get("MID"),
           "model_fast":os.environ.get("FAST"),"auth_kind":"api-key"},
 "mcp":{"enabled":[],"disabled":[]},
 "vaults":{"domes":[],"root_served":True},
 "federation":{"enabled":os.environ.get("FED","0")=="1","remotes":[]},
 "backends":{},"autonomy":{}
}
for name in ("savia-vaults","codegraph","codebase-memory-mcp"):
    (d["mcp"]["enabled"] if os.environ.get({ "savia-vaults":"ON_V","codegraph":"ON_CG","codebase-memory-mcp":"ON_CBM"}[name],"0")=="1" else d["mcp"]["disabled"]).append(name)
for n in os.environ.get("DOMES","").split():
    d["vaults"]["domes"].append({"name":n,"mode":os.environ.get("MODE_V","local"),
        "remote_url":os.environ.get("REM") or None,
        "confidentiality":{"SaviaDomains":"N1","SaviaLabs":"N2","savia-docs":"N2","SaviaLearning":"N2","Fronesia":"N2"}.get(n,"N2"),
        "backup":"local"})
for r in os.environ.get("REMS","").split():
    if r: d["federation"]["remotes"].append(r)
open(p,"w").write(json.dumps(d,ensure_ascii=False))
PY
  # cmd_from_answers termina con exit: en subshell para no cortar el cierre del asistente
  ( ANSWERS="$ANSWERS_TMP" MODULE=all cmd_from_answers )
  local rc=$?
  rm -f "$ANSWERS_TMP"
  [[ "$rc" -eq 0 ]] || exit "$rc"
  echo; echo "=== Savia configurada ==="; cmd_check
  exit 0
}

# ── headless/modulos ────────────────────────────────────────────────────────
cmd_from_answers(){
  local src="$ANSWERS"
  if [[ -z "$src" ]]; then
    if [[ -f "$STATE_FILE" ]]; then src="$STATE_FILE"; else err "sin respuestas ni estado"; exit 2; fi
  fi
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$src" || { err "json invalido: $src"; exit 2; }
  # merge (no reemplazo): preserva areas no mencionadas del estado previo
  python3 - "$src" "$STATE_FILE" <<'PY' || { err "no se puede escribir estado en $SHOME"; exit 2; }
import json,os,sys
src, st = sys.argv[1], sys.argv[2]
blob = json.load(open(src))
if os.path.exists(st):
    old = json.load(open(st))
    for k in ('profile','frontend','models','mcp','vaults','federation','backends','autonomy'):
        if k in blob and isinstance(blob[k], dict) and isinstance(old.get(k), dict):
            old[k].update(blob[k]); continue
        if k in blob: old[k] = blob[k]
    blob = old
blob["version"] = 1
open(st, "w").write(json.dumps(blob, indent=2, ensure_ascii=False) + "\n")
PY
  ok "estado: $STATE_FILE (respuestas + estado previo)"
  case "$MODULE" in
    identity) apply_user ;; models) apply_prefs ;; mcp) apply_mcp ;;
    vaults) apply_vaults ;; federation) apply_fed ;; backends) apply_backend ;;
    autonomy) apply_pmc ;; *) apply_all ;;
  esac
  exit 0
}

mkdir -p "$SHOME"
if [[ "${MODE:-}" == "check" ]]; then cmd_check; fi
if [[ -n "$ANSWERS" ]]; then cmd_from_answers; fi
if [[ "$MODULE" != "all" && -f "$STATE_FILE" ]]; then cmd_from_answers; fi
if [[ -t 0 ]]; then wizard; else cmd_check; fi
