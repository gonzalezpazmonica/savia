# l4-exec-lib.bash — evals L4 de COMPORTAMIENTO que ejecutan el guardarrail real.
# Ejecutor unico para los agentes cuyo script determinista es un hook o script
# (el agregador del Recommendation Tribunal usa l4_aggregate_cases de l4-eval-lib.bash).
#
# Formato de un case ejecutable en tests/evals/<agente>/{golden,edge,adversarial,bypass}.json:
#   "aggregate": {
#     "script": "<ruta repo del script o hook real>",
#     "args":   ["..."],                       # opcional; "{dir}" = directorio temporal del case
#     "cwd":    "{dir}",                       # opcional; por defecto, la raiz del repo
#     "stdin_command": "<orden>" | ["parte", "parte"],   # entrada de hook PreToolUse (Bash)
#     "stdin_json": {...} | "stdin": "<texto>" | [partes],  # otras entradas
#     "files": {"<ruta relativa a {dir}>": "<contenido>" | [partes]},
#     "env":   {"VAR": "valor"},
#     "expect": {"exit": N, "stdout_match": re, "stdout_not_match": re,
#                "stderr_match": re, "stderr_not_match": re,   # re = regex o lista (todas)
#                "stdout_empty": true, "json": {"<ruta jq>": <valor>},
#                "files_match": {"<ruta>": re}, "files_absent": ["<ruta>"]}
#   }
# Un case con "negative": true espera rechazo o bloqueo (l4_exec_shape).
# El script se resuelve desde la raiz del repo y corre sin las variables del
# operador que cambian su decision (ISOLATE en l4_exec_eval.py); el env del case
# se aplica despues. Fallan cerrado: claves desconocidas, "{{TMP}}" (marcador
# retirado) y un exit 0 sin otra expectativa.
# Las partes se concatenan al ejecutar: asi los fixtures no contienen literales
# con forma de credencial o PII que disparen los escaneres del repo.
# La matriz (scripts/eval-coverage-matrix.py) cuenta estos cases como comportamiento.
# Sin llamadas a modelo: solo se ejecuta el script determinista.

_L4_EXEC_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/l4_exec_eval.py"

# l4_exec_cases <fixture.json> [ORIG=REEMPLAZO ...]
# 0 si todos los cases ejecutables cumplen; 1 en la primera discrepancia (imprime
# el id del case); 2 si el fixture no tiene cases ejecutables o esta mal formado.
# ORIG=REEMPLAZO sustituye el script del case por una copia mutada.
l4_exec_cases() {
  local fixture="$1" m
  shift
  local -a extra=()
  for m in "$@"; do extra+=(--script "$m"); done
  python3 "$_L4_EXEC_PY" "$fixture" "${extra[@]}"
}

# l4_exec_mutant <script> <expresion-sed> <destino>
# Copia mutada del script. Falla si la mutacion no cambia nada: el mutante no existe.
# Si el script vive en .claude/hooks, enlaza lib/ junto a la copia.
l4_exec_mutant() {
  local src="$1" expr="$2" dst="$3"
  mkdir -p "$(dirname "$dst")"
  sed -E "$expr" "$src" > "$dst"
  ! cmp -s "$src" "$dst" || { echo "l4: la mutacion no cambia $src" >&2; return 1; }
  if [[ "$src" == .claude/hooks/* && ! -e "$(dirname "$dst")/lib" ]]; then
    ln -s "$PWD/.claude/hooks/lib" "$(dirname "$dst")/lib"
  fi
}

# l4_hook_copy <hook> <dstdir> — copia el hook y su lib/ para mutarlos sin tocar el repo.
l4_hook_copy() {
  mkdir -p "$2"
  cp "$1" "$2/"
  cp -R "$(dirname "$1")/lib" "$2/lib"
}

# l4_exec_shape <evaldir>
# Cada fixture (golden, edge, adversarial, bypass) tiene al menos un case ejecutable,
# el agente suma entre 3 y 5 y al menos uno es "negative".
l4_exec_shape() {
  local dir="$1" s c total=0 neg=0
  for s in golden edge adversarial bypass; do
    c=$(jq '[.cases // [] | .[] | select(has("aggregate"))] | length' "$dir/$s.json")
    [ "$c" -ge 1 ] || { echo "l4: $dir/$s.json sin case ejecutable" >&2; return 1; }
    total=$((total + c))
    neg=$((neg + $(jq '[.cases // [] | .[] | select(has("aggregate") and .negative == true)] | length' "$dir/$s.json")))
  done
  [ "$total" -ge 3 ] && [ "$total" -le 5 ] || { echo "l4: $total cases ejecutables (3-5)" >&2; return 1; }
  [ "$neg" -ge 1 ] || { echo "l4: ningun case negativo" >&2; return 1; }
}
