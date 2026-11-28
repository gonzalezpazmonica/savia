#!/usr/bin/env bash
# emergency-setup.sh — Setup rápido de LLM local para modo emergencia
# Soporta: Linux (amd64/arm64), macOS (Intel/Apple Silicon), Windows (usar .ps1)
set -euo pipefail

# Source portable OS detection + OLLAMA_BIN default
SCRIPT_DIR_EM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_EM/lib/os-detect.sh" 2>/dev/null && setup_paths || true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

MODEL=""
MIN_OLLAMA="0.20.0"  # primera version con /v1/messages nativo (docs/savia-dual.md)
MEMINFO="${EMERGENCY_MEMINFO:-/proc/meminfo}"
iso_date() { date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S+00:00"; }
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
  echo -e "${BOLD}PM-Workspace Emergency Setup${NC} — Instala Ollama + LLM local"
  echo "Uso: $0 [--model MODEL]. Soporta Linux/macOS. Windows: usar .ps1"
  echo "Modelos: 8GB→qwen2.5:3b | 16GB→qwen2.5:7b (default) | 32GB+→qwen2.5:14b"
  echo "--model fija un unico modelo para todos los alias. Requiere Ollama >= 0.20.0"; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      [[ -n "${2:-}" ]] || { echo "ERROR: --model requiere un valor (p. ej. --model qwen2.5:3b)" >&2; exit 2; }
      MODEL="$2"; shift 2 ;;
    *) echo "ERROR: argumento desconocido: $1 (ver --help)" >&2; exit 2 ;;
  esac
done
CACHE_DIR="$HOME/.pm-workspace-emergency"; OFFLINE=false

echo -e "\n${BOLD}${CYAN}PM-Workspace · Emergency Setup${NC}\n"

# ── 1. Detectar sistema y conectividad ───────────────────────────────────────
echo -e "${BLUE}[1/5]${NC} Detectando sistema..."
OS="$(uname -s)"; ARCH="$(uname -m)"
if [[ "$OS" == "Darwin" ]]; then
  RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0); RAM_GB=$((RAM_BYTES / 1024 / 1024 / 1024))
else
  # Redondeo al GB mas cercano: un equipo de 16 GB reporta ~15.6 GiB en MemTotal
  RAM_KB=$(awk '/^MemTotal:/ {print $2}' "$MEMINFO" 2>/dev/null || true)
  RAM_GB=$(( (${RAM_KB:-0} + 524288) / 1048576 ))
fi
echo -e "  OS: ${GREEN}$OS${NC} · Arch: ${GREEN}$ARCH${NC} · RAM: ${GREEN}${RAM_GB}GB${NC}"
[[ $RAM_GB -lt 8 ]] && echo -e "  ${YELLOW}⚠ RAM < 8GB${NC}"

# Model alias mapping (opus/sonnet/haiku → local models)
if [[ $RAM_GB -ge 32 ]]; then
  MODEL_LARGE="qwen2.5:14b"; MODEL_MEDIUM="qwen2.5:7b"; MODEL_SMALL="qwen2.5:3b"
elif [[ $RAM_GB -ge 16 ]]; then
  MODEL_LARGE="qwen2.5:7b"; MODEL_MEDIUM="qwen2.5:7b"; MODEL_SMALL="qwen2.5:3b"
else
  MODEL_LARGE="qwen2.5:3b"; MODEL_MEDIUM="qwen2.5:3b"; MODEL_SMALL="qwen2.5:3b"
fi
# --model fija un unico modelo para todos los alias; sin el, el default es el del tramo
if [[ -n "$MODEL" ]]; then
  MODEL_LARGE="$MODEL"; MODEL_MEDIUM="$MODEL"; MODEL_SMALL="$MODEL"
else
  MODEL="$MODEL_LARGE"
fi

# GPU
GPU_INFO="ninguna"
command -v nvidia-smi &>/dev/null && GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "NVIDIA")
[[ "$OS" == "Darwin" ]] && [[ "$ARCH" == "arm64" ]] && GPU_INFO="Apple Silicon (Metal)"
echo -e "  GPU: ${GREEN}$GPU_INFO${NC}"

# Conectividad
if curl -s --max-time 5 https://ollama.ai >/dev/null 2>&1; then
  echo -e "  Internet: ${GREEN}conectado${NC}"
else
  OFFLINE=true; echo -e "  Internet: ${YELLOW}SIN CONEXIÓN${NC}"
  [[ -d "$CACHE_DIR" && -f "$CACHE_DIR/.plan-executed" ]] \
    && echo -e "  ${GREEN}✓${NC} Caché local detectada" \
    || { echo -e "  ${RED}✗${NC} Sin caché. Ejecuta ${CYAN}./scripts/emergency-plan.sh${NC} con conexión."; exit 1; }
fi

# ── 2. Instalar Ollama ──────────────────────────────────────────────────────
echo -e "\n${BLUE}[2/5]${NC} Verificando Ollama..."
if command -v ollama &>/dev/null; then
  OLLAMA_VER=$(ollama --version 2>/dev/null || echo "desconocida")
  echo -e "  ${GREEN}✓${NC} Ollama instalado ($OLLAMA_VER)"
else
  if [[ "$OFFLINE" == true ]]; then
    OLLAMA_BIN="$CACHE_DIR/ollama-bin"
    if [[ -f "$OLLAMA_BIN" ]]; then
      echo -e "  ${YELLOW}→${NC} Instalando Ollama desde caché local..."
      if [[ "$OS" == "Darwin" ]]; then
        mkdir -p "$HOME/.local/bin" && cp "$OLLAMA_BIN" "$HOME/.local/bin/ollama"
        echo -e "  ${YELLOW}ℹ${NC} Añade ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC} a tu shell"
      else
        mkdir -p "$HOME/.local/bin"
        sudo cp "$OLLAMA_BIN" /usr/local/bin/ollama 2>/dev/null || cp "$OLLAMA_BIN" "$HOME/.local/bin/ollama"
      fi
      echo -e "  ${GREEN}✓${NC} Ollama instalado desde caché"
    else
      echo -e "  ${RED}✗${NC} No hay binario en caché. Ejecuta ${CYAN}emergency-plan.sh${NC} con conexión."; exit 1
    fi
  else
    echo -e "  ${YELLOW}→${NC} Instalando Ollama..."
    if [[ "$OS" == "Linux" ]]; then
      # SE-465 S2: instalador de una etiqueta fija, verificado por SHA-256 antes de ejecutar.
      source "$SCRIPT_DIR_EM/lib/verified-installer.sh"
      savia_install_ollama_pinned || { echo -e "  ${RED}✗${NC} Instalación de Ollama fallida"; exit 1; }
    elif [[ "$OS" == "Darwin" ]]; then
      # macOS: descargar tgz y extraer binario
      TMP_TGZ="$(mktemp)"; curl -fSL "https://ollama.com/download/ollama-darwin.tgz" -o "$TMP_TGZ"
      TMP_EX="$(mktemp -d)"; tar xzf "$TMP_TGZ" -C "$TMP_EX" 2>/dev/null
      mkdir -p "$HOME/.local/bin" && cp "$TMP_EX/ollama" "$HOME/.local/bin/ollama" && chmod +x "$HOME/.local/bin/ollama"
      rm -rf "$TMP_EX" "$TMP_TGZ"
      export PATH="$HOME/.local/bin:$PATH"
      echo -e "  ${YELLOW}ℹ${NC} Añade ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC} a ~/.zshrc"
    else
      echo -e "  ${RED}✗${NC} SO no soportado. En Windows usa ${CYAN}scripts/emergency-setup.ps1${NC}"; exit 1
    fi
  fi
  echo -e "  ${GREEN}✓${NC} Ollama instalado"
fi

# Claude Code pide <base>/v1/messages: Ollama solo lo sirve desde MIN_OLLAMA
OLLAMA_VERSION=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [[ -z "$OLLAMA_VERSION" ]]; then
  echo -e "  ${YELLOW}⚠${NC} No se pudo leer la version de Ollama; requiere >= $MIN_OLLAMA"
elif [[ "$(printf '%s\n%s\n' "$MIN_OLLAMA" "$OLLAMA_VERSION" | sort -V | head -1)" != "$MIN_OLLAMA" ]]; then
  echo -e "  ${RED}✗${NC} Ollama $OLLAMA_VERSION no sirve /v1/messages (API Anthropic). Actualiza a >= $MIN_OLLAMA"
  exit 1
fi

# ── 3. Iniciar servidor ─────────────────────────────────────────────────────
echo -e "\n${BLUE}[3/5]${NC} Verificando servidor Ollama..."
if curl -s http://localhost:11434/api/tags &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Servidor activo en :11434"
else
  echo -e "  ${YELLOW}→${NC} Iniciando servidor..."
  ollama serve &>/dev/null &
  sleep 3
  curl -s http://localhost:11434/api/tags &>/dev/null \
    && echo -e "  ${GREEN}✓${NC} Servidor iniciado" \
    || { echo -e "  ${RED}✗${NC} No se pudo iniciar. Ejecuta: ollama serve"; exit 1; }
fi

# ── 4. Verificar/descargar modelos ───────────────────────────────────────────
# Todos los alias deben resolver a un modelo presente: Claude Code usa haiku
# para tareas de fondo aunque el modelo principal sea otro.
installed_models() { ollama list 2>/dev/null | tail -n +2 | awk '{print $1}'; }
has_model() { installed_models | grep -qxF "$1"; }
NEEDED=$(printf '%s\n' "$MODEL" "$MODEL_LARGE" "$MODEL_MEDIUM" "$MODEL_SMALL" | awk '!seen[$0]++')
echo -e "\n${BLUE}[4/5]${NC} Verificando modelos: ${CYAN}$(echo $NEEDED)${NC}..."
for m in $NEEDED; do
  if has_model "$m"; then
    echo -e "  ${GREEN}✓${NC} $m disponible"
  elif [[ "$OFFLINE" == true ]]; then
    AVAILABLE=$(installed_models | head -1)
    if [[ -z "$AVAILABLE" ]]; then
      echo -e "  ${RED}✗${NC} No hay modelos cacheados. Ejecuta emergency-plan.sh con conexión."; exit 1
    fi
    echo -e "  ${YELLOW}⚠${NC} $m no disponible offline. Usando: ${CYAN}$AVAILABLE${NC}"
    [[ "$MODEL" == "$m" ]] && MODEL="$AVAILABLE"
    [[ "$MODEL_LARGE" == "$m" ]] && MODEL_LARGE="$AVAILABLE"
    [[ "$MODEL_MEDIUM" == "$m" ]] && MODEL_MEDIUM="$AVAILABLE"
    [[ "$MODEL_SMALL" == "$m" ]] && MODEL_SMALL="$AVAILABLE"
  else
    echo -e "  ${YELLOW}→${NC} Descargando $m (puede tardar minutos)..."
    ollama pull "$m" || { echo -e "  ${RED}✗${NC} Fallo al descargar $m"; exit 1; }
    echo -e "  ${GREEN}✓${NC} $m descargado"
  fi
done

# ── 5. Configurar variables ─────────────────────────────────────────────────
echo -e "\n${BLUE}[5/5]${NC} Configuración para Claude Code..."
ENV_FILE="$HOME/.pm-workspace-emergency.env"
cat > "$ENV_FILE" << ENVEOF
# PM-Workspace Emergency Mode — generado $(iso_date)
export ANTHROPIC_BASE_URL="http://localhost:11434"
# Placeholder: Ollama no valida credenciales; evita que Claude Code envie la
# clave u OAuth reales a localhost o se niegue a arrancar sin login.
export ANTHROPIC_AUTH_TOKEN="ollama"
export ANTHROPIC_API_KEY=""
export PM_EMERGENCY_MODEL="$MODEL"
export PM_EMERGENCY_MODE="active"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL_LARGE"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL_MEDIUM"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_SMALL"
export CLAUDE_CODE_SUBAGENT_MODEL="$MODEL_MEDIUM"
ENVEOF

echo -e "  ${GREEN}✓${NC} Variables en ${CYAN}$ENV_FILE${NC}"
echo -e "\n${GREEN}${BOLD}✓ Setup completado${NC}"
echo -e "Activar: ${CYAN}source $ENV_FILE${NC}"
echo -e "Estado:  ${CYAN}./scripts/emergency-status.sh${NC}"
