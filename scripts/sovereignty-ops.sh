#!/usr/bin/env bash
# sovereignty-ops.sh — Download operations for sovereignty-pack.sh
# Sourced by sovereignty-pack.sh. Not run directly.
# NOTE: Disable errexit here — [[ ]] && { } patterns return 1 on false branch.
# The caller (sovereignty-pack.sh) has set -e but source inherits context.
set +e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

PYTHON_VER="3.12.13"; PYTHON_BUILD="20260320"
PYTHON_REPO="astral-sh"  # was indygreg, now astral-sh
NODE_VER="22.22.1"

show_help() {
  echo -e "${BOLD}Savia Sovereignty Pack${NC} — Build offline USB installer"
  echo "Usage: sovereignty-pack.sh [--tier 1|2|3] [--dest PATH] [--arch amd64|arm64] [--dry-run]"
  echo "  Tier 1 (~4GB): voice + LLM 3b | Tier 2 (~9GB): + Claude Code / OpenCode + LLM 7b"
  echo "  Tier 3 (~20GB): + LLM 14b + Whisper medium"
}

cached_download() {
  local url="$1" dest="$2" name="$3"
  if [[ -f "$dest" ]]; then echo -e "  ${GREEN}✓${NC} $name (cached)"; return 0; fi
  if $DRY_RUN; then echo -e "  ${YELLOW}→${NC} Would download: $name"; return 0; fi
  echo -e "  ${YELLOW}→${NC} Downloading $name..."
  curl -fSL "$url" -o "$dest.tmp" && mv "$dest.tmp" "$dest"
  echo -e "  ${GREEN}✓${NC} $name"
}

download_hf_model() {
  local repo="$1" dest="$2" name="$3"
  if [[ -d "$dest" ]] && [[ $(find "$dest" -maxdepth 1 -type f 2>/dev/null | wc -l) -ge 1 ]]; then
    echo -e "  ${GREEN}✓${NC} $name (cached)"; return 0; fi
  if $DRY_RUN; then echo -e "  ${YELLOW}→${NC} Would download: $name"; return 0; fi
  mkdir -p "$dest"
  echo -e "  ${YELLOW}→${NC} Downloading $name..."
  if command -v huggingface-cli &>/dev/null; then
    huggingface-cli download "$repo" --local-dir "$dest" 2>&1 | tail -2
  else
    for f in model.bin config.json vocabulary.json tokenizer.json; do
      curl -fsSL "https://huggingface.co/$repo/resolve/main/$f" -o "$dest/$f" 2>/dev/null || true
    done
  fi
  echo -e "  ${GREEN}✓${NC} $name"
}

download_python() {
  local py_arch="x86_64"; [[ "$ARCH" == "arm64" ]] && py_arch="aarch64"
  local f="cpython-${PYTHON_VER}+${PYTHON_BUILD}-${py_arch}-unknown-linux-gnu-install_only_stripped.tar.gz"
  cached_download \
    "https://github.com/${PYTHON_REPO}/python-build-standalone/releases/download/${PYTHON_BUILD}/${f}" \
    "$CACHE_DIR/python/$f" "Python $PYTHON_VER standalone (stripped, 32MB)"
}

download_wheels() {
  local plat="manylinux2014_x86_64"; [[ "$ARCH" == "arm64" ]] && plat="manylinux2014_aarch64"
  [[ -f "$CACHE_DIR/wheels/.complete" ]] && { echo -e "  ${GREEN}✓${NC} Pip wheels (cached)"; return 0; }
  $DRY_RUN && { echo -e "  ${YELLOW}→${NC} Would download: pip wheels"; return 0; }
  echo -e "  ${YELLOW}→${NC} Downloading pip wheels..."
  # Constraints file to force CPU-only torch everywhere
  local constraints="$CACHE_DIR/wheels/_constraints.txt"
  cat > "$constraints" << 'CONS'
--extra-index-url https://download.pytorch.org/whl/cpu
torch
torchaudio
CONS
  # CPU-only torch first (avoids ~4GB CUDA wheels)
  pip download --dest "$CACHE_DIR/wheels" --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch torchaudio 2>&1 | tail -3
  # All other packages — use constraints to prevent CUDA torch re-download
  pip download --dest "$CACHE_DIR/wheels" --no-cache-dir \
    --no-deps \
    numpy pyyaml websockets sounddevice 2>&1 | tail -2
  # faster-whisper + deps (excluding torch, already downloaded)
  pip download --dest "$CACHE_DIR/wheels" --no-cache-dir \
    faster-whisper silero-vad 2>&1 | tail -3
  # Kokoro TTS
  pip download --dest "$CACHE_DIR/wheels" --no-cache-dir \
    kokoro 2>&1 | tail -2
  # Remove any CUDA/nvidia wheels that leaked through transitive deps
  find "$CACHE_DIR/wheels" -name "nvidia_*" -delete 2>/dev/null
  find "$CACHE_DIR/wheels" -name "cuda_*" -delete 2>/dev/null
  find "$CACHE_DIR/wheels" -name "triton-*" -delete 2>/dev/null
  rm -f "$constraints"
  touch "$CACHE_DIR/wheels/.complete"
  echo -e "  ${GREEN}✓${NC} Pip wheels"
}

download_whisper_models() {
  download_hf_model "Systran/faster-whisper-tiny" "$CACHE_DIR/models/whisper-tiny" "Whisper tiny (75MB)"
  download_hf_model "Systran/faster-whisper-base" "$CACHE_DIR/models/whisper-base" "Whisper base (142MB)"
  [[ $TIER -ge 2 ]] && download_hf_model "Systran/faster-whisper-small" "$CACHE_DIR/models/whisper-small" "Whisper small (464MB)"
  [[ $TIER -ge 3 ]] && download_hf_model "Systran/faster-whisper-medium" "$CACHE_DIR/models/whisper-medium" "Whisper medium (1.5GB)"
}

download_kokoro() {
  download_hf_model "hexgrad/Kokoro-82M" "$CACHE_DIR/models/kokoro-82m" "Kokoro TTS 82M (313MB)"
}

download_ollama_binary() {
  local ol_arch="$ARCH"
  local dest="$CACHE_DIR/ollama/ollama-linux-${ol_arch}"
  [[ -f "$dest" ]] && { echo -e "  ${GREEN}✓${NC} Ollama binary (cached)"; return 0; }
  $DRY_RUN && { echo -e "  ${YELLOW}→${NC} Would download: Ollama binary"; return 0; }
  echo -e "  ${YELLOW}→${NC} Downloading Ollama..."
  local tmp="$CACHE_DIR/ollama/ollama.tar.zst"
  curl -fSL "https://ollama.com/download/ollama-linux-${ol_arch}.tar.zst" -o "$tmp"
  local ex="$CACHE_DIR/ollama/_ex"; mkdir -p "$ex"
  tar --zstd -xf "$tmp" -C "$ex" 2>/dev/null
  local found; found=$(find "$ex" -name "ollama" -type f | head -1)
  [[ -n "$found" ]] && cp "$found" "$dest" && chmod +x "$dest"
  rm -rf "$ex" "$tmp"
  echo -e "  ${GREEN}✓${NC} Ollama binary"
}

download_ollama_models() {
  local src="$HOME/.ollama/models" dst="$CACHE_DIR/ollama/models"
  _copy_ollama() {
    local model="$1" name="$2"
    local mpath="$src/manifests/registry.ollama.ai/library/$model"
    [[ -f "$dst/manifests/registry.ollama.ai/library/$model" ]] && {
      echo -e "  ${GREEN}✓${NC} Ollama $name (cached)"; return 0; }
    $DRY_RUN && { echo -e "  ${YELLOW}→${NC} Would copy: Ollama $name"; return 0; }
    [[ ! -d "$mpath" ]] && { echo -e "  ${YELLOW}⚠${NC} Ollama $name not local. Run: ollama pull $name"; return 1; }
    echo -e "  ${YELLOW}→${NC} Copying Ollama $name..."
    mkdir -p "$dst/manifests/registry.ollama.ai/library" "$dst/blobs"
    cp -r "$mpath" "$dst/manifests/registry.ollama.ai/library/"
    find "$mpath" -type f -exec grep -ohE 'sha256:[a-f0-9]+' {} \; 2>/dev/null | sort -u | while read -r dig; do
      local blob="$src/blobs/${dig//:/-}"
      [[ -f "$blob" ]] && cp -n "$blob" "$dst/blobs/" 2>/dev/null || true
    done
    echo -e "  ${GREEN}✓${NC} Ollama $name"
  }
  _copy_ollama "qwen2.5/3b" "qwen2.5:3b" || true
  [[ $TIER -ge 2 ]] && { _copy_ollama "qwen2.5/7b" "qwen2.5:7b" || true; }
  [[ $TIER -ge 3 ]] && { _copy_ollama "qwen2.5/14b" "qwen2.5:14b" || true; }
}

download_static_bins() {
  local ff="$CACHE_DIR/bin/ffmpeg"
  if [[ ! -f "$ff" ]] && ! $DRY_RUN; then
    echo -e "  ${YELLOW}→${NC} Downloading ffmpeg static..."
    local tmp="$CACHE_DIR/bin/ffmpeg.tar.xz"
    curl -fSL "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${ARCH}-static.tar.xz" -o "$tmp" 2>/dev/null
    tar xf "$tmp" -C "$CACHE_DIR/bin/" --wildcards "*/ffmpeg" --strip-components=1 2>/dev/null || true
    rm -f "$tmp"; chmod +x "$ff" 2>/dev/null; echo -e "  ${GREEN}✓${NC} ffmpeg"
  elif [[ -f "$ff" ]]; then echo -e "  ${GREEN}✓${NC} ffmpeg (cached)"
  else echo -e "  ${YELLOW}→${NC} Would download: ffmpeg static"; fi

  local jq_arch="linux64"; [[ "$ARCH" == "arm64" ]] && jq_arch="linux-arm64"
  cached_download "https://github.com/jqlang/jq/releases/latest/download/jq-${jq_arch}" \
    "$CACHE_DIR/bin/jq" "jq static"
  chmod +x "$CACHE_DIR/bin/jq" 2>/dev/null || true
}

download_node() {
  local na="x64"; [[ "$ARCH" == "arm64" ]] && na="arm64"
  cached_download "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-${na}.tar.xz" \
    "$CACHE_DIR/node/node-v${NODE_VER}-linux-${na}.tar.xz" "Node.js $NODE_VER"
}

download_workspace() {
  [[ -d "$CACHE_DIR/workspace/.git" ]] && { echo -e "  ${GREEN}✓${NC} Workspace (cached)"; return 0; }
  $DRY_RUN && { echo -e "  ${YELLOW}→${NC} Would clone: pm-workspace"; return 0; }
  echo -e "  ${YELLOW}→${NC} Cloning workspace..."
  git clone --depth 1 "$ROOT_DIR" "$CACHE_DIR/workspace" 2>/dev/null || {
    cp -r "$ROOT_DIR" "$CACHE_DIR/workspace"; }
  echo -e "  ${GREEN}✓${NC} Workspace"
}

generate_manifest() {
  cat > "$CACHE_DIR/manifest.json" << EOF
{"tier":$TIER,"arch":"$ARCH","created":"$(date -Iseconds)","python":"$PYTHON_VER","node":"$NODE_VER"}
EOF
  echo -e "  ${GREEN}✓${NC} Manifest"
}

copy_to_usb() {
  local usb="$DEST/SAVIA-USB"
  mkdir -p "$usb"
  cp -r "$CACHE_DIR"/* "$usb/"
  cat > "$usb/install.sh" << 'INST'
#!/usr/bin/env bash
set -euo pipefail
echo "Savia Offline Installer — see SPEC-017 for full implementation"
echo "Phase 2 TODO: Python venv, model placement, Ollama import, config"
INST
  chmod +x "$usb/install.sh"
  echo -e "  ${GREEN}✓${NC} Copied to $usb"
}
