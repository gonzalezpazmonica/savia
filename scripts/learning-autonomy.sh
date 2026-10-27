#!/usr/bin/env bash
# learning-autonomy.sh — SCL-006: política de autonomía graduada por p_consistent
#
# El nivel de autonomía que una tarea/dominio puede ejecutar se gradúa por la
# consistencia medida (SE-292 S6 p_consistent), NO por decreto. Una tarea con
# p_consistent bajo se restringe a L0/L1 (draft/report-only); con p_consistent
# alto puede escalar a L2 (assisted) o L3 (unattended) — siempre que además
# cumpla los gates de loop-phasing (historial, aprobación humana).
#
# Umbrales (defaults, sobreescribibles):
#   p_consistent < 0.50 → L0 (draft, sin ejecución autónoma)
#   0.50 ≤ p < 0.70     → L1 (report-only)
#   0.70 ≤ p < 0.85     → L2 (assisted)
#   p ≥ 0.85            → L3 (unattended, solo con historial + aprobación)
#
# Usage:
#   learning-autonomy.sh --p-consistent <0-1> [--requested <L0|L1|L2|L3>]
#     [--history-ok] [--human-ok] [--json]
#
# Exit codes: 0 granted, 1 denied (solicitado > permitido), 2 usage,
#             3 input out of range
#
# Ref: docs/specs/SCL-006-autonomia-graduada.spec.md
# PURE_BASH — sin bindings de frontend.

set -uo pipefail

P=""
REQUESTED=""
HISTORY_OK=false
HUMAN_OK=false
JSON=false

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --p-consistent) [[ $# -ge 2 ]] || usage; P="$2"; shift 2 ;;
    --requested) [[ $# -ge 2 ]] || usage; REQUESTED="$2"; shift 2 ;;
    --history-ok) HISTORY_OK=true; shift ;;
    --human-ok) HUMAN_OK=true; shift ;;
    --json) JSON=true; shift ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

[[ -z "$P" ]] && usage

# Solo decimales planos: awk toma "0.5abc" como 0.5 y compara "abc" como texto.
[[ "$P" =~ ^([0-9]+(\.[0-9]*)?|\.[0-9]+)$ ]] || { echo "ERROR: p_consistent out of range [0,1]: $P" >&2; exit 3; }

# Range validation (locale-safe)
verdict=$(awk -v x="$P" 'BEGIN{ if (x<0 || x>1) print "INVALID"; else print "OK" }')
[[ "$verdict" == "OK" ]] || { echo "ERROR: p_consistent out of range [0,1]: $P" >&2; exit 3; }

# ── Determine allowed level from p_consistent ──
ALLOWED="L0"
if awk -v p="$P" 'BEGIN{exit !(p>=0.85)}'; then
  ALLOWED="L3"
elif awk -v p="$P" 'BEGIN{exit !(p>=0.70)}'; then
  ALLOWED="L2"
elif awk -v p="$P" 'BEGIN{exit !(p>=0.50)}'; then
  ALLOWED="L1"
fi

# ── L3 requires history + explicit human approval (loop-phasing gates) ──
if [[ "$ALLOWED" == "L3" ]] && { ! $HISTORY_OK || ! $HUMAN_OK; }; then
  ALLOWED="L2"  # L3 requiere ambos gates, no solo uno de ellos
fi

# ── Grant/deny ──
GRANTED=false
if [[ -z "$REQUESTED" ]]; then
  GRANTED=true
elif [[ "$REQUESTED" == "$ALLOWED" ]]; then
  GRANTED=true
else
  # Nivel numérico para comparar orden L0<L1<L2<L3
  lvl() { case "$1" in L0) echo 0;; L1) echo 1;; L2) echo 2;; L3) echo 3;; esac; }
  r=$(lvl "$REQUESTED"); a=$(lvl "$ALLOWED")
  # Concedido si lo solicitado es <= lo permitido
  if [[ -n "$r" && -n "$a" ]] && awk -v r="$r" -v a="$a" 'BEGIN{exit !(r<=a)}'; then
    GRANTED=true
  fi
fi

if $JSON; then
  printf '{"p_consistent":%s,"allowed":"%s","requested":"%s","granted":%s,"history_ok":%s,"human_ok":%s}\n' \
    "$P" "$ALLOWED" "${REQUESTED:-none}" "$GRANTED" "$HISTORY_OK" "$HUMAN_OK"
else
  echo "p_consistent: $P"
  echo "nivel permitido: $ALLOWED"
  if [[ -n "$REQUESTED" ]]; then echo "nivel solicitado: $REQUESTED"; fi
  if $GRANTED; then echo "veredicto: GRANTED"; else echo "veredicto: DENIED"; fi
fi

[[ "$GRANTED" == "true" ]]
