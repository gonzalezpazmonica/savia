#!/usr/bin/env bats
# SE-530 S1 — hecho-verificado.py: declarado / verificado / refutado (solo lectura).
# Cada caso positivo tiene su par negativo; los límites de H9 se prueban en 199/200.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
HV="$REPO_ROOT/scripts/hecho-verificado.py"
S1=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
S2=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

setup() {
  T="$(mktemp -d)"
  EV="$T/ev.jsonl"; : > "$EV"
}
teardown() { rm -rf "$T"; }

done_ok() {  # done_ok <job> <pr|-> [estado]
  mkdir -p "$T/runs/$1"
  local url=""; [ "$2" != "-" ] && url=" — https://example.test/r/pull/$2 (Draft)"
  printf 'ESTADO: %s%s\nresto\n' "${3:-OK}" "$url" > "$T/runs/$1/done"
}
head_rec() { printf '{"head":"%s","pr":%s}\n' "$2" "$1" >> "$EV"; }
chk() {  # chk <pr> <sha> <clase> <verificador> <ejecutor> <resultado> [extra-json-sin-llaves]
  local pp=",\"propuesta_por\":\"$4\""  # el recolector fija propuesta_por = verificador salvo que el caso lo cambie
  [[ "$7" == *propuesta_por* ]] && pp=""
  printf '{"pr":%s,"sha":"%s","clase":"%s","verificador":"%s","ejecutor":"%s","resultado":"%s"%s%s}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$pp" "${7:+,$7}" >> "$EV"
}
cls() { python3 "$HV" classify "$T/runs/$1/done" --evidence "$EV" "${@:2}"; }

@test "AC-1.3 OK sin PR ni nada más: declarado, salida 0" {
  done_ok j1 -
  run cls j1
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-1.4 OK con solo un fichero propio del ejecutor (autodeclaracion): declarado" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 autodeclaracion trabajador trabajador superada
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-1.5 ci_propio en verde no sube a verificado; ci con pruebas_base sí" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 ci ci-sistema trabajador superada '"pruebas_base":0,"pruebas_propias":3'
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  [[ "$output" == *"clase=ci_propio"* ]]
  chk 10 $S1 ci ci-sistema trabajador superada '"pruebas_base":12,"pruebas_propias":3'
  run cls j1
  [[ "${lines[0]}" == verificado:* ]]
  [[ "$output" == *"clase=ci_base"* ]]
}

@test "revision de revisora distinta sobre el SHA vigente: verificado" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada
  run cls j1
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "verificado: revision de revisora-a sobre aaaaaaaa" ]]
}

@test "negativo: verificador igual al ejecutor no cuenta" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision trabajador trabajador superada
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
}

@test "negativo: la orquestadora no verifica una revision; una clase mecanica sí" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision savia-orchestrator trabajador superada
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  chk 10 $S1 postcondicion savia-orchestrator trabajador superada
  run cls j1
  [[ "${lines[0]}" == verificado:* ]]
}

@test "negativo: --orchestrator cambia la lista" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision otra-orq trabajador superada
  run cls j1
  [[ "${lines[0]}" == verificado:* ]]
  run cls j1 --orchestrator "otra-orq"
  [[ "${lines[0]}" == declarado:* ]]
}

@test "D4: un nuevo SHA vigente invalida la verificacion anterior" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada
  head_rec 10 $S2
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  [[ "${lines[0]}" == *"1 de un SHA anterior"* ]]
}

@test "fail-closed: sin SHA vigente ninguna comprobacion cuenta" {
  done_ok j1 10
  chk 10 $S1 revision revisora-a trabajador superada
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
}

@test "refutado: un CI con pruebas de la base falla aunque una revision apruebe; exit 1" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada
  chk 10 $S1 ci ci-sistema trabajador fallida '"pruebas_base":5'
  run cls j1
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == refutado:* ]]
}

@test "negativo: fallo del propio ejecutor no refuta; se informa" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 ci trabajador trabajador fallida '"pruebas_base":5'
  run cls j1
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:*"comprobación propia del ejecutor falla"* ]]
}

@test "D3: comprobacion propuesta por el ejecutor sin aprobar no cuenta; aprobada por la persona sí" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 postcondicion revisora-a trabajador superada '"propuesta_por":"trabajador","contenido_hash":"h1"'
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  chk 10 $S1 postcondicion revisora-b trabajador superada '"propuesta_por":"trabajador","contenido_hash":"h1","aprobada_por":"savia-orchestrator","aprobada_hash":"h1"'
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  chk 10 $S1 postcondicion revisora-c trabajador superada '"propuesta_por":"trabajador","contenido_hash":"h1","aprobada_por":"persona","aprobada_hash":"h2"'
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  chk 10 $S1 postcondicion revisora-d trabajador superada '"propuesta_por":"trabajador","contenido_hash":"h1","aprobada_por":"persona","aprobada_hash":"h1"'
  run cls j1
  [[ "${lines[0]}" == verificado:* ]]
}

@test "negativo: campo de estado escrito por el ejecutor se ignora y se anota" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 autodeclaracion trabajador trabajador superada '"verificado":true,"estado":"verificado"'
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  [[ "$output" == *"anomalia=campo 'estado' escrito por el ejecutor, ignorado"* ]]
}

@test "negativo: registro sin ejecutor no cuenta" {
  done_ok j1 10; head_rec 10 $S1
  printf '{"pr":10,"sha":"%s","clase":"revision","verificador":"revisora-a","resultado":"superada"}\n' $S1 >> "$EV"
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
}

@test "AC-1.7 fail-closed: marca vacia, sin ESTADO e inexistente dan declarado y exit 2" {
  mkdir -p "$T/runs/v" "$T/runs/s"
  : > "$T/runs/v/done"; echo "todo bien" > "$T/runs/s/done"
  run cls v; [ "$status" -eq 2 ]; [[ "${lines[0]}" == declarado:* ]]
  run cls s; [ "$status" -eq 2 ]; [[ "${lines[0]}" == declarado:* ]]
  run python3 "$HV" classify "$T/runs/nada/done"; [ "$status" -eq 2 ]; [[ "${lines[0]}" == declarado:* ]]
}

@test "negativo: ESTADO PARCIAL/FALLO nunca es verificado aunque haya revision" {
  done_ok j1 10 PARCIAL; head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada
  run cls j1
  [[ "${lines[0]}" == declarado:*PARCIAL* ]]
}

@test "negativo: evidencia ilegible o linea corrupta no da verificado" {
  done_ok j1 10
  echo 'no es json' > "$EV"
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  [[ "$output" == *"anomalia=línea 1 inválida"* ]]
  run python3 "$HV" classify "$T/runs/j1/done" --evidence "$T/no-existe.jsonl"
  [[ "${lines[0]}" == declarado:* ]]
}

@test "adaptador --reviews: registro de merge-sprint (APPROVE verifica, HOLD refuta, revisor=autor no cuenta)" {
  done_ok j1 10; head_rec 10 $S1
  R="$T/reviews.jsonl"
  printf '{"pr":10,"sha":"%s","verdict":"APPROVE","reviewer":"rev","author":"aut","role":"correctness"}\n' $S1 > "$R"
  run python3 "$HV" classify "$T/runs/j1/done" --evidence "$EV" --reviews "$R"
  [[ "${lines[0]}" == verificado:* ]]
  printf '{"pr":10,"sha":"%s","verdict":"APPROVE","reviewer":"aut","author":"aut","role":"correctness"}\n' $S1 > "$R"
  run python3 "$HV" classify "$T/runs/j1/done" --evidence "$EV" --reviews "$R"
  [[ "${lines[0]}" == declarado:* ]]
  printf '{"pr":10,"sha":"%s","verdict":"HOLD","reviewer":"rev","author":"aut","role":"security"}\n' $S1 >> "$R"
  run python3 "$HV" classify "$T/runs/j1/done" --evidence "$EV" --reviews "$R"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == refutado:* ]]
}

@test "solo lectura: classify no modifica la marca ni la evidencia" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada
  before="$(sha256sum "$T/runs/j1/done" "$EV")"
  cls j1 >/dev/null
  [ "$before" = "$(sha256sum "$T/runs/j1/done" "$EV")" ]
}

# ---- measure ----

fill() {  # fill <n_ok> <n_con_revision>: n_ok marcas OK; las primeras n_con_revision con revision independiente
  local i pr
  for ((i = 1; i <= $1; i++)); do
    pr=$((1000 + i)); done_ok "j$i" "$pr"; head_rec "$pr" $S1
    [ "$i" -le "$2" ] && chk "$pr" $S1 revision revisora-a trabajador superada
  done
  true
}
msr() { python3 "$HV" measure --done-dir "$T/runs" --evidence "$EV" --until 2099-01-01 --window 100000 "$@"; }

@test "AC-1.1 la medicion es reproducible byte a byte" {
  fill 30 10
  msr > "$T/a.txt"; msr > "$T/b.txt"
  cmp "$T/a.txt" "$T/b.txt"
  grep -q '^n_ok: 30$' "$T/a.txt"
}

@test "AC-1.2 da la cifra por clase de evidencia" {
  fill 5 3
  chk 1004 $S1 ci ci-sistema trabajador superada '"pruebas_base":4'
  chk 1005 $S1 ci ci-sistema trabajador superada '"pruebas_base":0'
  run msr
  [[ "$output" == *"clase.revision: 3"* ]]
  [[ "$output" == *"clase.ci_base: 1"* ]]
  [[ "$output" == *"clase.ci_propio: 1"* ]]
  [[ "$output" == *"clase.persona: 0"* ]]
  [[ "$output" == *"estado.verificado: 4"* ]]
  [[ "$output" == *"estado.declarado: 1"* ]]
}

@test "AC-1.6 n=199: no concluyente aunque todo sea declarado" {
  fill 199 0
  run msr
  [[ "$output" == *"n_ok: 199"* ]]
  [[ "$output" == *"H9: no concluyente"* ]]
}

@test "AC-1.6 n=200 con 19 sin evidencia (9,5 %): H9 refutada" {
  fill 200 181
  run msr
  [[ "$output" == *"sin_evidencia_independiente: 19"* ]]
  [[ "$output" == *"porcentaje: 9.5"* ]]
  [[ "$output" == *"H9: refutada"* ]]
}

@test "AC-1.6 n=200 con 20 sin evidencia (10,0 %, umbral): H9 confirmada" {
  fill 200 180
  run msr
  [[ "$output" == *"sin_evidencia_independiente: 20"* ]]
  [[ "$output" == *"porcentaje: 10.0"* ]]
  [[ "$output" == *"H9: confirmada"* ]]
}

@test "measure: ventana excluye marcas fuera de fecha; PARCIAL e ilegibles no cuentan como OK" {
  fill 3 0
  done_ok viejo 2000; touch -d '2020-01-01' "$T/runs/viejo/done"
  done_ok parcial 2001 PARCIAL
  mkdir -p "$T/runs/roto"; : > "$T/runs/roto/done"
  run python3 "$HV" measure --done-dir "$T/runs" --evidence "$EV" --until "$(date -u +%F)" --window 14
  [[ "$output" == *"n_ok: 3"* ]]
  [[ "$output" == *"no_ok: 1"* ]]
  [[ "$output" == *"ilegibles: 1"* ]]
}

@test "measure fail-closed: directorio sin marcas sale 2 sin cifra" {
  mkdir -p "$T/vacio"
  run python3 "$HV" measure --done-dir "$T/vacio"
  [ "$status" -eq 2 ]
  [[ "$output" != *"H9:"* ]]
}

@test "measure fail-closed: --until invalido sale 2" {
  fill 1 0
  run python3 "$HV" measure --done-dir "$T/runs" --until manana
  [ "$status" -eq 2 ]
}

# ---- AC-1.8 y regla ----

@test "AC-1.8 el informe lleva el hash del prerregistro y check-prereg lo da por bueno" {
  P="$REPO_ROOT/docs/evidence/SE-530-S1-prerregistro.md"; M="$REPO_ROOT/docs/evidence/SE-530-S1-medicion.md"
  [ -f "$P" ]
  [ -f "$M" ]
  run python3 "$HV" check-prereg "$P" "$M"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == coincide:* ]]
}

@test "AC-1.8 negativo: editar una definicion del prerregistro antes de «Desviaciones» rompe check-prereg" {
  P="$REPO_ROOT/docs/evidence/SE-530-S1-prerregistro.md"; M="$REPO_ROOT/docs/evidence/SE-530-S1-medicion.md"
  sed 's/^Una comprobación es independiente/Una comprobación (umbral cambiado a posteriori) es independiente/' "$P" > "$T/pre.md"
  run cmp -s "$P" "$T/pre.md"
  [ "$status" -ne 0 ]  # la edición se aplicó de verdad
  run python3 "$HV" check-prereg "$T/pre.md" "$M"
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "NO coincide"* ]]
}

@test "AC-1.8 negativo: alterar el hash declarado en el informe rompe check-prereg" {
  P="$REPO_ROOT/docs/evidence/SE-530-S1-prerregistro.md"; M="$REPO_ROOT/docs/evidence/SE-530-S1-medicion.md"
  sed -E "s/^(prerregistro-sha256: )[0-9a-f]{64}\$/\1$(printf '0%.0s' {1..64})/" "$M" > "$T/med.md"
  run grep -c '^prerregistro-sha256: 0\{64\}$' "$T/med.md"
  [ "$output" = "1" ]  # el hash declarado se alteró de verdad
  run python3 "$HV" check-prereg "$P" "$T/med.md"
  [ "$status" -eq 1 ]
}

@test "AC-1.8 la seccion Desviaciones puede crecer sin romper el hash (se escribe tras medir)" {
  P="$REPO_ROOT/docs/evidence/SE-530-S1-prerregistro.md"; M="$REPO_ROOT/docs/evidence/SE-530-S1-medicion.md"
  { cat "$P"; echo "4. Desviacion nueva escrita despues de medir."; } > "$T/pre.md"
  run python3 "$HV" check-prereg "$T/pre.md" "$M"
  [ "$status" -eq 0 ]
}

@test "AC-1.8 informe sin hash o prerregistro inexistente: salida 2, nunca coincide" {
  M="$REPO_ROOT/docs/evidence/SE-530-S1-medicion.md"
  echo "sin hash" > "$T/med.md"
  run python3 "$HV" check-prereg "$REPO_ROOT/docs/evidence/SE-530-S1-prerregistro.md" "$T/med.md"
  [ "$status" -eq 2 ]
  run python3 "$HV" check-prereg "$T/no-existe.md" "$M"
  [ "$status" -eq 2 ]
}

@test "regla D5 existe y prohibe «terminado» para declarado" {
  R="$REPO_ROOT/docs/rules/domain/hecho-verificado.md"
  grep -q 'declarado, sin verificar' "$R"
  grep -qiE 'no usa.*terminado' "$R"
  [ "$(wc -l < "$R")" -le 150 ]
}

@test "--repo: una PR de otro repositorio con el mismo numero no hereda evidencia" {
  mkdir -p "$T/runs/x"
  printf 'ESTADO: OK — https://github.com/org/otro/pull/10\n' > "$T/runs/x/done"
  head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada
  run cls x --repo otro
  [[ "${lines[0]}" == verificado:* ]]
  run cls x --repo propio
  [[ "${lines[0]}" == declarado:*"otro repositorio (otro)"* ]]
  printf 'ESTADO: OK — https://github.com/org/propio/pull/10\n' > "$T/runs/x/done"
  run cls x --repo propio
  [[ "${lines[0]}" == verificado:* ]]
}

# ---- fallos de revision independiente (PR 1554) ----

@test "tipos inesperados en aprobada_por (lista/dict) no rompen: declarado, nunca salida 1" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 persona alguien trabajador superada '"propuesta_por":"trabajador","aprobada_por":["x"],"contenido_hash":"h","aprobada_hash":"h"'
  run cls j1
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
  chk 10 $S1 persona alguien trabajador superada '"propuesta_por":"trabajador","aprobada_por":{"a":1},"contenido_hash":["h"],"aprobada_hash":["h"]'
  run cls j1
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
}

@test "un error interno devuelve 2 (ilegible), no 1 (refutado)" {
  done_ok j1 10
  run python3 -c "
import sys, importlib.util
sp = importlib.util.spec_from_file_location('hv', '$HV'); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
m.cmd_classify = lambda a: 1/0
sys.exit(m.main(['classify', '$T/runs/j1/done']))"
  [ "$status" -eq 2 ]
}

@test "D3: propuesta_por distinta del ejecutor y sin aprobacion no cuenta" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 persona alguien trabajador superada '"propuesta_por":"otro-alias"'
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
  chk 10 $S1 persona alguien trabajador superada '"propuesta_por":"otro-alias","aprobada_por":"monica","contenido_hash":"h","aprobada_hash":"h"'
  run cls j1
  [[ "${lines[0]}" == verificado:* ]]
}

@test "verdict desconocido en el registro de revisiones no refuta: se anota y se ignora" {
  done_ok j1 10; head_rec 10 $S1
  printf '{"pr":10,"sha":"%s","reviewer":"revisora-a","author":"trabajador","verdict":"COMMENT"}\n' $S1 > "$T/rev.jsonl"
  run python3 "$HV" classify "$T/runs/j1/done" --evidence "$EV" --reviews "$T/rev.jsonl"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:* ]]
  [[ "$output" == *"anomalia=verdict desconocido"* ]]
  printf '{"pr":10,"sha":"%s","reviewer":"revisora-a","author":"trabajador","verdict":"HOLD"}\n' $S1 > "$T/rev.jsonl"
  run python3 "$HV" classify "$T/runs/j1/done" --evidence "$EV" --reviews "$T/rev.jsonl"
  [ "$status" -eq 1 ]
}

@test "una falla de la orquestadora no refuta pero impide verificar" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada
  chk 10 $S1 revision savia-orquestadora trabajador fallida
  run cls j1
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:*"no independiente"* ]]
}

@test "measure cuenta clase.revision solo si es independiente" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision savia-orquestadora trabajador superada
  run python3 "$HV" measure --done-dir "$T/runs" --evidence "$EV"
  [[ "$output" == *"clase.revision: 0"* ]]
  chk 10 $S1 revision revisora-a trabajador superada
  run python3 "$HV" measure --done-dir "$T/runs" --evidence "$EV"
  [[ "$output" == *"clase.revision: 1"* ]]
}

@test "marca que cita un repo sin --repo: declarado (fail-closed)" {
  mkdir -p "$T/runs/x"
  printf 'ESTADO: OK — https://github.com/org/otro/pull/10\n' > "$T/runs/x/done"
  head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada
  run cls x
  [[ "${lines[0]}" == declarado:*"--repo"* ]]
  run cls x --repo otro
  [[ "${lines[0]}" == verificado:* ]]
}

@test "pr: true (bool) no se toma como PR 1" {
  done_ok j1 -
  printf '{"head":"%s","pr":true}\n' $S1 >> "$EV"
  run cls j1
  [[ "$output" == *"anomalia=head inválido"* ]]
}

# ---- hallazgos de la revisión de #1554 ----

@test "marca que cita varias PR distintas: declarado aunque la primera este verificada" {
  mkdir -p "$T/runs/x"
  printf 'ESTADO: OK — https://github.com/org/propio/pull/10 y https://github.com/org/propio/pull/11\n' > "$T/runs/x/done"
  head_rec 10 $S1; chk 10 $S1 revision revisora-a trabajador superada
  run cls x --repo propio
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == declarado:*varias* ]]
}

@test "marca con la misma PR citada dos veces sigue contando (no es ambigua)" {
  mkdir -p "$T/runs/x"
  printf 'ESTADO: OK — https://github.com/org/propio/pull/10 (ver https://github.com/org/propio/pull/10)\n' > "$T/runs/x/done"
  head_rec 10 $S1; chk 10 $S1 revision revisora-a trabajador superada
  run cls x --repo propio
  [[ "${lines[0]}" == verificado:* ]]
}

@test "la PR citada no es la que la evidencia asocia al job: declarado" {
  done_ok jobA 10
  printf '{"head":"%s","pr":10,"job":"jobB"}\n{"head":"%s","pr":20,"job":"jobA"}\n' $S1 $S1 >> "$EV"
  chk 10 $S1 revision revisora-a trabajador superada
  run cls jobA
  [[ "${lines[0]}" == declarado:*"no es la que la evidencia asocia"* ]]
}

@test "la PR citada coincide con la del job en la evidencia: verificado" {
  done_ok jobA 10
  printf '{"head":"%s","pr":10,"job":"jobA"}\n' $S1 >> "$EV"
  chk 10 $S1 revision revisora-a trabajador superada
  run cls jobA
  [[ "${lines[0]}" == verificado:* ]]
}

@test "--repo ignora mayusculas y con owner/repo distingue el propietario" {
  mkdir -p "$T/runs/x"
  printf 'ESTADO: OK — https://github.com/Org/Propio/pull/10\n' > "$T/runs/x/done"
  head_rec 10 $S1; chk 10 $S1 revision revisora-a trabajador superada
  run cls x --repo propio
  [[ "${lines[0]}" == verificado:* ]]
  run cls x --repo org/propio
  [[ "${lines[0]}" == verificado:* ]]
  run cls x --repo fork/propio
  [[ "${lines[0]}" == declarado:*"otro repositorio"* ]]
}

@test "ESTADO: seguido de salto de linea y OK no es una marca valida" {
  mkdir -p "$T/runs/x"
  printf 'ESTADO:\nOK\n' > "$T/runs/x/done"
  run cls x
  [ "$status" -eq 2 ]
}

@test "D3 fail-closed: un registro de clase no mecanica sin propuesta_por no cuenta" {
  done_ok j1 10; head_rec 10 $S1
  printf '{"pr":10,"sha":"%s","clase":"persona","verificador":"alguien","ejecutor":"trabajador","resultado":"superada"}\n' $S1 >> "$EV"
  run cls j1
  [[ "${lines[0]}" == declarado:* ]]
}

@test "D3: una mecanica sin propuesta_por la recoge el recolector y cuenta" {
  done_ok j1 10; head_rec 10 $S1
  printf '{"pr":10,"sha":"%s","clase":"postcondicion","verificador":"recolector","ejecutor":"trabajador","resultado":"superada"}\n' $S1 >> "$EV"
  run cls j1
  [[ "${lines[0]}" == verificado:* ]]
}

@test "measure: --done-dir anidado con nombres de job repetidos falla con 2" {
  mkdir -p "$T/runs/a/job" "$T/runs/b/job"
  printf 'ESTADO: OK\n' > "$T/runs/a/job/done"; printf 'ESTADO: OK\n' > "$T/runs/b/job/done"
  run python3 "$HV" measure --done-dir "$T/runs" --evidence "$EV"
  [ "$status" -eq 2 ]
}

@test "measure informa del numero de anomalias" {
  done_ok j1 10; head_rec 10 $S1
  chk 10 $S1 revision revisora-a trabajador superada '"estado":"verificado"'
  run python3 "$HV" measure --done-dir "$T/runs" --evidence "$EV"
  [[ "$output" == *"anomalias: 1"* ]]
}
