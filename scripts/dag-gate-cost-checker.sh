#!/usr/bin/env bash
# dag-gate-cost-checker.sh
#
# SE-237: Verifica que en un DAG definido en YAML/JSON, los gates CHEAP
# aparecen antes que MEDIUM y EXPENSIVE (patrón coarse-to-fine).
#
# Uso:
#   dag-gate-cost-checker.sh plan.yaml
#   dag-gate-cost-checker.sh plan.json
#   dag-gate-cost-checker.sh < plan.yaml
#
# Formato de input (YAML o JSON):
#   stages:
#     - name: validate-spec
#       gate_type: CHEAP
#     - name: test-runner
#       gate_type: MEDIUM
#     - name: court-orchestrator
#       gate_type: EXPENSIVE
#
# O con un array plano de steps (se infiere el tipo por nombre):
#   steps:
#     - feasibility-probe
#     - test-runner
#     - court-orchestrator
#
# Exit codes:
#   0 — orden correcto (o DAG vacío)
#   1 — violación de orden detectada
#   2 — error de sintaxis en input
#
# Ref: docs/propuestas/SE-237-coarse-to-fine-dag-pattern.md
#      docs/rules/domain/coarse-to-fine-gates.md

set -euo pipefail

# ── Clasificación de agentes conocidos ──────────────────────────────────────
# Cada agente tiene un coste: CHEAP=1, MEDIUM=2, EXPENSIVE=3
declare -A AGENT_COST
# CHEAP
AGENT_COST["dag-typing-validate"]=1
AGENT_COST["dag-typing-validate.sh"]=1
AGENT_COST["spec-validator"]=1
AGENT_COST["spec-validator.sh"]=1
AGENT_COST["hashline-guard"]=1
AGENT_COST["hashline-guard.sh"]=1
AGENT_COST["validate-bash-global"]=1
AGENT_COST["validate-bash-global.sh"]=1
AGENT_COST["block-force-push"]=1
AGENT_COST["spec-id-duplicates-check"]=1
AGENT_COST["spec-id-duplicates-check.sh"]=1
AGENT_COST["validate-spec"]=1
AGENT_COST["validate-spec.sh"]=1
AGENT_COST["bash-syntax-check"]=1
AGENT_COST["syntax-check"]=1
AGENT_COST["lint"]=1

# MEDIUM
AGENT_COST["feasibility-probe"]=2
AGENT_COST["test-runner"]=2
AGENT_COST["dev-orchestrator"]=2
AGENT_COST["coherence-validator"]=2
AGENT_COST["lint-checks"]=2
AGENT_COST["unit-tests"]=2
AGENT_COST["fast-tests"]=2

# EXPENSIVE
AGENT_COST["court-orchestrator"]=3
AGENT_COST["truth-tribunal-orchestrator"]=3
AGENT_COST["security-attacker"]=3
AGENT_COST["security-defender"]=3
AGENT_COST["dotnet-developer"]=3
AGENT_COST["python-developer"]=3
AGENT_COST["typescript-developer"]=3
AGENT_COST["go-developer"]=3
AGENT_COST["java-developer"]=3
AGENT_COST["rust-developer"]=3
AGENT_COST["ruby-developer"]=3
AGENT_COST["php-developer"]=3
AGENT_COST["mobile-developer"]=3
AGENT_COST["frontend-developer"]=3
AGENT_COST["truth-tribunal"]=3
AGENT_COST["security-audit"]=3

# ── Función: obtener coste de un gate ────────────────────────────────────────
get_gate_cost() {
  local name="$1"
  local type="${2:-}"

  # Si se especifica el tipo explícitamente
  case "${type^^}" in
    CHEAP) echo 1; return ;;
    MEDIUM) echo 2; return ;;
    EXPENSIVE) echo 3; return ;;
  esac

  # Buscar por nombre en la tabla
  if [[ -n "${AGENT_COST[$name]+x}" ]]; then
    echo "${AGENT_COST[$name]}"
    return
  fi

  # Inferir por patrones de nombre
  if [[ "$name" =~ (validate|lint|check|guard|syntax|hash) ]]; then
    echo 1  # CHEAP
  elif [[ "$name" =~ (test|probe|orchestrat|plan) ]]; then
    echo 2  # MEDIUM
  elif [[ "$name" =~ (developer|court|tribunal|attacker|defender|audit) ]]; then
    echo 3  # EXPENSIVE
  else
    echo 2  # MEDIUM por defecto si no se reconoce
  fi
}

# ── Función: nombre legible del coste ────────────────────────────────────────
cost_name() {
  case "$1" in
    1) echo "CHEAP" ;;
    2) echo "MEDIUM" ;;
    3) echo "EXPENSIVE" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# ── Leer input ───────────────────────────────────────────────────────────────
INPUT_FILE=""
if [[ $# -gt 0 ]]; then
  if [[ -f "$1" ]]; then
    INPUT_FILE="$1"
  else
    echo "ERROR: fichero no encontrado: $1" >&2
    exit 2
  fi
fi

# ── Extraer stages/steps del DAG con Python ──────────────────────────────────
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 requerido" >&2
  exit 2
fi

# Un único parser para fichero y stdin. Antes había tres copias: la de stdin recibía el propio script
# por stdin (python3 - <<EOF) y siempre leía vacío → «DAG vacío», exit 0; la de fichero perdía el
# gate_type de las líneas de continuación (se añadía una copia del item); y un JSON roto daba exit 0.
PARSER=$(cat <<'PYTHON_EOF'
import sys, json
src = open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read()
if not src.strip():
    sys.exit(0)

def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)

if src.lstrip()[:1] in "{[":
    try:
        data = json.loads(src)
    except json.JSONDecodeError as exc:
        fail(f"JSON inválido: {exc}")
else:
    # YAML mínimo sin dependencias: "clave:" en columna 0, "- valor" o "- k: v" con continuaciones "k: v".
    data, section, item = {}, None, None
    for line in src.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not line[0].isspace():
            section, item = None, None
            if stripped.endswith(":"):
                section = stripped[:-1].strip()
                data[section] = []
            continue
        if section is None:
            continue
        if stripped.startswith("- "):
            value = stripped[2:].strip()
            if ":" in value and value[0] not in "\"'":
                k, v = value.split(":", 1)
                item = {k.strip(): v.strip().strip("\"'")}
                data[section].append(item)
            else:
                item = None
                data[section].append(value.strip("\"'"))
        elif ":" in stripped and item is not None:
            k, v = stripped.split(":", 1)
            item[k.strip()] = v.strip().strip("\"'")

if not isinstance(data, dict):
    fail("el DAG debe ser un objeto con stages, steps, pipeline o gates")

for key in ("stages", "steps", "pipeline", "gates"):
    items = data.get(key)
    if not items:
        continue
    if not isinstance(items, list):
        fail(f"'{key}' debe ser una lista")
    for it in items:
        if isinstance(it, dict):
            name = str(it.get("name", it.get("id", "unknown")))
            gate = str(it.get("gate_type", it.get("type", "")) or "")
        elif isinstance(it, str):
            name, gate = it, ""
        else:
            fail(f"elemento no válido en '{key}': {it!r}")
        print(f"{name.replace('|', '/')}|{gate}")
    break
PYTHON_EOF
)

if [[ -n "$INPUT_FILE" ]]; then
  DAG_STEPS=$(python3 -c "$PARSER" "$INPUT_FILE") || exit 2
else
  DAG_STEPS=$(python3 -c "$PARSER") || exit 2
fi

# ── DAG vacío → PASS ─────────────────────────────────────────────────────────
if [[ -z "$DAG_STEPS" ]]; then
  echo "OK: DAG vacío — sin stages que verificar"
  exit 0
fi

# ── Verificar orden de coste ──────────────────────────────────────────────────
VIOLATIONS=()
MAX_COST_SEEN=0
PREV_NAME=""
PREV_COST=0

while IFS='|' read -r step_name gate_type; do
  [[ -z "$step_name" ]] && continue
  
  step_cost=$(get_gate_cost "$step_name" "$gate_type")
  step_type=$(cost_name "$step_cost")
  
  if [[ "$step_cost" -lt "$MAX_COST_SEEN" ]]; then
    VIOLATIONS+=("VIOLATION: '${step_name}' (${step_type}, cost=${step_cost}) aparece después de '${PREV_NAME}' ($(cost_name $PREV_COST), cost=${PREV_COST})")
  fi
  
  if [[ "$step_cost" -gt "$MAX_COST_SEEN" ]]; then
    MAX_COST_SEEN="$step_cost"
  fi
  
  PREV_NAME="$step_name"
  PREV_COST="$step_cost"
  
done <<< "$DAG_STEPS"

# ── Reportar resultado ────────────────────────────────────────────────────────
if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
  echo "OK: orden coarse-to-fine correcto"
  exit 0
else
  echo "ERROR: ${#VIOLATIONS[@]} violación(es) de orden coarse-to-fine detectada(s):"
  for v in "${VIOLATIONS[@]}"; do
    echo "  - $v"
  done
  echo ""
  echo "Regla: los gates CHEAP deben aparecer antes que MEDIUM, y MEDIUM antes que EXPENSIVE."
  echo "Ref: docs/rules/domain/coarse-to-fine-gates.md"
  exit 1
fi
