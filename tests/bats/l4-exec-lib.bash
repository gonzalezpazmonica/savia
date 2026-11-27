# l4-exec-lib.bash — evals L4 de COMPORTAMIENTO que ejecutan el guardarrail real.
#
# Formato de un case ejecutable en tests/evals/<agente>/{golden,edge,adversarial,bypass}.json:
#   "aggregate": {
#     "script": "<ruta repo del script o hook real>",
#     "args":   ["..."],                       # opcional; "{dir}" = directorio temporal del case
#     "stdin_command": "<orden>" | ["parte", "parte"],   # entrada de hook PreToolUse (Bash)
#     "stdin_json": {...} | "stdin": "<texto>" | [partes],  # otras entradas
#     "files": {"<ruta relativa a {dir}>": "<contenido>" | [partes]},
#     "env":   {"VAR": "valor"},
#     "expect": {"exit": N, "stdout_match": re, "stdout_not_match": re,
#                "stderr_match": re, "stderr_not_match": re,
#                "files_match": {"<ruta>": re}, "files_absent": ["<ruta>"]}
#   }
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
