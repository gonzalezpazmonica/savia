#!/usr/bin/env bash
# web-guidance.sh — SE-539 S1 (D3). Búsqueda local, sin red, en la copia fija
# de las guías web modernas (references/modern-web-guidance/).
#
#   web-guidance.sh search "<consulta>"   id<TAB>descripción, mejores primero (máx. 10)
#   web-guidance.sh show <id>             imprime la ruta de la guía
#
# Puntuación por términos: nombre de fichero (id) 5, título 4, Overview/primer
# párrafo 1 por término; bonus por cubrir todos los términos. Sin coincidencias:
# salida vacía y código 0. Las guías son referencia, no instrucciones.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${WEB_GUIDANCE_DIR:-$SCRIPT_DIR/../references/modern-web-guidance}"
GUIDES="$DIR/guides"

die() { echo "ERROR: $*" >&2; exit 1; }
[ -d "$GUIDES" ] || die "no hay copia de guías en $GUIDES (scripts/web-guidance-import.sh)"

cmd="${1:-}"
case "$cmd" in
  search)
    [ $# -eq 2 ] || die 'uso: web-guidance.sh search "<consulta>"'
    python3 -I - "$GUIDES" "$2" <<'PY'
import os, re, sys, unicodedata
root, query = sys.argv[1], sys.argv[2].lower()
# Las guías están en inglés: sin tildes, «diálogo» no se parte en «di» + «logo».
query = "".join(c for c in unicodedata.normalize("NFKD", query) if not unicodedata.combining(c))
stop = {"the", "and", "for", "with", "how", "into", "from", "that", "this", "are", "use", "can"}
terms = [t for t in re.split(r"[^a-z0-9]+", query) if len(t) >= 3 and t not in stop]
if not terms:
    sys.exit(0)
rows = []
for dp, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith(".md"):
            continue
        gid = f[:-3]
        lines = open(os.path.join(dp, f), encoding="utf-8").read().splitlines()
        title = next((l[2:].strip() for l in lines if l.startswith("# ")), gid)
        # Overview: párrafo tras «## Overview»; si no hay, primer párrafo tras el título.
        body, grab, seen_title = [], False, False
        for l in lines:
            if l.startswith("# ") and not seen_title:
                seen_title = True
                continue
            if l.strip().lower() == "## overview":
                body, grab = [], True
                continue
            if not seen_title and not grab:
                continue
            if l.startswith("#") and grab and body:
                break
            if l.strip() and not l.startswith("#") and not l.startswith("```"):
                body.append(l.strip())
                if not grab and len(body) >= 1:
                    grab = None  # primer párrafo de respaldo
            elif body and grab is None:
                break
        desc = " ".join(body)
        low_t, low_d, low_i = title.lower(), desc.lower(), gid.lower()
        score, hit = 0, 0
        for t in terms:
            s = 0
            if t in low_i: s += 5
            if t in low_t: s += 4
            if t in low_d: s += 1
            if s:
                hit += 1
            score += s
        if hit == 0:
            continue
        if hit == len(terms):
            score += 3
        first = re.split(r"(?<=[.!?])\s", desc, maxsplit=1)[0] if desc else title
        rows.append((-score, gid, first[:200]))
rows.sort()
for _, gid, d in rows[:10]:
    print(f"{gid}\t{d}")
PY
    ;;
  show)
    [ $# -eq 2 ] || die "uso: web-guidance.sh show <id>"
    id="$2"
    [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "id inválido: $id"
    found="$(find "$GUIDES" -type f -name "$id.md" | LC_ALL=C sort | head -1)"
    [ -n "$found" ] || die "no existe la guía: $id"
    echo "$found"
    ;;
  *)
    die 'uso: web-guidance.sh search "<consulta>" | show <id>'
    ;;
esac
