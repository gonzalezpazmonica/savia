#!/usr/bin/env bash
# Generates a private Codex profile only after sandbox and enforcement probes pass.
set -euo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel)}"
TARGET="${SAVIA_CODEX_PROFILE_TARGET:-${CODEX_HOME:-$HOME/.codex}/autonomous-l2.config.toml}"
exec python3 "$ROOT/scripts/dual-cli/codex_profile.py" configure --target "$TARGET" "$@"
