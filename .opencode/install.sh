#!/bin/bash
# install.sh — One-line installer for PM-Workspace (Savia) with OpenCode
# Usage: curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/.opencode/install.sh | bash
#
# Environment variables:
#   SAVIA_HOME    — Installation directory (default: ~/savia)
#   SKIP_TESTS    — Set to 1 to skip smoke tests

set -euo pipefail
trap 'echo ""; echo "❌ Installation failed at line $LINENO. Run with bash -x for details."; exit 1' ERR

# --- Colors & helpers -----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${BLUE}🔍${NC} $*"; }
ok()    { echo -e "${GREEN}✅${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠️${NC}  $*"; }
fail()  { echo -e "${RED}❌${NC} $*"; }
step()  { echo -e "\n${BOLD}[$1/5]${NC} $2"; }

# --- Help -----------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "PM-Workspace (Savia) Installer for OpenCode"
  echo ""
  echo "Usage:"
  echo "  curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/.opencode/install.sh | bash"
  echo "  bash install.sh [--skip-tests] [--help]"
  echo ""
  echo "Options:"
  echo "  --skip-tests    Skip smoke tests after installation"
  echo "  --help, -h      Show this help message"
  echo ""
  echo "Environment variables:"
  echo "  SAVIA_HOME      Installation directory (default: ~/savia)"
  echo "  SKIP_TESTS      Set to 1 to skip smoke tests"
  echo ""
  echo "Exit codes:"
  echo "  0  Success"
  echo "  1  Missing prerequisites"
  echo "  2  Network or clone error"
  echo "  3  User cancelled"
  exit 0
fi

[[ "${1:-}" == "--skip-tests" ]] && SKIP_TESTS=1

# --- Banner ---------------------------------------------------------------------
echo -e "${BOLD}"
cat << 'BANNER'

    ,___,        ____             _
    (O,O)       / ___|  __ ___  _(_) __ _
    /)  )      \___ \ / _` \ \/ / |/ _` |
   ( (_ \       ___) | (_| |>  <| | (_| |
    `----'     |____/ \__,_/_/\_\_|\__,_|

    PM-Workspace — OpenCode Installer

BANNER
echo -e "${NC}"

# --- Step 1: Detect OS & architecture ------------------------------------------
step 1 "Detecting operating system..."

ARCH=$(uname -m)
OS="unknown"
DISTRO="unknown"

if [[ "$OSTYPE" == "darwin"* ]]; then
  OS="macos"
  DISTRO="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS="linux"
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="$ID"
  fi
  # Detect WSL
  if grep -qi microsoft /proc/version 2>/dev/null; then
    DISTRO="wsl-$DISTRO"
  fi
else
  fail "Unsupported OS: $OSTYPE. Use install.ps1 for Windows."
  exit 1
fi

ok "OS: ${DISTRO} (${ARCH})"

# --- Step 2: Check prerequisites ------------------------------------------------
step 2 "Checking prerequisites..."

MISSING=0
INSTALL_HINT=""

# Helper: suggest install command per distro
suggest() {
  local pkg="$1"
  case "$DISTRO" in
    macos)          echo "brew install $pkg" ;;
    ubuntu|debian)  echo "sudo apt-get install $pkg" ;;
    fedora|rhel)    echo "sudo dnf install $pkg" ;;
    arch|manjaro)   echo "sudo pacman -S $pkg" ;;
    *)              echo "Install $pkg via your package manager" ;;
  esac
}

for cmd in git curl; do
  if ! command -v "$cmd" &>/dev/null; then
    fail "$cmd not found"
    MISSING=1
    INSTALL_HINT="$INSTALL_HINT\n  $cmd: $(suggest "$cmd")"
  fi
done

if [[ $MISSING -eq 1 ]]; then
  echo ""
  echo -e "${YELLOW}Missing prerequisites. Install with:${NC}"
  echo -e "$INSTALL_HINT"
  echo ""
  read -r -p "Continue anyway? (y/N) " -n 1 REPLY
  echo ""
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    fail "Installation cancelled"
    exit 3
  fi
fi

# Check for Node.js (optional but recommended)
if ! command -v node &>/dev/null; then
  warn "Node.js not found — some scripts may require it"
fi

ok "Prerequisites satisfied"

# --- Step 3: Determine installation directory -----------------------------------
step 3 "Choosing installation directory..."

SAVIA_HOME="${SAVIA_HOME:-$HOME/savia}"
if [[ -d "$SAVIA_HOME" ]]; then
  info "$SAVIA_HOME already exists"
  if [[ -d "$SAVIA_HOME/.git" ]]; then
    ok "Git repository already present — updating..."
    (cd "$SAVIA_HOME" && git pull --quiet 2>/dev/null || warn "Git pull failed (non-critical)")
  else
    warn "$SAVIA_HOME exists but is not a git repo — keeping existing files"
  fi
else
  info "Will install to $SAVIA_HOME"
fi

# --- Step 4: Clone or update repository -----------------------------------------
step 4 "Downloading PM-Workspace..."

REPO_URL="https://github.com/gonzalezpazmonica/pm-workspace.git"

if [[ ! -d "$SAVIA_HOME" ]]; then
  info "Cloning pm-workspace to $SAVIA_HOME..."
  if git clone "$REPO_URL" "$SAVIA_HOME" 2>/dev/null; then
    ok "Cloned to $SAVIA_HOME"
  else
    fail "Clone failed. Check your internet connection and try again."
    exit 2
  fi
fi

# --- Step 5: Install dependencies ----------------------------------------------
step 5 "Installing script dependencies..."

if [[ -f "$SAVIA_HOME/scripts/package.json" ]]; then
  (cd "$SAVIA_HOME/scripts" && npm ci --silent 2>/dev/null) && ok "npm dependencies installed (lockfile)" || warn "npm ci had warnings (non-critical)"
else
  warn "No package.json found in scripts/ — skipping npm install"
fi

# --- Step 6: Verify OpenCode compatibility --------------------------------------
step 6 "Setting up OpenCode compatibility..."

# Ensure .opencode directory exists
if [[ -d "$SAVIA_HOME/.opencode" ]]; then
  ok ".opencode directory already exists"
else
  warn ".opencode directory missing — creating basic structure"
  mkdir -p "$SAVIA_HOME/.opencode"
  cp "$SAVIA_HOME/CLAUDE.md" "$SAVIA_HOME/.opencode/"
  cp "$SAVIA_HOME/CLAUDE.local.md" "$SAVIA_HOME/.opencode/"
  # Create symlinks
  (cd "$SAVIA_HOME/.opencode" && ln -sf ../.claude .claude && ln -sf ../docs docs && ln -sf ../projects projects && ln -sf ../scripts scripts)
  # Create init-pm.sh
  cat > "$SAVIA_HOME/.opencode/init-pm.sh" <<'EOF'
#!/bin/bash
# init-pm.sh — Carga variables de entorno de PM-Workspace para OpenCode
export PM_WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDE_PROJECT_DIR="$PM_WORKSPACE_ROOT"
# Cargar configuración de CLAUDE.md
if [[ -f "$PM_WORKSPACE_ROOT/CLAUDE.md" ]]; then
  source <(grep -E '^AZURE_DEVOPS_' "$PM_WORKSPACE_ROOT/CLAUDE.md" | sed 's/^/export /' | sed 's/ = /="/' | sed 's/$/"/')
fi
# Cargar PAT si existe
if [[ -f "$HOME/.azure/devops-pat" ]]; then
  export AZURE_DEVOPS_PAT_FILE="$HOME/.azure/devops-pat"
fi
echo "PM-Workspace variables cargadas. ORG_URL: ${AZURE_DEVOPS_ORG_URL:-no configurada}"
EOF
  chmod +x "$SAVIA_HOME/.opencode/init-pm.sh"
  ok "Created .opencode directory with symlinks and init-pm.sh"
fi

# --- Step 7: Smoke test --------------------------------------------------------
step 7 "Running smoke test..."

if [[ "${SKIP_TESTS:-0}" == "1" ]]; then
  warn "Skipping tests (SKIP_TESTS=1)"
else
  if [[ -f "$SAVIA_HOME/scripts/test-workspace.sh" ]]; then
    chmod +x "$SAVIA_HOME/scripts/test-workspace.sh"
    if bash "$SAVIA_HOME/scripts/test-workspace.sh" --mock 2>/dev/null; then
      ok "Smoke tests passed"
    else
      warn "Some tests failed (this is normal without Azure DevOps configured)"
    fi
  else
    warn "Test script not found — skipping"
  fi
fi

# --- Step 8: Optional — CodeGraph MCP -------------------------------------------
step 8 "Optional: CodeGraph MCP (AST indexing engine)"

info "CodeGraph indexes source code with tree-sitter and serves it via MCP."
info "Powers the .acm engine and ast-comprehension queries (35% cheaper, 70% fewer tool calls in upstream benchmarks)."
info "It is OPT-IN per project. NOT installed by default."
echo ""
echo "  To enable later for a specific project:"
echo "    1. npm i -g @colbymchenry/codegraph"
echo "    2. cd <project> && codegraph init -i"
echo "    3. Set mcp.codegraph.enabled = true in opencode.json"
echo "    4. Ensure .codegraph/ is in the project .gitignore (mandatory for N4)"
echo ""
echo "  Docs: .opencode/skills/codegraph/SKILL.md"
echo "  Rule: docs/rules/domain/codegraph-confidentiality.md"

if command -v codegraph &>/dev/null; then
  ok "codegraph CLI already on PATH ($(codegraph --version 2>/dev/null || echo unknown))"
else
  info "codegraph CLI not on PATH — install only when you need it"
fi

# --- Done -----------------------------------------------------------------------
# --- SE-372: ofrecer el inicializador interactivo savia setup -----------------
if [[ -f "$SAVIA_HOME/scripts/savia-setup.sh" ]]; then
  echo ""
  if [[ -t 0 && "${SKIP_SETUP:-0}" != "1" ]]; then
    read -r -p "Run interactive 'savia setup' now (configures vaults/MCPs/models)? (y/N) " -n 1 REPLY
    echo ""
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      (cd "$SAVIA_HOME" && bash scripts/savia-setup.sh) || warn "savia setup finalizado con errores (puedes reintentarlo: bash scripts/savia-setup.sh)"
    else
      info "Puedes ejecutarlo después: bash $SAVIA_HOME/scripts/savia-setup.sh  (configura vaults local/remoto, MCPs, modelos, federación)"
    fi
  else
    info "Setup no interactivo — mostrando estado:"
    (cd "$SAVIA_HOME" && bash scripts/savia-setup.sh --check) || true
  fi
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  🦉 Savia is ready for OpenCode!${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo ""
echo "  Next steps:"
echo ""
echo "    1. Load PM-Workspace environment:"
echo "       cd $SAVIA_HOME/.opencode && source init-pm.sh"
echo ""
echo "    2. Start OpenCode:"
echo "       opencode"
echo ""
echo "    3. Load a skill:"
echo "       /skill azure-devops-queries"
echo ""
echo "    4. Use any of the 400+ commands manually:"
echo "       Read .opencode/commands/*.md and follow steps"
echo ""
echo "  For detailed instructions, see:"
echo "    $SAVIA_HOME/.opencode/README.md"
echo ""
echo "  Docs: https://github.com/gonzalezpazmonica/pm-workspace#readme"
echo ""