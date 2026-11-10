#!/usr/bin/env bash
# surface-map-authorize.sh — SE-243 Authorization helper
# Creates authorization file for attack-surface-map.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/output/security"

TARGET=""

usage() {
  echo "Usage: $0 --target <domain>"
  echo ""
  echo "Creates output/security/authorization-{target}.txt"
  echo "Required before running attack-surface-map.sh"
  exit 1
}

# --target is a DNS name: it ends up in a file path and in tool argv, so
# anything else (path separators, leading '-', spaces, quotes) is rejected.
valid_target() {
  local t="$1"
  [[ ${#t} -le 253 ]] || return 1
  [[ "$t" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target) [[ $# -ge 2 ]] || { echo "ERROR: --target needs a value"; usage; }; TARGET="$2"; shift 2 ;;
      -h|--help) usage ;;
      *) echo "Unknown option: $1"; usage ;;
    esac
  done
  [[ -z "${TARGET}" ]] && { echo "ERROR: --target is required"; usage; }
  valid_target "${TARGET}" || { echo "ERROR: --target must be a domain name: ${TARGET}"; usage; }
}

main() {
  parse_args "$@"

  mkdir -p "${OUTPUT_DIR}"

  local auth_file="${OUTPUT_DIR}/authorization-${TARGET}.txt"

  echo ""
  echo "=== Attack Surface Mapping Authorization ==="
  echo ""
  echo "Target: ${TARGET}"
  echo ""
  echo "WARNING: Only scan domains you own or have explicit written permission to scan."
  echo "Unauthorized scanning may be illegal in your jurisdiction."
  echo ""
  printf "Do you have permission to scan '%s'? (type AUTHORIZED to confirm): " "${TARGET}"
  read -r response

  if [[ "${response}" != "AUTHORIZED" ]]; then
    echo "Aborted. Authorization not granted."
    exit 1
  fi

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "${auth_file}" <<EOF
AUTHORIZED
target: ${TARGET}
timestamp: ${timestamp}
authorized_by: $(whoami)
scope: attack-surface-mapping (subfinder, httpx, theHarvester, dnstwist)
valid_days: 30
expires: $(date -u -d "+30 days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+30d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "check timestamp")
EOF

  echo ""
  echo "Authorization file created: ${auth_file}"
  echo "Valid for 30 days from ${timestamp}"
  echo ""
  echo "You can now run: bash scripts/attack-surface-map.sh --target ${TARGET}"
}

main "$@"
