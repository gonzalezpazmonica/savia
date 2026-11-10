#!/usr/bin/env bash
# dynamic-web-security-test.sh — SE-245 Dynamic Web Security Testing
# Tests web endpoints for XSS, SQLi using DalFox, sqlmap, Nuclei
# REQUIRES: output/security/authorization-{target}.txt with "AUTHORIZED"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/output/security"
DATE_STAMP=$(date +%Y%m%d)

TARGET=""
TOOLS="xss,sqli,nuclei"
SAFE="true"
TARGET_HOST=""

usage() {
  echo "Usage: $0 --target <url> [--tools xss,sqli,nuclei] [--safe]"
  echo ""
  echo "Options:"
  echo "  --target  Base URL to test (e.g. http://localhost:8080)"
  echo "  --tools   Comma-separated tools: xss,sqli,nuclei (default: all)"
  echo "  --safe    Conservative mode — level 1, no destructive payloads (default: on)"
  echo ""
  echo "Requires authorization file: output/security/authorization-{host}.txt"
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target) TARGET="$2"; shift 2 ;;
      --tools)  TOOLS="$2";  shift 2 ;;
      --safe)   SAFE="true"; shift ;;
      -h|--help) usage ;;
      *) echo "Unknown option: $1"; usage ;;
    esac
  done
  [[ -z "${TARGET}" ]] && { echo "ERROR: --target is required"; usage; }
  # Extract hostname from URL
  TARGET_HOST=$(echo "${TARGET}" | sed 's|^[a-z]*://||' | cut -d'/' -f1 | cut -d':' -f1)
}

check_authorization() {
  local host="$1"
  local auth_file="${OUTPUT_DIR}/authorization-${host}.txt"

  if [[ ! -f "${auth_file}" ]]; then
    echo "ERROR: Authorization file not found: ${auth_file}"
    echo ""
    echo "To authorize testing of '${host}', create the file:"
    echo "  ${auth_file}"
    echo ""
    echo "Its first line must be exactly 'AUTHORIZED'."
    echo "Only test endpoints you own or have explicit permission to test."
    exit 1
  fi

  # Allowlist estricta, igual que network-recon (S03r): la primera línea debe ser
  # exactamente AUTHORIZED. Una denylist de negaciones dejaba pasar
  # "NOT  AUTHORIZED", "NOT YET AUTHORIZED" o "REVOKED (was AUTHORIZED)".
  local first_line
  first_line=$(head -n 1 "${auth_file}" | tr -d '\r')
  if [[ "${first_line}" != "AUTHORIZED" ]]; then
    echo "ERROR: Authorization file does not start with the line 'AUTHORIZED': ${auth_file}"
    exit 1
  fi

  # Verify file is not older than 30 days
  local file_epoch
  file_epoch=$(stat -c %Y "${auth_file}" 2>/dev/null || stat -f %m "${auth_file}" 2>/dev/null)
  local now_epoch
  now_epoch=$(date +%s)
  local age=$(( now_epoch - file_epoch ))
  local max_age=$((30 * 24 * 3600))

  if [[ ${age} -gt ${max_age} ]]; then
    echo "ERROR: Authorization file is older than 30 days. Re-authorize."
    exit 1
  fi
  # Fecha futura (reloj o touch manipulado): la autorización no caduca nunca.
  if [[ ${age} -lt -300 ]]; then
    echo "ERROR: Authorization file has a future timestamp. Re-authorize."
    exit 1
  fi

  echo "[auth] Authorization verified for host: ${host}"
}

run_dalfox() {
  local target_url="$1"
  local outfile="$2"
  echo "[dalfox] Starting XSS scan (safe mode: ${SAFE})..."
  local dalfox_args=("url" "${target_url}" "--output" "${outfile}" "--format" "json" "--silence")
  if command -v dalfox &>/dev/null; then
    dalfox "${dalfox_args[@]}" 2>/dev/null || true
    echo "[dalfox] Done (native binary)"
  elif docker info &>/dev/null 2>&1; then
    docker run --rm "ghcr.io/hahwul/dalfox:latest" "${dalfox_args[@]}" 2>/dev/null > "${outfile}" || true
    echo "[dalfox] Done (Docker fallback)"
  else
    echo "[dalfox] SKIP — not available"
  fi
}

run_sqlmap() {
  local target_url="$1"
  local outdir="$2"
  echo "[sqlmap] Starting SQLi scan (safe mode: level 1 risk 1)..."
  # Always use conservative settings: --level 1 --risk 1 --batch
  local sqlmap_args=("-u" "${target_url}" "--forms" "--batch"
                     "--level" "1" "--risk" "1"
                     "--output-dir" "${outdir}" "--quiet")
  if command -v sqlmap &>/dev/null; then
    sqlmap "${sqlmap_args[@]}" 2>/dev/null || true
    echo "[sqlmap] Done (native binary)"
  elif docker info &>/dev/null 2>&1; then
    docker run --rm "paoloo/sqlmap" "${sqlmap_args[@]}" 2>/dev/null || true
    echo "[sqlmap] Done (Docker fallback)"
  else
    echo "[sqlmap] SKIP — not available"
  fi
}

run_nuclei_web() {
  local target_url="$1"
  local outfile="$2"
  echo "[nuclei] Starting web vulnerability scan..."
  if command -v nuclei &>/dev/null; then
    nuclei -u "${target_url}" -tags "xss,sqli,lfi" -silent -json -o "${outfile}" 2>/dev/null || true
    echo "[nuclei] Done (native binary)"
  elif docker info &>/dev/null 2>&1; then
    docker run --rm "projectdiscovery/nuclei" -u "${target_url}" -tags "xss,sqli,lfi" -silent -json 2>/dev/null > "${outfile}" || true
    echo "[nuclei] Done (Docker fallback)"
  else
    echo "[nuclei] SKIP — not available"
  fi
}

main() {
  parse_args "$@"

  mkdir -p "${OUTPUT_DIR}"

  # Authorization gate
  check_authorization "${TARGET_HOST}"

  local report_dir="${OUTPUT_DIR}/dynamic-test-${TARGET_HOST}-${DATE_STAMP}"
  mkdir -p "${report_dir}/sqlmap"

  local xss_out="${report_dir}/dalfox-results.json"
  local nuclei_out="${report_dir}/nuclei-results.json"

  echo "[dynamic-web-test] Target: ${TARGET}"
  echo "[dynamic-web-test] Host: ${TARGET_HOST}"
  echo "[dynamic-web-test] Safe mode: ${SAFE}"
  echo "[dynamic-web-test] Report: ${report_dir}"

  IFS=',' read -ra TOOL_LIST <<< "${TOOLS}"
  for tool in "${TOOL_LIST[@]}"; do
    case "${tool}" in
      xss)    run_dalfox "${TARGET}" "${xss_out}" ;;
      sqli)   run_sqlmap "${TARGET}" "${report_dir}/sqlmap" ;;
      nuclei) run_nuclei_web "${TARGET}" "${nuclei_out}" ;;
      *)      echo "[warn] Unknown tool: ${tool}" ;;
    esac
  done

  # Build consolidated JSON report
  local report_json="${OUTPUT_DIR}/dynamic-test-${TARGET_HOST}-${DATE_STAMP}.json"
  cat > "${report_json}" <<EOF
{
  "target": "${TARGET}",
  "host": "${TARGET_HOST}",
  "date": "${DATE_STAMP}",
  "safe_mode": ${SAFE},
  "tools": "${TOOLS}",
  "report_dir": "${report_dir}",
  "xss_results": "${xss_out}",
  "sqli_dir": "${report_dir}/sqlmap",
  "nuclei_results": "${nuclei_out}"
}
EOF

  echo "[dynamic-web-test] Report written: ${report_json}"
  echo "[dynamic-web-test] Done."
}

main "$@"
