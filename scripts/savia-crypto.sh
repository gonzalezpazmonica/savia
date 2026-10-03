#!/bin/bash
# savia-crypto.sh — RSA + AES hybrid encryption using openssl only
# Uso: bash scripts/savia-crypto.sh {keygen|encrypt|decrypt|export-pubkey} [args]
#
# E2E encryption for Company Savia messaging.
# RSA-4096 for key exchange, AES-256-CBC for message body.
# Zero external dependencies — openssl only.

set -euo pipefail

# ── Constantes ──────────────────────────────────────────────────────
KEYS_DIR="$HOME/.pm-workspace/savia-keys"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colores ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}ℹ${NC}  $1"; }
log_ok()    { echo -e "${GREEN}✅${NC} $1"; }
log_warn()  { echo -e "${YELLOW}⚠️${NC}  $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

# ── Source: encrypt and decrypt operations ───────────────────────
source "$SCRIPTS_DIR/savia-crypto-ops.sh"

# ── Keygen: generate RSA-4096 keypair ───────────────────────────────
do_keygen() {
  local force="${1:-}"

  if [ -f "$KEYS_DIR/private.pem" ] && [ "$force" != "--force" ]; then
    log_warn "Keypair already exists at $KEYS_DIR/"
    log_info "Use --force to regenerate (WARNING: old encrypted messages become unreadable)"
    return 1
  fi

  mkdir -p "$KEYS_DIR"

  log_info "Generating RSA-4096 keypair..."
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
    -out "$KEYS_DIR/private.pem" 2>/dev/null

  openssl rsa -in "$KEYS_DIR/private.pem" -pubout \
    -out "$KEYS_DIR/public.pem" 2>/dev/null

  chmod 600 "$KEYS_DIR/private.pem"
  chmod 644 "$KEYS_DIR/public.pem"

  log_ok "Keypair generated at $KEYS_DIR/"
  log_info "Private key: $KEYS_DIR/private.pem (chmod 600)"
  log_info "Public key:  $KEYS_DIR/public.pem"
  log_info "Run 'export-pubkey' to publish your public key to the company repo"
}

# ── Export pubkey to main:pubkeys/ ─────────────────────────────────
do_export_pubkey() {
  local repo_dir="${1:?Uso: savia-crypto.sh export-pubkey <repo_dir> <handle>}"
  local handle="${2:?Falta handle}"

  if [ ! -f "$KEYS_DIR/public.pem" ]; then
    log_error "No public key found. Run 'keygen' first."
    return 1
  fi

  local pubkey_content
  pubkey_content=$(cat "$KEYS_DIR/public.pem")

  bash "$(dirname "$0")/savia-branch.sh" write "$repo_dir" main "pubkeys/${handle}.pem" "$pubkey_content" \
    "[main] crypto: @$handle pubkey"

  log_ok "Public key exported to main:pubkeys/$handle.pem"
}

# ── Main ────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    keygen)        do_keygen "$@" ;;
    encrypt)       do_encrypt "$@" ;;
    decrypt)       do_decrypt "$@" ;;
    export-pubkey) do_export_pubkey "$@" ;;
    help|*)
      echo "savia-crypto.sh — E2E encryption for Company Savia"
      echo ""
      echo "Commands:"
      echo "  keygen [--force]                — Generate RSA-4096 keypair"
      echo "  encrypt <pubkey.pem> [text]     — Encrypt (stdin or arg)"
      echo "  decrypt [package|-]            — Decrypt with private key (stdin if - or absent)"
      echo "  export-pubkey <repo_dir> <handle> — Copy pubkey to repo"
      ;;
  esac
}

main "$@"
