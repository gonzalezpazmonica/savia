#!/usr/bin/env bash
set -uo pipefail
# context-dome-generate.sh -- Genera CONTEXT_DOME.md por modulo con BF bajo.
# SE-252 -- Bus Factor Shield
#
# Exit codes: 0 ok (incluye "nada que generar" y modulos saltados con WARN)
#             1 uso o entrada invalida (argumentos, proyecto, sin scan del proyecto,
#               scan de otro proyecto)
#             2 scan JSON ilegible (corrupto o sin lista 'modules')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BF_OUTPUT_DIR="${BF_OUTPUT_DIR:-$PROJECT_DIR/output/bus-factor}"

# -- Defaults -----------------------------------------------------------------
PROJECT_PATH=""
MODULE_FILTER=""
MIN_RISK="HIGH"
DRY_RUN=false
FORCE=false
REDACT_OWNERS=false

# -- Ayuda --------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
Usage: context-dome-generate.sh --project <path> [options]

Options:
  --project   <path>   Directorio del repositorio (obligatorio)
  --module    <name>   Solo generar cupula para este modulo (name o path del scan)
  --min-risk  <level>  Riesgo minimo: CRITICAL|HIGH|MEDIUM|LOW (default: HIGH)
  --dry-run            Muestra que se generaria sin escribir
  --force              Regenera aunque la cupula se haya editado a mano
  --redact-owners      Escribe los owners sin dominio de email (repos publicos)
  --help               Muestra esta ayuda
EOF
  exit 1
}

need_value() { [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR: $1 requiere un valor" >&2; usage; }; }

# -- Parseo de argumentos -----------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  need_value "$@"; PROJECT_PATH="$2"; shift 2 ;;
    --module)   need_value "$@"; MODULE_FILTER="$2"; shift 2 ;;
    --min-risk) need_value "$@"; MIN_RISK="$2";      shift 2 ;;
    --dry-run)  DRY_RUN=true;       shift ;;
    --force)    FORCE=true;         shift ;;
    --redact-owners) REDACT_OWNERS=true; shift ;;
    --help|-h)  usage ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; usage ;;
  esac
done

if [[ -z "$PROJECT_PATH" ]]; then
  echo "ERROR: --project es obligatorio" >&2
  usage
fi

case "$MIN_RISK" in
  CRITICAL|HIGH|MEDIUM|LOW) ;;
  *) echo "ERROR: --min-risk invalido: '$MIN_RISK' (CRITICAL|HIGH|MEDIUM|LOW)" >&2; exit 1 ;;
esac

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: --project no es un directorio: $PROJECT_PATH" >&2
  exit 1
fi

PROJECT_NAME="$(basename "$(cd "$PROJECT_PATH" && pwd)")"

# -- Encontrar JSON del scan mas reciente DE ESTE proyecto --------------------
# Aislamiento N4 (mismo criterio que bus-factor-report/-distribute): solo
# <nombre>.json o <nombre>-<YYYYMMDD>T<HHMMSS>Z.json (nombre por defecto de
# bus-factor-scan.sh). Sin fallback a otro proyecto ni a prefijos parecidos
# (app vs app-backend): sus owners acabarian en esta cupula.
find_latest_scan() {
  local dir="$1" name="$2"
  ls -t "$dir/$name.json" \
        "$dir/$name"-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z.json \
        2>/dev/null | head -1
}

SCAN_JSON=$(find_latest_scan "$BF_OUTPUT_DIR" "$PROJECT_NAME")
if [[ -z "$SCAN_JSON" ]]; then
  echo "ERROR: no se encontro JSON de scan del proyecto '$PROJECT_NAME' en $BF_OUTPUT_DIR" >&2
  echo "INFO: ejecuta primero: bash scripts/bus-factor-scan.sh --project $PROJECT_PATH" >&2
  exit 1
fi

echo "INFO: usando scan: $SCAN_JSON" >&2

# -- Extraer modulos elegibles del JSON (una linea JSON por modulo) -----------
# Los valores viajan por argv, nunca interpolados en el codigo Python.
MODULES_JSONL=$(python3 - "$SCAN_JSON" "$MIN_RISK" "$MODULE_FILTER" "$PROJECT_NAME" <<'PY'
import json, sys
scan, min_risk, module_filter, project = sys.argv[1:5]
risk_map = {'CRITICAL': 4, 'HIGH': 3, 'MEDIUM': 2, 'LOW': 1}
try:
    with open(scan, encoding='utf-8') as fh:
        data = json.load(fh)
    modules = data['modules']
    assert isinstance(modules, list), "'modules' no es una lista"
except (OSError, ValueError, KeyError, TypeError, AssertionError) as e:
    print(f"ERROR: scan JSON ilegible en {scan}: {e}", file=sys.stderr)
    sys.exit(2)
# Defensa adicional: un scan renombrado de otro proyecto tampoco vale.
if data.get('project') not in (None, project):
    print(f"ERROR: el scan {scan} es del proyecto '{data.get('project')}', no de '{project}'", file=sys.stderr)
    sys.exit(1)
for mod in modules:
    rl = mod.get('risk_level', 'LOW')
    if risk_map.get(rl, 0) < risk_map[min_risk]:
        continue
    path = mod.get('path') or mod.get('name')
    if module_filter and module_filter not in (mod.get('name'), path):
        continue
    print(json.dumps({
        'name': mod.get('name', path),
        'path': path,
        'bus_factor': mod.get('bus_factor'),
        'risk_level': rl,
        'owners': mod.get('owners') or [],
        'warnings': mod.get('warnings') or [],
    }))
PY
)
PY_RC=$?
if [[ $PY_RC -ne 0 ]]; then
  exit "$PY_RC"
fi

if [[ -z "$MODULES_JSONL" ]]; then
  echo "INFO: no hay modulos con riesgo >= $MIN_RISK" >&2
  exit 0
fi

MODULE_COUNT=$(printf '%s\n' "$MODULES_JSONL" | wc -l)
echo "INFO: generando cupulas para $MODULE_COUNT modulos ..." >&2

# -- Funciones auxiliares de extraccion ---------------------------------------

extract_purpose() {
  local mod_path="$1"
  local full_path="$PROJECT_PATH/$mod_path"
  local purpose=""

  # 1. CONTEXT.md del modulo
  if [[ -f "$full_path/CONTEXT.md" ]]; then
    purpose=$(head -20 "$full_path/CONTEXT.md" | grep -v "^#" | grep -v "^---" | grep -v "^$" | head -5 | tr '\n' ' ')
  fi

  # 2. README.md del modulo
  if [[ -z "$purpose" ]] && [[ -f "$full_path/README.md" ]]; then
    purpose=$(grep -A3 "^## " "$full_path/README.md" 2>/dev/null | head -4 | grep -v "^##" | grep -v "^$" | head -2 | tr '\n' ' ')
    if [[ -z "$purpose" ]]; then
      purpose=$(head -5 "$full_path/README.md" | grep -v "^#" | grep -v "^$" | head -2 | tr '\n' ' ')
    fi
  fi

  # 3. Comentarios cabecera del primer archivo fuente (orden estable)
  if [[ -z "$purpose" ]]; then
    local first_file
    first_file=$(find "$full_path" -maxdepth 1 -type f \( -name "*.py" -o -name "*.ts" -o -name "*.go" -o -name "*.cs" -o -name "*.java" \) 2>/dev/null | sort | head -1)
    if [[ -n "$first_file" ]]; then
      purpose=$(head -10 "$first_file" | grep -E "^(#|//|/\*|\*)" | grep -v "^#!/" | head -3 | sed 's|^[#/*\s]*||' | tr '\n' ' ')
    fi
  fi

  echo "${purpose:-[sin descripcion detectada -- documentar manualmente]}"
}

extract_key_decisions() {
  local mod_path="$1"

  # git log buscando patrones de decision. -E: sin el, '|' es literal en BRE
  # y no casaba nunca. Solo HEAD: commits de ramas sin integrar (quiza
  # privadas o abandonadas) no deben acabar en un fichero del modulo.
  local patterns="why:|because|NOTE:|HACK:|FIXME:|decision:|tradeoff:|SE-|SPEC-"
  local log_output
  log_output=$(git -C "$PROJECT_PATH" log --oneline -E --grep="$patterns" \
    --max-count=20 -- "$mod_path/" ":(exclude)$mod_path/CONTEXT_DOME.md" 2>/dev/null) || true

  if [[ -z "$log_output" ]]; then
    echo "[sin decisiones documentadas en commits -- revisar ADRs del proyecto]"
  else
    echo "$log_output"
  fi
}

extract_dependencies() {
  local mod_path="$1"
  local full_path="$PROJECT_PATH/$mod_path"

  # Detectar imports segun extension
  local deps=""
  if [[ -d "$full_path" ]]; then
    # Python
    deps+=$(grep -rh "^import \|^from " "$full_path" --include="*.py" 2>/dev/null | sort -u | head -10)
    # TypeScript/JavaScript
    deps+=$(grep -rh "^import " "$full_path" --include="*.ts" --include="*.tsx" --include="*.js" 2>/dev/null | grep "from " | sed "s/.*from '\(.*\)'.*/\1/" | sort -u | head -10)
    # Go
    deps+=$(grep -rh '^\s*"' "$full_path" --include="*.go" 2>/dev/null | sed 's/^\s*//' | sort -u | head -10)
    # C#
    deps+=$(grep -rh "^using " "$full_path" --include="*.cs" 2>/dev/null | sort -u | head -10)
  fi

  if [[ -z "${deps// /}" ]]; then
    echo "[sin dependencias externas detectadas automaticamente]"
  else
    echo "$deps" | head -15
  fi
}

extract_runbook() {
  local mod_path="$1"
  local full_path="$PROJECT_PATH/$mod_path"
  local runbook=""
  local sources=0

  # Makefile targets
  if [[ -f "$full_path/Makefile" ]]; then
    local targets
    targets=$(grep -E "^[a-zA-Z_-]+:" "$full_path/Makefile" 2>/dev/null | sed 's/:.*//' | head -8)
    if [[ -n "$targets" ]]; then
      runbook+="### Makefile targets\n\`\`\`\n$targets\n\`\`\`\n"
      ((sources++)) || true
    fi
  fi

  # package.json scripts (ruta por argv: un apostrofo no rompe el codigo)
  if [[ -f "$full_path/package.json" ]]; then
    local scripts
    scripts=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); [print(f'  npm run {k}: {v}') for k,v in d.get('scripts',{}).items()]" "$full_path/package.json" 2>/dev/null | head -8)
    if [[ -n "$scripts" ]]; then
      runbook+="### npm scripts\n\`\`\`\n$scripts\n\`\`\`\n"
      ((sources++)) || true
    fi
  fi

  # README ## Usage section
  if [[ -f "$full_path/README.md" ]]; then
    local usage_section
    usage_section=$(awk '/^## (Usage|Uso|Getting Started|Quick Start)/{found=1; next} found && /^## /{exit} found{print}' "$full_path/README.md" 2>/dev/null | head -15)
    if [[ -n "$usage_section" ]]; then
      runbook+="### README Usage\n$usage_section\n"
      ((sources++)) || true
    fi
  fi

  # Dockerfile CMD / ENTRYPOINT
  if [[ -f "$full_path/Dockerfile" ]]; then
    local docker_cmd
    docker_cmd=$(grep -E "^(CMD|ENTRYPOINT|RUN)" "$full_path/Dockerfile" 2>/dev/null | tail -3)
    if [[ -n "$docker_cmd" ]]; then
      runbook+="### Dockerfile\n\`\`\`dockerfile\n$docker_cmd\n\`\`\`\n"
      ((sources++)) || true
    fi
  fi

  # Calcular confianza
  local confidence="low"
  if [[ $sources -ge 2 ]]; then
    confidence="high"
  elif [[ $sources -eq 1 ]]; then
    confidence="medium"
  fi

  if [[ -z "${runbook// /}" ]] || [[ $sources -eq 0 ]]; then
    echo "CONFIDENCE:low"
    echo "[sin runbook detectado -- documentar manualmente]"
  else
    echo "CONFIDENCE:$confidence"
    printf '%b' "$runbook"
  fi
}

extract_recent_commits() {
  local mod_path="$1"
  # Excluir merge commits, chore, format, typo, style (-E: '\|' es GNU) y los
  # commits que solo tocan la propia cupula (si no, cada commit de la cupula
  # la cambiaria y se regeneraria en cada ciclo).
  git -C "$PROJECT_PATH" log \
    --oneline \
    --max-count=10 \
    --no-merges \
    -E --invert-grep \
    --grep="^(chore|format|typo|style)" \
    -- "$mod_path/" ":(exclude)$mod_path/CONTEXT_DOME.md" 2>/dev/null || true
}

# Huella del contenido generado, sin las lineas volatiles (generated_at y la
# propia huella). Detecta si la cupula se edito a mano desde que se genero.
# En python: sha256sum no existe en macOS.
dome_digest() {
  python3 - "$1" <<'PY'
import hashlib, re, sys
lines = open(sys.argv[1], encoding='utf-8').read().splitlines(keepends=True)
body = ''.join(l for l in lines if not re.match(r'(generated_at|dome_hash): ', l))
print(hashlib.sha256(body.encode('utf-8')).hexdigest()[:16])
PY
}

# Fija la huella en el frontmatter (sin sed -i: su sintaxis difiere en BSD).
set_dome_hash() {
  python3 - "$1" "$2" <<'PY'
import sys
path, h = sys.argv[1:3]
text = open(path, encoding='utf-8').read()
open(path, 'w', encoding='utf-8').write(text.replace('\ndome_hash: PENDING\n', f'\ndome_hash: {h}\n', 1))
PY
}

# Campos del modulo, normalizados y con quoting YAML/markdown seguro.
module_fields() {
  python3 - "$1" "$REDACT_OWNERS" <<'PY'
import json, sys
m = json.loads(sys.argv[1]); redact = sys.argv[2] == 'true'
def who(o):
    d = str(o.get('dev', 'desconocido'))
    return d.split('@', 1)[0] if redact else d
def cell(v):
    return str(v).replace('|', '\\|').replace('\n', ' ')
try:
    bf = float(m['bus_factor'])
    bf_txt = str(int(bf)) if bf == int(bf) else str(bf)
    plan = 'urgent' if bf <= 1 else ('high' if bf <= 2 else 'ok')
except (TypeError, ValueError, KeyError):
    bf_txt, plan = 'null', 'unknown'
owners = m['owners']
yaml_owners = '\n'.join('  - ' + json.dumps(who(o), ensure_ascii=False) for o in owners)
table = ['| Developer | Score | Archivos propios |', '|-----------|-------|-----------------|']
table += [f"| {cell(who(o))} | {cell(o.get('score', '-'))} | {cell(o.get('files_owned', '-'))} |" for o in owners]
if not owners:
    table.append('| desconocido | - | - |')
print(json.dumps({
    'path': str(m['path'] or ''), 'path_yaml': json.dumps(str(m['path'] or ''), ensure_ascii=False),
    'bf': bf_txt, 'plan': plan, 'risk': str(m['risk_level']),
    'owners_yaml': ('knowledge_owners:\n' + yaml_owners) if owners else 'knowledge_owners: []',
    'table': '\n'.join(table), 'warnings': json.dumps(m['warnings'], ensure_ascii=False),
}))
PY
}

field() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"; }

# -- Generar CONTEXT_DOME.md por modulo ---------------------------------------

generate_dome() {
  local fields
  if ! fields=$(module_fields "$1"); then
    echo "WARN: modulo con datos invalidos en el scan (saltando)" >&2
    return
  fi

  local mod_path path_yaml bus_factor plan risk_level owners_yaml owners_table warnings_json
  mod_path=$(field "$fields" path); path_yaml=$(field "$fields" path_yaml)
  bus_factor=$(field "$fields" bf); plan=$(field "$fields" plan)
  risk_level=$(field "$fields" risk); owners_yaml=$(field "$fields" owners_yaml)
  owners_table=$(field "$fields" table); warnings_json=$(field "$fields" warnings)

  # Ruta relativa y dentro del proyecto: ni absoluta ni con '..'.
  if [[ -z "$mod_path" || "$mod_path" == /* || "/$mod_path/" == */../* ]]; then
    echo "WARN: ruta insegura en el scan: '$mod_path' (saltando)" >&2
    return
  fi

  local full_path="$PROJECT_PATH/$mod_path"
  local dome_path="$full_path/CONTEXT_DOME.md"
  local generated_at
  generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY-RUN: generaria $dome_path (BF=$bus_factor, risk=$risk_level)"
    return
  fi

  if [[ ! -d "$full_path" ]]; then
    echo "WARN: directorio no existe: $full_path (saltando)" >&2
    return
  fi

  # Un directorio del modulo que sea symlink hacia fuera tampoco vale.
  local real_mod real_proj
  real_mod=$(cd "$full_path" && pwd -P)
  real_proj=$(cd "$PROJECT_PATH" && pwd -P)
  if [[ "$real_mod/" != "$real_proj/"* ]]; then
    echo "WARN: $full_path apunta fuera del proyecto ($real_mod) (saltando)" >&2
    return
  fi

  if [[ -L "$dome_path" ]]; then
    echo "WARN: $dome_path es un symlink; no se sigue (saltando)" >&2
    return
  fi

  # No pisar una cupula revisada a mano (ciclo de vida: revision manual por el
  # knowledge owner y regeneracion posterior). Sin huella valida = editada.
  local old_hash=""
  if [[ -f "$dome_path" ]]; then
    old_hash=$(sed -n 's/^dome_hash: //p' "$dome_path" | head -1)
    if [[ "$FORCE" != "true" && "$old_hash" != "$(dome_digest "$dome_path")" ]]; then
      echo "WARN: $dome_path editada manualmente; no se regenera (usa --force)" >&2
      return
    fi
  fi

  # Extraer datos
  local purpose key_decisions deps runbook_raw runbook_confidence runbook_content recent_commits
  purpose=$(extract_purpose "$mod_path")
  key_decisions=$(extract_key_decisions "$mod_path")
  deps=$(extract_dependencies "$mod_path")
  runbook_raw=$(extract_runbook "$mod_path")
  runbook_confidence=$(echo "$runbook_raw" | head -1 | sed 's/CONFIDENCE://')
  runbook_content=$(echo "$runbook_raw" | tail -n +2)
  recent_commits=$(extract_recent_commits "$mod_path")

  # Plan de distribucion sugerido
  local dist_plan
  case "$plan" in
    urgent) dist_plan="**URGENTE**: BF=$bus_factor. Identificar backup owner esta semana. Usar bus-factor-distribute.sh --target <candidato>." ;;
    high)   dist_plan="Riesgo HIGH. Planificar sesion de pair-review con segundo dev antes del proximo sprint." ;;
    ok)     dist_plan="Riesgo controlado. Revisar trimestralmente." ;;
    *)      dist_plan="Bus factor desconocido en el scan. Revisar manualmente." ;;
  esac

  # Se escribe en un temporal fuera del modulo y se mueve solo si cambia.
  local tmp
  tmp=$(mktemp "$TMP_WORK/dome.XXXXXX")
  cat > "$tmp" << DOMEEOF
---
module: $path_yaml
bus_factor: $bus_factor
risk_level: $risk_level
$owners_yaml
generated_at: $generated_at
spec: SE-252
warnings: $warnings_json
runbook_confidence: $runbook_confidence
dome_hash: PENDING
---

# Context Dome -- $mod_path

## Proposito

$purpose

## Decisiones no obvias

$key_decisions

## Dependencias criticas

$deps

## Runbook minimo

$runbook_content

## Knowledge owners actuales

$owners_table

## Plan de distribucion sugerido

$dist_plan

## Historial de cambios relevantes

$recent_commits
DOMEEOF

  local new_hash
  new_hash=$(dome_digest "$tmp")
  if [[ -f "$dome_path" && "$new_hash" == "$old_hash" ]]; then
    echo "UNCHANGED: $dome_path" >&2
    return
  fi
  set_dome_hash "$tmp" "$new_hash" || { echo "WARN: no se pudo fijar dome_hash en $dome_path (saltando)" >&2; return; }
  # mktemp crea 0600; la cupula es un fichero normal del repo (umask).
  chmod "$(printf '%o' $(( 0666 & ~0$(umask) )))" "$tmp"
  if ! mv -f "$tmp" "$dome_path"; then
    echo "WARN: no se pudo escribir $dome_path (saltando)" >&2
    return
  fi

  echo "OK: $dome_path (BF=$bus_factor, risk=$risk_level, runbook=$runbook_confidence)" >&2
}

# Directorio de trabajo para temporales; se elimina al salir.
TMP_WORK=$(mktemp -d)
trap 'rm -rf "$TMP_WORK"' EXIT

# -- Iterar sobre modulos elegibles -------------------------------------------

while IFS= read -r mod_json; do
  [[ -n "$mod_json" ]] && generate_dome "$mod_json"
done <<< "$MODULES_JSONL"

echo "INFO: generacion completada" >&2
