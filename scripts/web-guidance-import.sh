#!/usr/bin/env bash
# web-guidance-import.sh — SE-539 S1 (D1, D2, D6).
#
# Importa las guías de GoogleChrome/modern-web-guidance en un commit EXACTO a
# references/modern-web-guidance/ como copia fija de solo texto:
#   - solo skills/modern-web-guidance/guides/**/*.md + LICENSE + NOTICE
#   - rechaza ramas, etiquetas y HEAD (solo 40 hexadecimales en minúscula)
#   - copia defensiva: sin enlaces simbólicos ni duros, sin ficheros que no
#     sean .md dentro de guides/, máx. 300 ficheros y 4 MB, sin rutas con ..
#   - reescribe ``(via `npx -y modern-web-guidance@latest retrieve "<id>"`)``
#     a enlaces relativos; un id inexistente aborta con el id en el mensaje
#   - la copia final no contiene «npx»
#   - todo o nada: se construye en un temporal y se sustituye al final por renombrado junto al destino
#
# Uso: web-guidance-import.sh <commit40>
# Entorno (tests): WEB_GUIDANCE_TARBALL=<tar.gz local> evita la red;
#                  WEB_GUIDANCE_DEST=<dir> cambia el destino.
# Actualizar es volver a entrar con otro commit (D6); no hay actualización automática.
set -euo pipefail

REPO="GoogleChrome/modern-web-guidance"
MAX_FILES=300
MAX_BYTES=$((4 * 1024 * 1024))
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${WEB_GUIDANCE_DEST:-$SCRIPT_DIR/../references/modern-web-guidance}"

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -eq 1 ] || die "uso: web-guidance-import.sh <commit de 40 hexadecimales>"
COMMIT="$1"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "se exige un commit de 40 hexadecimales en minúscula (no rama, etiqueta ni HEAD): '$COMMIT'"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TGZ="$WORK/src.tgz"

if [ -n "${WEB_GUIDANCE_TARBALL:-}" ]; then
  [ -f "$WEB_GUIDANCE_TARBALL" ] || die "no existe WEB_GUIDANCE_TARBALL: $WEB_GUIDANCE_TARBALL"
  cp "$WEB_GUIDANCE_TARBALL" "$TGZ"
else
  gh api "repos/$REPO/tarball/$COMMIT" > "$TGZ" || die "no se pudo descargar $REPO@$COMMIT"
fi

# 1. Inspección del listado antes de extraer nada.
tar -tvzf "$TGZ" > "$WORK/list.txt" || die "tarball ilegible"
if grep -qE '^[lh]' "$WORK/list.txt"; then
  die "el árbol contiene enlaces (simbólicos o duros): importación rechazada"
fi
tar -tzf "$TGZ" > "$WORK/names.txt"
if grep -qE '(^|/)\.\.(/|$)|^/' "$WORK/names.txt"; then
  die "el tarball contiene rutas con '..' o absolutas: importación rechazada"
fi
# Topes sobre el listado (tamaño declarado, columna 3 de GNU tar -tv): un tar.gz que se infla al
# extraer se rechaza antes de escribir nada. Tras extraer se vuelven a comprobar sobre disco.
read -r L_FILES L_BYTES < <(awk '/^-/ && /\/skills\/modern-web-guidance\/guides\// {n++; s+=$3} END{print n+0, s+0}' "$WORK/list.txt")
[ "$L_FILES" -le "$MAX_FILES" ] || die "demasiados ficheros en el listado: $L_FILES > $MAX_FILES"
[ "$L_BYTES" -le "$MAX_BYTES" ] || die "demasiado grande según el listado: $L_BYTES > $MAX_BYTES bytes"

# 2. Extracción acotada a guides/ y LICENSE (sin propietario ni permisos del origen).
mkdir "$WORK/x"
tar -xzf "$TGZ" -C "$WORK/x" --no-same-owner --no-same-permissions \
  --wildcards '*/skills/modern-web-guidance/guides/*' '*/LICENSE' 2>/dev/null \
  || die "fallo al extraer el tarball"
TOP="$(find "$WORK/x" -mindepth 1 -maxdepth 1 -type d)"
[ "$(printf '%s\n' "$TOP" | wc -l)" -eq 1 ] && [ -n "$TOP" ] || die "estructura inesperada del tarball"
GUIDES="$TOP/skills/modern-web-guidance/guides"
[ -d "$GUIDES" ] || die "no existe skills/modern-web-guidance/guides en $COMMIT"
[ -f "$TOP/LICENSE" ] && [ ! -L "$TOP/LICENSE" ] || die "falta LICENSE"

# 3. Copia defensiva: solo ficheros regulares .md.
[ -z "$(find "$GUIDES" -type l)" ] || die "enlace simbólico dentro de guides/"
OTHER="$(find "$GUIDES" -type f ! -name '*.md' | head -1)"
[ -z "$OTHER" ] || die "fichero que no es .md dentro de guides/: ${OTHER#"$GUIDES"/}"
OTHER="$(find "$GUIDES" ! -type f ! -type d | head -1)"
[ -z "$OTHER" ] || die "entrada que no es fichero regular dentro de guides/: ${OTHER#"$GUIDES"/}"
NFILES="$(find "$GUIDES" -type f | wc -l)"
[ "$NFILES" -ge 1 ] || die "guides/ sin ficheros"
[ "$NFILES" -le "$MAX_FILES" ] || die "demasiados ficheros: $NFILES > $MAX_FILES"
NBYTES="$(find "$GUIDES" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')"
[ "$NBYTES" -le "$MAX_BYTES" ] || die "demasiado grande: $NBYTES > $MAX_BYTES bytes"

# 4. Hash del árbol (origen, antes de reescribir): sha256 de «sha256  ruta» ordenado.
TREE_HASH="$(cd "$GUIDES" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"

# 5. Reescritura de referencias cruzadas y construcción de la copia en temporal.
OUT="$WORK/out"
mkdir -p "$OUT/guides"
python3 -I - "$GUIDES" "$OUT/guides" <<'PY'
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
ids = {}
for dp, _, fs in os.walk(src):
    for f in fs:
        rel = os.path.relpath(os.path.join(dp, f), src)
        gid = f[:-3]
        if gid in ids:
            sys.exit(f"ERROR: id duplicado '{gid}': {ids[gid]} y {rel}")
        ids[gid] = rel
pat = re.compile(r'\(via `npx -y modern-web-guidance@latest retrieve "([^"`]*)"`\)')
missing = set()
for gid, rel in sorted(ids.items()):
    text = open(os.path.join(src, rel), encoding="utf-8").read()
    def sub(m, rel=rel):
        t = m.group(1)
        if t not in ids:
            missing.add(t)
            return m.group(0)
        link = os.path.relpath(ids[t], os.path.dirname(rel)).replace(os.sep, "/")
        return f"([{t}]({link}))"
    new = pat.sub(sub, text)
    out = os.path.join(dst, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(new)
    os.chmod(out, 0o644)
if missing:
    sys.exit("ERROR: referencias cruzadas a ids inexistentes: " + ", ".join(sorted(missing)))
PY
if grep -rqi 'npx' "$OUT/guides"; then
  die "quedan referencias a npx tras la reescritura: $(grep -rli npx "$OUT/guides" | head -3 | tr '\n' ' ')"
fi

cp "$TOP/LICENSE" "$OUT/LICENSE"
chmod 644 "$OUT/LICENSE"
cat > "$OUT/NOTICE" <<EOF
Copia fija de las guías de $REPO (Apache-2.0, ver LICENSE).
Solo texto: skills/modern-web-guidance/guides/**/*.md. Sin código ni manifiestos.
Las órdenes de recuperación por red de las referencias cruzadas se reescribieron a enlaces relativos.
No editar a mano: para actualizar, ejecutar scripts/web-guidance-import.sh <commit> (SE-539 D6).

URL: https://github.com/$REPO
Commit: $COMMIT
Date: $(date -u +%F)
Files: $NFILES
Tree-SHA256: $TREE_HASH
EOF
chmod 644 "$OUT/NOTICE"

# 6. Sustitución de la copia anterior (solo si todo lo anterior pasó). La copia nueva se prepara en un
# temporal junto a DEST (mismo sistema de ficheros): los dos mv son renombrados, no copia y borrado.
# Si el segundo falla, la copia anterior vuelve a su sitio. Hay un instante sin DEST entre ambos.
mkdir -p "$(dirname "$DEST")"
STAGE="$(mktemp -d "$(dirname "$DEST")/.wg.XXXXXX")"
trap 'rm -rf "$WORK" "$STAGE"' EXIT
cp -R "$OUT" "$STAGE/new"
if [ -e "$DEST" ]; then
  mv "$DEST" "$STAGE/old"
fi
if ! mv "$STAGE/new" "$DEST"; then
  [ -e "$STAGE/old" ] && mv "$STAGE/old" "$DEST"
  die "no se pudo colocar la copia nueva en $DEST; se conserva la anterior"
fi
echo "OK: $NFILES guías importadas de $REPO@$COMMIT en $DEST (tree $TREE_HASH)"
