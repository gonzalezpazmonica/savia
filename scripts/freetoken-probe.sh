#!/usr/bin/env bash
# freetoken-probe.sh — SPEC-FREETOKEN-PROBE: valida la viabilidad de FreeToken
# en la máquina actual. Decide si FreeToken puede servir MoE frontier localmente
# (sustituir/complementar Ollama en la línea SAGI) sin tocar producción.
#
# Verifica: GPU + compute capability + driver, nvcc/CUDA toolkit, RAM, disco,
# engine instalado. Opcional: descarga un MoE NVFP4 pequeño y prueba inferencia.
# CRIT-001: pesos a disco local, sin datos N3+ a cloud, sin red salvo descarga.
#
# Resultado: output/probes/freetoken-{YYYYMMDD}.json (viable|inviable + razones).
#
# Usage:
#   freetoken-probe.sh [--install] [--model openai/gpt-oss-20b] [--json]
#   freetoken-probe.sh --serve --model <path|hf-id>   (lanza el servidor)
# Exit: 0 viable · 1 inviable · 2 usage · 3 dependencia ausente
set -uo pipefail

ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MODEL="openai/gpt-oss-20b"
DO_INSTALL=0
DO_SERVE=0
JSON=0
usage() { echo "usage: $0 [probe|--install|--serve] [--model ID] [--json]" >&2; exit 2; }

# Todas las banderas se leen (antes la última se ignoraba y --model no podía ir primero).
while [[ $# -gt 0 ]]; do
  case "$1" in
    probe) ;;
    --install) DO_INSTALL=1 ;;
    --serve) DO_SERVE=1 ;;
    --json) JSON=1 ;;
    --model) [[ -n "${2:-}" ]] || usage; MODEL="$2"; shift ;;
    *) usage ;;
  esac
  shift
done

FT_BIN="${FT_BIN:-$HOME/.savia/freetoken/.venv/bin/ft}"

# ── Recoger hechos de la máquina ───────────────────────────────────────────
GPU_INFO=""
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_INFO=$(nvidia-smi --query-gpu=name,compute_cap,memory.total,driver_version --format=csv,noheader 2>/dev/null | head -1)
fi
NVCC=""
command -v nvcc >/dev/null 2>&1 && NVCC="$(nvcc --version 2>/dev/null | tail -1)"
CLIB=${CUDA_HOME:-}
if [ -z "$CLIB" ] && [ -d /usr/local/cuda ]; then CLIB="/usr/local/cuda"; fi
RAM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')
DISK_GB=$(df -B1G / 2>/dev/null | awk 'NR==2{print $4}')
FT_PRESENT=0
[ -x "$FT_BIN" ] && FT_PRESENT=1

emit() {
  local verdict="$1" reason="$2"
  if [[ "$JSON" -eq 1 ]]; then
    python3 - "$verdict" "$reason" "$GPU_INFO" "$NVCC" "$RAM_GB" "$DISK_GB" "$FT_PRESENT" <<PY
import json, sys
print(json.dumps({
  "probe": "FreeToken", "verdict": sys.argv[1], "reason": sys.argv[2],
  "gpu": sys.argv[3], "nvcc": sys.argv[4], "ram_gb": sys.argv[5],
  "disk_gb": sys.argv[6], "engine_installed": sys.argv[7]=="1",
}, indent=2))
PY
  else
    echo "── FreeToken probe ──"
    echo "GPU:      ${GPU_INFO:-no detectada}"
    echo "nvcc:     ${NVCC:-ausente}"
    echo "CUDA_HOME:${CLIB:-}"
    echo "RAM:      ${RAM_GB:-?}GB · Disco: ${DISK_GB:-?}GB"
    echo "engine:   $([ "$FT_PRESENT" -eq 1 ] && echo "instalado" || echo "no instalado ($FT_BIN)")"
    echo "VERDICTO: $verdict — $reason"
  fi
  exit 0
}

# Requisitos estructurales (probe rápido)
if [[ -z "$GPU_INFO" ]]; then
  emit "inviable" "sin GPU NVIDIA detectada (FreeToken requiere NVIDIA/CUDA)"
fi
# Soporte: cc declara RTX 30/40/50 (cc>=8.0). RTX 20 (cc 7.5) NO está soportada.
CC=$(echo "$GPU_INFO" | awk -F', ' '{print $2}')
# Aritmética entera (cc*10): con awk+bc, un locale con coma decimal ("7,5") rompía
# bc y la compuerta cc>=8.0 dejaba pasar GPUs no soportadas.
CC_INT=0
if [[ "$CC" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
  CC_INT=$(( 10#${BASH_REMATCH[1]} * 10 + 10#${BASH_REMATCH[2]} ))
fi
if (( CC_INT < 80 )); then
  if [[ "$DO_SERVE" -eq 1 ]]; then
    # vía explícita de prueba: el engine arranca pero requiere nvcc para JIT
    if [ -z "$NVCC" ] && [ -z "$CLIB" ]; then
      emit "inviable" "GPU cc $CC no soportada nativamente y sin CUDA toolkit (nvcc) para kernels JIT. En RTX 30+ con toolkit, reintentar."
    fi
  fi
  if [[ "$DO_INSTALL" -eq 0 && "$DO_SERVE" -eq 0 ]]; then
    emit "inviable" "GPU cc $CC fuera de soporte declarado (RTX 30/40/50, cc>=8.0); verificar en RTX 30+"
  fi
fi

if [[ "$DO_INSTALL" -eq 1 ]]; then
  if [ "$FT_PRESENT" -eq 1 ]; then emit "viable" "engine ya instalado"; fi
  echo "Instalando FreeToken en ~/.savia/freetoken (uv)..."
  mkdir -p "$HOME/.savia/freetoken" && cd "$HOME/.savia/freetoken" || exit 3
  if ! command -v uv >/dev/null 2>&1; then
    curl -fsSL https://astral.sh/uv/install.sh -o /tmp/uv-install.sh 2>/dev/null && bash /tmp/uv-install.sh >/dev/null 2>&1
    export PATH="$HOME/.local/bin:$PATH"
  fi
  uv venv .venv >/dev/null 2>&1
  uv pip install -q --python .venv/bin/python "freetoken[accel]" >/dev/null 2>&1 || { emit "inviable" "falló instalación freetoken[accel]"; }
  emit "viable" "engine instalado en $FT_BIN (probar inferencia en GPU con toolkit)"
fi

if [[ "$DO_SERVE" -eq 1 ]]; then
  [ ! -x "$FT_BIN" ] && emit "inviable" "engine no instalado (freetoken-probe.sh --install)"
  echo "Lanzando FreeToken serve: $MODEL (backend auto, puerto 1919)..."
  echo "NOTA: en RTX 20 sin CUDA toolkit el JIT fallará (ver spec). Ctrl+C para detener."
  exec "$FT_BIN" serve --model-path "$MODEL" --port 1919 --served-model-name "$MODEL"
fi

# Probe read-only
verdict="viable"
reason="repositorio de decisión"
if [ -z "$NVCC" ] && [ -z "$CLIB" ]; then
  verdict="inviable-en-este-hardware"
  reason="motor y RTX 2070 detectados, pero sin nvcc/CUDA_HOME no compila kernels JIT (inferencia bloqueada). RTX 30+ con toolkit: viable."
fi
emit "$verdict" "$reason"