#!/usr/bin/env bash
# Ejecuta cada suite BATS en su propio proceso para la suite nocturna (nightly-full-bats.yml).
#
# Uso: nightly-bats-run.sh <dir-salida> [suite...]
#   Sin suites: tests/*.bats y tests/bats/*.bats.
#   Escribe en <dir-salida>: all.txt, serial.txt, parallel.txt, rc.txt, failed.txt, summary.md
#   y un .tap por suite. Por stdout solo imprime `total=N` y `failed=M` (para $GITHUB_OUTPUT).
#   Sale 0 si ha podido medir (el paso de informe decide el rojo); 2 si no hay suites;
#   3 si falla el propio registro (escribir all.txt o rc.txt, contar, resumir, o un registro sin
#   exactamente una línea por suite): entonces no imprime contadores, porque unos contadores
#   sacados de un registro roto podrían salir en verde.
#   Los códigos se registran en un fichero privado de mktemp (las suites no reciben su ruta) y
#   solo al cerrar se mueven a <dir-salida>/rc.txt: lo que una suite escriba ahí se sobrescribe.
#
# Las suites marcadas `# nightly: serial` (en sus 3 primeras líneas) miden latencia real o comprueban que el árbol no cambia:
# en paralelo ven las escrituras de las demás, así que corren solas tras el lote paralelo.
# Una suite que no deja su línea en rc.txt (proceso muerto) cuenta como fallo `missing`: nunca
# desaparece del total.
#
# Variables: NIGHTLY_BATS_BIN (bats), NIGHTLY_TIMEOUT_S (900), NIGHTLY_JOBS (4).
set -uo pipefail

die() { echo "nightly-bats-run: $*" >&2; exit 3; }

OUT="${1:?uso: nightly-bats-run.sh <dir-salida> [suite...]}"
shift
export NIGHTLY_OUT="$OUT"
export NIGHTLY_BATS_BIN="${NIGHTLY_BATS_BIN:-bats}"
export NIGHTLY_TIMEOUT_S="${NIGHTLY_TIMEOUT_S:-900}"
JOBS="${NIGHTLY_JOBS:-4}"

mkdir -p "$OUT" || die "no se puede crear $OUT"
: > "$OUT/rc.txt" || die "no se puede escribir $OUT/rc.txt"
# La lista se calcula antes de escribirla: un fallo de escritura sale 3 (no 2, «sin suites»)
# y una all.txt vieja de otra ejecución no sobrevive a una escritura fallida.
if (($#)); then
  suites=$(printf '%s\n' "$@" | grep -v '^$')
else
  # ls sale 2 si falta uno de los dos patrones: no es error, cuenta lo que haya.
  suites=$(ls tests/*.bats tests/bats/*.bats 2>/dev/null)
fi
if [[ -n "$suites" ]]; then
  printf '%s\n' "$suites" > "$OUT/all.txt" || die "no se puede escribir $OUT/all.txt"
else
  : > "$OUT/all.txt" || die "no se puede escribir $OUT/all.txt"
fi
if [[ ! -s "$OUT/all.txt" ]]; then
  echo "nightly-bats-run: no hay suites que ejecutar" >&2
  exit 2
fi

# Rutas por línea (-d '\n') y pasadas como argumento ("$1"), nunca pegadas al código del shell.
# El marcador solo vale en las 3 primeras líneas (tras el shebang): un texto igual en el cuerpo
# de una suite no la reclasifica.
: > "$OUT/serial.txt" || die "no se puede escribir $OUT/serial.txt"
while IFS= read -r suite_path; do
  if head -n 3 -- "$suite_path" 2>/dev/null | grep -qE '^# nightly: serial'; then
    printf '%s\n' "$suite_path" >> "$OUT/serial.txt" || die "no se puede escribir $OUT/serial.txt"
  fi
done < "$OUT/all.txt"
# grep sale 1 si todas son serie (lista vacía): no es error; 2 sí.
grep -vxFf "$OUT/serial.txt" "$OUT/all.txt" > "$OUT/parallel.txt"
(( $? <= 1 )) || die "no se puede escribir $OUT/parallel.txt"

# Registro privado: los códigos se escriben en un fichero de mktemp fuera de $OUT (ruta
# predecible) y cuya ruta la suite no recibe. Al final se mueve a $OUT/rc.txt.
NIGHTLY_RC=$(mktemp) || die "no se puede crear el registro privado"
export NIGHTLY_RC
RC="$NIGHTLY_RC"

run_one() {
  local out
  out="$NIGHTLY_OUT/$(printf '%s' "$1" | tr '/ ' '__').tap"
  # La suite no hereda la ruta del registro: quien se mide no escribe su propio resultado.
  env -u NIGHTLY_OUT -u NIGHTLY_RC timeout "$NIGHTLY_TIMEOUT_S" "$NIGHTLY_BATS_BIN" "$1" > "$out" 2>&1
  echo "$? $1" >> "$NIGHTLY_RC"
}
export -f run_one
xargs -d '\n' -r -n1 -P "$JOBS" bash -c 'run_one "$1"' _ < "$OUT/parallel.txt"
xargs -d '\n' -r -n1 -P 1 bash -c 'run_one "$1"' _ < "$OUT/serial.txt"

# Suites sin línea en el registro: fallo explícito.
cut -d' ' -f2- "$RC" | sort > "$OUT/ran.txt" || die "no se puede leer el registro"
sort "$OUT/all.txt" | comm -23 - "$OUT/ran.txt" | sed 's/^/missing /' >> "$RC" \
  || die "no se pueden registrar las suites sin código"
# Comprobación de cierre: el registro tiene exactamente una línea por suite de all.txt, ni una
# más ni una menos. Una línea duplicada o de una suite que no está en la lista no es un resultado.
cut -d' ' -f2- "$RC" | sort > "$OUT/ran.txt" || die "no se puede leer el registro"
expected=$(sort "$OUT/all.txt") || die "no se puede leer $OUT/all.txt"
[[ "$(cat "$OUT/ran.txt")" == "$expected" ]] \
  || die "el registro no tiene exactamente una línea por suite (duplicadas, ajenas o sin registrar)"
mv -f "$RC" "$OUT/rc.txt" || die "no se puede escribir $OUT/rc.txt"
RC="$OUT/rc.txt"

total=$(wc -l < "$OUT/all.txt") || die "no se puede contar $OUT/all.txt"
awk '$1 != "0"' "$RC" | sort -k2 > "$OUT/failed.txt" || die "no se puede calcular $OUT/failed.txt"
failed=$(wc -l < "$OUT/failed.txt") || die "no se puede contar $OUT/failed.txt"
[[ "$total" =~ ^[0-9]+$ && "$failed" =~ ^[0-9]+$ ]] || die "contadores no numéricos"
# Las filas se calculan antes de escribir: dentro del bloque solo se comprobaría el último echo.
rows=$(awk '{e=$1; $1=""; sub(/^ /, ""); print "| " e " | `" $0 "` |"}' "$OUT/failed.txt") \
  || die "no se puede construir la tabla de $OUT/summary.md"
(( failed == 0 )) || [[ -n "$rows" ]] || die "tabla vacía con $failed suites fallidas"
{
  echo "## Nightly full BATS: $((total - failed))/$total suites pass"
  echo
  echo '| exit | suite |'
  echo '|---|---|'
  [[ -z "$rows" ]] || printf '%s\n' "$rows"
  echo
  echo "exit 124 = timeout ($NIGHTLY_TIMEOUT_S s); missing = la suite no registró su código de salida."
} > "$OUT/summary.md" || die "no se puede escribir $OUT/summary.md"

echo "total=$total"
echo "failed=$failed"
