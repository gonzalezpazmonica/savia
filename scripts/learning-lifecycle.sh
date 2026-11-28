#!/usr/bin/env bash
# learning-lifecycle.sh — SCL-001 S2: sustrato como artefacto de despliegue
#
# State machine for learning proposals / sustrado entries:
#   proposed(shadow) → canary → active → superseded
#
# - shadow: no effect on gates or behaviour (equivale a INFERRED).
# - canary: active on a declared subset, with before/after measurement.
# - active: human_authored, global effect.
# - superseded: tombstone + quarantine window (CRIT-024), never deleted.
#
# Gate anti-auto-activación (CRIT-031 / ART-11): proposed→active and
# canary→active REQUIRE provenance:human_authored with a human trailer.
# Today only the trailer FORMAT is checked, not who wrote it (R10, S5/S6). active→superseded and
# rollback ARE automatable (reversible, CRIT-022).
#
# Usage:
#   learning-lifecycle.sh --file <artifact.md> --to <state> \
#     [--actor <who>] [--reason <why>] [--human-trailer <sig>] \
#     [--subset <domain>] [--metric-before <L>] [--metric-after <L>] \
#     [--ledger <path>] [--strict]
#
# Exit codes: 0 ok (o sin cambio), 1 invalid transition, 2 usage, 3 missing file,
#             4 trailer humano ausente o con formato inválido,
#             5 canary→active sin las dos métricas numéricas, o con regresión,
#             6 no se pudo escribir el registro (la transición se deshace)
#
# SE-497 S0: --human-trailer debe casar ENTERO con
#   ^(sha:[0-9a-f]{40}|se488:[A-Za-z0-9._-]{1,64})$
# y se valida antes de tocar el fichero. Ningún valor recibido por argumento se
# interpola en sed ni se concatena en JSON: la cabecera la edita y el registro
# lo codifica python3, con los valores pasados como argumentos.
# Límite: el formato no prueba que firme una persona (eso es R10, S5/S6).
#
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md (S2, AC-2.1..2.6)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FILE=""
TO=""
ACTOR="agent"
REASON=""
HUMAN_TRAILER=""
SUBSET=""
METRIC_BEFORE=""
METRIC_AFTER=""
LEDGER="${SCL_LEDGER:-$ROOT/output/learning-loop/lifecycle.jsonl}"
STRICT=false

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    --actor) ACTOR="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    --human-trailer) HUMAN_TRAILER="$2"; shift 2 ;;
    --subset) SUBSET="$2"; shift 2 ;;
    --metric-before) METRIC_BEFORE="$2"; shift 2 ;;
    --metric-after) METRIC_AFTER="$2"; shift 2 ;;
    --ledger) LEDGER="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

[[ -z "$FILE" || -z "$TO" ]] && usage
[[ -f "$FILE" ]] || { echo "ERROR: file not found: $FILE" >&2; exit 3; }

case "$TO" in
  proposed|canary|active|superseded) ;;
  *) echo "ERROR: --to debe ser proposed|canary|active|superseded" >&2; exit 2 ;;
esac

CURRENT=$(grep -m1 '^[[:space:]]*lifecycle: ' "$FILE" | sed 's/^[[:space:]]*lifecycle: //' || echo "proposed")
PROV=$(grep -m1 '^[[:space:]]*provenance: ' "$FILE" | sed 's/^[[:space:]]*provenance: //' || echo "INFERRED")
ID=$(grep -m1 '^[[:space:]]*id: ' "$FILE" | sed 's/^[[:space:]]*id: //') \
  || { ID="${FILE##*/}"; ID="${ID%.md}"; }   # sin sustitución de órdenes: conserva el nombre tal cual

# ── Valid transitions ──
valid=false
case "$CURRENT" in
  proposed)
    case "$TO" in proposed|canary) valid=true ;; esac ;;
  canary)
    case "$TO" in canary|active|proposed|superseded) valid=true ;; esac ;;
  active)
    case "$TO" in active|superseded) valid=true ;; esac ;;
  superseded)
    case "$TO" in superseded) valid=true ;; esac ;;
esac

# ── Registro: una línea JSON por evento, codificada (S0-3) ──
record() {  # record <to> <status|""> <revert>
  mkdir -p "$(dirname "$LEDGER")"
  python3 - "$LEDGER" "$ID" "$CURRENT" "$1" "$ACTOR" "$REASON" "$METRIC_BEFORE" "$METRIC_AFTER" "$2" "$3" <<'PY'
import json, sys, time
led, lid, cur, to, actor, reason, mb, ma, status, revert = sys.argv[1:11]
d = {"id": lid, "from": cur, "to": to, "actor": actor}
if status: d["status"] = status
d.update({"reason": reason, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
if not status: d.update({"metric_before": mb, "metric_after": ma, "revert": revert})
with open(led, "a", encoding="utf-8") as f: f.write(json.dumps(d, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
}

# ── Edición de la cabecera sin interpolar nada en sed (S0-7) ──
apply_state() {  # apply_state <to> <trailer|"">
  python3 - "$FILE" "$1" "$2" <<'PY'
import os, re, sys, time
path, to, trailer = sys.argv[1:4]
L = open(path, encoding="utf-8", errors="surrogateescape").read().splitlines(keepends=True)
lo, hi = 0, len(L)
if L and L[0].strip() == "---":
    for k in range(1, len(L)):
        if L[k].strip() == "---": lo, hi = 1, k; break
def find(key):
    for k in range(lo, hi):
        if re.match(r"\s*%s:( |$)" % key, L[k].rstrip("\n")): return k
    return None
def setval(k, key, val):
    ind = re.match(r"\s*", L[k]).group(0)
    L[k] = "%s%s: %s\n" % (ind, key, val)
lc = find("lifecycle")
if lc is None: sys.exit(1)
setval(lc, "lifecycle", to)
if to == "active":
    pv = find("provenance")
    if pv is not None: setval(pv, "provenance", "human_authored")
    keep = [k for k in range(lo, hi) if not re.match(r"\s*human_trailer:", L[k])]
    L[lo:hi] = [L[k] for k in keep]; hi = lo + len(keep)
    at = find("created_utc"); at = find("lifecycle") if at is None else at
    L.insert(at + 1, "human_trailer: %s\n" % trailer)
elif to == "superseded" and find("tombstone") is None:
    L.insert(lc + 1, "tombstone: superseded %s — no borrado, cuarentena (CRIT-024)\n"
             % time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
tmp = path + ".tmp.%d" % os.getpid()
with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f: f.writelines(L)
os.chmod(tmp, os.stat(path).st_mode & 0o7777)
os.replace(tmp, path)
PY
}

# ── Trailer humano: formato cerrado sobre la cadena completa (S0-1, S0-2; CRIT-031) ──
TRAILER_RE='^(sha:[0-9a-f]{40}|se488:[A-Za-z0-9._-]{1,64})$'
trailer_ok() {
  local v="$1"
  [[ "$v" != *$'\n'* && "$v" != *$'\r'* ]] || return 1
  LC_ALL=C; [[ "$v" =~ $TRAILER_RE ]]
}
if [[ "$TO" == "active" ]]; then
  if [[ -z "$HUMAN_TRAILER" ]]; then
    # El intento rechazado se registra siempre, también con --strict: es evidencia de auditoría.
    if $STRICT; then echo "BLOCKED [learning-lifecycle]: transition to active requires --human-trailer (CRIT-031/ART-11)" >&2
    else echo "REFUSED: active requires human_authored trailer" >&2; fi
    record active refused-no-human ""
    exit 4
  fi
  if ! ( trailer_ok "$HUMAN_TRAILER" ); then
    echo "BLOCKED [learning-lifecycle]: --human-trailer no cumple el formato (sha:<40 hex> o se488:<id>); fichero sin tocar" >&2
    record active refused-invalid-trailer ""
    exit 4
  fi
fi

[[ "$valid" == "true" ]] || { echo "ERROR: invalid transition $CURRENT → $TO" >&2; exit 1; }

# ── Idempotencia (S0-5): repetir un estado que no cambia nada no escribe ni registra ──
if [[ "$CURRENT" == "$TO" ]]; then
  if [[ "$TO" != "active" ]] || grep -qxF "human_trailer: $HUMAN_TRAILER" "$FILE"; then
    echo "SIN CAMBIO: $CURRENT → $TO (id=$ID)"
    exit 0
  fi
fi

# ── canary→active: las dos métricas, numéricas y sin regresión (S0-4; provisional hasta el recibo de S5) ──
REVERT=false
if [[ "$CURRENT" == "canary" && "$TO" == "active" ]]; then
  NUM_RE='^-?[0-9]+(\.[0-9]+)?$'
  if ! [[ "$METRIC_BEFORE" =~ $NUM_RE && "$METRIC_AFTER" =~ $NUM_RE ]]; then
    echo "BLOCKED [learning-lifecycle]: canary → active exige --metric-before y --metric-after numéricas; sigue en canary" >&2
    record active refused-no-metrics ""
    exit 5
  fi
  if ! awk -v b="$METRIC_BEFORE" -v a="$METRIC_AFTER" 'BEGIN{exit (a < b)}'; then
    echo "BLOCKED [learning-lifecycle]: canary metric regression (before=$METRIC_BEFORE after=$METRIC_AFTER) — no asciende, vuelve a proposed" >&2
    TO="proposed"
    REASON="canary regression: before=$METRIC_BEFORE after=$METRIC_AFTER ($REASON)"
    REVERT=true
  fi
fi

# ── Apply + record ──
TR=""; [[ "$TO" == "active" ]] && TR="$HUMAN_TRAILER"
# RESTO-497-b: sin fila de auditoría no hay transición. Se guarda una copia de la
# lección y, si el registro no se puede escribir, se restaura y se sale con 6.
BAK="$(mktemp "${TMPDIR:-/tmp}/learning-lifecycle.XXXXXX")" \
  || { echo "ERROR: no se pudo crear la copia de seguridad de $FILE" >&2; exit 6; }
cp -p "$FILE" "$BAK" || { rm -f "$BAK"; echo "ERROR: no se pudo copiar $FILE" >&2; exit 6; }
apply_state "$TO" "$TR" || { rm -f "$BAK"; echo "ERROR: no se pudo actualizar la cabecera de $FILE" >&2; exit 1; }
if ! record "$TO" "" "$REVERT" 2>/dev/null; then
  cp -p "$BAK" "$FILE"; rm -f "$BAK"
  echo "ERROR [learning-lifecycle]: no se pudo escribir el registro $LEDGER; transición deshecha, $FILE sin cambios" >&2
  exit 6
fi
rm -f "$BAK"

echo "TRANSITION: $CURRENT → $TO (id=$ID actor=$ACTOR)"
$REVERT && exit 5
exit 0
