#!/usr/bin/env bash
# opencode-install.sh — SE-077 Slice 1
#
# Installs OpenCode in `~/.savia/opencode/` and links the savia-gates plugin.
# Idempotent: re-running upgrades the binary in place and refreshes the plugin
# symlink and config.
#
# Two OpenCode lines, one npm package each (savia-gates is a dual V1/V2 plugin):
#   v2  @opencode/cli  recommended (default)
#   v1  opencode-ai    needs >= 1.18.29 (object plugins)
# (@opencode-ai/cli is NOT OpenCode.) The config key differs: `plugins` in v2,
# `plugin` in v1; the file written here uses the one of the chosen flavor.
#
# Usage:
#   bash scripts/opencode-install.sh                  # v2, latest pinned
#   bash scripts/opencode-install.sh --flavor v1
#   bash scripts/opencode-install.sh --version 2.0.32
#   bash scripts/opencode-install.sh --link-only      # skip download, just relink plugin
#   bash scripts/opencode-install.sh --dry-run
#   bash scripts/opencode-install.sh --uninstall      # remove ~/.savia/opencode
#
# Exit codes: 0 ok | 2 usage | 3 download/install error
#
# Reference: SE-077 (docs/propuestas/SE-077-opencode-replatform-v114.md)
# Reference: docs/rules/domain/opencode-savia-bridge.md
# Reference: docs/rules/domain/autonomous-safety.md

set -uo pipefail

ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SAVIA_HOME="${SAVIA_HOME:-${HOME}/.savia}"
OPENCODE_DIR="${SAVIA_HOME}/opencode"
PLUGIN_SRC="${ROOT}/scripts/opencode-plugin/savia-gates"
PLUGIN_DST="${OPENCODE_DIR}/plugins/savia-gates"
FLAVOR="${SAVIA_OPENCODE_FLAVOR:-v2}"
DEFAULT_V1="1.19.3"
DEFAULT_V2="2.0.32"
VERSION="${OPENCODE_VERSION:-}"
DRY_RUN=0
LINK_ONLY=0
UNINSTALL=0

usage() {
  cat <<USG
Usage: opencode-install.sh [--flavor v1|v2] [--version X.Y.Z] [--link-only] [--dry-run] [--uninstall]

Env:
  SAVIA_HOME              default ${HOME}/.savia
  SAVIA_OPENCODE_FLAVOR   v2 (default, @opencode/cli) or v1 (opencode-ai >= 1.18.29)
  OPENCODE_VERSION        default ${DEFAULT_V2} (v2) / ${DEFAULT_V1} (v1)
USG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)    VERSION="${2:?}"; shift 2 ;;
    --flavor)     FLAVOR="${2:?}"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --link-only)  LINK_ONLY=1; shift ;;
    --uninstall)  UNINSTALL=1; shift ;;
    --help|-h)    usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit "${2:-3}"; }

case "$FLAVOR" in
  v1) NPM_PKG="opencode-ai";   VERSION="${VERSION:-$DEFAULT_V1}" ;;
  v2) NPM_PKG="@opencode/cli"; VERSION="${VERSION:-$DEFAULT_V2}" ;;
  *)  echo "Unknown flavor: $FLAVOR (use v1 or v2)" >&2; usage >&2; exit 2 ;;
esac

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: $*"
  else
    "$@"
  fi
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  if [[ -d "${OPENCODE_DIR}" ]]; then
    run rm -rf "${OPENCODE_DIR}"
    echo "uninstalled: ${OPENCODE_DIR}"
  else
    echo "nothing to uninstall: ${OPENCODE_DIR} not present"
  fi
  exit 0
fi

# Plugin source must exist in the repo
[[ -d "${PLUGIN_SRC}" ]] || die "plugin source not found: ${PLUGIN_SRC}"

# Step 1: ensure the directory tree
run mkdir -p "${OPENCODE_DIR}/bin" "${OPENCODE_DIR}/plugins"

# Step 2: download OpenCode binary unless link-only mode
if [[ "$LINK_ONLY" -ne 1 ]]; then
  install_npm() {
    command -v npm >/dev/null 2>&1 || return 1
    run npm install --prefix "${OPENCODE_DIR}" "${NPM_PKG}@${VERSION}" >/dev/null 2>&1 || return 1
    run ln -sf "${OPENCODE_DIR}/node_modules/.bin/opencode" "${OPENCODE_DIR}/bin/opencode"
  }
  if [[ "$FLAVOR" == "v2" ]]; then
    # npm only: the registry checks the package integrity; there is no installer script to trust.
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "DRY-RUN: would npm install ${NPM_PKG}@${VERSION} under ${OPENCODE_DIR}"
    else
      install_npm || die "npm install ${NPM_PKG}@${VERSION} failed (need npm; or install manually and re-run with --link-only)" 3
    fi
  elif command -v curl >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "DRY-RUN: would download opencode v${VERSION} via official installer (npm ${NPM_PKG} as fallback)"
    else
      # Official installer pattern (mirrors https://opencode.ai/install). The
      # installer pins SAVIA_HOME by setting OPENCODE_INSTALL_DIR. If the
      # network is unreachable we fail soft and let the user retry.
      if ! OPENCODE_INSTALL_DIR="${OPENCODE_DIR}/bin" \
           OPENCODE_VERSION="${VERSION}" \
           curl -fsSL https://opencode.ai/install 2>/dev/null | bash >/dev/null 2>&1; then
        echo "WARN: official installer unavailable — falling back to npm" >&2
        install_npm || die "npm install ${NPM_PKG}@${VERSION} failed (run --link-only after manual install)" 3
      fi
    fi
  else
    die "curl not available — install opencode manually then re-run with --link-only" 3
  fi
fi

# Step 3: link the plugin into the OpenCode plugins dir
run mkdir -p "${OPENCODE_DIR}/plugins"
if [[ "$DRY_RUN" -ne 1 ]]; then
  rm -rf "${PLUGIN_DST}"
  ln -s "${PLUGIN_SRC}" "${PLUGIN_DST}"
fi

# Step 3b: parity manifest. The plugin no longer writes it on load (its install
# dir is part of the engine fingerprint); it is generated here, deterministic and
# rewritten only when the bindings change. Soft-fail without bun.
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN: would generate ${PLUGIN_DST}/manifest.json"
elif command -v bun >/dev/null 2>&1; then
  SAVIA_PLUGIN_DIR="${PLUGIN_DST}" bun "${PLUGIN_SRC}/lib/manifest.ts" "${ROOT}" \
    || echo "WARN: manifest generation failed (parity-audit will report it missing)" >&2
else
  echo "WARN: bun not found — manifest.json not generated (parity-audit needs it)" >&2
fi

# Step 4: register the plugin in an OpenCode config. The key differs by flavor (v1 `plugin`, v2 `plugins`) and
# a bare name would be read as an npm package, so the entry is the linked directory.
OC_CONFIG="${OPENCODE_DIR}/opencode.json"
if [[ "$DRY_RUN" -ne 1 ]]; then
  if [[ "$FLAVOR" == "v2" ]]; then
    cat > "${OC_CONFIG}" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugins": [{ "package": "${PLUGIN_DST}" }]
}
EOF
  else
    cat > "${OC_CONFIG}" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugin": ["${PLUGIN_DST}"]
}
EOF
  fi
fi

# Step 5: stamp version
if [[ "$DRY_RUN" -ne 1 ]]; then
  echo "${VERSION}" > "${OPENCODE_DIR}/.installed-version"
  echo "${FLAVOR}" > "${OPENCODE_DIR}/.installed-flavor"
fi

cat <<DONE
opencode installed:
  binary  : ${OPENCODE_DIR}/bin/opencode
  plugin  : ${PLUGIN_DST} -> ${PLUGIN_SRC}
  config  : ${OC_CONFIG}
  version : ${VERSION} (${FLAVOR}, npm ${NPM_PKG})

next:
  ${OPENCODE_DIR}/bin/opencode --version
  cd ${ROOT} && OPENCODE_CONFIG=${OC_CONFIG} ${OPENCODE_DIR}/bin/opencode "explica el contenido de docs/ROADMAP.md"
DONE
