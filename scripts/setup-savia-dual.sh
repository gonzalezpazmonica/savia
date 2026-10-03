#!/usr/bin/env bash
# setup-savia-dual.sh — Installer for Savia Dual (Linux/macOS)
#
# Fully idempotent: re-running this script will NOT re-download Ollama,
# re-pull models, or overwrite an existing config. Only missing pieces are
# added. Use --force to rewrite config, or --reconfigure to regenerate
# only the config without touching Ollama/models.
#
# Persistent activation (systemd/launchd service and the ~/.bashrc/~/.zshrc
# block that exports ANTHROPIC_BASE_URL in every shell) requires the double
# opt-in of SPEC-186: SAVIA_DUAL_FAILOVER_ENABLED=true AND --confirm-autonomous.
# Without both, only ~/.savia/dual/{config.json,env} are written.
#
# Usage:
#   ./scripts/setup-savia-dual.sh              # install + configure (+ launch claude on a TTY)
#   ./scripts/setup-savia-dual.sh --no-launch  # install only, do not exec claude
#   ./scripts/setup-savia-dual.sh --dry-run    # show what would happen, write nothing
#   ./scripts/setup-savia-dual.sh --reconfigure # regenerate config only
#   ./scripts/setup-savia-dual.sh --force      # rewrite config even if present
#   SAVIA_DUAL_FAILOVER_ENABLED=true ./scripts/setup-savia-dual.sh --confirm-autonomous
#                                              # also install service + shell integration
#   ./scripts/setup-savia-dual.sh -- --resume  # pass args after -- to claude
#
# Exit codes: 0 ok · 1 install step failed · 2 invalid argument
set -uo pipefail

DRY_RUN=0
RECONFIG_ONLY=0
FORCE=0
NO_LAUNCH=0
CONFIRM_AUTONOMOUS=0
CLAUDE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --reconfigure) RECONFIG_ONLY=1; FORCE=1 ;;
    --force) FORCE=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    --confirm-autonomous) CONFIRM_AUTONOMOUS=1 ;;
    --) shift; CLAUDE_ARGS=("$@"); break ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -27
      exit 0
      ;;
    *) printf '[savia-dual] Unknown argument: %s (see --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\033[0;36m[savia-dual]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[savia-dual]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[0;31m[savia-dual]\033[0m %s\n' "$*" >&2; }
run() { if [[ $DRY_RUN -eq 1 ]]; then echo "  + $*"; else eval "$*"; fi }

# Resolve repo dir from this script's location (absolute, symlink-safe).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_PATH="$SCRIPT_DIR/savia-dual-proxy.py"
PYTHON_BIN="$(command -v python3 || true)"

# ── Detect OS ───────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Linux) PLATFORM="linux" ;;
  Darwin) PLATFORM="macos" ;;
  *) err "Unsupported OS: $OS (use savia-dual-setup.ps1 on Windows)"; exit 1 ;;
esac
say "Platform: $PLATFORM"

# ── Install/update Ollama ───────────────────────────────────────────────────
install_ollama() {
  if command -v ollama >/dev/null 2>&1; then
    say "Ollama present: $(ollama --version 2>/dev/null | head -1)"
    return 0
  fi
  say "Installing Ollama from official installer..."
  if [[ "$PLATFORM" == "linux" ]]; then
    run "curl -fsSL https://ollama.com/install.sh | sh"
  else
    if command -v brew >/dev/null 2>&1; then
      run "brew install ollama"
    else
      warn "Homebrew not found. Download Ollama from https://ollama.com/download/mac"
      return 1
    fi
  fi
}

if [[ $RECONFIG_ONLY -eq 0 ]]; then
  install_ollama || exit 1
fi

# ── Start Ollama daemon (idempotent) ────────────────────────────────────────
ensure_ollama_running() {
  if curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    return 0
  fi
  say "Starting Ollama daemon..."
  if [[ "$PLATFORM" == "linux" ]]; then
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q "^ollama.service"; then
      run "sudo systemctl start ollama" || run "nohup ollama serve >/tmp/ollama.log 2>&1 &"
    else
      run "nohup ollama serve >/tmp/ollama.log 2>&1 &"
    fi
  else
    run "nohup ollama serve >/tmp/ollama.log 2>&1 &"
  fi
  sleep 2
}
[[ $RECONFIG_ONLY -eq 0 ]] && ensure_ollama_running

# ── Detect hardware (stays local, never logged to tracked files) ────────────
detect_ram_gb() {
  if [[ "$PLATFORM" == "linux" ]]; then
    awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo
  else
    sysctl -n hw.memsize | awk '{printf "%d", $1/1024/1024/1024}'
  fi
}

detect_vram_gb() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
      | head -1 | awk '{printf "%d", $1/1024}'
    return
  fi
  if [[ "$PLATFORM" == "macos" ]]; then
    # Apple Silicon: unified memory, approximate as RAM/2
    local ram; ram=$(detect_ram_gb)
    echo "$((ram / 2))"
    return
  fi
  echo "0"
}

RAM_GB=$(detect_ram_gb)
VRAM_GB=$(detect_vram_gb)
say "Hardware detection complete (values kept local, not logged)."

# ── List installed gemma4 variants (idempotency source of truth) ────────────
list_installed_gemma4() {
  ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^gemma4:' || true
}

# ── Pick gemma4 variant by hardware (ideal pick) ────────────────────────────
pick_variant() {
  local ram="$1" vram="$2"
  if [[ "$ram" -lt 12 ]]; then
    echo "gemma4:e2b"; return
  fi
  if [[ "$ram" -lt 24 ]]; then
    echo "gemma4:e4b"; return
  fi
  if [[ "$vram" -ge 12 ]]; then
    echo "gemma4:26b"; return
  fi
  if [[ "$ram" -ge 32 ]]; then
    echo "gemma4:e4b"; return
  fi
  echo "gemma4:e2b"
}

# ── Reuse already-downloaded variant when possible ──────────────────────────
# Priority:
#   1. If the ideal pick is already installed → use it.
#   2. Else, if ANY gemma4 variant is already installed → reuse it (best fit
#      by hardware, no new download).
#   3. Else → pull the ideal pick.
IDEAL=$(pick_variant "$RAM_GB" "$VRAM_GB")
INSTALLED=$(list_installed_gemma4)

choose_from_installed() {
  # Any already-installed gemma4 variant is acceptable — the user downloaded
  # it deliberately. Prefer the largest one (26b > e4b > e2b) since disk
  # space was already spent.
  local installed="$1"
  local has_e2b=0 has_e4b=0 has_26b=0
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    case "$m" in
      gemma4:e2b) has_e2b=1 ;;
      gemma4:e4b) has_e4b=1 ;;
      gemma4:26b) has_26b=1 ;;
    esac
  done <<< "$installed"
  [[ $has_26b -eq 1 ]] && { echo "gemma4:26b"; return; }
  [[ $has_e4b -eq 1 ]] && { echo "gemma4:e4b"; return; }
  [[ $has_e2b -eq 1 ]] && { echo "gemma4:e2b"; return; }
  # Another gemma4 tag (e.g. gemma4:12b): still usable, never leave it empty.
  printf '%s\n' "$installed" | sed '/^$/d' | head -1
}

if echo "$INSTALLED" | grep -qx "$IDEAL"; then
  MODEL="$IDEAL"
  say "Ideal variant already installed: $MODEL (skipping download)"
elif [[ -n "$INSTALLED" ]]; then
  REUSE=$(choose_from_installed "$INSTALLED")
  MODEL="$REUSE"
  say "Reusing already-installed variant: $MODEL (ideal would be $IDEAL, skipping download)"
else
  MODEL="$IDEAL"
  say "No gemma4 variant installed — will pull $MODEL"
fi

# ── Download model (only if truly missing) ──────────────────────────────────
if [[ $RECONFIG_ONLY -eq 0 ]]; then
  if echo "$INSTALLED" | grep -qx "$MODEL"; then
    say "Model $MODEL already present — no download needed."
  else
    say "Downloading $MODEL (this may take a while)..."
    run "ollama pull $MODEL"
  fi
fi

# ── Write config ────────────────────────────────────────────────────────────
CONFIG_DIR="$HOME/.savia/dual"
CONFIG_PATH="$CONFIG_DIR/config.json"
ENV_PATH="$CONFIG_DIR/env"
run "mkdir -p '$CONFIG_DIR'"

if [[ -f "$CONFIG_PATH" && $FORCE -eq 0 ]]; then
  say "Config already exists: $CONFIG_PATH (use --force to rewrite)"
  WRITE_CONFIG=0
else
  WRITE_CONFIG=1
fi

if [[ -f "$ENV_PATH" && $FORCE -eq 0 ]]; then
  say "Env file already exists: $ENV_PATH (use --force to rewrite)"
  WRITE_ENV=0
else
  WRITE_ENV=1
fi

if [[ $DRY_RUN -eq 0 && $WRITE_CONFIG -eq 1 ]]; then
  cat > "$CONFIG_PATH" <<JSON
{
  "listen_host": "127.0.0.1",
  "listen_port": 8787,
  "anthropic_upstream": "${SAVIA_API_UPSTREAM:-https://api.anthropic.com}",
  "ollama_upstream": "http://127.0.0.1:11434",
  "fallback_triggers": {
    "network_error": true,
    "http_5xx": true,
    "http_429": true,
    "timeout_seconds": 30
  },
  "circuit_breaker": {
    "consecutive_failures": 3,
    "cooldown_seconds": 60
  },
  "local_model": "$MODEL",
  "log_path": "$HOME/.savia/dual/events.jsonl"
}
JSON
  say "Config written: $CONFIG_PATH"
fi

if [[ $DRY_RUN -eq 0 && $WRITE_ENV -eq 1 ]]; then
  cat > "$ENV_PATH" <<ENV
# Source this file to route Claude Code through Savia Dual.
export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"
export SAVIA_DUAL_ACTIVE="1"
export OLLAMA_KEEP_ALIVE="24h"
ENV
  say "Env file:       $ENV_PATH"
fi

# ── Install system-wide systemd service (Linux) ─────────────────────────────
install_systemd_system_service() {
  [[ "$PLATFORM" != "linux" ]] && return 0
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl not available — cannot install system service."
    return 1
  fi
  if [[ -z "$PYTHON_BIN" ]]; then
    err "python3 not found in PATH — cannot create service."
    return 1
  fi
  if [[ ! -f "$PROXY_PATH" ]]; then
    err "Proxy script not found: $PROXY_PATH"
    return 1
  fi

  local unit_path="/etc/systemd/system/savia-dual-proxy.service"
  local svc_user="${SUDO_USER:-$USER}"
  local svc_home; svc_home="$(getent passwd "$svc_user" | cut -d: -f6)"
  [[ -z "$svc_home" ]] && svc_home="$HOME"

  # Ensure Ollama starts on boot too (installer usually does this already).
  if systemctl list-unit-files 2>/dev/null | grep -q '^ollama\.service'; then
    run "sudo systemctl enable --now ollama.service >/dev/null 2>&1 || true"
  fi

  local tmp_unit; tmp_unit="$(mktemp)"
  cat > "$tmp_unit" <<UNIT
[Unit]
Description=Savia Dual Proxy (inference sovereignty failover)
Documentation=file://$SCRIPT_DIR/../docs/rules/domain/savia-dual.md
After=network-online.target ollama.service
Wants=network-online.target

[Service]
Type=simple
User=$svc_user
Environment=HOME=$svc_home
Environment=SAVIA_DUAL_CONFIG=$svc_home/.savia/dual/config.json
ExecStart=$PYTHON_BIN $PROXY_PATH
Restart=on-failure
RestartSec=3
StandardOutput=append:/var/log/savia-dual-proxy.log
StandardError=append:/var/log/savia-dual-proxy.log

[Install]
WantedBy=multi-user.target
UNIT

  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] Would install systemd unit at $unit_path"
    cat "$tmp_unit"
    rm -f "$tmp_unit"
    return 0
  fi

  say "Installing systemd unit (requires sudo): $unit_path"
  if ! sudo install -m 0644 "$tmp_unit" "$unit_path"; then
    err "Failed to install unit file (sudo denied?)"
    rm -f "$tmp_unit"
    return 1
  fi
  rm -f "$tmp_unit"

  sudo touch /var/log/savia-dual-proxy.log
  sudo chown "$svc_user":"$svc_user" /var/log/savia-dual-proxy.log 2>/dev/null || true

  sudo systemctl daemon-reload
  sudo systemctl enable savia-dual-proxy.service >/dev/null
  sudo systemctl restart savia-dual-proxy.service
  sleep 1

  if systemctl is-active --quiet savia-dual-proxy.service; then
    say "Service active: savia-dual-proxy.service (enabled at boot)"
  else
    err "Service failed to start. Check: sudo journalctl -u savia-dual-proxy -n 50"
    return 1
  fi
}

# ── Install launchd agent (macOS) ───────────────────────────────────────────
install_launchd_agent() {
  [[ "$PLATFORM" != "macos" ]] && return 0
  local plist_path="$HOME/Library/LaunchAgents/com.savia.dual.proxy.plist"
  run "mkdir -p '$HOME/Library/LaunchAgents'"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] Would install launchd agent at $plist_path"
    return 0
  fi
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.savia.dual.proxy</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON_BIN</string>
    <string>$PROXY_PATH</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/.savia/dual/proxy.log</string>
  <key>StandardErrorPath</key><string>$HOME/.savia/dual/proxy.log</string>
</dict></plist>
PLIST
  launchctl unload "$plist_path" 2>/dev/null || true
  launchctl load "$plist_path"
  say "launchd agent loaded: com.savia.dual.proxy"
}

# ── Shell integration (auto-source env on every new shell) ──────────────────
install_shell_integration() {
  local marker="# >>> savia-dual >>>"
  local endmark="# <<< savia-dual <<<"
  local block="$marker
# Auto-added by setup-savia-dual.sh — do not edit between markers.
if [ -f \"$ENV_PATH\" ]; then . \"$ENV_PATH\"; fi
$endmark"

  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    if grep -qF "$marker" "$rc"; then
      say "Shell integration already in $rc"
      continue
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      say "[dry-run] Would append savia-dual block to $rc"
      continue
    fi
    printf '\n%s\n' "$block" >> "$rc"
    say "Shell integration added to $rc"
  done
}

# ── Double opt-in (SPEC-186) for anything outside ~/.savia/dual ────────────
# The gate prints its own diagnostics; here they are folded into one notice.
GLOBAL_OK=0
optin_args=(--skill savia-dual)
[[ $CONFIRM_AUTONOMOUS -eq 1 ]] && optin_args+=(--confirm-autonomous)
if (cd "$SCRIPT_DIR/.." && bash scripts/savia-double-optin-check.sh "${optin_args[@]}") >/dev/null 2>&1; then
  GLOBAL_OK=1
fi

SERVICE_STATE="not installed (double opt-in missing)"
INSTALL_FAILED=0
if [[ $GLOBAL_OK -eq 1 ]]; then
  if [[ "$PLATFORM" == "linux" ]]; then
    if install_systemd_system_service; then
      SERVICE_STATE="savia-dual-proxy.service (enabled at boot)"
    else
      warn "System service install failed — you can run the proxy manually."
      SERVICE_STATE="install FAILED"; INSTALL_FAILED=1
    fi
  else
    if install_launchd_agent; then
      SERVICE_STATE="launchd agent com.savia.dual.proxy"
    else
      SERVICE_STATE="install FAILED"; INSTALL_FAILED=1
    fi
  fi
  install_shell_integration
else
  warn "Double opt-in missing: service and shell rc integration skipped."
  warn "To enable them: SAVIA_DUAL_FAILOVER_ENABLED=true $0 --confirm-autonomous"
fi

# ── Health check ────────────────────────────────────────────────────────────
PROXY_STATE="not checked (dry-run)"
if [[ $DRY_RUN -eq 0 ]]; then
  if curl -fsS --max-time 3 http://127.0.0.1:8787/health >/dev/null 2>&1; then
    PROXY_STATE="running (health OK)"
  else
    PROXY_STATE="not running — start it: $PYTHON_BIN $PROXY_PATH"
  fi
fi

# ── Final summary (states what actually happened, nothing more) ─────────────
cat <<EOF

Savia Dual setup finished.

  Service:  $SERVICE_STATE
  Proxy:    http://127.0.0.1:8787 — $PROXY_STATE
  Config:   $CONFIG_PATH
  Events:   $HOME/.savia/dual/events.jsonl
  Model:    $MODEL

Reconfigure:  ./scripts/setup-savia-dual.sh --reconfigure
EOF

# ── Auto-launch Claude Code with env applied ────────────────────────────────
# A child process CANNOT modify its parent shell's environment, so running
# `bash setup.sh && claude` would leave ANTHROPIC_BASE_URL unset in the parent.
# Solution: source the env in THIS script's process and exec claude here.
# The exec'd claude inherits ANTHROPIC_BASE_URL and routes through the proxy.
if [[ $DRY_RUN -eq 0 && $NO_LAUNCH -eq 0 ]]; then
  if [[ -t 1 ]] && command -v claude >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    . "$ENV_PATH"
    say "Launching Claude Code with Savia Dual active (ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL)"
    echo
    exec claude ${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}
  else
    cat <<EOF

To start Claude Code with Savia Dual active in the current shell:
  source $ENV_PATH && claude

Or open a NEW terminal (shell integration will load it automatically):
  claude
EOF
  fi
fi

exit "$INSTALL_FAILED"
