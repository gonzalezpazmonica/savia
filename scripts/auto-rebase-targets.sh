#!/usr/bin/env bash
# auto-rebase-targets.sh — decide qué PR abiertas tienen conflicto REAL con main.
#
# Lo usa .github/workflows/auto-rebase-open-prs.yml antes de tocar ninguna rama.
#
# Causa (2026-11-11): justo después de cada push a main, GitHub devuelve
# mergeable=UNKNOWN / mergeStateStatus=UNKNOWN para todas las PR (la
# mergeabilidad se recalcula de forma perezosa). El workflow trataba UNKNOWN
# como «rebasable» e integraba main en TODAS las PR abiertas en cada avance de
# main: 4 tandas sobre 7-8 ramas en una tarde, ~50 runs de CI por tanda.
#
# Regla: solo es objetivo una PR con mergeable=CONFLICTING o
# mergeStateStatus=DIRTY. Las UNKNOWN se vuelven a consultar por rondas
# (`gh pr view`, que además fuerza el cálculo). Si tras las rondas siguen
# UNKNOWN, NO se tocan: el siguiente push a main o
# `scripts/resolve-all-open-prs.sh` las recogerá. Ante la duda, no se empuja.
#
# Entrada: array JSON por stdin con number, headRefName, mergeable,
#          mergeStateStatus (formato de `gh pr list --json`).
# Salida:  una línea «<número> <rama>» por objetivo, en stdout.
#          Diagnóstico por PR en stderr.
# Exit:    0 = decisión tomada (puede no haber objetivos)
#          2 = entrada no válida (no se decide nada: fail-closed)
#
# Entorno: AUTO_REBASE_POLL_ROUNDS (6), AUTO_REBASE_POLL_SECONDS (10), GH_BIN (gh).
set -uo pipefail

ROUNDS="${AUTO_REBASE_POLL_ROUNDS:-6}"
SLEEP_S="${AUTO_REBASE_POLL_SECONDS:-10}"
GH_BIN="${GH_BIN:-gh}"

[[ "$ROUNDS" =~ ^[0-9]+$ ]] || { echo "auto-rebase-targets: AUTO_REBASE_POLL_ROUNDS no numérico" >&2; exit 2; }
[[ "$SLEEP_S" =~ ^[0-9]+$ ]] || { echo "auto-rebase-targets: AUTO_REBASE_POLL_SECONDS no numérico" >&2; exit 2; }

input=$(cat)
if ! jq -e 'type == "array" and all(.[]; (.number|type) == "number" and (.headRefName|type) == "string")' \
     >/dev/null 2>&1 <<<"$input"; then
  echo "auto-rebase-targets: entrada no válida (se esperaba array de PR de gh pr list)" >&2
  exit 2
fi

# Clasifica un par mergeable/state: conflict | clean | unknown | other
classify() {
  local m="$1" s="$2"
  if [[ "$m" == "CONFLICTING" || "$s" == "DIRTY" ]]; then echo conflict
  elif [[ "$m" == "UNKNOWN" || "$s" == "UNKNOWN" || -z "$m" || -z "$s" ]]; then echo unknown
  elif [[ "$m" == "MERGEABLE" && "$s" == "CLEAN" ]]; then echo clean
  else echo other
  fi
}

declare -A branch_of=() verdict=() last=()
order=()
while read -r num branch m s; do
  order+=("$num")
  branch_of[$num]="$branch"
  verdict[$num]=$(classify "$m" "$s")
  last[$num]="$m/$s"
done < <(jq -r '.[] | "\(.number) \(.headRefName) \(.mergeable // "") \(.mergeStateStatus // "")"' <<<"$input")

round=0
while (( round < ROUNDS )); do
  pending=()
  for n in "${order[@]}"; do [[ "${verdict[$n]}" == unknown ]] && pending+=("$n"); done
  (( ${#pending[@]} == 0 )) && break
  round=$((round + 1))
  sleep "$SLEEP_S"
  for n in "${pending[@]}"; do
    if out=$("$GH_BIN" pr view "$n" --json mergeable,mergeStateStatus \
               --jq '"\(.mergeable // "") \(.mergeStateStatus // "")"' 2>/dev/null); then
      read -r m s <<<"$out"
      verdict[$n]=$(classify "${m:-}" "${s:-}")
      last[$n]="${m:-?}/${s:-?}"
    fi
    # Fallo de gh: se queda en unknown y se reintenta en la siguiente ronda.
  done
done

for n in "${order[@]}"; do
  case "${verdict[$n]}" in
    conflict) echo "PR #$n (${branch_of[$n]}) ${last[$n]} → conflicto real, se integra main" >&2
              printf '%s %s\n' "$n" "${branch_of[$n]}" ;;
    clean)    echo "PR #$n ${last[$n]} → limpia, no se toca" >&2 ;;
    unknown)  echo "PR #$n ${last[$n]} → mergeabilidad sin calcular tras $round rondas, no se toca" >&2 ;;
    *)        echo "PR #$n ${last[$n]} → sin conflicto con main, no se toca" >&2 ;;
  esac
done
exit 0
