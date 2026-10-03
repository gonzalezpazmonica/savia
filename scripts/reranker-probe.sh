#!/usr/bin/env bash
# reranker-probe.sh — SE-032 Slice 1 reranker viability probe.
#
# Evalúa preconditions para integrar un reranker (cross-encoder) sobre
# outputs de memoria/búsqueda. No instala nada — solo reporta.
#
# Modelo por defecto de scripts/rerank.py: BAAI/bge-reranker-base (--model lo cambia).
#
# Usage:
#   reranker-probe.sh
#   reranker-probe.sh --json
#
# Exit codes:
#   0 — VIABLE (python3 + sentence-transformers disponibles)
#   1 — BLOCKED (missing deps) o NEEDS_INSTALL
#   2 — usage error
#
# Ref: SE-032, ROADMAP §Tier 3 Champions
# Safety: read-only. set -uo pipefail.

set -uo pipefail

JSON=0

usage() {
  cat <<EOF
Usage:
  $0 [--json]

Probe preconditions para reranker (cross-encoder) integration.
Ref: SE-032.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Collect signals
PYTHON_VERSION=""
PYTHON_MAJOR=0
PIP_OK=0
SENTENCE_TRANS=0
TORCH_OK=0
DISK_FREE_GB=0

if command -v python3 >/dev/null 2>&1; then
  PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')" 2>/dev/null)
  PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
fi

command -v pip3 >/dev/null 2>&1 && PIP_OK=1

if command -v python3 >/dev/null 2>&1; then
  python3 -c "import sentence_transformers" 2>/dev/null && SENTENCE_TRANS=1
  python3 -c "import torch" 2>/dev/null && TORCH_OK=1
fi

# Disk free in GB
if command -v df >/dev/null 2>&1; then
  DISK_FREE_GB=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' | head -1)
  DISK_FREE_GB="${DISK_FREE_GB:-0}"
fi

VERDICT="VIABLE"
EXIT_CODE=0
REASONS=()

if [[ "$PYTHON_MAJOR" -lt 3 ]]; then
  VERDICT="BLOCKED"
  EXIT_CODE=1
  REASONS+=("Python 3 required, not found")
fi

if [[ "$PIP_OK" -eq 0 ]]; then
  # BLOCKED (sin Python) prevalece: instalar con pip no lo resuelve.
  [[ "$VERDICT" == "VIABLE" ]] && VERDICT="NEEDS_INSTALL"
  [[ "$EXIT_CODE" -eq 0 ]] && EXIT_CODE=1
  REASONS+=("pip3 not available")
fi

if [[ "$SENTENCE_TRANS" -eq 0 ]]; then
  [[ "$VERDICT" == "VIABLE" ]] && VERDICT="NEEDS_INSTALL"
  [[ "$EXIT_CODE" -eq 0 ]] && EXIT_CODE=1
  REASONS+=("sentence-transformers not installed (pip install sentence-transformers)")
fi

if [[ "$TORCH_OK" -eq 0 ]]; then
  [[ "$VERDICT" == "VIABLE" ]] && VERDICT="NEEDS_INSTALL"
  [[ "$EXIT_CODE" -eq 0 ]] && EXIT_CODE=1
  REASONS+=("torch not installed (required by sentence-transformers)")
fi

if [[ "${DISK_FREE_GB:-0}" -lt 3 ]]; then
  REASONS+=("disk free < 3GB (reranker model ~600MB, torch ~2GB)")
fi

if [[ "$JSON" -eq 1 ]]; then
  reasons_json=""
  for r in "${REASONS[@]}"; do
    r_esc=$(echo "$r" | sed 's/"/\\"/g')
    reasons_json+="\"$r_esc\","
  done
  reasons_json="[${reasons_json%,}]"
  cat <<JSON
{"verdict":"$VERDICT","python_version":"$PYTHON_VERSION","python_major":$PYTHON_MAJOR,"pip_ok":$PIP_OK,"sentence_transformers":$SENTENCE_TRANS,"torch":$TORCH_OK,"disk_free_gb":$DISK_FREE_GB,"reasons":$reasons_json}
JSON
else
  echo "=== SE-032 Reranker Viability Probe ==="
  echo ""
  echo "Python:"
  echo "  version:  ${PYTHON_VERSION:-not installed}"
  echo ""
  echo "Dependencies:"
  echo "  pip3:                   $([ "$PIP_OK" -eq 1 ] && echo '✅' || echo '❌')"
  echo "  sentence-transformers:  $([ "$SENTENCE_TRANS" -eq 1 ] && echo '✅' || echo '❌')"
  echo "  torch:                  $([ "$TORCH_OK" -eq 1 ] && echo '✅' || echo '❌')"
  echo ""
  echo "Disk: ${DISK_FREE_GB}GB free"
  echo ""
  echo "VERDICT: $VERDICT"
  for r in "${REASONS[@]}"; do
    echo "  • $r"
  done
  echo ""
  if [[ "$VERDICT" == "VIABLE" ]]; then
    echo "Next steps:"
    echo "  python3 scripts/rerank.py usara el backend cross-encoder."
    echo "  La primera invocacion descarga BAAI/bge-reranker-base (~560MB) del HF Hub."
  elif [[ "$VERDICT" == "NEEDS_INSTALL" ]]; then
    echo "Install:"
    echo "  pip install sentence-transformers torch"
  fi
fi

exit $EXIT_CODE
