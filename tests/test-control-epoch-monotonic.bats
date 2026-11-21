#!/usr/bin/env bats
# SE-498 R2 — check obligatorio de main: una PR solo puede cambiar config/control/REVOCATION_EPOCH
# a exactamente el valor de main + 1 (fichero ausente = 0), como fichero regular 100644.
#
# El workflow control-epoch.yml ejecuta ESTE fichero desde la base (main), nunca desde la cabeza
# de la PR: la cabeza solo se lee como datos con git ls-tree / git cat-file.
#
# Entradas (entorno): CONTROL_EPOCH_REPO (repo git; por defecto el de este fichero),
# CONTROL_EPOCH_BASE (ref de main; por defecto origin/main), CONTROL_EPOCH_HEAD (cabeza; por defecto HEAD).

EPOCH_FILE=config/control/REVOCATION_EPOCH

epoch_value() {  # epoch_value <repo> <blob-sha> → entero o fallo
  git -C "$1" cat-file blob "$2" | python3 -I -c '
import re, sys
data = sys.stdin.buffer.read()
if not re.fullmatch(rb"[0-9]{1,9}\n?", data):
    sys.exit(1)
print(int(data))'
}

epoch_verdict() {
  local g="${CONTROL_EPOCH_REPO:-$(cd "$BATS_TEST_DIRNAME/.." && pwd)}"
  local base="${CONTROL_EPOCH_BASE:-origin/main}" head="${CONTROL_EPOCH_HEAD:-HEAD}"
  local mb mb_ls head_ls base_ls mode type sha base_val head_val
  git -C "$g" rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "FALLO: base ilegible ($base)"; return 1; }
  git -C "$g" rev-parse --verify -q "$head^{commit}" >/dev/null || { echo "FALLO: cabeza ilegible ($head)"; return 1; }
  mb=$(git -C "$g" merge-base "$base" "$head") || { echo "FALLO: sin merge-base"; return 1; }
  mb_ls=$(git -C "$g" ls-tree "$mb" -- "$EPOCH_FILE")
  head_ls=$(git -C "$g" ls-tree "$head" -- "$EPOCH_FILE")
  base_ls=$(git -C "$g" ls-tree "$base" -- "$EPOCH_FILE")
  if [[ "$mb_ls" == "$head_ls" ]]; then echo "OK: la PR no toca $EPOCH_FILE"; return 0; fi
  [[ -n "$head_ls" ]] || { echo "FALLO: la PR borra o renombra $EPOCH_FILE"; return 1; }
  read -r mode type sha _ <<< "$head_ls"
  [[ "$mode" == 100644 && "$type" == blob ]] || { echo "FALLO: $EPOCH_FILE debe ser un fichero regular 100644 ($mode $type)"; return 1; }
  head_val=$(epoch_value "$g" "$sha") || { echo "FALLO: $EPOCH_FILE de la PR no es un entero de 1-9 cifras"; return 1; }
  if [[ -z "$base_ls" ]]; then
    base_val=0
  else
    base_val=$(epoch_value "$g" "$(awk '{print $3}' <<< "$base_ls")") || { echo "FALLO: $EPOCH_FILE de main ilegible"; return 1; }
  fi
  [[ "$head_val" -eq $((base_val + 1)) ]] || { echo "FALLO: main está en $base_val; la PR solo puede subirlo a $((base_val + 1)), no a $head_val"; return 1; }
  echo "OK: $EPOCH_FILE de $base_val a $head_val"
}

@test "SE-498 R2: REVOCATION_EPOCH solo sube exactamente en 1 sobre main" {
  run epoch_verdict
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
}
