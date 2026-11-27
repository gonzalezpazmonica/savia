# l4-script-cases-lib.bash — evals L4 de COMPORTAMIENTO para agentes cuyo script
# determinista no es el agregador del Recommendation Tribunal (ese usa
# l4_aggregate_cases de l4-eval-lib.bash).
#
# Un case ejecutable lleva "aggregate" (lo que cuenta scripts/eval-coverage-matrix.py
# como comportamiento). Forma:
#   "aggregate": {
#     "run":   ["subcomando", "arg", ...],        # argumentos del script
#     "stdin": "texto",                           # opcional (payload de un hook)
#     "env":   {"VAR": "valor"},                  # opcional
#     "files": {"ruta/relativa": "contenido"},    # opcional, se crean en el dir del case
#     "expect": {
#       "exit": 0,                                # obligatorio
#       "stdout_match": ["regex"], "stdout_not_match": ["regex"],
#       "stderr_match": ["regex"],
#       "stdout_empty": true,
#       "json": {".ruta.jq": <valor esperado>},   # stdout parseado con jq
#       "files_absent": ["ruta/relativa"]         # efectos que NO deben ocurrir
#     }
#   }
# "{{TMP}}" en cualquier cadena se sustituye por el directorio del case (rutas absolutas
# para payloads de hooks). El script se ejecuta con cwd = ese directorio y sin las variables
# de entorno del operador que cambian su decisión (L4_SCRIPT_ISOLATE).
# Un case con "negative": true espera rechazo/bloqueo; cada agente necesita al menos uno.
#
# No llama a ningún modelo: ejecuta el script real con entradas sintéticas.

L4_SCRIPT_ISOLATE=(CLAUDE_PROJECT_DIR OPENCODE_PROJECT_DIR SAVIA_WORKSPACE_DIR PROJECT_ROOT AGENTS_DIR
  SAVIA_HOOK_PROFILE SAVIA_DOME_GUARD SAVIA_GATES_PIN SAVIA_SPACE_DOMES_FILE SAVIA_DOME_READ_DIR
  COHERENCE_SCORE_PASS COHERENCE_SCORE_CONDITIONAL COHERENCE_PREMISES_DIR
  COURT_MAX_LOC COURT_SCORE_PASS COURT_SCORE_CONDITIONAL COURT_MAX_FIX_ROUNDS)

# l4_script_cases <fixture.json> <script> <tmpdir>
# Devuelve 1 en la primera discrepancia (imprime el id del case) y 2 si el fixture
# no tiene ningún case ejecutable.
l4_script_cases() {
  local fixture="$1" script="$2" tmp="$3" total idx n=0 id d spec rc re k want got f
  [ -f "$script" ] || { echo "l4: script ausente: $script" >&2; return 2; }
  script="$(cd "$(dirname "$script")" && pwd)/$(basename "$script")"
  total=$(jq '.cases // [] | length' "$fixture")
  for ((idx = 0; idx < total; idx++)); do
    jq -e ".cases[$idx] | has(\"aggregate\")" "$fixture" >/dev/null || continue
    n=$((n + 1))
    id=$(jq -r ".cases[$idx].id" "$fixture")
    d="$tmp/script-case-$idx-$RANDOM"; mkdir -p "$d"; d="$(cd "$d" && pwd -P)"
    spec=$(jq -c --arg t "$d" ".cases[$idx].aggregate
      | walk(if type == \"string\" then gsub(\"\\\\{\\\\{TMP\\\\}\\\\}\"; \$t) else . end)" "$fixture")
    while IFS= read -r -d '' f; do
      mkdir -p "$d/$(dirname "$f")"
      jq -j --arg f "$f" '.files[$f]' <<<"$spec" > "$d/$f"
    done < <(jq -j '.files // {} | keys[] | . + "\u0000"' <<<"$spec")
    local -a args=() envs=() unsets=()
    while IFS= read -r -d '' f; do args+=("$f"); done < <(jq -j '.run // [] | .[] | tostring + "\u0000"' <<<"$spec")
    while IFS= read -r -d '' f; do envs+=("$f"); done < <(jq -j '.env // {} | to_entries[] | "\(.key)=\(.value)\u0000"' <<<"$spec")
    for k in "${L4_SCRIPT_ISOLATE[@]}"; do unsets+=(-u "$k"); done
    if jq -e 'has("stdin")' <<<"$spec" >/dev/null; then
      jq -j '.stdin' <<<"$spec" > "$d/.stdin"
    else
      : > "$d/.stdin"
    fi
    rc=0
    (cd "$d" && env "${unsets[@]}" "${envs[@]}" bash "$script" "${args[@]}" \
      < "$d/.stdin" > "$d/.stdout" 2> "$d/.stderr") || rc=$?
    want=$(jq '.expect.exit' <<<"$spec")
    if [ "$rc" != "$want" ]; then
      echo "l4: case '$id': exit $rc != esperado $want; stderr: $(head -c 300 "$d/.stderr")" >&2; return 1
    fi
    while IFS= read -r -d '' re; do
      grep -qE -- "$re" "$d/.stdout" || { echo "l4: case '$id': stdout no casa /$re/" >&2; return 1; }
    done < <(jq -j '.expect.stdout_match // [] | .[] | . + "\u0000"' <<<"$spec")
    while IFS= read -r -d '' re; do
      ! grep -qE -- "$re" "$d/.stdout" || { echo "l4: case '$id': stdout casa /$re/ y no debia" >&2; return 1; }
    done < <(jq -j '.expect.stdout_not_match // [] | .[] | . + "\u0000"' <<<"$spec")
    while IFS= read -r -d '' re; do
      grep -qE -- "$re" "$d/.stderr" || { echo "l4: case '$id': stderr no casa /$re/" >&2; return 1; }
    done < <(jq -j '.expect.stderr_match // [] | .[] | . + "\u0000"' <<<"$spec")
    if jq -e '.expect.stdout_empty == true' <<<"$spec" >/dev/null && [ -s "$d/.stdout" ]; then
      echo "l4: case '$id': stdout no vacio: $(head -c 200 "$d/.stdout")" >&2; return 1
    fi
    while IFS= read -r -d '' k; do
      want=$(jq -c --arg k "$k" '.expect.json[$k]' <<<"$spec")
      got=$(jq -c "$k" "$d/.stdout" 2>/dev/null) || got="<stdout no es JSON>"
      [ "$want" = "$got" ] || { echo "l4: case '$id': $k=$got != esperado $want" >&2; return 1; }
    done < <(jq -j '.expect.json // {} | keys_unsorted[] | . + "\u0000"' <<<"$spec")
    while IFS= read -r -d '' f; do
      [ ! -e "$d/$f" ] || { echo "l4: case '$id': efecto prohibido, existe $f" >&2; return 1; }
    done < <(jq -j '.expect.files_absent // [] | .[] | . + "\u0000"' <<<"$spec")
  done
  [ "$n" -gt 0 ] || { echo "l4: $fixture sin cases aggregate" >&2; return 2; }
}

# l4_script_cases_shape <evaldir>
# Cada fixture (golden, edge, adversarial, bypass) tiene al menos un case ejecutable,
# el agente suma entre 3 y 5 y al menos uno es negativo.
l4_script_cases_shape() {
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

# l4_hook_copy <hook> <dstdir> — copia el hook y su lib/ para mutarlos sin tocar el repo.
l4_hook_copy() {
  mkdir -p "$2"
  cp "$1" "$2/"
  cp -R "$(dirname "$1")/lib" "$2/lib"
}
