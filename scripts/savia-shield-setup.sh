#!/usr/bin/env bash
# savia-shield-setup.sh — Instalador de Savia Shield
# Verifica dependencias, instala Ollama + modelo, configura hooks
set -uo pipefail

# Source portable OS detection
SCRIPT_DIR_SS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_SS/lib/os-detect.sh" 2>/dev/null && setup_paths || true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

echo -e "\n${BOLD}${CYAN}Savia Shield — Setup${NC}\n"

ERRORS=0; WARNINGS=0
check_ok()   { echo -e "  ${GREEN}OK${NC} $1"; }
check_warn() { echo -e "  ${YELLOW}WARN${NC} $1"; WARNINGS=$((WARNINGS+1)); }
check_fail() { echo -e "  ${RED}FAIL${NC} $1"; ERRORS=$((ERRORS+1)); }

# 1. Python 3
echo -e "${BOLD}[1/6]${NC} Python 3..."
if command -v python3 >/dev/null 2>&1; then
  PY_VER=$(python3 --version 2>&1)
  check_ok "$PY_VER"
else
  check_fail "Python 3 no encontrado. Instala Python 3.12+"
fi

# 2. jq
echo -e "${BOLD}[2/6]${NC} jq..."
if command -v jq >/dev/null 2>&1; then
  check_ok "$(jq --version 2>&1)"
else
  check_fail "jq no encontrado. Instala con: winget install jqlang.jq"
fi

# 3. Ollama
echo -e "${BOLD}[3/6]${NC} Ollama..."
OLLAMA_CMD=""
for p in ollama "$HOME/AppData/Local/Programs/Ollama/ollama" /usr/local/bin/ollama; do
  if command -v "$p" >/dev/null 2>&1 || [ -f "$p" ]; then
    OLLAMA_CMD="$p"; break
  fi
done
if [ -n "$OLLAMA_CMD" ]; then
  check_ok "$($OLLAMA_CMD --version 2>&1)"
else
  check_warn "Ollama no encontrado. Instalando..."
  if command -v winget >/dev/null 2>&1; then
    winget install Ollama.Ollama --accept-package-agreements --accept-source-agreements 2>&1 | tail -3
    check_ok "Ollama instalado via winget"
  elif [[ "$(uname)" == "Darwin" ]]; then
    brew install ollama 2>&1 | tail -3
    check_ok "Ollama instalado via brew"
  else
    # SE-465 S2: instalador de una etiqueta fija, verificado por SHA-256 antes de ejecutar.
    source "$SCRIPT_DIR_SS/lib/verified-installer.sh"
    if savia_install_ollama_pinned 2>&1 | tail -3; [ "${PIPESTATUS[0]}" -eq 0 ]; then
      check_ok "Ollama $OLLAMA_PINNED_VERSION instalado (instalador verificado)"
    else
      check_warn "Instalación de Ollama fallida"
    fi
  fi
fi

# 4. Modelo qwen2.5:7b
echo -e "${BOLD}[4/6]${NC} Modelo qwen2.5:7b..."
if curl -s --max-time 3 http://localhost:11434/api/tags 2>/dev/null | grep -q "qwen2.5:7b"; then
  check_ok "Modelo ya descargado"
else
  check_warn "Descargando modelo qwen2.5:7b (~4.7GB)..."
  ollama pull qwen2.5:7b 2>&1 | tail -3
  check_ok "Modelo descargado"
fi

# 5. Presidio + spaCy
echo -e "${BOLD}[5/6]${NC} Presidio + spaCy..."
if python3 -c "import presidio_analyzer" 2>/dev/null; then
  check_ok "Presidio instalado"
else
  check_warn "Instalando Presidio..."
  # SE-465 S4: versiones y hashes fijados en un lock versionado.
  pip install --require-hashes -r "$SCRIPT_DIR_SS/requirements/shield-presidio.lock.txt" 2>&1 | tail -3
  check_ok "Presidio instalado"
fi
if python3 -c "import spacy; spacy.load('es_core_news_md')" 2>/dev/null; then
  check_ok "spaCy modelo espanol instalado"
else
  check_warn "Descargando spaCy modelo espanol..."
  python3 -m spacy download es_core_news_md 2>&1 | tail -3
  check_ok "spaCy modelo espanol descargado"
fi

# 6. Verificar hooks
echo -e "${BOLD}[6/8]${NC} Hooks registrados..."
if grep -q "data-sovereignty-gate" .claude/settings.json 2>/dev/null; then
  check_ok "Gate hook registrado"
else
  check_fail "Gate hook no encontrado en .claude/settings.json"
fi

# 7. Auth token
echo -e "${BOLD}[7/8]${NC} Auth token..."
if [ -f "$HOME/.savia/shield-token" ]; then
  check_ok "Token presente ($(wc -c < "$HOME/.savia/shield-token") bytes)"
else
  check_warn "Generando token de autenticacion..."
  mkdir -p "$HOME/.savia"
  python3 -c "import secrets; print(secrets.token_hex(32))" > "$HOME/.savia/shield-token"
  chmod 600 "$HOME/.savia/shield-token"
  check_ok "Token generado"
fi

# 8. Start daemons
echo -e "${BOLD}[8/8]${NC} Daemons..."
if curl -sf --max-time 2 http://127.0.0.1:8444/health >/dev/null 2>&1; then
  check_ok "Shield daemon ya corriendo"
else
  check_warn "Arrancando Shield daemon..."
  python3 scripts/savia-shield-daemon.py --port 8444 2>/dev/null &
  sleep 15
  if curl -sf --max-time 2 http://127.0.0.1:8444/health >/dev/null 2>&1; then
    check_ok "Shield daemon arrancado"
  else
    check_fail "Shield daemon no arranco"
  fi
fi
if curl -sf --max-time 2 http://127.0.0.1:8443/ -o /dev/null 2>&1; then
  check_ok "Shield proxy ya corriendo"
else
  check_warn "Arrancando Shield proxy..."
  python3 scripts/savia-shield-proxy.py --port 8443 2>/dev/null &
  sleep 2
  check_ok "Shield proxy arrancado"
fi

# Resumen
echo ""
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}${BOLD}Savia Shield instalado y operativo${NC}"
  echo -e "  Errores: 0 | Avisos: $WARNINGS"
  echo -e "\n  Para activar el proxy (proteccion de conversacion):"
  echo -e "  ${CYAN}export ANTHROPIC_BASE_URL=http://127.0.0.1:8443${NC}"
  echo -e "\n  Verificar: ${CYAN}bats tests/test-data-sovereignty.bats${NC}"
  echo -e "  Documento: ${CYAN}docs/savia-shield.md${NC}"
else
  echo -e "${RED}${BOLD}Savia Shield: $ERRORS errores encontrados${NC}"
  echo -e "  Corrige los errores y ejecuta de nuevo."
fi
