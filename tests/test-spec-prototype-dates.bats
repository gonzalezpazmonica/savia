#!/usr/bin/env bats
# Coherencia de calendario en los prototipos S0 (docs/specs/assets/*.html).
# Un prototipo es el texto literal que la operadora confirma; si dice
# «viernes 14 de noviembre de 2026» y el 14 es sábado, la caducidad que firma
# no es la que cree firmar (hallazgo P1 de la revisión de la PR #1502).
# Sin año explícito en la frase, se toma el primer año 20XX del mismo fichero.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  CHECK="$BATS_TEST_TMPDIR/check_dates.py"
  cat > "$CHECK" <<'PY'
import datetime, re, sys
DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
         "septiembre", "octubre", "noviembre", "diciembre"]
PAT = re.compile(r"\b(%s)\s+(\d{1,2})\s+de\s+(%s)(?:\s+de\s+(20\d\d))?" %
                 ("|".join(DIAS), "|".join(MESES)), re.IGNORECASE)
errores, vistas = 0, 0
for path in sys.argv[1:]:
    texto = open(path, encoding="utf-8").read()
    anio_fichero = re.search(r"\b(20\d\d)\b", texto)
    for m in PAT.finditer(texto):
        dia, n, mes, anio = m.group(1).lower(), int(m.group(2)), m.group(3).lower(), m.group(4)
        anio = anio or (anio_fichero.group(1) if anio_fichero else None)
        if anio is None:
            print(f"{path}: «{m.group(0)}» sin año deducible"); errores += 1; continue
        vistas += 1
        try:
            real = DIAS[datetime.date(int(anio), MESES.index(mes) + 1, n).weekday()]
        except ValueError:
            print(f"{path}: «{m.group(0)}» no es una fecha válida"); errores += 1; continue
        if real != dia:
            print(f"{path}: «{m.group(0)}» ({anio}) cae en {real}"); errores += 1
print(f"fechas={vistas} errores={errores}")
sys.exit(1 if errores else 0)
PY
}

@test "prototipos reales: toda fecha con día de la semana cuadra con el calendario" {
  run python3 "$CHECK" docs/specs/assets/*.html
  [ "$status" -eq 0 ]
  [[ "$output" == *"errores=0"* ]]
  # El test tiene que estar mirando algo: SE-496 contiene fechas con día.
  [[ "$output" != *"fechas=0 "* ]]
}

@test "negativo: viernes 14 de noviembre de 2026 (es sábado) se detecta" {
  printf '<p>Hasta el viernes 14 de noviembre de 2026, 23:59.</p>\n' > "$BATS_TEST_TMPDIR/mal.html"
  run python3 "$CHECK" "$BATS_TEST_TMPDIR/mal.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cae en sábado"* ]]
}

@test "negativo: frase sin año usa el año del fichero y detecta el error" {
  printf '<p>Válido en 2026.</p><p>hasta el viernes 14 de noviembre</p>\n' > "$BATS_TEST_TMPDIR/mal2.html"
  run python3 "$CHECK" "$BATS_TEST_TMPDIR/mal2.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cae en sábado"* ]]
}

@test "negativo: fecha imposible (31 de noviembre) falla" {
  printf '<p>lunes 31 de noviembre de 2026</p>\n' > "$BATS_TEST_TMPDIR/mal3.html"
  run python3 "$CHECK" "$BATS_TEST_TMPDIR/mal3.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es una fecha válida"* ]]
}

@test "fail-closed: fecha sin año y sin año en el fichero falla" {
  printf '<p>el viernes 13 de noviembre</p>\n' > "$BATS_TEST_TMPDIR/sinanio.html"
  run python3 "$CHECK" "$BATS_TEST_TMPDIR/sinanio.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin año deducible"* ]]
}

@test "positivo: viernes 13 de noviembre de 2026 pasa" {
  printf '<p>Hasta el viernes 13 de noviembre de 2026.</p>\n' > "$BATS_TEST_TMPDIR/bien.html"
  run python3 "$CHECK" "$BATS_TEST_TMPDIR/bien.html"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fechas=1 errores=0"* ]]
}
