#!/usr/bin/env bats
# SE-471 — Relevo nocturno con evidencia: declarado, validado y aceptado.
# Ref: docs/specs/SE-471-overnight-handoff-evidence-digest.spec.md
# Fixtures sintéticas: tests/fixtures/se471-handoff (5 runs + log). `gh` siempre falso, en un PATH temporal.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/scripts/overnight-handoff-digest.sh"
  FIX="$ROOT/tests/fixtures/se471-handoff"
  TMP="$(mktemp -d)"
  FAKEBIN="$TMP/bin"
  GHLOG="$TMP/gh-args.log"
  mkdir -p "$FAKEBIN"
}

teardown() {
  rm -rf "$TMP"
}

# gh falso: registra cada argumento en GHLOG y responde según el número de PR.
# 101 CI verde · 102 CI rojo · 103 CI pendiente · 104 verde + CHANGES_REQUESTED · 105 merged.
make_fake_gh() {
  local mode="${1:-ok}"
  cat > "$FAKEBIN/gh" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do printf '%s\n' "\$a" >> "$GHLOG"; done
printf -- '---\n' >> "$GHLOG"
[ "$mode" = "fail" ] && { echo "error connecting to api.github.com" >&2; exit 1; }
url="\${@: -1}"
green='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","state":"SUCCESS"}]'
case "\$url" in
  */pull/101) echo "{\"state\":\"OPEN\",\"isDraft\":true,\"reviewDecision\":\"\",\"statusCheckRollup\":\$green,\"mergedAt\":null}" ;;
  */pull/102) echo '{"state":"OPEN","isDraft":true,"reviewDecision":"","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},{"status":"COMPLETED","conclusion":"FAILURE"}],"mergedAt":null}' ;;
  */pull/103) echo '{"state":"OPEN","isDraft":true,"reviewDecision":"","statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":null}],"mergedAt":null}' ;;
  */pull/104) echo "{\"state\":\"OPEN\",\"isDraft\":false,\"reviewDecision\":\"CHANGES_REQUESTED\",\"statusCheckRollup\":\$green,\"mergedAt\":null}" ;;
  */pull/105) echo "{\"state\":\"MERGED\",\"isDraft\":false,\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":\$green,\"mergedAt\":\"2026-10-24T08:00:00Z\"}" ;;
  *) echo "no pull requests found" >&2; exit 1 ;;
esac
EOF
  chmod +x "$FAKEBIN/gh"
}

mark() { # mark <runs> <nombre> <contenido literal>
  mkdir -p "$1/$2"
  printf '%s\n' "$3" > "$1/$2/done"
}

# jq-lite: evalúa una expresión Python sobre el JSON de $output (variable d).
jget() {
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$output" "$1"
}

@test "AC1: offline, 5 runs — cada run bien clasificado y decisiones en el orden de S1" {
  run bash "$SCRIPT" --runs-dir "$FIX/runs" --log "$FIX/runs.log" --format json
  [ "$status" -eq 0 ]
  [ "$(jget '",".join(r["nombre"]+"="+r["declarado"] for r in d["runs"])')" = \
    "a-ok=OK,b-parcial=PARCIAL,c-fallo=FALLO,d-sin-marca=sin_marca,e-malformada=malformada" ]
  [ "$(jget '",".join(x["categoria"] for x in d["decisiones"])')" = "sin_marca_rc,fallo,parcial,malformada" ]
  [ "$(jget '",".join(str(x["posicion"]) for x in d["decisiones"])')" = "1,2,4,5" ]
  # cada entrada lleva su «Siguiente» literal y la ruta de la marca
  [ "$(jget '[x["siguiente"] for x in d["decisiones"] if x["run"]=="c-fallo"][0]')" = \
    "Siguiente: arreglar el baseline antes de relanzar." ]
  [ "$(jget '[x["marca"] for x in d["decisiones"] if x["run"]=="b-parcial"][0]')" = "$FIX/runs/b-parcial/done" ]
  [ "$(jget 'd["totales"]["runs"]')" = "5" ]
  [ "$(jget 'd["ventana"]["desde"] is not None and d["ventana"]["hasta"] is not None')" = "True" ]
}

@test "AC1: el OK y el sin marca con rc=0 no son decisiones; sin marca con rc=1 sí" {
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" ok1 'ESTADO: OK https://github.com/o/r/pull/1'
  printf '2026-10-24T01:00:00Z end limpio rc=0\n2026-10-24T01:00:00Z end roto rc=1\n2026-10-24T01:00:00Z start vivo\n' > "$TMP/log"
  run bash "$SCRIPT" --runs-dir "$R" --log "$TMP/log" --format json
  [ "$status" -eq 0 ]
  [ "$(jget '",".join(x["run"] for x in d["decisiones"])')" = "roto" ]
}

@test "AC1: formato md con cabecera de totales, ventana y decisiones" {
  run bash "$SCRIPT" --runs-dir "$FIX/runs" --log "$FIX/runs.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Runs: 5 · OK 1 · PARCIAL 1 · FALLO 1 · sin marca 1 · malformada 1"* ]]
  [[ "$output" == *"Ventana: "* ]]
  [[ "$output" == *"2. [FALLO] c-fallo — Siguiente: arreglar el baseline antes de relanzar."* ]]
}

@test "AC1: tolera variantes de marca (negrita, URL en otra línea, Pendiente) sin adivinar" {
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" negrita '**ESTADO:** PARCIAL — tests a medias'
  mark "$R" url2 $'ESTADO: OK\nPR abierta en https://github.com/o/r/pull/7.\nSiguiente: revisar.'
  mark "$R" okay 'ESTADO: OKAY todo bien'
  mark "$R" vacia ''
  run bash "$SCRIPT" --runs-dir "$R" --format json
  [ "$status" -eq 0 ]
  [ "$(jget '",".join(r["nombre"]+"="+r["declarado"] for r in d["runs"])')" = \
    "negrita=PARCIAL,okay=malformada,url2=OK,vacia=malformada" ]
  [ "$(jget '[r["pr_url"] for r in d["runs"] if r["nombre"]=="url2"][0]')" = "https://github.com/o/r/pull/7" ]
}

@test "AC2: marca sin línea ESTADO sale malformada, aparece en decisiones y nunca cuenta como OK" {
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" sin-estado $'OK, todo listo\nhttps://github.com/o/r/pull/9\nSiguiente: nada'
  run bash "$SCRIPT" --runs-dir "$R" --format json
  [ "$status" -eq 0 ]
  [ "$(jget 'd["runs"][0]["declarado"]')" = "malformada" ]
  [ "$(jget 'd["totales"]["OK"]')" = "0" ]
  [ "$(jget 'd["totales"]["malformada"]')" = "1" ]
  [ "$(jget '",".join(x["categoria"]+":"+x["run"] for x in d["decisiones"])')" = "malformada:sin-estado" ]
}

@test "AC3: offline ningún run sale validado/aceptado sí, aunque haya un gh que diría verde y merged" {
  make_fake_gh ok
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" verde 'ESTADO: OK https://github.com/o/r/pull/101'
  mark "$R" merged 'ESTADO: OK https://github.com/o/r/pull/105'
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" --runs-dir "$R" --format json
  [ "$status" -eq 0 ]
  [ "$(jget 'sorted({r["validado"] for r in d["runs"]} | {r["aceptado"] for r in d["runs"]})')" = "['desconocido']" ]
  [ "$(jget 'd["modo"]')" = "offline" ]
  [ ! -e "$GHLOG" ]
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" --runs-dir "$R"
  [[ "$output" == *"| verde | OK | desconocido | desconocido |"* ]]
}

@test "AC4: --max-decisions 2 con 5 candidatas lista 2 y dice +3 sin listar" {
  R="$TMP/runs"; mkdir -p "$R"
  for i in 1 2 3; do mark "$R" "fallo$i" 'ESTADO: FALLO roto'; done
  mark "$R" parcial 'ESTADO: PARCIAL a medias'
  mark "$R" mala 'sin estado'
  run bash "$SCRIPT" --runs-dir "$R" --max-decisions 2 --format json
  [ "$status" -eq 0 ]
  [ "$(jget 'len(d["decisiones"])')" = "2" ]
  [ "$(jget 'd["sin_listar"]')" = "3" ]
  run bash "$SCRIPT" --runs-dir "$R" --max-decisions 2
  [[ "$output" == *"+3 sin listar"* ]]
  run bash "$SCRIPT" --runs-dir "$R" --format json
  [ "$(jget 'len(d["decisiones"])')" = "5" ]
  [ "$(jget 'd["sin_listar"]')" = "0" ]
}

@test "AC4: valores de tope inválidos y runs-dir inexistente fallan con exit 2" {
  run bash "$SCRIPT" --runs-dir "$FIX/runs" --max-decisions -1
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" --runs-dir "$TMP/no-existe"
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" --runs-dir "$FIX/runs" --since ayer
  [ "$status" -eq 2 ]
}

@test "AC5: no escribe fuera de stdout — mtimes y listado del árbol de fixtures idénticos" {
  make_fake_gh ok
  cp -a "$FIX" "$TMP/fx"
  mkdir -p "$TMP/cwd"
  snap() { (cd "$1" && find . -printf '%p %T@ %s\n' | LC_ALL=C sort); }
  before_fx="$(snap "$TMP/fx")"; before_repo="$(snap "$FIX")"
  sleep 0.05
  (cd "$TMP/cwd" && PATH="$FAKEBIN:$PATH" bash "$SCRIPT" --runs-dir "$TMP/fx/runs" --log "$TMP/fx/runs.log" --online --format json >/dev/null)
  (cd "$TMP/cwd" && bash "$SCRIPT" --runs-dir "$TMP/fx/runs" --log "$TMP/fx/runs.log" >/dev/null)
  bash "$SCRIPT" --runs-dir "$FIX/runs" --log "$FIX/runs.log" >/dev/null
  [ "$(snap "$TMP/fx")" = "$before_fx" ]
  [ "$(snap "$FIX")" = "$before_repo" ]
  [ -z "$(ls -A "$TMP/cwd")" ]
}

@test "AC6: --online da los tres estados de validado y OK con CI rojo va en posición 3, antes que PARCIAL" {
  make_fake_gh ok
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" a-verde 'ESTADO: OK https://github.com/o/r/pull/101'
  mark "$R" b-rojo $'ESTADO: OK\nhttps://github.com/o/r/pull/102\nSiguiente: mirar el job que falla.'
  mark "$R" c-pendiente 'ESTADO: OK https://github.com/o/r/pull/103'
  mark "$R" d-cambios 'ESTADO: OK https://github.com/o/r/pull/104'
  mark "$R" e-merged 'ESTADO: OK https://github.com/o/r/pull/105'
  mark "$R" f-parcial 'ESTADO: PARCIAL https://github.com/o/r/pull/101'
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" --runs-dir "$R" --online --format json
  [ "$status" -eq 0 ]
  [ "$(jget 'd["modo"]')" = "online" ]
  [ "$(jget '",".join(r["nombre"]+"="+r["validado"]+"/"+r["aceptado"] for r in d["runs"])')" = \
    "a-verde=sí/desconocido,b-rojo=no/desconocido,c-pendiente=desconocido/desconocido,d-cambios=no/desconocido,e-merged=sí/sí,f-parcial=sí/desconocido" ]
  [ "$(jget '",".join(str(x["posicion"])+":"+x["run"] for x in d["decisiones"])')" = "3:b-rojo,3:d-cambios,4:f-parcial" ]
  [ "$(jget 'd["decisiones"][0]["siguiente"]')" = "Siguiente: mirar el job que falla." ]
  # la URL llega a gh como argumento tras `--`
  grep -qx -- '--' "$GHLOG"
  [ "$(grep -A1 -x -- '--' "$GHLOG" | grep -c '^https://github.com/o/r/pull/')" -eq 6 ]
}

@test "AC6: si gh falla, aviso «degradado a offline», todo desconocido y exit 0" {
  make_fake_gh fail
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" a 'ESTADO: OK https://github.com/o/r/pull/102'
  mark "$R" b 'ESTADO: OK https://github.com/o/r/pull/101'
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" --runs-dir "$R" --online --format json
  [ "$status" -eq 0 ]
  [ "$(jget 'd["degradado"]')" = "True" ]
  [ "$(jget 'd["modo"]')" = "offline" ]
  [[ "$(jget 'd["avisos"]')" == *"degradado a offline"* ]]
  [ "$(jget 'sorted({r["validado"] for r in d["runs"]})')" = "['desconocido']" ]
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" --runs-dir "$R" --online
  [ "$status" -eq 0 ]
  [[ "$output" == *"Aviso: degradado a offline"* ]]
}

@test "AC7: offline sobre 200 marcas generadas tarda menos de 2 s" {
  R="$TMP/runs"; mkdir -p "$R"
  for i in $(seq 1 200); do
    case $((i % 4)) in
      0) s="OK https://github.com/o/r/pull/$i" ;; 1) s="PARCIAL falta algo" ;; 2) s="FALLO roto" ;; 3) s="" ;;
    esac
    mkdir -p "$R/run-$i"
    if [ -n "$s" ]; then printf 'ESTADO: %s\nSiguiente: paso %s\n' "$s" "$i" > "$R/run-$i/done"
    else printf 'sin estado\n' > "$R/run-$i/done"; fi
  done
  t0=$(date +%s%N)
  run bash "$SCRIPT" --runs-dir "$R" --format json
  t1=$(date +%s%N)
  [ "$status" -eq 0 ]
  [ "$(jget 'd["totales"]["runs"]')" = "200" ]
  [ "$(jget 'd["sin_listar"]')" = "143" ]
  [ $(( (t1 - t0) / 1000000 )) -lt 2000 ]
}

@test "AC8: URL maliciosas no llegan a gh, no crean ficheros y salen desconocido con url_rechazada" {
  make_fake_gh ok
  R="$TMP/runs"; mkdir -p "$R" "$TMP/cwd"
  mark "$R" m-repo $'ESTADO: OK\nPR: --repo otro/repo'
  mark "$R" m-subst 'ESTADO: OK — https://github.com/a/b/pull/$(touch x)'
  mark "$R" m-semicolon 'ESTADO: OK — https://github.com/a/b/pull/1;id'
  (cd "$TMP/cwd" && PATH="$FAKEBIN:$PATH" bash "$SCRIPT" --runs-dir "$R" --online --format json) > "$TMP/out.json"
  output="$(cat "$TMP/out.json")"
  [ ! -s "$GHLOG" ]
  [ -z "$(find "$TMP" "$ROOT" -maxdepth 3 -name x -newer "$FAKEBIN/gh" 2>/dev/null)" ]
  [ "$(jget '",".join(r["nombre"]+"="+r["validado"]+":"+"|".join(r["avisos"]) for r in d["runs"])')" = \
    "m-repo=desconocido:url_rechazada,m-semicolon=desconocido:url_rechazada,m-subst=desconocido:url_rechazada" ]
  [ "$(jget 'all(r["pr_url"] is None for r in d["runs"])')" = "True" ]
}

@test "AC8: control positivo — la misma noche con una URL válida sí llega a gh" {
  make_fake_gh ok
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" m-semicolon 'ESTADO: OK — https://github.com/a/b/pull/1;id'
  mark "$R" valida 'ESTADO: OK — https://github.com/a/b/pull/101'
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" --runs-dir "$R" --online --format json
  [ "$status" -eq 0 ]
  [ "$(grep -c '^https://' "$GHLOG")" -eq 1 ]
  grep -qx 'https://github.com/a/b/pull/101' "$GHLOG"
}

@test "--since deja fuera las marcas anteriores a la ventana y la cabecera la muestra" {
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" vieja 'ESTADO: FALLO de anteayer'
  mark "$R" nueva 'ESTADO: FALLO de anoche'
  touch -d '2026-10-20T03:00:00Z' "$R/vieja/done"
  touch -d '2026-10-24T03:00:00Z' "$R/nueva/done"
  run bash "$SCRIPT" --runs-dir "$R" --since 2026-10-23T20:00:00Z --format json
  [ "$status" -eq 0 ]
  [ "$(jget '",".join(r["nombre"] for r in d["runs"])')" = "nueva" ]
  [ "$(jget 'd["ventana"]["desde"]')" = "2026-10-23T20:00:00Z" ]
  run bash "$SCRIPT" --runs-dir "$R" --format json
  [ "$(jget '",".join(r["nombre"] for r in d["runs"])')" = "nueva,vieja" ]
}

@test "AC8: enlace a comentario y puntuación final se recortan; a gh solo llega la URL limpia" {
  make_fake_gh ok
  R="$TMP/runs"; mkdir -p "$R"
  mark "$R" comentario 'ESTADO: OK — revisión en https://github.com/a/b/pull/101#issuecomment-123).'
  mark "$R" parentesis 'ESTADO: OK (https://github.com/a/b/pull/102);'
  mark "$R" frag-inyeccion 'ESTADO: OK https://github.com/a/b/pull/103#;$(touch x)'
  mark "$R" punto-coma-id 'ESTADO: OK https://github.com/a/b/pull/104;id'
  PATH="$FAKEBIN:$PATH" run bash "$SCRIPT" --runs-dir "$R" --online --format json
  [ "$status" -eq 0 ]
  [ "$(jget '",".join(r["nombre"]+"="+str(r["pr_url"]) for r in d["runs"])')" = \
    "comentario=https://github.com/a/b/pull/101,frag-inyeccion=https://github.com/a/b/pull/103,parentesis=https://github.com/a/b/pull/102,punto-coma-id=None" ]
  [ "$(grep '^https://' "$GHLOG" | LC_ALL=C sort | tr '\n' ' ')" = \
    "https://github.com/a/b/pull/101 https://github.com/a/b/pull/102 https://github.com/a/b/pull/103 " ]
  [ "$(jget '[r["avisos"] for r in d["runs"] if r["nombre"]=="punto-coma-id"][0]')" = "['url_rechazada']" ]
}
