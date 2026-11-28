#!/bin/bash
# savia-travel-ops.sh — Pack and init operations for savia-travel.sh
# Sourced by savia-travel.sh. Do not run directly.

# ── Pack: create portable package ───────────────────────────────────
do_pack() {
  local ts pkg_dir version size
  ts=$(get_timestamp); pkg_dir="$OUTPUT_DIR/savia-portable-$ts"
  if [ -d "$pkg_dir" ]; then
    log_warn "Package dir already exists: $pkg_dir"; return 1
  fi
  log_info "Creating portable package at $pkg_dir ..."
  mkdir -p "$pkg_dir/portable-config" "$pkg_dir/profiles"
  # 1 — Shallow clone
  log_info "Step 1/5 — Shallow clone..."
  git clone --depth 1 "file://$WORKSPACE_DIR" "$pkg_dir/pm-workspace" 2>/dev/null
  log_ok "Repository cloned (depth=1)"
  # 2 — Manifest
  log_info "Step 2/5 — Manifest..."
  version=$(get_version)
  cat > "$pkg_dir/portable-config/manifest.json" <<MANIFEST
{ "tool":"pm-workspace","version":"$version","date":"$(get_date)",
  "os_origin":"$(uname -s)",
  "components":{"pm-workspace":true,"profiles":false,"dependencies_list":true}}
MANIFEST
  log_ok "Manifest created"
  # 3 — Dependencies
  log_info "Step 3/5 — Dependencies list..."
  cat > "$pkg_dir/portable-config/dependencies.txt" <<'DEPS'
git       # Version control (required)
openssl   # Encryption (required)
bash      # Version 4+ (required)
curl      # HTTP client (required)
jq        # JSON processing (required)
node      # Node.js for Claude Code (recommended)
npm       # Claude Code installer (recommended)
DEPS
  log_ok "Dependencies list created"
  # 4 — Encrypted backup
  log_info "Step 4/5 — Encrypted backups..."
  if [ -d "$BACKUP_DIR" ]; then
    local latest; latest=$(ls -t "$BACKUP_DIR"/pm-backup-*.enc 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
      cp "$latest" "$pkg_dir/profiles/"
      sed -i 's/"profiles":false/"profiles":true/' \
        "$pkg_dir/portable-config/manifest.json" 2>/dev/null || true
      log_ok "Backup included: $(basename "$latest")"
    else log_warn "No encrypted backups found"; fi
  else log_warn "No backup directory"; fi
  # 5 — Entry point
  log_info "Step 5/5 — Entry point..."
  cat > "$pkg_dir/savia-init.sh" <<'INITSCRIPT'
#!/bin/bash
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$D/pm-workspace/scripts/savia-travel.sh" ]; then
  bash "$D/pm-workspace/scripts/savia-travel.sh" init "$D"
else echo "ERROR: pm-workspace not found."; exit 1; fi
INITSCRIPT
  chmod +x "$pkg_dir/savia-init.sh"
  log_ok "Entry point created"
  # Summary
  size=$(du -sh "$pkg_dir" 2>/dev/null | cut -f1)
  echo ""
  echo -e "${CYAN}=== Package Summary ===${NC}"
  echo "  Location: $pkg_dir"
  echo "  Size:     $size"
  echo "  Version:  $version"
  echo ""
  echo "Copy to USB or cloud. On new machine: bash savia-init.sh"
}

# ── Init: bootstrap on new machine ─────────────────────────────────
do_init() {
  local pkg_path="${1:-}"
  if [ -z "$pkg_path" ] || [ ! -d "$pkg_path" ]; then
    log_error "Usage: savia-travel.sh init <path-to-savia-portable>"; return 1
  fi
  log_info "Bootstrapping from $pkg_path ..."
  # 1 — Detect OS
  local os_type="unknown"
  case "${OSTYPE:-}" in
    linux*) os_type="Linux" ;; darwin*) os_type="macOS" ;;
    msys*|cygwin*) os_type="WSL" ;;
  esac
  log_info "OS: $os_type"
  # 2 — Check deps
  local missing=()
  for dep in git openssl bash curl jq; do
    command -v "$dep" &>/dev/null || missing+=("$dep")
  done
  [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] && missing+=("bash4+")
  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing: ${missing[*]}"
    case "$os_type" in
      Linux) echo "  sudo apt install ${missing[*]}" ;;
      macOS) echo "  brew install ${missing[*]}" ;;
      *)     echo "  Install manually: ${missing[*]}" ;;
    esac
    return 1
  fi
  log_ok "All dependencies found"
  # 3 — Claude Code
  if command -v npm &>/dev/null; then
    if ! command -v claude &>/dev/null; then
      log_info "Installing Claude Code via npm..."
      npm install -g @anthropic-ai/claude-code@2.1.332 2>/dev/null && \
        log_ok "Claude Code installed" || \
        log_warn "Install failed — install Claude Code manually"
    else log_ok "Claude Code already installed"; fi
  else log_warn "npm not found — install Node.js for Claude Code"; fi
  # 4 — Copy workspace
  local target="$HOME/claude"
  if [ -d "$target/.git" ]; then
    log_ok "pm-workspace exists at $target"
  elif [ -d "$pkg_path/pm-workspace" ]; then
    log_info "Copying pm-workspace to $target ..."
    cp -r "$pkg_path/pm-workspace" "$target"
    log_ok "Installed at $target"
  else log_error "No pm-workspace in package"; fi
  # 5 — Restore profile
  local enc_file
  enc_file=$(ls "$pkg_path/profiles/"*.enc 2>/dev/null | head -1 || true)
  if [ -n "$enc_file" ] && [ -f "$target/scripts/backup.sh" ]; then
    log_info "Restoring encrypted profile..."
    bash "$target/scripts/backup.sh" restore "$enc_file" || \
      log_warn "Restore failed — run /backup restore manually"
  else log_info "No profile backup to restore"; fi
  # Summary
  echo ""
  echo -e "${CYAN}=== Bootstrap Complete ===${NC}"
  echo "  OS:           $os_type"
  echo "  pm-workspace: $target"
  echo "  Claude Code:  $(command -v claude &>/dev/null && echo 'yes' || echo 'no')"
  echo ""
  echo "Next: cd $target && claude"
  echo "Then: /profile-setup to configure your identity"
}
