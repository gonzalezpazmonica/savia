#!/usr/bin/env bash
# verified-installer.sh — SE-465 S2 (alertas SE-442 #84, #93).
#
# Sustituye `curl <url> | sh` por: descargar a un fichero temporal, comprobar
# su SHA-256 contra un valor fijado en el repo y solo entonces ejecutarlo.
# Si el hash no coincide, no se ejecuta nada y se devuelve error.
#
# Uso (tras `source`):
#   savia_run_verified_installer <url> <sha256> [VAR=valor ...]
#   savia_install_ollama_pinned        # Linux: instalador oficial de una etiqueta fija
#
# Para subir de versión de Ollama: cambiar OLLAMA_PINNED_VERSION, descargar
# $OLLAMA_INSTALLER_URL y fijar su `sha256sum` en OLLAMA_INSTALLER_SHA256.

OLLAMA_PINNED_VERSION="0.40.18"
OLLAMA_INSTALLER_URL="https://raw.githubusercontent.com/ollama/ollama/v${OLLAMA_PINNED_VERSION}/scripts/install.sh"
OLLAMA_INSTALLER_SHA256="17659c2456c9e65a3b11056b76da51774911cb822f47bf44f7f3ecc0c40528a8"

_savia_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else return 1
  fi
}

savia_run_verified_installer() {
  local url="${1:-}" want="${2:-}"
  shift 2 2>/dev/null || true
  if [[ -z "$url" || ! "$want" =~ ^[0-9a-f]{64}$ ]]; then
    echo "ERROR: savia_run_verified_installer <url> <sha256 de 64 hex> [VAR=valor ...]" >&2
    return 2
  fi
  local tmp got rc a
  for a in "$@"; do
    [[ "$a" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || { echo "ERROR: argumento no es VAR=valor: $a" >&2; return 2; }
  done
  tmp="$(mktemp)" || return 2
  if ! curl -fsSL -o "$tmp" "$url"; then
    rm -f "$tmp"; echo "ERROR: no se pudo descargar $url" >&2; return 3
  fi
  if ! got="$(_savia_sha256 "$tmp")"; then
    rm -f "$tmp"; echo "ERROR: falta sha256sum/shasum para verificar $url" >&2; return 3
  fi
  if [[ "$got" != "$want" ]]; then
    rm -f "$tmp"
    echo "ERROR: SHA-256 de $url no coincide (esperado $want, obtenido $got); no se ejecuta" >&2
    return 4
  fi
  env "$@" sh "$tmp"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

savia_install_ollama_pinned() {
  savia_run_verified_installer "$OLLAMA_INSTALLER_URL" "$OLLAMA_INSTALLER_SHA256" \
    "OLLAMA_VERSION=$OLLAMA_PINNED_VERSION"
}
