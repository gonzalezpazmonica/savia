#!/usr/bin/env bash
# learning-proposal.sh — SCL-001 S1: canonical learning proposal capture
#
# Unifies "esto paso, esto salio mal/bien, esto propongo cambiar" into a
# single versionable, citable learning proposal artifact. The markdown file is
# the source of truth (CRIT-003 / ADR-006); the SaviaVaults graph is only the
# navigation index.
#
# Idempotency: the same evidence hash within a 24h window produces at most one
# proposal (AC-1.3). Provenance is always INFERRED — activation is human-only
# (CRIT-031 / ART-11).
#
# Usage:
#   learning-proposal.sh --origin <origen> \
#     --evidence <ruta[:hash]>[,<ruta[:hash]>...] \
#     --diagnosis <texto> \
#     --change <cambio propuesto> \
#     --target <criterio|memoria|skill|spec> \
#     [--criterion-id <CRIT-XXX>] \
#     [--when <cuándo aplica>] [--confidence <alta|media|baja>] \
#     [--expected-p-consistent <0-1>] \
#     [--trigger <ledger|contradiction|divergence|recurrence>] \
#     [--output-dir <path>] [--graph-index <path>] [--id <id>]
#
# Exit codes: 0 created, 1 duplicate (idempotency), 2 usage error, 3 evidence missing
#
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md (S1, AC-1.1..1.5)
# PURE_BASH — no frontend bindings.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ORIGIN=""
EVIDENCE=""
DIAGNOSIS=""
CHANGE=""
TARGET=""
CRITERION_ID=""
EXPECTED_PC=""
TRIGGER="ledger"
OUTPUT_DIR="${SCL_PROPOSALS_DIR:-$ROOT/docs/learning-proposals}"
GRAPH_INDEX="${SCL_GRAPH_INDEX:-$ROOT/output/learning-loop/graph-index.jsonl}"
PERSIST=false
FORCE_ID=""
WHEN=""
CONFIDENCE=""

usage() {
  # Toda la cabecera de comentarios, sin rango fijo que se rompa al editarla.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --origin) ORIGIN="$2"; shift 2 ;;
    --evidence) EVIDENCE="$2"; shift 2 ;;
    --diagnosis) DIAGNOSIS="$2"; shift 2 ;;
    --change) CHANGE="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --criterion-id) CRITERION_ID="$2"; shift 2 ;;
    --expected-p-consistent) EXPECTED_PC="$2"; shift 2 ;;
    --trigger) TRIGGER="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --graph-index) GRAPH_INDEX="$2"; shift 2 ;;
    --persist) PERSIST=true; shift ;;
    --id) FORCE_ID="$2"; shift 2 ;;
    --when) WHEN="$2"; shift 2 ;;
    --confidence) CONFIDENCE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

[[ -z "$ORIGIN" || -z "$EVIDENCE" || -z "$DIAGNOSIS" || -z "$CHANGE" || -z "$TARGET" ]] && usage

case "$TARGET" in
  criterio|memoria|skill|spec) ;;
  *) echo "ERROR: --target debe ser criterio|memoria|skill|spec" >&2; exit 2 ;;
esac

# --when es texto libre que va al frontmatter: sin saltos de línea (inyectaría claves) y entrecomillado.
case "$WHEN" in
  *$'\n'*|*$'\r'*) echo "ERROR: --when no admite saltos de línea" >&2; exit 2 ;;
esac
if [[ "$WHEN" =~ [[:cntrl:]] ]]; then echo "ERROR: --when no admite caracteres de control" >&2; exit 2; fi
if (( ${#WHEN} > 200 )); then echo "ERROR: --when admite como mucho 200 caracteres" >&2; exit 2; fi
WHEN_YAML=""
[[ -n "$WHEN" ]] && WHEN_YAML="\"$(printf '%s' "$WHEN" | sed 's/\\/\\\\/g; s/"/\\"/g')\""

case "$CONFIDENCE" in
  ""|alta|media|baja) ;;
  *) echo "ERROR: --confidence debe ser alta|media|baja" >&2; exit 2 ;;
esac

if [[ -n "$CRITERION_ID" ]]; then
  [[ "$TARGET" == "criterio" ]] || { echo "ERROR: --criterion-id requires --target criterio" >&2; exit 2; }
  [[ "$CRITERION_ID" =~ ^CRIT-[0-9]{3}$ ]] || { echo "ERROR: --criterion-id must match CRIT-XXX" >&2; exit 2; }
fi

# ── Evidence hash (deterministic): sort evidence entries, hash each path's content ──
# Evidence format: path[:hash]. If no explicit hash, compute sha256 of the file.
EVIDENCE_ENTRIES=()
IFS=',' read -ra RAW <<< "$EVIDENCE"
for entry in "${RAW[@]}"; do
  entry="$(echo "$entry" | tr -d '[:space:]')"
  [[ -z "$entry" ]] && continue
  path="${entry%%:*}"
  h="${entry#*:}"
  if [[ "$h" == "$entry" ]]; then
    if [[ -f "$path" ]]; then
      h="$(sha256sum "$path" | cut -d' ' -f1)"
    else
      echo "ERROR: evidence path not found and no hash given: $path" >&2
      exit 3
    fi
  fi
  EVIDENCE_ENTRIES+=("$path:$h")
done
[[ ${#EVIDENCE_ENTRIES[@]} -eq 0 ]] && { echo "ERROR: no valid evidence" >&2; exit 3; }

EVIDENCE_HASH=$(printf '%s\n' "${EVIDENCE_ENTRIES[@]}" | sort | sha256sum | cut -d' ' -f1)

# ── Idempotency (AC-1.3): same evidence hash within 24h → at most 1 proposal ──
if [[ -d "$OUTPUT_DIR" ]]; then
  WINDOW_START=$(date -u -d "24 hours ago" +%s 2>/dev/null || echo "")
  for f in "$OUTPUT_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    if grep -q "^evidence_hash: $EVIDENCE_HASH" "$f" 2>/dev/null; then
      ts=$(grep -m1 '^created_utc: ' "$f" | sed 's/created_utc: //')
      if [[ -n "$WINDOW_START" && -n "$ts" ]]; then
        created=$(date -u -d "$ts" +%s 2>/dev/null || echo "")
        if [[ -n "$created" && $created -ge $WINDOW_START ]]; then
          echo "DUPLICATE: proposal for evidence $EVIDENCE_HASH exists in 24h window" >&2
          echo "$f"
          exit 1
        fi
      fi
    fi
  done
fi

# ── IDs ──
if [[ -n "$FORCE_ID" ]]; then
  ID="$FORCE_ID"
else
  ID="LP-$(date -u +%Y%m%d)-${EVIDENCE_HASH:0:8}"
fi
CREATED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$OUTPUT_DIR"
FILE="$OUTPUT_DIR/$ID.md"

# ── Artifact (markdown is the truth, CRIT-003) ──
cat > "$FILE" <<EOF
---
id: $ID
type: learning_proposal
provenance: INFERRED
lifecycle: proposed
origin: $ORIGIN
trigger: $TRIGGER
target: $TARGET
criterion_id: $CRITERION_ID
evidence_hash: $EVIDENCE_HASH
created_utc: $CREATED_UTC
expected_p_consistent: ${EXPECTED_PC:-}
when: $WHEN_YAML
confidence: $CONFIDENCE
---

# Learning Proposal $ID

## Origen

$ORIGIN

## Cuándo aplica

${WHEN:-sin condición de uso declarada (añadir con --when)}${CONFIDENCE:+ · confianza: $CONFIDENCE}

## Evidencia

$(printf '%s\n' "${EVIDENCE_ENTRIES[@]}")

## Diagnóstico

$DIAGNOSIS

## Cambio propuesto

$CHANGE

## Destino

$TARGET

## Métrica esperada

$([ -n "$EXPECTED_PC" ] && echo "p_consistent esperado: $EXPECTED_PC" || echo "sin baseline declarado")
EOF

# ── Graph index entry (SaviaVaults navigation index, not source of truth) ──
mkdir -p "$(dirname "$GRAPH_INDEX")"
{
  printf '%s' '{"type":"learning_proposal","id":"'"$ID"'","provenance":"INFERRED","lifecycle":"proposed",'
  printf '%s' '"origin":"'"$ORIGIN"'","trigger":"'"$TRIGGER"'","target":"'"$TARGET"'","criterion_id":"'"$CRITERION_ID"'",'
  printf '%s' '"evidence_hash":"'"$EVIDENCE_HASH"'","created_utc":"'"$CREATED_UTC"'",'
  printf '%s' '"relations":{"proposes_change":"'"$TARGET"'","evidence_from":'"$(printf '%s' "${EVIDENCE_ENTRIES[@]}" | tr '\n' ' ' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip().split()))' 2>/dev/null || echo '[]')"'}}'
  echo ""
} >> "$GRAPH_INDEX"

echo "CREATED: $FILE"
echo "id: $ID"
echo "evidence_hash: $EVIDENCE_HASH"

# ── Persist to learning dome (SCL-002): cross-instance durable lesson ──
if $PERSIST; then
  PERSIST_SCRIPT="${SCL_PERSIST_SCRIPT:-$ROOT/scripts/learning-persist.sh}"
  if [[ -f "$PERSIST_SCRIPT" ]]; then
    if bash "$PERSIST_SCRIPT" --file "$FILE" "${SCL_PERSIST_COMMIT:+--commit}" 2>/dev/null; then
      echo "persisted: true"
    else
      echo "persisted: false"
    fi
  fi
fi
exit 0
