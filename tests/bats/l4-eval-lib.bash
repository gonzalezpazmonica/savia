# l4-eval-lib.bash — utilidades compartidas de las evals L4 de agentes (SE-387 D).
#
# Formato de un fixture en tests/evals/<agente>/{golden,edge,adversarial,bypass}.json:
#   { "scenario": "...", "agent": "...", "cases": [ { "id", "input", "expected",
#       "checks": [ {"id", "target", "must_match" | "must_not_match"} ],
#       "aggregate": {...} } ] }
#
# Un "check" es una aserción estática y comprobable sobre un fichero:
#   target = "agent"            -> el fichero de definición del agente bajo prueba
#   target = "<ruta repo>"      -> cualquier otro fichero del repo
#   must_match / must_not_match -> expresión regular extendida (grep -E)
#
# Las evals de definición no ejecutan ningún modelo: comprueban que el contrato
# declarado del agente (vetos, listas de delegación, restricciones, umbrales)
# sigue escrito. El comportamiento con modelo se corre aparte; ver
# tests/evals/README.md (sección "Evals L4 de agentes").

# l4_check_one <fichero> <regex> <match|nomatch>
l4_check_one() {
  local file="$1" re="$2" mode="$3"
  [ -f "$file" ] || { echo "l4: fichero ausente: $file" >&2; return 2; }
  if [ "$mode" = match ]; then
    grep -qE -- "$re" "$file"
  else
    ! grep -qE -- "$re" "$file"
  fi
}

# l4_run_checks <fixture.json> <agent-file>
# Aplica todos los checks de todos los cases. Devuelve 1 en el primero que falle
# (imprime su id) y 2 si el fixture no contiene ningún check.
l4_run_checks() {
  local fixture="$1" agent_file="$2" n=0 line id target re mode file
  while IFS= read -r line; do
    n=$((n + 1))
    id=$(jq -r '.id' <<<"$line")
    target=$(jq -r '.target' <<<"$line")
    if jq -e 'has("must_match")' <<<"$line" >/dev/null; then
      re=$(jq -r '.must_match' <<<"$line"); mode=match
    elif jq -e 'has("must_not_match")' <<<"$line" >/dev/null; then
      re=$(jq -r '.must_not_match' <<<"$line"); mode=nomatch
    else
      echo "l4: check sin must_match/must_not_match: $id" >&2; return 2
    fi
    if [ "$target" = agent ]; then file="$agent_file"; else file="$target"; fi
    if ! l4_check_one "$file" "$re" "$mode"; then
      echo "l4: FALLA check '$id' ($mode /$re/ en $file)" >&2
      return 1
    fi
  done < <(jq -c '.cases[].checks[]?' "$fixture")
  [ "$n" -gt 0 ] || { echo "l4: $fixture sin checks" >&2; return 2; }
}

# l4_check_count <fixture.json> -> número de checks
l4_check_count() {
  jq '[.cases[].checks[]?] | length' "$1"
}

# l4_mutate_remove <agent-file> <regex> <destino>
# Copia el agente sin las líneas que casan con <regex> (para probar que el check
# detecta la ausencia). Falla si la regex no elimina nada: el mutante no existe.
l4_mutate_remove() {
  local src="$1" re="$2" dst="$3"
  grep -vE -- "$re" "$src" > "$dst"
  ! cmp -s "$src" "$dst"
}

# l4_aggregate_cases <fixture.json> <aggregate.sh> <tmpdir>
# Ejecuta de verdad el agregador determinista con los jueces sintéticos de cada
# case que tenga "aggregate" y compara con "expect" (exit, verdict,
# consensus_score, veto_triggered, veto_judges). Devuelve 1 en la primera
# discrepancia y 2 si el fixture no tiene ningún case ejecutable.
# En "judges", un objeto {"raw": "<texto>"} escribe el fichero tal cual
# (para entradas que no son JSON); "remove_file": N borra el fichero N-ésimo.
l4_aggregate_cases() {
  local fixture="$1" script="$2" tmp="$3" idx n=0 total i j rc out id d
  local -a files
  total=$(jq '.cases | length' "$fixture")
  for ((idx = 0; idx < total; idx++)); do
    jq -e ".cases[$idx] | has(\"aggregate\")" "$fixture" >/dev/null || continue
    n=$((n + 1))
    id=$(jq -r ".cases[$idx].id" "$fixture")
    d="$tmp/case-$idx"; mkdir -p "$d"
    files=(); i=0
    while IFS= read -r j; do
      if jq -e 'has("raw")' <<<"$j" >/dev/null; then
        jq -r '.raw' <<<"$j" > "$d/j$i.json"
      else
        printf '%s\n' "$j" > "$d/j$i.json"
      fi
      files+=("$d/j$i.json"); i=$((i + 1))
    done < <(jq -c ".cases[$idx].aggregate.judges[]" "$fixture")
    if jq -e ".cases[$idx].aggregate | has(\"remove_file\")" "$fixture" >/dev/null; then
      local rm_i; rm_i=$(jq ".cases[$idx].aggregate.remove_file" "$fixture")
      unlink "${files[$rm_i]}"
    fi
    rc=0; out=$(bash "$script" --judges "${files[@]}" 2>/dev/null) || rc=$?
    if [ "$rc" -ne "$(jq ".cases[$idx].aggregate.expect.exit" "$fixture")" ]; then
      echo "l4: case '$id': exit $rc != esperado" >&2; return 1
    fi
    [ "$rc" -eq 0 ] || continue
    local k want got
    for k in verdict consensus_score veto_triggered veto_judges; do
      jq -e ".cases[$idx].aggregate.expect | has(\"$k\")" "$fixture" >/dev/null || continue
      want=$(jq -c ".cases[$idx].aggregate.expect.$k" "$fixture")
      got=$(jq -c ".$k" <<<"$out")
      if [ "$want" != "$got" ]; then
        echo "l4: case '$id': $k=$got != esperado $want" >&2; return 1
      fi
    done
  done
  [ "$n" -gt 0 ] || { echo "l4: $fixture sin cases aggregate" >&2; return 2; }
}

# l4_weights_check <fixture.json> [doc]
# Para cada case con "weights": cada perfil del doc (### <perfil> ...) debe
# listar exactamente una vez cada dimension y sumar 1.00. Devuelve 1 si no.
l4_weights_check() {
  local fixture="$1" override="${2:-}" n=0 doc p d idx total ok
  total=$(jq '.cases | length' "$fixture")
  for ((idx = 0; idx < total; idx++)); do
    jq -e ".cases[$idx] | has(\"weights\")" "$fixture" >/dev/null || continue
    n=$((n + 1))
    doc="${override:-$(jq -r ".cases[$idx].weights.file" "$fixture")}"
    [ -f "$doc" ] || { echo "l4: doc de pesos ausente: $doc" >&2; return 2; }
    local dims; dims=$(jq -r ".cases[$idx].weights.dimensions | join(\" \")" "$fixture")
    for p in $(jq -r ".cases[$idx].weights.profiles[]" "$fixture"); do
      ok=$(LC_ALL=C awk -v prof="$p" -v dims="$dims" '
        /^### / { inprof = ($2 == prof); next }
        inprof && $1 == "|" && $2 ~ /^[a-z_]+$/ && $4 ~ /^[0-9.]+$/ { seen[$2]++; sum += $4 }
        END {
          nd = split(dims, arr, " "); good = 1
          for (i = 1; i <= nd; i++) if (seen[arr[i]] != 1) good = 0
          d = sum - 1; if (d < 0) d = -d
          print (good && d < 0.0001) ? "ok" : "bad sum=" sum
        }' "$doc")
      [ "$ok" = ok ] || { echo "l4: perfil '$p' invalido en $doc: $ok" >&2; return 1; }
    done
  done
  [ "$n" -gt 0 ] || { echo "l4: $fixture sin cases weights" >&2; return 2; }
}
