#!/usr/bin/env bash
set -uo pipefail
# hook-audit-detector: HOOK-04
# (silenciar errores en `source savia-env.sh` es intencional: passthrough
#  silencioso si savia-env no esta disponible)
# subagent-audience-filter.sh — SE-221 Slice 3 — Subagent audience filter
# PreToolUse hook para Task: cuando un subagente arranca, filtra los imports
# lazy candidatos a aquellos donde el subagente esta en `audience`.
#
# Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md (AC-16)
# Inspiracion: CaMeL audience-as-capability + deny-by-default sobre audience-restringido.
#
# Comportamiento:
# - Si el subagente_type esta listado en audience → fragmento candidato.
# - Si audience contiene "all-agents" → fragmento candidato.
# - Si audience contiene "humans-only" → DENEGADO (subagente nunca lee).
# - Sin audience (default implicito = all-agents) → candidato.
# - Subagente desconocido → solo "all-agents" (deny by default).
#
# El hook PASSTHROUGH del input JSON. El filtro se publica como side-effect en
# output/audience-filter.jsonl con la lista filtrada. Otros componentes pueden
# consumir esa lista. NO bloquea ni modifica la invocacion del Task tool.

# Resolucion de paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAVIA_ENV="${SCRIPT_DIR}/../../scripts/savia-env.sh"
if [[ -f "$SAVIA_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$SAVIA_ENV" 2>/dev/null || true
fi
PHYSICAL_WS="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE="${SAVIA_WORKSPACE_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

GRAPH_JSON="${WORKSPACE}/output/context-audience-graph.json"
AUDIT_LOG="${WORKSPACE}/output/audience-filter.jsonl"

# Leer stdin
INPUT=""
if [[ ! -t 0 ]]; then
  if command -v timeout >/dev/null 2>&1 && timeout --version >/dev/null 2>&1; then
    INPUT=$(timeout 3 cat 2>/dev/null) || true
  else
    INPUT=$(cat 2>/dev/null) || true
  fi
fi

passthrough() {
  printf '%s' "$INPUT"
  exit 0
}

[[ -z "$INPUT" ]] && exit 0

# Necesitamos jq y python3
if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  passthrough
fi

# Solo procesamos JSON valido con tool_name=Task
if ! printf '%s' "$INPUT" | jq -e 'type == "object" and has("tool_name")' >/dev/null 2>&1; then
  passthrough
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
if [[ "$TOOL_NAME" != "Task" && "$TOOL_NAME" != "Agent" ]]; then
  passthrough
fi

SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || echo "")
if [[ -z "$SUBAGENT" ]]; then
  passthrough
fi

# Si no hay graph JSON, passthrough (no podemos filtrar)
if [[ ! -f "$GRAPH_JSON" ]]; then
  passthrough
fi

# Calcular lista filtrada
FILTERED_LIST=$(python3 - "$SUBAGENT" "$GRAPH_JSON" "$WORKSPACE" <<'PY'
import sys
import json
import os
import re
from pathlib import Path

subagent = sys.argv[1]
graph_path = sys.argv[2]
ws = sys.argv[3]

try:
    with open(graph_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    print(json.dumps({"subagent": subagent, "allowed": [], "denied": [], "error": "graph load failed"}))
    sys.exit(0)

agents = data.get("agents", {})
# allowed: paths donde el subagente o all-agents apareza en audience
allowed_set = set(agents.get(subagent, []))
allowed_set.update(agents.get("all-agents", []))

# Lista todos los ficheros con audience
all_audience_files = set()
for files in agents.values():
    all_audience_files.update(files)

# denied: ficheros con audience que no incluyen al subagente ni all-agents
denied_set = all_audience_files - allowed_set

# Filtrar files con humans-only - los excluimos del allowed
humans_only = set(agents.get("humans-only", []))
allowed_set -= humans_only
denied_set |= (humans_only & all_audience_files)

# Ficheros sin audience explicita → implicitamente all-agents → ya cubiertos
out = {
    "subagent": subagent,
    "allowed": sorted(allowed_set),
    "denied": sorted(denied_set),
    "n_allowed": len(allowed_set),
    "n_denied": len(denied_set),
}
print(json.dumps(out))
PY
)

# Escribir audit log con timestamp
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
{
  printf '{"ts":"%s","filter":' "$TS"
  printf '%s' "$FILTERED_LIST"
  printf '}\n'
} >> "$AUDIT_LOG" 2>/dev/null || true

# Passthrough — no bloqueamos
passthrough
