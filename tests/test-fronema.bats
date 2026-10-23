#!/usr/bin/env bats
# Ref: SE-344 — fronema.py CLI (AC-11: ≥12 tests cubriendo AC-1..AC-9 + determinismo)

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FRO="$ROOT_DIR/scripts/fronema.py"
  TMPV="$(mktemp -d)"
  export TMPV
}

teardown() {
  rm -rf "$TMPV" 2>/dev/null || true
}

_reg() {
  python3 "$FRO" register --tension "$1" --decision "$2" --razon "$3" --limites "$4" \
    --senal "s1" --pregunta "p1" --dominio SFT --fuente "test" --vault "$TMPV"
}

@test "SE-344 AC-1: register crea nota draft con verificacion pending" {
  _reg "rigor ↔ velocidad" "dec" "raz" "lim" >/dev/null
  [ -f "$TMPV/pc-0001.md" ]
  grep -q "madurez: draft" "$TMPV/pc-0001.md"
  grep -q "verificacion: pending" "$TMPV/pc-0001.md"
  grep -q "phronesis-case" "$TMPV/pc-0001.md"
}

@test "SE-344 AC-2: register rechaza sin tension / sin senal / sin decision / sin limites" {
  run python3 "$FRO" register --decision d --razon r --limites l --senal s --pregunta p --dominio SFT --fuente f --vault "$TMPV"
  [ "$status" -eq 2 ]
  run python3 "$FRO" register --tension t --decision d --razon r --limites l --pregunta p --dominio SFT --fuente f --vault "$TMPV"
  [ "$status" -eq 2 ]
  run python3 "$FRO" register --tension t --razon r --limites l --senal s --pregunta p --dominio SFT --fuente f --vault "$TMPV"
  [ "$status" -eq 2 ]
  run python3 "$FRO" register --tension t --decision d --razon r --senal s --pregunta p --dominio SFT --fuente f --vault "$TMPV"
  [ "$status" -eq 2 ]
}

@test "SE-344 AC-2: register rechaza dominio no-L23 y nivel N3/N4/N4b" {
  run python3 "$FRO" register --tension t --decision d --razon r --limites l --senal s --pregunta p --dominio XXX --fuente f --vault "$TMPV"
  [ "$status" -eq 2 ]
  for n in N3 N4 N4b; do
    run python3 "$FRO" register --tension t --decision d --razon r --limites l --senal s --pregunta p --dominio SFT --fuente f --nivel "$n" --vault "$TMPV"
    [ "$status" -eq 2 ]
  done
}

@test "SE-344 AC-3: register con verificacion+resultado crea verified (seed)" {
  python3 "$FRO" register --tension t --decision d --razon r --limites l --senal s --pregunta p --dominio CYB --fuente f --verificacion T+90 --resultado "ok" --vault "$TMPV" >/dev/null
  grep -q "madurez: verified" "$TMPV/pc-0001.md"
}

@test "SE-344 AC-4: verify promueve draft->verified; caso inexistente -> exit 3" {
  _reg "t" "d" "r" "l" >/dev/null
  python3 "$FRO" verify --id pc-0001 --resultado "ok" --vault "$TMPV" >/dev/null
  grep -q "madurez: verified" "$TMPV/pc-0001.md"
  run python3 "$FRO" verify --id pc-9999 --resultado x --vault "$TMPV"
  [ "$status" -eq 3 ]
}

@test "SE-344 AC-5: overrule marca (no borra) y query lo muestra" {
  _reg "t" "d" "r" "l" >/dev/null
  python3 "$FRO" overrule --id pc-0001 --resultado "desmentido" --vault "$TMPV" >/dev/null
  [ -f "$TMPV/pc-0001.md" ]
  grep -q "madurez: overruled" "$TMPV/pc-0001.md"
  python3 "$FRO" query --madurez overruled --vault "$TMPV" | grep -q "pc-0001"
}

@test "SE-344 AC-6: query filtra por tension (case-insensitive) y ordena verified primero" {
  python3 "$FRO" register --tension "Seguridad ↔ Operatividad" --decision a --razon r --limites l --senal s --pregunta p --dominio CYB --fuente f --verificacion T+90 --resultado ok --vault "$TMPV" >/dev/null
  _reg "rigor ↔ velocidad" "b" "r" "l" >/dev/null
  out=$(python3 "$FRO" query --tension "SEGURIDAD" --vault "$TMPV")
  echo "$out" | grep -q "pc-0001"
  echo "$out" | grep -q "verified"
  echo "$out" | grep -q "Seguridad"
}

@test "SE-344 AC-7: query sin resultados -> exit 1" {
  run python3 "$FRO" query --tension "nada-que-no-existe" --vault "$TMPV"
  [ "$status" -eq 1 ]
}

@test "SE-344 AC-8: train enmascara (sin decision/razon) y registra brier en JSONL local" {
  python3 "$FRO" register --tension "t" --decision "decision-secreta" --razon "razon-secreta" --limites "l" \
    --senal "s" --pregunta "p" --dominio SFT --fuente "f" --verificacion T+90 --resultado ok --vault "$TMPV" >/dev/null
  TMP_TRAIN="$TMPV/train"
  export FRONESIS_TRAIN_DIR="$TMP_TRAIN"
  printf "decision-secreta\n80\n" | python3 "$FRO" train --dominio SFT --sesion s1 --vault "$TMPV" > "$TMPV/train.out"
  unset FRONESIS_TRAIN_DIR
  ! grep -q "Decisión real" "$TMPV/train.out"
  ! grep -q "decision-secreta" "$TMPV/train.out"
  [ -f "$TMP_TRAIN/s1.jsonl" ]
  python3 -c "import json; r=json.loads(open('$TMP_TRAIN/s1.jsonl').read()); assert 'brier' in r and 'confianza' in r"
}

@test "SE-344 AC-9: graduate marca graduado sin borrar y sugiere destino" {
  _reg "t" "d" "r" "l" >/dev/null
  run python3 "$FRO" graduate --id pc-0001 --vault "$TMPV"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "destino"
  [ -f "$TMPV/pc-0001.md" ]
  grep -q "graduado a regla" "$TMPV/pc-0001.md"
}

@test "SE-344 AC-10: CRIT-001 — sin librerias de red" {
  ! grep -nE "import (urllib|requests|socket)|http://|https://" "$FRO"
}

@test "SE-344 determinismo: list es estable y register 2x genera ids secuenciales" {
  _reg "t1" "d" "r" "l" >/dev/null
  _reg "t2" "d" "r" "l" >/dev/null
  run python3 "$FRO" list --vault "$TMPV"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "pc-0001"
  echo "$output" | grep -q "pc-0002"
}

@test "SE-344 calibrate: sugiere graduacion tras >=3 sesiones >=90%" {
  _reg "t" "d" "r" "l" >/dev/null
  python3 "$FRO" calibrate --id pc-0001 --aciertos 9 --total 10 --vault "$TMPV" >/dev/null
  python3 "$FRO" calibrate --id pc-0001 --aciertos 9 --total 10 --vault "$TMPV" >/dev/null
  run python3 "$FRO" calibrate --id pc-0001 --aciertos 9 --total 10 --vault "$TMPV"
  echo "$output" | grep -qi "sugerencia"
}

# ── Comportamiento: register, validación y round-trip del frontmatter ─────────

_regx() { python3 "$FRO" register --tension "${T:-t}" --decision "${D:-d}" --razon r --limites l \
    --senal s --pregunta p --dominio "${DOM:-SFT}" --fuente f --vault "$TMPV" "$@"; }

_field() { grep -m1 "^$2:" "$TMPV/$1.md" | sed "s/^$2: *//"; }

@test "SE-344: register imprime ok <id> madurez=<estado> y normaliza dominio y nivel a mayúsculas" {
  run _regx --nivel n1 --dominio sft
  [ "$status" -eq 0 ]
  [ "$output" = "ok pc-0001 madurez=draft" ]
  grep -q "^  - SFT$" "$TMPV/pc-0001.md"
  grep -q "^nivel: N1$" "$TMPV/pc-0001.md"
}

@test "SE-344: varios --dominio se guardan todos y uno inválido rechaza el registro entero" {
  python3 "$FRO" register --tension t --decision d --razon r --limites l --senal s --pregunta p \
    --dominio SFT --dominio cyb --fuente f --vault "$TMPV" >/dev/null
  [ "$(grep -c '^  - \(SFT\|CYB\)$' "$TMPV/pc-0001.md")" -eq 2 ]
  run python3 "$FRO" register --tension t --decision d --razon r --limites l --senal s --pregunta p \
    --dominio SFT --dominio ZZZ --fuente f --vault "$TMPV"
  [ "$status" -eq 2 ]
  [[ "$output" == *"dominio no-L23: ZZZ"* ]]
  [ ! -e "$TMPV/pc-0002.md" ]
}

@test "SE-344: campo obligatorio en blanco se nombra en el error y no escribe nada" {
  run python3 "$FRO" register --tension "   " --decision d --razon r --limites l --senal s --pregunta p --dominio SFT --fuente f --vault "$TMPV"
  [ "$status" -eq 2 ]
  [[ "$output" == *"campo obligatorio vacío: tension"* ]]
  [ -z "$(ls "$TMPV")" ]
}

@test "SE-344: nivel N3 se rechaza con el mensaje de solo N1/N2" {
  run _regx --nivel N3
  [ "$status" -eq 2 ]
  [[ "$output" == *"nivel inválido: N3 (solo N1/N2)"* ]]
}

@test "SE-344: madurez verified exige verificacion Y resultado; con uno solo queda draft" {
  run _regx --resultado ok
  [ "$output" = "ok pc-0001 madurez=draft" ]
  run _regx --verificacion T+30
  [ "$output" = "ok pc-0002 madurez=draft" ]
  run _regx --verificacion T+30 --resultado ok
  [ "$output" = "ok pc-0003 madurez=verified" ]
}

@test "SE-344: la verificación solo admite las ventanas definidas" {
  run _regx --verificacion T+7
  [ "$status" -eq 2 ]
}

@test "SE-344: los ids son secuenciales tras el mayor existente, aunque falten huecos; --id manda" {
  _regx --id pc-0005 >/dev/null
  run _regx
  [ "$output" = "ok pc-0006 madurez=draft" ]
  run _regx --id custom-1
  [ "$output" = "ok custom-1 madurez=draft" ]
  [ -f "$TMPV/custom-1.md" ]
}

@test "SE-344: valores con dos puntos y comillas sobreviven al round-trip de escritura y lectura" {
  D='usar "x": sí' _regx >/dev/null
  run python3 "$FRO" query --vault "$TMPV"
  [[ "$output" == *$'\t''usar "x": sí' ]]
}

@test "SE-344: la decisión larga se trunca a 60 caracteres en query" {
  D="$(printf 'z%.0s' $(seq 1 80))" _regx >/dev/null
  run python3 "$FRO" query --vault "$TMPV"
  [[ "$output" == *"$(printf 'z%.0s' $(seq 1 60))" ]]
  [[ "$output" != *"$(printf 'z%.0s' $(seq 1 61))"* ]]
}

# ── Comportamiento: verify / overrule / graduate / calibrate ──────────────────

@test "SE-344: verify guarda ventana, resultado, arrepentimiento y corrección, y usa T+90 por defecto" {
  _regx >/dev/null
  run python3 "$FRO" verify --id pc-0001 --resultado "salió bien" --arrepentimiento "poco" --correccion "ajustar" --vault "$TMPV"
  [ "$output" = "ok pc-0001 -> verified" ]
  f="$TMPV/pc-0001.md"
  grep -q "verificacion: T+90" "$f"
  grep -q "resultado: salió bien" "$f"
  grep -q "arrepentimiento: poco" "$f"
  grep -q "correccion: ajustar" "$f"
  grep -q "^madurez: verified$" "$f"
  grep -q "^verified_at: " "$f"
}

@test "SE-344: verify con --ventana T+30 la guarda y una ventana inválida es error de argumentos" {
  _regx >/dev/null
  python3 "$FRO" verify --id pc-0001 --resultado ok --ventana T+30 --vault "$TMPV" >/dev/null
  grep -q "verificacion: T+30" "$TMPV/pc-0001.md"
  run python3 "$FRO" verify --id pc-0001 --resultado ok --ventana T+1 --vault "$TMPV"
  [ "$status" -eq 2 ]
}

@test "SE-344: un caso overruled no admite verify, calibrate ni graduate (exit 3), pero sí overrule" {
  _regx >/dev/null
  python3 "$FRO" overrule --id pc-0001 --resultado desmentido --correccion "rehacer" --vault "$TMPV" >/dev/null
  grep -q "correccion: rehacer" "$TMPV/pc-0001.md"
  for c in "verify --resultado x" "calibrate --aciertos 1 --total 1" "graduate"; do
    run python3 "$FRO" $c --id pc-0001 --vault "$TMPV"
    [ "$status" -eq 3 ]
    [[ "$output" == *"caso pc-0001 ya overruled"* ]]
  done
  run python3 "$FRO" overrule --id pc-0001 --resultado otra --vault "$TMPV"
  [ "$status" -eq 0 ]
  [[ "$output" == *"overruled (no borrado; es historial)"* ]]
}

@test "SE-344: overrule y graduate sobre caso inexistente dan exit 3 con el id" {
  run python3 "$FRO" overrule --id pc-0042 --resultado x --vault "$TMPV"
  [ "$status" -eq 3 ]
  [[ "$output" == *"caso pc-0042 no existe"* ]]
  run python3 "$FRO" graduate --id pc-0042 --vault "$TMPV"
  [ "$status" -eq 3 ]
}

@test "SE-344: graduate deja constancia de destino y fecha, y el caso ya no es verified" {
  _regx --verificacion T+30 --resultado ok >/dev/null
  run python3 "$FRO" graduate --id pc-0001 --vault "$TMPV"
  [[ "$output" == *"destino sugerido: CRITERIO.md o regla de dominio"* ]]
  grep -q "^madurez: overruled$" "$TMPV/pc-0001.md"
  grep -q "^overruled_at: " "$TMPV/pc-0001.md"
}

@test "SE-344: calibrate informa del ratio con dos decimales y acumula las sesiones" {
  _regx >/dev/null
  run python3 "$FRO" calibrate --id pc-0001 --aciertos 2 --total 3 --vault "$TMPV"
  [ "$output" = "ok pc-0001 aciertos=2/3 ratio=0.67" ]
  python3 "$FRO" calibrate --id pc-0001 --aciertos 1 --total 3 --vault "$TMPV" >/dev/null
  [ "$(grep -c "^  - .*sesiones" "$TMPV/pc-0001.md")" -eq 2 ]
}

@test "SE-344: calibrate con total 0 da ratio 0.00 sin dividir por cero" {
  _regx >/dev/null
  run python3 "$FRO" calibrate --id pc-0001 --aciertos 0 --total 0 --vault "$TMPV"
  [ "$status" -eq 0 ]
  [ "$output" = "ok pc-0001 aciertos=0/0 ratio=0.00" ]
}

@test "SE-344: la sugerencia de graduar sale en la 3ª sesión con ratio >= 0.90, con el comando exacto, y no antes" {
  _regx >/dev/null
  run python3 "$FRO" calibrate --id pc-0001 --aciertos 9 --total 10 --vault "$TMPV"
  [[ "$output" != *"SUGERENCIA"* ]]
  run python3 "$FRO" calibrate --id pc-0001 --aciertos 9 --total 10 --vault "$TMPV"
  [[ "$output" != *"SUGERENCIA"* ]]
  run python3 "$FRO" calibrate --id pc-0001 --aciertos 9 --total 10 --vault "$TMPV"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUGERENCIA: caso pc-0001 estable >=90% en >=3 sesiones"* ]]
  [[ "$output" == *"fronema.py graduate --id pc-0001"* ]]
  [[ "$output" != *"Traceback"* ]]
  [ "$(grep -c "^  - .*sesiones" "$TMPV/pc-0001.md")" -eq 3 ]
}

@test "SE-344: con ratio 0.89 en la 3ª sesión no hay sugerencia" {
  _regx >/dev/null
  for i in 1 2; do python3 "$FRO" calibrate --id pc-0001 --aciertos 89 --total 100 --vault "$TMPV" >/dev/null; done
  run python3 "$FRO" calibrate --id pc-0001 --aciertos 89 --total 100 --vault "$TMPV"
  [ "$status" -eq 0 ]
  [[ "$output" != *"SUGERENCIA"* ]]
}

# ── Comportamiento: query / list ──────────────────────────────────────────────

@test "SE-344: query imprime cinco columnas separadas por tabulador: id, madurez, tensión, [dominios], decisión" {
  python3 "$FRO" register --tension "ten" --decision "dec" --razon r --limites l --senal s --pregunta p \
    --dominio SFT --dominio CYB --fuente f --vault "$TMPV" >/dev/null
  run python3 "$FRO" query --vault "$TMPV"
  [ "$output" = $'pc-0001\tdraft\tten\t[SFT,CYB]\tdec' ]
}

@test "SE-344: query filtra por dominio sin distinguir mayúsculas y por madurez" {
  DOM=CYB _regx >/dev/null
  DOM=SFT _regx --verificacion T+30 --resultado ok >/dev/null
  run python3 "$FRO" query --dominio cyb --vault "$TMPV"
  [ "$(echo "$output" | wc -l)" -eq 1 ]
  [[ "$output" == pc-0001* ]]
  run python3 "$FRO" query --madurez verified --vault "$TMPV"
  [[ "$output" == pc-0002* ]]
  run python3 "$FRO" query --dominio cyb --madurez verified --vault "$TMPV"
  [ "$status" -eq 1 ]
}

@test "SE-344: orden por madurez verified < calibrated < draft < overruled y por fecha dentro del mismo nivel" {
  _regx >/dev/null
  _regx >/dev/null
  _regx --verificacion T+30 --resultado ok >/dev/null
  _regx >/dev/null
  python3 "$FRO" overrule --id pc-0004 --resultado x --vault "$TMPV" >/dev/null
  run python3 "$FRO" query --vault "$TMPV"
  [ "$(echo "$output" | cut -f1 | tr '\n' ' ')" = "pc-0003 pc-0001 pc-0002 pc-0004 " ]
}

@test "SE-344: query sin precedentes escribe (sin precedentes) en stderr y sale 1; vault inexistente igual" {
  run python3 "$FRO" query --vault "$TMPV"
  [ "$status" -eq 1 ]
  [[ "$output" == *"(sin precedentes)"* ]]
  run python3 "$FRO" query --vault "$TMPV/no-existe"
  [ "$status" -eq 1 ]
}

@test "SE-344: query solo considera notas phronesis-case e ignora otras notas y ficheros no md" {
  _regx >/dev/null
  printf -- '---\nentity: {type: other, id: x-1}\n---\n' > "$TMPV/otra.md"
  printf 'texto\n' > "$TMPV/readme.txt"
  run python3 "$FRO" query --vault "$TMPV"
  [ "$(echo "$output" | wc -l)" -eq 1 ]
  [[ "$output" == pc-0001* ]]
}

@test "SE-344: list es un alias de query con sus filtros" {
  DOM=CYB _regx >/dev/null
  DOM=SFT _regx >/dev/null
  run python3 "$FRO" list --dominio SFT --vault "$TMPV"
  [[ "$output" == pc-0002* ]]
  [ "$(echo "$output" | wc -l)" -eq 1 ]
}

# ── Comportamiento: train ─────────────────────────────────────────────────────

_seed_train() {
  python3 "$FRO" register --tension "ten-visible" --decision "decision-secreta" --razon "razon-secreta" --limites "lim-visible" \
    --senal "senal-visible" --pregunta p --dominio SFT --fuente f --verificacion T+90 --resultado "res-final" --vault "$TMPV" >/dev/null
  export FRONESIS_TRAIN_DIR="$TMPV/train"
}

@test "SE-344 train: la parte enmascarada no contiene decisión ni razón; la revelación sí" {
  _seed_train
  out="$(printf 'lo que sea\n50\n' | python3 "$FRO" train --dominio SFT --vault "$TMPV")"
  masked="$(echo "$out" | sed -n '/=== CASO ENMASCARADO ===/,/=== REVELACIÓN ===/p')"
  [[ "$masked" == *"ten-visible"* ]]
  [[ "$masked" == *"senal-visible"* ]]
  [[ "$masked" == *"lim-visible"* ]]
  [[ "$masked" != *"decision-secreta"* ]]
  [[ "$masked" != *"razon-secreta"* ]]
  reveal="$(echo "$out" | sed -n '/=== REVELACIÓN ===/,$p')"
  [[ "$reveal" == *"Decisión real: decision-secreta"* ]]
  [[ "$reveal" == *"Razón: razon-secreta"* ]]
  [[ "$reveal" == *"Consecuencia: res-final"* ]]
}

@test "SE-344 train: acierto con confianza 80 da brier 0.04; fallo con confianza 80 da 0.64" {
  _seed_train
  printf 'creo que decision-secreta\n80\n' | python3 "$FRO" train --dominio SFT --sesion a --vault "$TMPV" >/dev/null
  printf 'otra cosa\n80\n' | python3 "$FRO" train --dominio SFT --sesion b --vault "$TMPV" >/dev/null
  [ "$(jq -r .acierto "$TMPV/train/a.jsonl")" = "1" ]
  [ "$(jq -r .brier "$TMPV/train/a.jsonl")" = "0.04" ]
  [ "$(jq -r .confianza "$TMPV/train/a.jsonl")" = "0.8" ]
  [ "$(jq -r .acierto "$TMPV/train/b.jsonl")" = "0" ]
  [ "$(jq -r .brier "$TMPV/train/b.jsonl")" = "0.64" ]
}

@test "SE-344 train: la comparación de acierto ignora mayúsculas" {
  _seed_train
  printf 'DECISION-SECRETA\n100\n' | python3 "$FRO" train --dominio SFT --vault "$TMPV" >/dev/null
  [ "$(jq -r .acierto "$TMPV/train/s1.jsonl")" = "1" ]
}

@test "SE-344 train: respuesta vacía cuenta como fallo y confianza no numérica vale 0.5" {
  _seed_train
  run bash -c "printf '\nabc\n' | python3 '$FRO' train --dominio SFT --vault '$TMPV'"
  [ "$status" -eq 0 ]
  [ "$(jq -r .acierto "$TMPV/train/s1.jsonl")" = "0" ]
  [ "$(jq -r .confianza "$TMPV/train/s1.jsonl")" = "0.5" ]
  [ "$(jq -r .brier "$TMPV/train/s1.jsonl")" = "0.25" ]
  [[ "$output" == *"brier=0.2500 (confianza=0.50, acierto=0)"* ]]
}

@test "SE-344 train: sin casos verified/calibrated falla con exit 1; los draft no entran" {
  export FRONESIS_TRAIN_DIR="$TMPV/train"
  _regx >/dev/null
  run bash -c "printf 'x\n50\n' | python3 '$FRO' train --dominio SFT --vault '$TMPV'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no hay casos verified/calibrated para entrenar"* ]]
  [ ! -e "$TMPV/train" ]
}

@test "SE-344 train: la misma sesión y dominio eligen siempre el mismo caso; el registro se añade al fichero" {
  for i in 1 2 3 4 5 6; do
    _regx --verificacion T+30 --resultado ok >/dev/null
  done
  export FRONESIS_TRAIN_DIR="$TMPV/train"
  for i in 1 2 3; do
    printf 'x\n50\n' | python3 "$FRO" train --dominio SFT --sesion fija --vault "$TMPV" >/dev/null
  done
  [ "$(jq -r .id "$TMPV/train/fija.jsonl" | sort -u | wc -l)" -eq 1 ]
  [ "$(wc -l < "$TMPV/train/fija.jsonl")" -eq 3 ]
}

@test "SE-344: una decisión que parece un mapa YAML ({a}) se escribe entrecomillada y vuelve como texto" {
  D='{a}' _regx >/dev/null
  grep -q '^decision: "{a}"$' "$TMPV/pc-0001.md"
  run python3 "$FRO" query --vault "$TMPV"
  [[ "$output" == *$'\t''{a}' ]]
}
