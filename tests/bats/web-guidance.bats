#!/usr/bin/env bats
# SE-539 S1 — importador de guías web modernas (copia fija, sin código) y búsqueda local.
# Los fixtures son sintéticos: ningún test de importación usa la red.
IMP="scripts/web-guidance-import.sh"
SRCH="scripts/web-guidance.sh"
REAL="references/modern-web-guidance"
SHA="2b4aa13a72dd47cd135b06ce5abfccd92e19b24f"

setup() {
  set -o pipefail
  TMP=$(mktemp -d)
  mkdir -p "$TMP/src/GoogleChrome-modern-web-guidance-2b4aa13/skills/modern-web-guidance/guides/ui-components" \
           "$TMP/src/GoogleChrome-modern-web-guidance-2b4aa13/skills/modern-web-guidance/guides/ui-behaviors"
  TOP="$TMP/src/GoogleChrome-modern-web-guidance-2b4aa13"
  G="$TOP/skills/modern-web-guidance/guides"
  echo "Apache License fixture" > "$TOP/LICENSE"
  printf '# Dialog\n\n## Overview\n\nUse the native dialog element for modal windows.\n\nSee `light-dismiss-a-dialog` (via `npx -y modern-web-guidance@latest retrieve "light-dismiss-a-dialog"`) for more.\n' > "$G/ui-components/dialog.md"
  printf '# Light-Dismiss a Dialog\n\nClose a dialog by clicking the backdrop.\n\nBack to `dialog` (via `npx -y modern-web-guidance@latest retrieve "dialog"`).\n' > "$G/ui-behaviors/light-dismiss-a-dialog.md"
  DEST="$TMP/dest"
}

teardown() {
  rm -rf "$TMP"
}

_pack() { tar -czf "$TMP/f.tgz" -C "$TMP/src" .; }
_import() { WEB_GUIDANCE_TARBALL="$TMP/f.tgz" WEB_GUIDANCE_DEST="$DEST" bash "$IMP" "${1:-$SHA}"; }

@test "AC-1/AC-4 positivo: copia solo md, LICENSE y NOTICE; sin npx; enlaces resuelven" {
  _pack
  run _import
  [ "$status" -eq 0 ]
  [ -f "$DEST/LICENSE" ]
  [ -f "$DEST/NOTICE" ]
  grep -q "https://github.com/GoogleChrome/modern-web-guidance" "$DEST/NOTICE"
  grep -q "$SHA" "$DEST/NOTICE"
  grep -qE "^Tree-SHA256: [0-9a-f]{64}$" "$DEST/NOTICE"
  grep -qE "^Date: [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$DEST/NOTICE"
  run bash -c "find '$DEST' -type f ! -name '*.md' ! -name LICENSE ! -name NOTICE"
  [ -z "$output" ]
  run grep -r npx "$DEST"
  [ "$status" -ne 0 ]
  d="$DEST/guides/ui-components"
  grep -q '(\[light-dismiss-a-dialog\](../ui-behaviors/light-dismiss-a-dialog.md))' "$d/dialog.md"
  [ -f "$d/../ui-behaviors/light-dismiss-a-dialog.md" ]
  run bash -c "find '$DEST' -type f -perm /111"
  [ -z "$output" ]
}

@test "AC-2 negativo: rechaza rama, etiqueta, HEAD y hashes mal formados" {
  _pack
  for ref in main v1.0.0 HEAD 2b4aa13 "${SHA}0" "${SHA:0:39}" "${SHA^^}"; do
    run _import "$ref"
    [ "$status" -ne 0 ]
  done
  [ ! -e "$DEST" ]
  run bash "$IMP"
  [ "$status" -ne 0 ]
}

@test "AC-3 negativo: enlace simbolico en el arbol rechaza todo" {
  ln -s /etc/passwd "$G/ui-components/evil.md"
  _pack
  run _import
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "AC-3 negativo: fichero no md dentro de guides rechaza todo" {
  echo 'console.log(1)' > "$G/ui-components/x.js"
  _pack
  run _import
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "AC-3 negativo: mas de 300 ficheros rechaza todo" {
  for i in $(seq 1 299); do echo "# g$i" > "$G/ui-components/g$i.md"; done
  _pack
  run _import
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "AC-3 borde: exactamente 300 ficheros se acepta" {
  for i in $(seq 1 298); do echo "# g$i" > "$G/ui-components/g$i.md"; done
  _pack
  run _import
  [ "$status" -eq 0 ]
}

@test "AC-3 negativo: mas de 4 MB rechaza todo" {
  head -c 4300000 /dev/zero | tr '\0' 'a' > "$G/ui-components/big.md"
  _pack
  run _import
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

# _shim <orden> <script> — instala en $TMP/bin un envoltorio de la orden real (REAL_<ORDEN>).
_shim() {
  mkdir -p "$TMP/bin"
  printf '#!/usr/bin/env bash\nREAL=%q\n%s\n' "$(command -v "$1")" "$2" > "$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}

@test "P2-2 negativo: los topes se comprueban en el listado, antes de extraer nada" {
  # 5 MB de ceros: el tar.gz ocupa unos KB y se inflaría al extraer.
  head -c 5000000 /dev/zero > "$G/ui-components/bomba.md"
  _pack
  _shim tar 'for a in "$@"; do case "$a" in -x*|--extract) echo x >> "$TMP/tar-x.log";; esac; done; exec "$REAL" "$@"'
  run env PATH="$TMP/bin:$PATH" TMP="$TMP" WEB_GUIDANCE_TARBALL="$TMP/f.tgz" WEB_GUIDANCE_DEST="$DEST" bash "$IMP" "$SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"demasiado grande"* ]]
  [ ! -e "$TMP/tar-x.log" ]
  [ ! -e "$DEST" ]
}

@test "P2-2 negativo: mas de 300 ficheros en el listado se rechaza antes de extraer" {
  for i in $(seq 1 299); do echo "# g$i" > "$G/ui-components/g$i.md"; done
  _pack
  _shim tar 'for a in "$@"; do case "$a" in -x*|--extract) echo x >> "$TMP/tar-x.log";; esac; done; exec "$REAL" "$@"'
  run env PATH="$TMP/bin:$PATH" TMP="$TMP" WEB_GUIDANCE_TARBALL="$TMP/f.tgz" WEB_GUIDANCE_DEST="$DEST" bash "$IMP" "$SHA"
  [ "$status" -ne 0 ]
  [[ "$output" == *"demasiados ficheros"* ]]
  [ ! -e "$TMP/tar-x.log" ]
}

@test "P2-1 negativo: si la sustitucion final falla, la copia anterior sigue en su sitio" {
  _pack
  run _import
  [ "$status" -eq 0 ]
  echo previa > "$DEST/guides/marca.md"
  # El primer mv cuyo destino es DEST falla (disco lleno simulado); el resto, normal.
  _shim mv 'last="${!#}"; if [ "$last" = "$DEST" ] && [ ! -e "$TMP/mv-fallo" ]; then : > "$TMP/mv-fallo"; echo "mv: no space left" >&2; exit 1; fi; exec "$REAL" "$@"'
  mkdir -p "$TMP/othertmp"
  run env PATH="$TMP/bin:$PATH" TMP="$TMP" DEST="$DEST" TMPDIR="$TMP/othertmp" \
    WEB_GUIDANCE_TARBALL="$TMP/f.tgz" WEB_GUIDANCE_DEST="$DEST" bash "$IMP" "$SHA"
  [ "$status" -ne 0 ]
  [ -e "$TMP/mv-fallo" ]
  [ "$(cat "$DEST/guides/marca.md")" = previa ]
  [ -f "$DEST/NOTICE" ]
  # Sin restos del temporal junto al destino.
  [ -z "$(find "$(dirname "$DEST")" -maxdepth 1 -name '.wg.*')" ]
}

@test "P2-1 positivo: la sustitucion se prepara junto al destino, no en TMPDIR" {
  _pack
  run _import
  [ "$status" -eq 0 ]
  _shim mv 'printf "%s\n" "$*" >> "$TMP/mv.log"; exec "$REAL" "$@"'
  mkdir -p "$TMP/othertmp"
  run env PATH="$TMP/bin:$PATH" TMP="$TMP" TMPDIR="$TMP/othertmp" \
    WEB_GUIDANCE_TARBALL="$TMP/f.tgz" WEB_GUIDANCE_DEST="$DEST" bash "$IMP" "$SHA"
  [ "$status" -eq 0 ]
  [ -s "$TMP/mv.log" ]
  run grep -c othertmp "$TMP/mv.log"
  [ "$output" = 0 ]
  [ -z "$(find "$(dirname "$DEST")" -maxdepth 1 -name '.wg.*')" ]
}

@test "P2-6 negativo: enlace duro en el arbol rechaza todo" {
  ln "$G/ui-components/dialog.md" "$G/ui-behaviors/duro.md"
  _pack
  run _import
  [ "$status" -ne 0 ]
  [[ "$output" == *"enlaces"* ]]
  [ ! -e "$DEST" ]
}

@test "P2-6 negativo: el listado rechaza el enlace simbolico por si solo (guarda 1)" {
  ln -s /etc/passwd "$G/ui-components/evil.md"
  _pack
  run _import
  [ "$status" -ne 0 ]
  [[ "$output" == *"contiene enlaces"* ]]
}

@test "AC-5 negativo: referencia a id inexistente falla con el id y no deja copia" {
  printf '# Bad\n\nSee (via `npx -y modern-web-guidance@latest retrieve "no-existe-xyz"`).\n' > "$G/ui-components/bad.md"
  _pack
  run _import
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-existe-xyz"* ]]
  [ ! -e "$DEST" ]
}

@test "reimportar sustituye la copia anterior sin dejar restos" {
  _pack
  run _import
  [ "$status" -eq 0 ]
  echo stale > "$DEST/guides/stale.md"
  run _import
  [ "$status" -eq 0 ]
  [ ! -e "$DEST/guides/stale.md" ]
}

@test "search sobre fixture: puntua nombre y titulo y 'show' imprime la ruta" {
  _pack
  _import
  run env WEB_GUIDANCE_DIR="$DEST" bash "$SRCH" search "light dismiss dialog"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | head -1 | cut -f1)" = "light-dismiss-a-dialog" ]
  run env WEB_GUIDANCE_DIR="$DEST" bash "$SRCH" show dialog
  [ "$status" -eq 0 ]
  [[ "$output" == *"ui-components/dialog.md" ]]
  run env WEB_GUIDANCE_DIR="$DEST" bash "$SRCH" show ../../etc/passwd
  [ "$status" -ne 0 ]
  run env WEB_GUIDANCE_DIR="$DEST" bash "$SRCH" show no-existe
  [ "$status" -ne 0 ]
}

@test "AC-7 negativo: consulta sin coincidencias da lista vacia y codigo 0" {
  _pack
  _import
  run env WEB_GUIDANCE_DIR="$DEST" bash "$SRCH" search "zzzqqq inexistente"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "web-guidance.sh no contiene ordenes de red" {
  run grep -nE '\b(curl|wget|gh api|npx|npm|nc)\b' "$SRCH"
  [ "$status" -ne 0 ]
}

@test "AC-6 copia real: light-dismiss-a-dialog entre los tres primeros, sin red" {
  [ -d "$REAL/guides" ]
  if unshare -rn true 2>/dev/null; then
    run unshare -rn bash "$SRCH" search "light dismiss dialog"
  else
    run env http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 bash "$SRCH" search "light dismiss dialog"
  fi
  [ "$status" -eq 0 ]
  echo "$output" | head -3 | cut -f1 | grep -qx "light-dismiss-a-dialog"
}

@test "AC-1/AC-4 copia real: solo md/LICENSE/NOTICE, sin npx, enlaces cruzados resuelven" {
  run bash -c "find '$REAL' -type f ! -name '*.md' ! -name LICENSE ! -name NOTICE"
  [ -z "$output" ]
  run bash -c "find '$REAL' -type l -o -type f -perm /111"
  [ -z "$output" ]
  [ "$(find "$REAL/guides" -name '*.md' | wc -l)" -eq 211 ]
  grep -q "$SHA" "$REAL/NOTICE"
  run grep -r npx "$REAL"
  [ "$status" -ne 0 ]
  run python3 -I - "$REAL" <<'PY'
import os, re, sys
bad = []
for dp, _, fs in os.walk(sys.argv[1]):
    for f in fs:
        if not f.endswith(".md"):
            continue
        p = os.path.join(dp, f)
        for m in re.finditer(r"\]\((\.\./[^)]+\.md|[^):/ ]+\.md)\)", open(p, encoding="utf-8").read()):
            if not os.path.isfile(os.path.normpath(os.path.join(dp, m.group(1)))):
                bad.append((p, m.group(1)))
print(bad)
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ]
}
