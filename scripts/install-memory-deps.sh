#!/usr/bin/env bash
# Installs the optional vector-memory stack in Savia's isolated CPU-only venv.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${SAVIA_VENV_DIR:-$HOME/.savia/venv}"
SYSTEM_PYTHON="${SAVIA_SYSTEM_PYTHON:-python3}"

command -v "$SYSTEM_PYTHON" >/dev/null 2>&1 || {
  echo "ERROR: Python 3 not found: $SYSTEM_PYTHON" >&2
  exit 1
}

"$SYSTEM_PYTHON" -m venv "$VENV_DIR"
PYTHON="$VENV_DIR/bin/python"
[[ -x "$PYTHON" ]] || PYTHON="$VENV_DIR/Scripts/python.exe"
[[ -x "$PYTHON" ]] || {
  echo "ERROR: venv Python not found under $VENV_DIR" >&2
  exit 1
}
"$PYTHON" -m pip install --upgrade pip

# SE-442 S5: lock con hashes (incluye la wheel CPU de torch del indice oficial
# de PyTorch). Sin sdist ni paquetes sin hash: pip aborta si algo no coincide.
"$PYTHON" -m pip install --require-hashes --only-binary=:all: \
  --extra-index-url https://download.pytorch.org/whl/cpu \
  -r "$ROOT/scripts/requirements-memory.lock.txt"
"$PYTHON" -m pip check
"$PYTHON" -c "import faiss, sentence_transformers, torch; assert not torch.cuda.is_available()"

echo "Memory dependencies installed: $PYTHON"
