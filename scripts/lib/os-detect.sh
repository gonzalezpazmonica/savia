#!/usr/bin/env bash
# scripts/lib/os-detect.sh — Portable OS detection and path defaults
# Source this from other scripts: source "$(dirname "$0")/lib/os-detect.sh"
# Provides: detect_os() → "linux" | "macos" | "windows" | "unknown"
#           jq() en Windows — salida sin CRLF (--binary), exportada
#           setup_paths() → exports OLLAMA_BIN, ANDROID_HOME, JAVA_HOME

detect_os() {
  case "$(uname -s 2>/dev/null || echo 'Windows')" in
    Linux*)               echo "linux"   ;;
    Darwin*)              echo "macos"   ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    Windows_NT*)          echo "windows" ;;
    *)                    echo "unknown" ;;
  esac
}

setup_paths() {
  local os
  os=$(detect_os)
  case "$os" in
    windows)
      OLLAMA_BIN="${OLLAMA_BIN:-$HOME/AppData/Local/Programs/Ollama/ollama.exe}"
      ANDROID_HOME="${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}"
      JAVA_HOME="${JAVA_HOME:-$HOME/AppData/Local/Programs/Eclipse Adoptium/jdk-17}"
      ;;
    macos)
      OLLAMA_BIN="${OLLAMA_BIN:-/usr/local/bin/ollama}"
      ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
      JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}"
      ;;
    linux)
      OLLAMA_BIN="${OLLAMA_BIN:-/usr/local/bin/ollama}"
      ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
      JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
      ;;
    *)
      OLLAMA_BIN="${OLLAMA_BIN:-ollama}"
      ANDROID_HOME="${ANDROID_HOME:-}"
      JAVA_HOME="${JAVA_HOME:-}"
      ;;
  esac
  export OLLAMA_BIN ANDROID_HOME JAVA_HOME
}

# jq para Windows termina cada línea en \r\n; $(...) solo quita el \n y las
# comparaciones con la salida de `jq -r` fallaban en silencio ("x\r" != "x").
# --binary emite \n. Exportada: la heredan los bash hijos. Fuera de Windows no
# define nada.
case "${OSTYPE:-}" in
  msys*|cygwin*) jq() { command jq --binary "$@"; }; export -f jq ;;
esac
