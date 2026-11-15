#!/usr/bin/env bats
# SE-376 S03 — merge-plan: el cálculo de orden y choques del plan del merge-sprint, ejecutado sobre
# repos git reales y pequeños (sin gh ni red). Se extrae el cálculo de plan_order del script real,
# así que cualquier cambio en él cae aquí: choques por pares con merge-tree, registros y derivados
# sin aviso, orden voraz por grado, solapamientos sin conflicto y pares no calculables.
# Ref: docs/specs/SE-500-merge-sprint-sin-realineacion.spec.md · .claude/skills/merge-plan/SKILL.md · scripts/merge-sprint.sh
set -uo pipefail

SCRIPT="scripts/merge-sprint.sh"
DERIVED_RE='^(gen/derivado\.md$)'
REGISTRY_RE='^registro\.json$'

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  W="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
  R="$W/repo"
  # El cálculo vive en el heredoc de plan_order: se extrae del script real, no se copia.
  sed -n "/^plan_order()/,/^}/p" "$ROOT/$SCRIPT" | sed -n "/<<'PY'/,/^PY\$/p" | sed '1d;$d' > "$W/plan.py"
  [ -s "$W/plan.py" ]
  git init -q -b main "$R"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
  seq 1 30 | sed 's/^/linea /' > "$R/f.txt"
  seq 1 30 | sed 's/^/linea /' > "$R/g.txt"
  seq 1 30 | sed 's/^/linea /' > "$R/h.txt"
  mkdir -p "$R/gen"; echo base > "$R/gen/derivado.md"; echo base > "$R/gen/otro.md"; echo '{}' > "$R/registro.json"
  git -C "$R" add -A; git -C "$R" commit -qm base
}

teardown() { cd /; }

# edit <rama> <fichero:linea:texto>... → crea la rama desde main con esos cambios y devuelve el sha por stdout
edit() {
  local br="$1"; shift
  git -C "$R" checkout -q -b "$br" main
  local spec f l t
  for spec in "$@"; do
    f="${spec%%:*}"; rest="${spec#*:}"; l="${rest%%:*}"; t="${rest#*:}"
    if [ "$l" = "0" ]; then printf '%s\n' "$t" > "$R/$f"; else sed -i "${l}s/.*/$t/" "$R/$f"; fi
  done
  git -C "$R" add -A; git -C "$R" commit -qm "$br"
  git -C "$R" rev-parse HEAD
  git -C "$R" checkout -q main
}

# pr <num> <sha> <ficheros separados por coma> → objeto JSON de candidata
pr() { python3 -c 'import json,sys; print(json.dumps({"pr":int(sys.argv[1]),"head":sys.argv[2],"files":[f for f in sys.argv[3].split(",") if f]}))' "$1" "$2" "$3"; }

plan() { # plan <json-array> [dpaths] → JSON del cálculo
  python3 "$W/plan.py" "$R" "$1" "$DERIVED_RE" "$REGISTRY_RE" "${2:-}"
}
get() { printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[sys.argv[1]], separators=(",",":"), ensure_ascii=False))' "$2"; }

@test "tres PR en ficheros distintos: sin choques ni avisos y orden ascendente" {
  a="$(edit pa f.txt:1:AAA)"; b="$(edit pb g.txt:1:BBB)"; c="$(edit pc h.txt:1:CCC)"
  out="$(plan "[$(pr 10 "$a" f.txt),$(pr 11 "$b" g.txt),$(pr 12 "$c" h.txt)]")"
  [ "$(get "$out" order)" = "[10,11,12]" ]
  [ "$(get "$out" collisions)" = "[]" ]
  [ "$(get "$out" warnings)" = "[]" ]
}

@test "dos PR editan la misma línea: choque con el fichero y la independiente va primero" {
  a="$(edit pa f.txt:5:UNO)"; b="$(edit pb f.txt:5:DOS)"; c="$(edit pc h.txt:1:CCC)"
  out="$(plan "[$(pr 10 "$a" f.txt),$(pr 11 "$b" f.txt),$(pr 12 "$c" h.txt)]")"
  [ "$(get "$out" collisions)" = '[{"files":["f.txt"],"pr":10,"with":11}]' ]
  [ "$(get "$out" order)" = "[12,10,11]" ]
  # un fichero en conflicto no se avisa además como «solapamiento sin conflicto»
  [ "$(get "$out" warnings)" = "[]" ]
}

@test "estrella: la PR que choca con dos va la última y las otras dos primero ([11,12,10])" {
  b="$(edit pb f.txt:3:BBB g.txt:3:BBB)"; a="$(edit pa f.txt:3:AAA)"; c="$(edit pc g.txt:3:CCC)"
  out="$(plan "[$(pr 10 "$b" f.txt,g.txt),$(pr 11 "$a" f.txt),$(pr 12 "$c" g.txt)]")"
  [ "$(get "$out" order)" = "[11,12,10]" ]
  [ "$(get "$out" collisions)" = '[{"files":["f.txt"],"pr":10,"with":11},{"files":["g.txt"],"pr":10,"with":12}]' ]
}

@test "orden de entrada irrelevante: se ordena por número de PR antes de calcular" {
  a="$(edit pa f.txt:5:UNO)"; b="$(edit pb f.txt:5:DOS)"; c="$(edit pc h.txt:1:CCC)"
  directo="$(plan "[$(pr 10 "$a" f.txt),$(pr 11 "$b" f.txt),$(pr 12 "$c" h.txt)]")"
  invertido="$(plan "[$(pr 12 "$c" h.txt),$(pr 11 "$b" f.txt),$(pr 10 "$a" f.txt)]")"
  [ "$directo" = "$invertido" ]
  [ "$(get "$invertido" order)" = "[12,10,11]" ]
}

@test "un choque solo en el registro o en un derivado no avisa ni altera el orden; el mixto solo lista lo real" {
  a="$(edit pa registro.json:0:'{"a":1}' gen/derivado.md:0:uno)"
  b="$(edit pb registro.json:0:'{"b":2}' gen/derivado.md:0:dos)"
  out="$(plan "[$(pr 10 "$a" registro.json,gen/derivado.md),$(pr 11 "$b" registro.json,gen/derivado.md)]")"
  [ "$(get "$out" collisions)" = "[]" ]
  [ "$(get "$out" warnings)" = "[]" ]
  [ "$(get "$out" order)" = "[10,11]" ]
  a2="$(edit pa2 registro.json:0:'{"a":1}' f.txt:2:UNO)"
  b2="$(edit pb2 registro.json:0:'{"b":2}' f.txt:2:DOS)"
  out="$(plan "[$(pr 10 "$a2" registro.json,f.txt),$(pr 11 "$b2" registro.json,f.txt)]")"
  [ "$(get "$out" collisions)" = '[{"files":["f.txt"],"pr":10,"with":11}]' ]
}

@test "las rutas D de la lista cerrada se excluyen: prefijo con / y ruta exacta" {
  a="$(edit pa f.txt:0:uno g.txt:0:uno)"; b="$(edit pb f.txt:0:dos g.txt:0:dos)"
  out="$(plan "[$(pr 10 "$a" f.txt,g.txt),$(pr 11 "$b" f.txt,g.txt)]" "$(printf 'f.txt\n')")"
  [ "$(get "$out" collisions)" = '[{"files":["g.txt"],"pr":10,"with":11}]' ]
  out="$(plan "[$(pr 10 "$a" f.txt,g.txt),$(pr 11 "$b" f.txt,g.txt)]" "$(printf 'f.txt\ng.txt\n')")"
  [ "$(get "$out" collisions)" = "[]" ]
}

@test "mismo fichero en líneas distintas: aviso de solapamiento sin conflicto, sin colisión y sin reordenar" {
  a="$(edit pa f.txt:1:ARRIBA)"; b="$(edit pb f.txt:30:ABAJO)"
  out="$(plan "[$(pr 10 "$a" f.txt),$(pr 11 "$b" f.txt)]")"
  [ "$(get "$out" collisions)" = "[]" ]
  [ "$(get "$out" order)" = "[10,11]" ]
  [[ "$(get "$out" warnings)" == *"#10 solapa con #11 en f.txt (sin conflicto previsto)"* ]]
}

@test "el solapamiento en registros o derivados tampoco avisa" {
  a="$(edit pa registro.json:0:'{"a":1}')"; b="$(edit pb gen/derivado.md:0:otro)"
  out="$(plan "[$(pr 10 "$a" registro.json,gen/derivado.md),$(pr 11 "$b" registro.json,gen/derivado.md)]")"
  [ "$(get "$out" warnings)" = "[]" ]
}

@test "head ausente del repo (nonexistent): aviso de colisión no calculable, nunca se da por independiente en silencio" {
  a="$(edit pa f.txt:5:UNO)"
  out="$(plan "[$(pr 10 "$a" f.txt),$(pr 11 0000000000000000000000000000000000000000 f.txt)]")"
  [ "$(get "$out" collisions)" = "[]" ]
  [[ "$(get "$out" warnings)" == *"#10 y #11: colisión no calculable (head ausente del repo)"* ]]
  [ "$(get "$out" order)" = "[10,11]" ]
}

@test "caso límite: lista empty de candidatas → orden vacío sin error" {
  out="$(plan "[]")"
  [ "$(get "$out" order)" = "[]" ]
  [ "$(get "$out" collisions)" = "[]" ]
}

@test "caso límite: una sola PR (zero pares) → su orden y ningún aviso" {
  a="$(edit pa f.txt:5:UNO)"
  out="$(plan "[$(pr 7 "$a" f.txt)]")"
  [ "$(get "$out" order)" = "[7]" ]
  [ "$(get "$out" warnings)" = "[]" ]
}

@test "cadena 10–11–12: el voraz elige un conjunto sin choques entre sí ([10,12,11]) y no pierde ninguna PR" {
  a="$(edit pa f.txt:3:AAA)"; b="$(edit pb f.txt:3:BBB g.txt:3:BBB)"; c="$(edit pc g.txt:3:CCC)"
  out="$(plan "[$(pr 10 "$a" f.txt),$(pr 11 "$b" f.txt,g.txt),$(pr 12 "$c" g.txt)]")"
  [ "$(get "$out" order)" = "[10,12,11]" ]
}

@test "determinismo: mismas entradas, misma salida byte a byte con otro locale" {
  a="$(edit pa f.txt:5:UNO)"; b="$(edit pb f.txt:5:DOS)"
  j="[$(pr 10 "$a" f.txt),$(pr 11 "$b" f.txt)]"
  x="$(plan "$j")"
  y="$(LC_ALL=C LANG=C plan "$j")"
  [ "$x" = "$y" ]
}

@test "error: JSON de candidatas ilegible → el cálculo falla (no devuelve un orden inventado)" {
  run python3 "$W/plan.py" "$R" 'esto no es json' "$DERIVED_RE" "$REGISTRY_RE" ""
  [ "$status" -ne 0 ]
  [[ "$output" != *'"order"'* ]]
}

@test "el voraz deja fuera a las que chocan con una ya elegida y las coloca al final por número ([10,13,14,11,12])" {
  a="$(edit pa f.txt:5:UNO)"; b="$(edit pb f.txt:5:DOS)"
  c="$(edit pc g.txt:3:CCC h.txt:3:CCC)"; d="$(edit pd g.txt:3:DDD)"; e="$(edit pe h.txt:3:EEE)"
  out="$(plan "[$(pr 10 "$a" f.txt),$(pr 11 "$b" f.txt),$(pr 12 "$c" g.txt,h.txt),$(pr 13 "$d" g.txt),$(pr 14 "$e" h.txt)]")"
  [ "$(get "$out" order)" = "[10,13,14,11,12]" ]
}

@test "error de merge-tree (historias sin relación): aviso de colisión no calculable, no un par independiente" {
  a="$(edit pa f.txt:5:UNO)"
  git -C "$R" checkout -q --orphan huerfana
  git -C "$R" rm -rfq . > /dev/null 2>&1
  echo otro > "$R/z.txt"
  git -C "$R" add z.txt
  git -C "$R" commit -qm huerfana
  h="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" checkout -q main
  out="$(plan "[$(pr 10 "$a" f.txt),$(pr 11 "$h" z.txt)]")"
  [[ "$(get "$out" warnings)" == *"colisión no calculable (merge-tree falló)"* ]]
  [ "$(get "$out" collisions)" = "[]" ]
}

@test "ruta D con prefijo (termina en /): excluye lo de dentro; sin la entrada, el mismo choque sí avisa" {
  a="$(edit pa gen/otro.md:0:uno)"; b="$(edit pb gen/otro.md:0:dos)"
  j="[$(pr 10 "$a" gen/otro.md),$(pr 11 "$b" gen/otro.md)]"
  [ "$(get "$(plan "$j" "gen/")" collisions)" = "[]" ]
  [ "$(get "$(plan "$j" "")" collisions)" = '[{"files":["gen/otro.md"],"pr":10,"with":11}]' ]
}
