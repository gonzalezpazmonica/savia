#!/usr/bin/env bash
# Ejecuta cada suite BATS en su propio proceso para la suite nocturna (nightly-full-bats.yml).
#
# Uso: nightly-bats-run.sh <dir-salida> [suite...]
#   Sin suites: tests/*.bats y tests/bats/*.bats.
#   Escribe en <dir-salida>: all.txt, serial.txt, parallel.txt, rc.txt, failed.txt, summary.md
#   y un .tap por suite. Por stdout solo imprime `total=N` y `failed=M` (para $GITHUB_OUTPUT).
#   Sale 0 si ha podido medir (el paso de informe decide el rojo); 2 si no hay suites.
#
# Las suites marcadas `# nightly: serial` (en sus 3 primeras líneas) miden latencia real o comprueban que el árbol no cambia:
# en paralelo ven las escrituras de las demás, así que corren solas tras el lote paralelo.
# Una suite que no deja su línea en rc.txt (proceso muerto) cuenta como fallo `missing`: nunca
# desaparece del total.
#
# Variables: NIGHTLY_BATS_BIN (bats), NIGHTLY_TIMEOUT_S (900), NIGHTLY_JOBS (4).
set -uo pipefail

OUT="${1:?uso: nightly-bats-run.sh <dir-salida> [suite...]}"
shift
export NIGHTLY_OUT="$OUT"
export NIGHTLY_BATS_BIN="${NIGHTLY_BATS_BIN:-bats}"
export NIGHTLY_TIMEOUT_S="${NIGHTLY_TIMEOUT_S:-900}"
JOBS="${NIGHTLY_JOBS:-4}"

mkdir -p "$OUT"
: > "$OUT/rc.txt"
if (($#)); then
  printf '%s\n' "$@" | grep -v '^$' > "$OUT/all.txt"
else
  ls tests/*.bats tests/bats/*.bats 2>/dev/null > "$OUT/all.txt"
fi
if [[ ! -s "$OUT/all.txt" ]]; then
  echo "nightly-bats-run: no hay suites que ejecutar" >&2
  exit 2
fi

# Rutas por línea (-d '\n') y pasadas como argumento ("$1"), nunca pegadas al código del shell.
# El marcador solo vale en las 3 primeras líneas (tras el shebang): un texto igual en el cuerpo
# de una suite no la reclasifica.
: > "$OUT/serial.txt"
while IFS= read -r suite_path; do
  head -n 3 -- "$suite_path" 2>/dev/null | grep -qE '^# nightly: serial' && printf '%s\n' "$suite_path" >> "$OUT/serial.txt"
done < "$OUT/all.txt"
grep -vxFf "$OUT/serial.txt" "$OUT/all.txt" > "$OUT/parallel.txt"

run_one() {
  local out
  out="$NIGHTLY_OUT/$(printf '%s' "$1" | tr '/ ' '__').tap"
  timeout "$NIGHTLY_TIMEOUT_S" "$NIGHTLY_BATS_BIN" "$1" > "$out" 2>&1
  echo "$? $1" >> "$NIGHTLY_OUT/rc.txt"
}
export -f run_one
xargs -d '\n' -r -n1 -P "$JOBS" bash -c 'run_one "$1"' _ < "$OUT/parallel.txt"
xargs -d '\n' -r -n1 -P 1 bash -c 'run_one "$1"' _ < "$OUT/serial.txt"

# Suites sin línea en rc.txt: fallo explícito.
cut -d' ' -f2- "$OUT/rc.txt" | sort > "$OUT/ran.txt"
sort "$OUT/all.txt" | comm -23 - "$OUT/ran.txt" | sed 's/^/missing /' >> "$OUT/rc.txt"

total=$(wc -l < "$OUT/all.txt")
awk '$1 != "0"' "$OUT/rc.txt" | sort -k2 > "$OUT/failed.txt"
failed=$(wc -l < "$OUT/failed.txt")
{
  echo "## Nightly full BATS: $((total - failed))/$total suites pass"
  echo
  echo '| exit | suite |'
  echo '|---|---|'
  awk '{e=$1; $1=""; sub(/^ /, ""); print "| " e " | `" $0 "` |"}' "$OUT/failed.txt"
  echo
  echo "exit 124 = timeout ($NIGHTLY_TIMEOUT_S s); missing = la suite no registró su código de salida."
} > "$OUT/summary.md"

echo "total=$total"
echo "failed=$failed"
