#!/usr/bin/env bash
# emergency-status.sh — Estado del sistema de emergencia PM-Workspace
# Uso: ./scripts/emergency-status.sh
# Exit: 0 = listo para modo emergencia · 1 = hay problemas (detallados arriba)
set -euo pipefail

MIN_OLLAMA="0.20.0"  # primera version con /v1/messages nativo (docs/savia-dual.md)
ENV_FILE="$HOME/.pm-workspace-emergency.env"
MEMINFO="${EMERGENCY_MEMINFO:-/proc/meminfo}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

echo -e "\n${BOLD}${CYAN}PM-Workspace · Emergency Status${NC}\n"

ISSUES=0

# ── Ollama instalado ─────────────────────────────────────────────────────────
if command -v ollama &>/dev/null; then
  VER=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  if [[ -z "$VER" ]]; then
    echo -e "  ${RED}✗${NC} Ollama instalado, version ilegible (requiere >= $MIN_OLLAMA)"
    ISSUES=$((ISSUES + 1))
  elif [[ "$(printf '%s\n%s\n' "$MIN_OLLAMA" "$VER" | sort -V | head -1)" != "$MIN_OLLAMA" ]]; then
    echo -e "  ${RED}✗${NC} Ollama v$VER no sirve /v1/messages (API Anthropic)"
    echo -e "    → Actualiza a >= $MIN_OLLAMA"
    ISSUES=$((ISSUES + 1))
  else
    echo -e "  ${GREEN}✓${NC} Ollama instalado (v$VER)"
  fi
else
  echo -e "  ${RED}✗${NC} Ollama NO instalado"
  echo -e "    → Ejecuta: ${CYAN}./scripts/emergency-setup.sh${NC}"
  ISSUES=$((ISSUES + 1))
fi

# ── Servidor activo ──────────────────────────────────────────────────────────
if curl -s --max-time 3 http://localhost:11434/api/tags &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Servidor Ollama activo (:11434)"
else
  echo -e "  ${RED}✗${NC} Servidor Ollama NO responde"
  echo -e "    → Ejecuta: ${CYAN}ollama serve${NC}"
  ISSUES=$((ISSUES + 1))
fi

# ── Modelos disponibles ─────────────────────────────────────────────────────
if command -v ollama &>/dev/null; then
  MODELS=$(ollama list 2>/dev/null | tail -n +2 || echo "")
  if [[ -n "$MODELS" ]]; then
    MODEL_COUNT=$(echo "$MODELS" | wc -l | tr -d ' ')
    echo -e "  ${GREEN}✓${NC} Modelos disponibles: ${BOLD}$MODEL_COUNT${NC}"
    echo "$MODELS" | while IFS= read -r line; do
      NAME=$(echo "$line" | awk '{print $1}')
      SIZE=$(echo "$line" | awk '{print $3, $4}')
      echo -e "    · $NAME ($SIZE)"
    done
  else
    echo -e "  ${YELLOW}⚠${NC} No hay modelos descargados"
    echo -e "    → Ejecuta: ${CYAN}ollama pull qwen2.5:7b${NC}"
    ISSUES=$((ISSUES + 1))
  fi
fi

# ── Configuracion generada por emergency-setup.sh ──────────────────────────
# Se lee con grep, sin `source`: el estado no debe ejecutar ni exportar nada.
if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "  ${RED}✗${NC} Falta $ENV_FILE"
  echo -e "    → Ejecuta: ${CYAN}./scripts/emergency-setup.sh${NC}"
  ISSUES=$((ISSUES + 1))
elif command -v ollama &>/dev/null; then
  INSTALLED=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)
  WANTED=$(grep -E '^export (PM_EMERGENCY_MODEL|ANTHROPIC_DEFAULT_(OPUS|SONNET|HAIKU)_MODEL|CLAUDE_CODE_SUBAGENT_MODEL)=' "$ENV_FILE" \
    | sed -E 's/^[^=]+="?([^"]*)"?$/\1/' | awk 'NF && !seen[$0]++' || true)
  for m in $WANTED; do
    if ! grep -qxF "$m" <<< "$INSTALLED"; then
      echo -e "  ${RED}✗${NC} Modelo configurado y no descargado: $m"
      echo -e "    → Ejecuta: ${CYAN}ollama pull $m${NC}"
      ISSUES=$((ISSUES + 1))
    fi
  done
fi

# ── Variables de entorno ────────────────────────────────────────────────────
echo ""
if [[ "${PM_EMERGENCY_MODE:-}" == "active" ]]; then
  echo -e "  ${GREEN}✓${NC} Modo emergencia: ${BOLD}ACTIVO${NC}"
  echo -e "    ANTHROPIC_BASE_URL=${CYAN}${ANTHROPIC_BASE_URL:-no configurado}${NC}"
  echo -e "    PM_EMERGENCY_MODEL=${CYAN}${PM_EMERGENCY_MODEL:-no configurado}${NC}"
  # Claude Code añade /v1/messages a la base: una base con /v1 pide /v1/v1/messages
  if [[ "${ANTHROPIC_BASE_URL:-}" =~ /v1/?$ ]]; then
    echo -e "  ${RED}✗${NC} ANTHROPIC_BASE_URL acaba en /v1: Claude Code pediria /v1/v1/messages"
    echo -e "    → Usa ${CYAN}http://localhost:11434${NC} (sin /v1)"
    ISSUES=$((ISSUES + 1))
  fi
  if [[ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    echo -e "  ${RED}✗${NC} ANTHROPIC_AUTH_TOKEN vacio: Claude Code enviaria tus credenciales reales a localhost o pediria /login"
    echo -e "    → ${CYAN}source $ENV_FILE${NC} (fija un placeholder)"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo -e "  ${YELLOW}○${NC} Modo emergencia: INACTIVO"
  echo -e "    → Para activar: ${CYAN}source ~/.pm-workspace-emergency.env${NC}"
fi

# ── Hardware ────────────────────────────────────────────────────────────────
echo ""
# Sin /proc (macOS) awk no imprime nada y sale 0: hay que caer a sysctl a mano
RAM_KB=$(awk '/^MemTotal:/ {print $2}' "$MEMINFO" 2>/dev/null || true)
[[ -z "$RAM_KB" ]] && RAM_KB=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024)}' || true)
RAM_FREE_KB=$(awk '/^MemAvailable:/ {print $2}' "$MEMINFO" 2>/dev/null || true)
RAM_GB=$(( (${RAM_KB:-0} + 524288) / 1048576 ))
RAM_FREE_GB=$(( ${RAM_FREE_KB:-0} / 1048576 ))
echo -e "  RAM total: ${BOLD}${RAM_GB}GB${NC} · Libre: ${BOLD}${RAM_FREE_GB}GB${NC}"

if command -v nvidia-smi &>/dev/null; then
  # nvidia-smi puede estar instalado sin driver cargado (sale 9): con pipefail+set -e
  # abortaba el informe sin resumen. Un fallo aqui no es un problema del modo emergencia.
  GPU=$(nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader 2>/dev/null | head -1 || true)
  if [[ -n "$GPU" ]]; then
    echo -e "  GPU: ${BOLD}$GPU${NC}"
  else
    echo -e "  GPU no disponible (nvidia-smi sin respuesta)"
  fi
else
  echo -e "  GPU no disponible (nvidia-smi no instalado)"
fi

# ── Resumen ─────────────────────────────────────────────────────────────────
echo ""
if [[ $ISSUES -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}Sistema listo para modo emergencia.${NC}"
else
  echo -e "${YELLOW}${BOLD}$ISSUES problema(s) detectado(s). Revisa las sugerencias arriba.${NC}"
  echo ""
  exit 1
fi
echo ""
