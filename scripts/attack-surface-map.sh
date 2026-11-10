#!/usr/bin/env bash
# attack-surface-map.sh — SE-243 Attack Surface Mapping
# Maps attack surface using subfinder, httpx, theHarvester, dnstwist
# REQUIRES: output/security/authorization-{target}.txt with "AUTHORIZED"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/output/security"
DATE_STAMP=$(date +%Y%m%d)

TARGET=""
TOOLS="subfinder,httpx,theharvester,dnstwist"

usage() {
  echo "Usage: $0 --target <domain> [--tools subfinder,httpx,theharvester,dnstwist]"
  echo ""
  echo "Requires authorization file: output/security/authorization-{target}.txt"
  echo "Create it with: scripts/surface-map-authorize.sh --target <domain>"
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
      --tools)  [[ $# -ge 2 ]] || { echo "ERROR: --tools needs a value"; usage; }; TOOLS="$2";  shift 2 ;;
      -h|--help) usage ;;
      *) echo "Unknown option: $1"; usage ;;
    esac
  done
  [[ -z "${TARGET}" ]] && { echo "ERROR: --target is required"; usage; }
  valid_target "${TARGET}" || { echo "ERROR: --target must be a domain name: ${TARGET}"; usage; }
}

check_authorization() {
  local target="$1"
  local auth_file="${OUTPUT_DIR}/authorization-${target}.txt"

  if [[ ! -f "${auth_file}" ]]; then
    echo "ERROR: Authorization file not found: ${auth_file}"
    echo ""
    echo "To authorize scanning of '${target}', run:"
    echo "  bash scripts/surface-map-authorize.sh --target ${target}"
    echo ""
    echo "Only scan domains you own or have explicit written permission to scan."
    exit 1
  fi

  # The first line must be exactly AUTHORIZED: "NOT AUTHORIZED" or
  # "UNAUTHORIZED" contain the word but are not a grant.
  local first_line=""
  IFS= read -r first_line < "${auth_file}" || true
  if [[ "${first_line%$'\r'}" != "AUTHORIZED" ]]; then
    echo "ERROR: Authorization file does not contain 'AUTHORIZED': ${auth_file}"
    exit 1
  fi

  # Verify file is not older than 30 days
  local file_epoch
  file_epoch=$(stat -c %Y "${auth_file}" 2>/dev/null || stat -f %m "${auth_file}" 2>/dev/null)
  local now_epoch
  now_epoch=$(date +%s)
  local max_age=$((30 * 24 * 3600))
  local age=$(( now_epoch - file_epoch ))

  if [[ ${age} -gt ${max_age} ]]; then
    echo "ERROR: Authorization file is older than 30 days (${auth_file})"
    echo "Re-authorize by running: bash scripts/surface-map-authorize.sh --target ${target}"
    exit 1
  fi

  echo "[auth] Authorization verified for target: ${target}"
}

run_subfinder() {
  local target="$1"
  local outfile="$2"
  echo "[subfinder] Starting subdomain enumeration..."
  if command -v subfinder &>/dev/null; then
    subfinder -d "${target}" -silent -o "${outfile}" 2>/dev/null
    echo "[subfinder] Done (native binary)"
  elif docker info &>/dev/null 2>&1; then
    docker run --rm "projectdiscovery/subfinder" -d "${target}" -silent 2>/dev/null > "${outfile}"
    echo "[subfinder] Done (Docker fallback)"
  else
    echo "[subfinder] SKIP — not available (no binary, no Docker)"
  fi
}

run_httpx() {
  local infile="$1"
  local outfile="$2"
  [[ ! -s "${infile}" ]] && { echo "[httpx] SKIP — no input"; return; }
  echo "[httpx] Probing HTTP endpoints..."
  if command -v httpx &>/dev/null; then
    httpx -l "${infile}" -silent -json -o "${outfile}" 2>/dev/null
    echo "[httpx] Done (native binary)"
  elif docker info &>/dev/null 2>&1; then
    docker run --rm -i "projectdiscovery/httpx" -silent -json < "${infile}" > "${outfile}" 2>/dev/null
    echo "[httpx] Done (Docker fallback)"
  else
    echo "[httpx] SKIP — not available"
  fi
}

run_theharvester() {
  local target="$1"
  local outdir="$2"
  echo "[theHarvester] Gathering OSINT..."
  if command -v theHarvester &>/dev/null; then
    theHarvester -d "${target}" -b bing,crtsh -f "${outdir}/harvest" 2>/dev/null
    echo "[theHarvester] Done (native binary)"
  elif docker info &>/dev/null 2>&1; then
    docker run --rm "secsi/theharvester" -d "${target}" -b bing,crtsh 2>/dev/null > "${outdir}/harvest.txt"
    echo "[theHarvester] Done (Docker fallback)"
  else
    echo "[theHarvester] SKIP — not available"
  fi
}

run_dnstwist() {
  local target="$1"
  local outfile="$2"
  echo "[dnstwist] Detecting typosquatting domains..."
  if command -v dnstwist &>/dev/null; then
    dnstwist --registered --format json "${target}" 2>/dev/null > "${outfile}"
    echo "[dnstwist] Done (native binary)"
  elif docker info &>/dev/null 2>&1; then
    docker run --rm "elceef/dnstwist" --registered --format json "${target}" 2>/dev/null > "${outfile}"
    echo "[dnstwist] Done (Docker fallback)"
  else
    echo "[dnstwist] SKIP — not available"
  fi
}

main() {
  parse_args "$@"

  # Ensure output dir exists
  mkdir -p "${OUTPUT_DIR}"

  # Authorization gate
  check_authorization "${TARGET}"

  local report_dir="${OUTPUT_DIR}/attack-surface-${TARGET}-${DATE_STAMP}"
  mkdir -p "${report_dir}/raw"

  local subdomains_file="${report_dir}/subdomains.txt"
  local httpx_file="${report_dir}/raw/httpx.json"
  local dnstwist_file="${report_dir}/raw/dnstwist.json"
  local harvest_dir="${report_dir}/raw"

  echo "[attack-surface-map] Target: ${TARGET}"
  echo "[attack-surface-map] Report: ${report_dir}"

  # Run requested tools
  IFS=',' read -ra TOOL_LIST <<< "${TOOLS}"
  for tool in "${TOOL_LIST[@]}"; do
    case "${tool}" in
      subfinder)      run_subfinder "${TARGET}" "${subdomains_file}" ;;
      httpx)          run_httpx "${subdomains_file}" "${httpx_file}" ;;
      theharvester)   run_theharvester "${TARGET}" "${harvest_dir}" ;;
      dnstwist)       run_dnstwist "${TARGET}" "${dnstwist_file}" ;;
      *)              echo "[warn] Unknown tool: ${tool}" ;;
    esac
  done

  # Build consolidated JSON report
  local report_json="${OUTPUT_DIR}/surface-map-${TARGET}-${DATE_STAMP}.json"
  local subcount=0
  [[ -f "${subdomains_file}" ]] && subcount=$(wc -l < "${subdomains_file}" | tr -d ' ')

  cat > "${report_json}" <<EOF
{
  "target": "${TARGET}",
  "date": "${DATE_STAMP}",
  "tools": "${TOOLS}",
  "report_dir": "${report_dir}",
  "subdomains_found": ${subcount},
  "subdomains_file": "${subdomains_file}",
  "httpx_results": "${httpx_file}",
  "dnstwist_results": "${dnstwist_file}"
}
EOF

  echo "[attack-surface-map] Report written: ${report_json}"
  echo "[attack-surface-map] Done."
}

main "$@"
