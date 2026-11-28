#!/usr/bin/env bash
# sonora-tests.sh — SE-537: tests de Savia Sonora (app) igual en local que en CI.
#
#   bash scripts/sonora-tests.sh [backend|frontend|all]   (por defecto: all)
#
# backend : pytest de projects/savia-sonora/app con Python 3.12 y dependencias
#           instaladas solo desde uv.lock (uv sync --frozen). Sin descargas de
#           modelos: HF_HUB_OFFLINE=1 y los tests que cargan pesos se saltan con
#           motivo (scripts/sonora-tests-weights.txt).
# frontend: vitest y tsc con pnpm fijado y el lockfile congelado.
#
# Variables:
#   SONORA_VENV            entorno virtual (def. ~/.cache/savia-sonora-tests/venv312)
#   SONORA_PYTHON_VERSION  versión de Python para uv (def. 3.12)
#   SONORA_PNPM            orden pnpm (def. corepack pnpm@10.34.9)
#   SONORA_WITH_WEIGHTS=1  ejecuta también los tests que necesitan pesos
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/projects/savia-sonora/app"
WEIGHTS_LIST="$REPO_ROOT/scripts/sonora-tests-weights.txt"
PNPM_PIN="pnpm@10.34.9"

usage() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

backend() {
  local venv="${SONORA_VENV:-$HOME/.cache/savia-sonora-tests/venv312}"
  local pyver="${SONORA_PYTHON_VERSION:-3.12}"
  command -v uv >/dev/null 2>&1 || { echo "ERROR: falta uv" >&2; return 1; }
  echo "== backend: uv sync --frozen (Python $pyver) en $venv"
  # Solo el Python instalado en la máquina: nada de descargas implícitas.
  (cd "$APP" && UV_PYTHON_DOWNLOADS=never UV_PROJECT_ENVIRONMENT="$venv" \
    uv sync --frozen --python "$pyver")
  echo "== backend: pytest"
  (cd "$APP" && \
    QT_QPA_PLATFORM=offscreen HF_HUB_OFFLINE=1 \
    PYTHONPATH="$REPO_ROOT/scripts/lib${PYTHONPATH:+:$PYTHONPATH}" \
    SONORA_WEIGHTS_SKIP_FILE="$WEIGHTS_LIST" \
    "$venv/bin/python" -m pytest src-pyloid/tests/ -q -rs \
      -p sonora_weights_skip -p no:cacheprovider)
}

frontend() {
  local pnpm="${SONORA_PNPM:-corepack $PNPM_PIN}"
  echo "== frontend: $pnpm install --frozen-lockfile"
  # shellcheck disable=SC2086  # la orden pnpm puede llevar prefijo (corepack)
  (cd "$APP" && COREPACK_ENABLE_DOWNLOAD_PROMPT=0 $pnpm install --frozen-lockfile)
  echo "== frontend: vitest"
  # shellcheck disable=SC2086
  (cd "$APP" && $pnpm exec vitest run)
  echo "== frontend: tsc -b"
  # shellcheck disable=SC2086
  (cd "$APP" && $pnpm exec tsc -b)
}

mode="${1:-all}"
case "$mode" in
  -h|--help) usage; exit 0 ;;
  backend) backend ;;
  frontend) frontend ;;
  all) backend; frontend ;;
  *) echo "modo desconocido: $mode (backend|frontend|all)" >&2; exit 2 ;;
esac
