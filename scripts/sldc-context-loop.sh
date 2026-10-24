#!/usr/bin/env bash
# sldc-context-loop.sh — SE-311 S1: post-merge → feed SaviaVaults (spec/ADR/release)
#
# Cierra el ciclo de conocimiento: al mergear un PR, detecta los artefactos que
# toco (specs, ADRs en docs/propuestas, CHANGELOG.d), genera notas grounded con
# citacion de fuentes, y las escribe en las cupulas de SaviaVaults (A2A /share).
# Si el vault/LLM falla, la nota queda pendiente local y se re-envia con --flush.
#
# Usage:
#   sldc-context-loop.sh --base <ref> --head <ref> [--dry-run] [--feed]
#   sldc-context-loop.sh --list-pending
#   sldc-context-loop.sh --flush-pending [--dry-run]
#
# Env:
#   SLDC_VAULTS_URL        A2A base (default http://127.0.0.1:8923)
#   SLDC_WRITE_DOME        dome destino (default example-context)
#   SLDC_MAX_CONFIDENTIALITY  nivel maximo (default N2)
#   SLDC_PENDING_DIR       pendientes locales (default ~/.savia/sldc-pending)
#   SLDC_LLM_CMD           hook opcional de resumen (default: extraccion determinista)
#
# Exit: 0 = ok (o pendiente encolado), 1 = error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VAULTS_URL="${SLDC_VAULTS_URL:-http://127.0.0.1:8923}"
WRITE_DOME="${SLDC_WRITE_DOME:-example-context}"
MAX_CONF="${SLDC_MAX_CONFIDENTIALITY:-N2}"
PENDING_DIR="${SLDC_PENDING_DIR:-$HOME/.savia/sldc-pending}"
LLM_CMD="${SLDC_LLM_CMD:-}"
BASE_REF=""; HEAD_REF=""; DRY_RUN=0; FEED=0; ACTION=""

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

# ── clasificacion de artefactos del diff ─────────────────────────────────────
classify_changed() {
  # $1 = lista de paths separados por newline. Emite 3 lineas: specs, adrs, clg.
  local specs="" adrs="" clg=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      projects/*/specs/*.spec.md) specs="$specs $f" ;;
      docs/propuestas/*.md)       adrs="$adrs $f" ;;
      CHANGELOG.d/*.md)           clg="$clg $f" ;;
    esac
  done <<< "$1"
  echo "$specs"
  echo "$adrs"
  echo "$clg"
}

# ── extraccion determinista (default sin LLM) ────────────────────────────────
spec_status() {
  local v
  v=$(grep -m1 '^status:' "$1" 2>/dev/null | sed 's/^status:[[:space:]]*//')
  if [[ -z "$v" ]]; then v=$(grep -m1 '\*\*Estado:\*\*' "$1" 2>/dev/null | sed 's/\*\*Estado:\*\*[[:space:]]*//'); fi
  echo "${v:-unknown}"
}
spec_title()  { grep -m1 '^# Spec:' "$1" 2>/dev/null | sed 's/^# Spec:[[:space:]]*//' || echo "$(basename "$1")"; }
proposal_title() { grep -m1 '^title:' "$1" 2>/dev/null | sed 's/^title:[[:space:]]*//' || echo "$(basename "$1")"; }
chg_first()   { grep -m1 '^- ' "$1" 2>/dev/null | sed 's/^- //' || echo "cambio documentado"; }

# ── construccion de notas (JSON compacto, 1 nota por linea) ─────────────────
build_notes() {
  local specs="$1" adrs="$2" clg="$3"
  python3 - "$WRITE_DOME" "$specs" "$adrs" "$clg" <<'PY'
import json, os, re, sys
from datetime import date
dome, specs, adrs, clg = sys.argv[1], sys.argv[2].split(), sys.argv[3].split(), sys.argv[4].split()

def status_of(p):
    t = open(p, encoding="utf-8").read() if os.path.exists(p) else ""
    m = re.search(r'^status:\s*(.+)', t, re.M)
    if not m: m = re.search(r'\*\*Estado:\*\*\s*(.+)', t)
    return m.group(1).strip() if m else "unknown"

def title_of(p):
    t = open(p, encoding="utf-8").read() if os.path.exists(p) else ""
    m = re.search(r'^# Spec:\s*(.+)', t, re.M)
    if not m: m = re.search(r'^title:\s*(.+)', t, re.M)
    return m.group(1).strip() if m else os.path.basename(p)

def first_change(p):
    t = open(p, encoding="utf-8").read() if os.path.exists(p) else ""
    m = re.search(r'^- (.+)$', t, re.M)
    return m.group(1).strip() if m else "cambio documentado"

today = date.today().isoformat()
out = []
for s in specs:
    base = os.path.basename(s).replace(".spec.md", "")
    out.append({"dome": dome, "path": "specs/" + base + "-status.md",
                "content": "# " + title_of(s) + "\n\n## Estado\n\n" + status_of(s) + " (actualizado post-merge por SDLC Context Loop, " + today + ").\n\n## Fuente\n\n- " + s + "\n"})
for a in adrs:
    slug = re.sub(r'[^a-z0-9-]+', '-', os.path.basename(a).replace(".md", "").lower()).strip('-')
    out.append({"dome": dome, "path": "decisions/" + today + "-" + slug + ".md",
                "content": "# Decision: " + title_of(a) + "\n\n## Contexto\n\nDocumentada en " + a + ".\n\n## Fuente\n\n- " + a + "\n"})
for c in clg:
    slug = re.sub(r'[^a-z0-9-]+', '-', os.path.basename(c).replace(".md", "")).strip('-')
    out.append({"dome": dome, "path": "releases/" + slug + ".md",
                "content": "# Release\n\n- " + first_change(c) + "\n\n## Fuente\n\n- " + c + "\n"})
for n in out:
    print(json.dumps(n, ensure_ascii=False))
PY
}
# ── alimentar cupulas ────────────────────────────────────────────────────────
feed_note() {
  # $1 = JSON nota
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY: $(echo "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["dome"]+"/"+d["path"])')"
    return 0
  fi
  local resp
  # curl caido (conexion rechazada, timeout) o respuesta vacia = no entregada: nunca "OK"
  resp=$(curl -s --max-time 10 -X POST "$VAULTS_URL/share" -H "Content-Type: application/json" -d "$1") || return 1
  [[ -n "$resp" ]] || return 1
  if echo "$resp" | grep -q '"error"'; then
    return 1
  fi
  echo "OK: $(echo "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["dome"]+"/"+d["path"])')"
}

enqueue_pending() {
  mkdir -p "$PENDING_DIR"
  local n=0
  while IFS= read -r note; do
    [[ -z "$note" ]] && continue
    local f="$PENDING_DIR/$(date -u +%Y%m%d%H%M%S)-$RANDOM.json"
    echo "$note" > "$f"
    n=$((n+1))
  done <<< "$1"
  echo "PENDING: $n nota(s) encoladas en $PENDING_DIR"
}

flush_pending() {
  mkdir -p "$PENDING_DIR"
  local ok=0 fail=0
  for f in "$PENDING_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    if feed_note "$(cat "$f")"; then
      ok=$((ok+1))
      # --dry-run no consume la cola: solo informa de lo que se enviaria
      [[ "$DRY_RUN" == "1" ]] || rm -f "$f"
    else
      fail=$((fail+1))
    fi
  done
  echo "FLUSH: $ok enviadas, $fail fallidas"
}

list_pending() {
  mkdir -p "$PENDING_DIR"
  local n=0
  for f in "$PENDING_DIR"/*.json; do
    [[ -f "$f" ]] && { echo "  - $(basename "$f")"; n=$((n+1)); }
  done
  echo "pendientes: $n"
}

# ── main ────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_REF="$2"; shift 2 ;;
    --head) HEAD_REF="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --feed) FEED=1; shift ;;
    --list-pending) ACTION=list; shift ;;
    --flush-pending) ACTION=flush; shift ;;
    -h|--help) usage ;;
    *) echo "error: argumento desconocido: $1" >&2; usage ;;
  esac
done

# Las acciones se despachan tras leer todos los argumentos (--dry-run puede ir despues)
case "$ACTION" in
  list) list_pending; exit 0 ;;
  flush) flush_pending; exit 0 ;;
esac

if [[ -z "$BASE_REF" ]]; then
  echo "error: --base requerido" >&2; usage
fi
HEAD_REF="${HEAD_REF:-$BASE_REF}"

# Si stdin esta pipeado, leer los ficheros cambiados de ahi (modo testable);
# si no, calcular el diff con git.
if [[ ! -t 0 ]]; then
  CHANGED=$(cat)
else
  CHANGED=$(git -C "$ROOT" diff --name-only "$BASE_REF"..."$HEAD_REF" 2>/dev/null)
  if [[ -z "$CHANGED" ]]; then
    CHANGED=$(git -C "$ROOT" diff --name-only "$BASE_REF" "$HEAD_REF" 2>/dev/null)
  fi
fi

mapfile -t _categorized <<< "$(classify_changed "$CHANGED")"
specs="${_categorized[0]:-}"
adrs="${_categorized[1]:-}"
clg="${_categorized[2]:-}"
NOTES=$(build_notes "$specs" "$adrs" "$clg")

if [[ -z "$NOTES" ]]; then
  echo "NO_ARTIFACTS: el diff no toca specs/ADRs/CHANGELOG — nada que alimentar"
  exit 0
fi

if [[ "$FEED" == "1" ]]; then
  while IFS= read -r note; do
    [[ -z "$note" ]] && continue
    if ! feed_note "$note"; then
      echo "fallo al alimentar, encolando pendiente"
      enqueue_pending "$note"
    fi
  done <<< "$NOTES"
else
  echo "== Notas generadas (usa --feed para escribir en las cupulas) =="
  echo "$NOTES" | python3 -m json.tool --no-ensure-ascii 2>/dev/null || echo "$NOTES"
fi

exit 0
