#!/usr/bin/env bash
# install.sh — prepara Soul Continuidad en tu cuenta, sin permisos de administración (Linux y macOS).
#
#   1. Busca un Node.js que ejecute el TypeScript de Soul (el de Ubuntu/Debian no: ERR_NO_TYPESCRIPT).
#      Si no lo hay, descarga el Node.js LTS oficial de nodejs.org, comprueba su SHA-256 con
#      SHASUMS256.txt y lo deja en ~/.savia/node.
#   2. Crea la orden «soul» en ~/.local/bin (sin alias). No pisa una orden «soul» que no sea suya.
#   3. Dice el siguiente paso: soul setup.
#
# Uso: bash install.sh [--download]
#   --download   baja el Node oficial aunque el del PATH ya sirva.
# Variables (para espejos corporativos): SOUL_NODE_MIRROR (https://nodejs.org/dist), SOUL_NODE_LINE (latest-v24.x).
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR="${SOUL_NODE_MIRROR:-https://nodejs.org/dist}"
LINE="${SOUL_NODE_LINE:-latest-v24.x}"
DEST="$HOME/.savia/node"
BIN_DIR="$HOME/.local/bin"
MARK="# soul-continuity: generado por install.sh"
FORCE=0

for a in "$@"; do
  case "$a" in
    --download) FORCE=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "install.sh: opción desconocida: $a (usa --help)" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# ¿Este Node ejecuta el TypeScript de Soul? Se prueba de verdad con la sonda del lanzador.
works() { [ -x "$1" ] && "$1" --experimental-strip-types --no-warnings "$PKG/bin/sonda.ts" 2>/dev/null | grep -q '^soul-ts-ok '; }

fetch() { # url destino
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then wget -q "$1" -O "$2"
  else die "necesito curl o wget para descargar Node.js. Instala uno de los dos, o Node.js LTS oficial con nvm o fnm, y repite."
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

download_node() {
  local os arch name want got
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) die "sistema no admitido por install.sh: $(uname -s). Instala Node.js LTS desde https://nodejs.org." ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=x64 ;; aarch64|arm64) arch=arm64 ;; *) die "arquitectura no admitida: $(uname -m). Instala Node.js LTS desde https://nodejs.org." ;; esac
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' EXIT
  say "Descargando Node.js LTS oficial ($LINE, $os-$arch) de $MIRROR…"
  fetch "$MIRROR/$LINE/SHASUMS256.txt" "$tmp/SHASUMS256.txt" || die "no pude descargar $MIRROR/$LINE/SHASUMS256.txt"
  name="$(grep -Eo "node-v[0-9]+\.[0-9]+\.[0-9]+-$os-$arch\.tar\.gz$" "$tmp/SHASUMS256.txt" | head -n1 || true)"
  [ -n "$name" ] || die "no encuentro Node.js para $os-$arch en $MIRROR/$LINE"
  want="$(grep -E "  $name$" "$tmp/SHASUMS256.txt" | cut -d' ' -f1)"
  fetch "$MIRROR/$LINE/$name" "$tmp/$name" || die "no pude descargar $name"
  got="$(sha256 "$tmp/$name")"
  [ -n "$want" ] && [ "$got" = "$want" ] || die "la suma SHA-256 de $name no coincide con SHASUMS256.txt: descarga corrupta o manipulada. No se instala nada."
  mkdir -p "$tmp/x"
  tar -xzf "$tmp/$name" -C "$tmp/x"
  works "$tmp/x/${name%.tar.gz}/bin/node" || die "el Node descargado no ejecuta TypeScript; no se instala."
  mkdir -p "$(dirname "$DEST")"
  # Un ~/.savia/node anterior que no sirve se aparta, no se borra.
  if [ -e "$DEST" ]; then mv "$DEST" "$DEST.anterior-$(date +%Y%m%d%H%M%S)"; fi
  mv "$tmp/x/${name%.tar.gz}" "$DEST"
  say "Node.js $("$DEST/bin/node" --version) instalado en $DEST"
}

tmp=""
NODE=""
if [ "$FORCE" = 0 ]; then
  if works "$DEST/bin/node"; then NODE="$DEST/bin/node"
  elif p="$(command -v node 2>/dev/null)" && works "$p"; then NODE="$p"
  fi
fi
if [ -z "$NODE" ]; then
  download_node
  NODE="$DEST/bin/node"
fi
say "Node.js que usará Soul: $NODE ($("$NODE" --version))"

mkdir -p "$BIN_DIR"
W="$BIN_DIR/soul"
if [ -e "$W" ] && ! grep -qF "$MARK" "$W"; then
  printf 'install.sh: ya hay una orden «soul» en %s que no creé yo; no la toco. Usa: "%s" "%s/bin/soul.mjs"\n' "$W" "$NODE" "$PKG" >&2
else
  printf '#!/bin/sh\n%s\nexec "%s" "%s/bin/soul.mjs" "$@"\n' "$MARK" "$NODE" "$PKG" > "$W"
  chmod 755 "$W"
  say "Orden creada: $W"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "Aviso: $BIN_DIR no está en tu PATH. Añade esta línea a ~/.bashrc (o ~/.zshrc) y abre una terminal nueva:"
     say "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
say ""
say "Siguiente paso, en tu terminal: soul setup"
