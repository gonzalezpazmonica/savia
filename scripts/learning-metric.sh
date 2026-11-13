#!/usr/bin/env bash
export LC_ALL=C
# learning-metric.sh — SCL-001 S3: métrica de aprendizaje L (determinista)
#
# L = w_p*p_consistent + w_d*(1 - divergencia) + w_i*ignorancia_resuelta
#
# Componentes (todos computables, ver spec):
#   - p_consistent        (SE-292 S6): fracción de ejecuciones consistentes
#   - divergencia         (Labs L1): distancia grafo-modelo, 0=solo, 1=max
#   - ignorancia_resuelta (Labs L2): certificados resueltos / total
#
# Determinismo (AC-3.1): misma entrada → misma L. Sin fechas, sin azar.
# Agnosticismo (AC-3.5): L no depende del modelo que ejecutó — inputs son
# escalares medidos, no identidades de proveedor.
#
# Usage:
#   learning-metric.sh --p-consistent <0-1> --divergence <0-1> \
#     --ignorance-resolved <0-1> [--w-p 0.5] [--w-d 0.3] [--w-i 0.2] [--json]
#     [--measured]
#
# SE-515 S1 (AC-4): sin --measured, la salida sale marcada «no medido» (los
# valores pueden ser por defecto). Solo quien mide los tres componentes pasa
# --measured. SAVIA_LEARNING_APPLIED=off vuelve a la salida anterior.
#
# Exit codes: 0 ok, 2 usage, 3 input out of range
#
# Ref: docs/specs/SCL-001-aprendizaje-continuo.spec.md (S3, AC-3.1/3.2/3.5)

set -uo pipefail

P=""; D=""; I=""
W_P="0.5"; W_D="0.3"; W_I="0.2"
JSON=false
MEASURED=false

usage() {
  sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --p-consistent) P="$2"; shift 2 ;;
    --divergence) D="$2"; shift 2 ;;
    --ignorance-resolved) I="$2"; shift 2 ;;
    --w-p) W_P="$2"; shift 2 ;;
    --w-d) W_D="$2"; shift 2 ;;
    --w-i) W_I="$2"; shift 2 ;;
    --json) JSON=true; shift ;;
    --measured) MEASURED=true; shift ;;
    -h|--help) usage ;;
    *) shift ;;
  esac
done

[[ -z "$P" || -z "$D" || -z "$I" ]] && usage

# Refutación Codex (PR #1523): la salida JSON interpola los valores tal cual; «.7» o «1.» no son
# números JSON. Se normalizan a «0.7» y «1.0»; cualquier otra forma no decimal se rechaza (exit 3).
norm() {
  local x="$1"
  [[ "$x" == .* ]] && x="0$x"
  [[ "$x" == *. ]] && x="${x}0"
  [[ "$x" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: not a decimal number: $1" >&2; exit 3; }
  printf '%s' "$x"
}
P=$(norm "$P") || exit 3; D=$(norm "$D") || exit 3; I=$(norm "$I") || exit 3
W_P=$(norm "$W_P") || exit 3; W_D=$(norm "$W_D") || exit 3; W_I=$(norm "$W_I") || exit 3

# Range validation: all in [0,1] (explicit verdict, locale-safe)
for v in "$P" "$D" "$I" "$W_P" "$W_D" "$W_I"; do
  verdict=$(awk -v x="$v" 'BEGIN{ if (x<0 || x>1) print "INVALID"; else print "OK" }')
  [[ "$verdict" == "OK" ]] || { echo "ERROR: value out of range [0,1]: $v" >&2; exit 3; }
done

# Deterministic scalar via awk (no external RNG)
L=$(awk -v p="$P" -v d="$D" -v i="$I" -v wp="$W_P" -v wd="$W_D" -v wi="$W_I" \
  'BEGIN { l = wp*p + wd*(1-d) + wi*i; printf "%.6f", l }')

DIVERGENCE_TERM=$(awk -v d="$D" 'BEGIN { printf "%.6f", 1-d }')

STATUS="no medido"
$MEASURED && STATUS="medido"
LEGACY=false
[[ "${SAVIA_LEARNING_APPLIED:-on}" == "off" ]] && LEGACY=true

if $JSON; then
  if $LEGACY; then
    printf '{"L":%s,"components":{"p_consistent":%s,"divergence":%s,"divergence_term":%s,"ignorance_resolved":%s},"weights":{"w_p":%s,"w_d":%s,"w_i":%s}}\n' \
      "$L" "$P" "$D" "$DIVERGENCE_TERM" "$I" "$W_P" "$W_D" "$W_I"
  else
    printf '{"L":%s,"measured":%s,"status":"%s","components":{"p_consistent":%s,"divergence":%s,"divergence_term":%s,"ignorance_resolved":%s},"weights":{"w_p":%s,"w_d":%s,"w_i":%s}}\n' \
      "$L" "$MEASURED" "$STATUS" "$P" "$D" "$DIVERGENCE_TERM" "$I" "$W_P" "$W_D" "$W_I"
  fi
else
  echo "L=$L"
  echo "  p_consistent=$P divergence=$D (term=$DIVERGENCE_TERM) ignorance_resolved=$I"
  $LEGACY || echo "  estado=$STATUS"
fi
exit 0
