#!/usr/bin/env bash
# install.sh — SaviaVaults installer (Linux / macOS)
# Copyright (c) 2026 Savia. MIT License.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[savia-vaults]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

info "SaviaVaults Installer"
echo ""

# ── Check Node.js ──
if ! command -v node &>/dev/null; then
  err "Node.js not found. Install Node.js 22+ from https://nodejs.org"
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt 22 ]]; then
  err "Node.js $NODE_VERSION detected. SaviaVaults requires Node.js 22+. Install from https://nodejs.org"
fi
info "Node.js $(node -v) ✓"

# ── Check Git ──
if ! command -v git &>/dev/null; then
  err "Git not found. Install git from https://git-scm.com"
fi
info "Git $(git --version | cut -d' ' -f3) ✓"

# ── Check npm ──
if ! command -v npm &>/dev/null; then
  err "npm not found. Reinstall Node.js (npm comes bundled)."
fi
info "npm $(npm -v) ✓"
echo ""

# ── Install globally from this checkout ──
# SE-465 S3 (alerta SE-442 #83): savia-vaults no está publicado en el registro
# npm; `npm install -g savia-vaults` sin versión instalaba lo que hubiera bajo
# ese nombre. Se instala desde la fuente local con el lock versionado.
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
info "Installing savia-vaults from $PROJECT_DIR..."
(cd "$PROJECT_DIR" && npm ci 2>&1 && npm run build 2>&1 && npm link 2>&1) || {
  warn "Install from source failed. Run from the checkout: node $PROJECT_DIR/dist/cli/index.js <command>"
  exit 0
}

info "SaviaVaults installed successfully!"
echo ""

# ── Register vaults CLI symlink ──
VAULTS_SCRIPT="${SCRIPT_DIR}/vaults"
if [[ -f "$VAULTS_SCRIPT" ]]; then
  if [[ -w /usr/local/bin ]]; then
    ln -sf "$VAULTS_SCRIPT" /usr/local/bin/vaults 2>/dev/null && info "vaults command registered: /usr/local/bin/vaults" || warn "Could not symlink to /usr/local/bin. Add to PATH manually: export PATH=\"$SCRIPT_DIR:\$PATH\""
  else
    warn "No write permission to /usr/local/bin. Add to PATH: export PATH=\"$SCRIPT_DIR:\$PATH\""
  fi
fi

info "Quick start:"
echo "  savia-vaults init my-knowledge"
echo "  cd vaults/my-knowledge"
echo "  savia-vaults serve --transport mcp"
echo ""
info "Documentation: https://github.com/gonzalezpazmonica/savia-vaults"
