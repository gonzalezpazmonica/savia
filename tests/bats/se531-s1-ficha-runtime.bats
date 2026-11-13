#!/usr/bin/env bats
# SE-531 S1 — ficha de runtime: esquema, validador fail-closed y lectores.
# Ref: docs/specs/SE-531-ficha-de-harness-ejecutable.spec.md (AC-S1b..S1i)
# Cada regla: caso positivo (fichas reales pasan) y negativo (copia mutada falla nombrando ficha y campo).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CHECK="$REPO_ROOT/scripts/harness_ficha.py"
FIELDS="aislamiento rc_en_error senal_cuota informa_uso reanudacion limpieza flujo_llamadas"

setup() {
  D="$BATS_TEST_TMPDIR/fichas"
  mkdir -p "$D"
  cp "$REPO_ROOT"/contracts/runtime/*.yaml "$D/"
}

check() { python3 -I "$CHECK" check "$D"; }

# Ficha medida válida (runtime ficticio) en $D/fake.yaml
write_fake() {
  cat > "$D/fake.yaml" <<YAML
ficha: fake
runtime:
  aislamiento: sandbox_de_ordenes
  rc_en_error: no_fiable
  rc_deteccion: {tipo: literal, valor: "API error"}
  senal_cuota: campo_del_flujo
  informa_uso: si
  reanudacion: por_sesion
  limpieza: grupo_de_procesos
  flujo_llamadas: json
  fuente: {aislamiento: a, rc_en_error: a, rc_deteccion: a, senal_cuota: a, informa_uso: a, reanudacion: a, limpieza: a, flujo_llamadas: a}
  version_cli: {aislamiento: "1", rc_en_error: "1", rc_deteccion: "1", senal_cuota: "1", informa_uso: "1", reanudacion: "1", limpieza: "1", flujo_llamadas: "1"}
YAML
}

# Sustituye el valor de rc_deteccion en fake.yaml (sin depender del delimitador de sed)
set_det() { python3 -I -c 'import sys; p=sys.argv[1]; t=open(p).read().replace("API error", sys.argv[2]); open(p,"w").write(t)' "$D/fake.yaml" "$1"; }

py() { python3 -I -c "import sys; sys.path.insert(0, '$REPO_ROOT/scripts'); import harness_ficha as h; $1"; }

@test "fichas reales pasan y el resumen cuenta no_medido" {
  run check
  [ "$status" -eq 0 ]
  [[ "$output" == *"fichas=4 errores=0 no_medido=28"* ]]
}

@test "cuatro fichas esperadas existen" {
  for f in claude-code opencode codex yema; do [ -f "$REPO_ROOT/contracts/runtime/$f.yaml" ]; done
}

@test "AC-S1c: cada campo obligatorio ausente falla nombrando ficha y campo" {
  for f in $FIELDS; do
    cp "$REPO_ROOT"/contracts/runtime/*.yaml "$D/"
    sed -i "/^  $f:/d" "$D/codex.yaml"
    run check
    [ "$status" -eq 1 ]
    [[ "$output" == *"codex: $f: campo obligatorio ausente"* ]]
  done
}

@test "AC-S1b: ficha sin bloque runtime falla" {
  printf 'ficha: sinbloque\n' > "$D/sinbloque.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"sinbloque: runtime: bloque ausente"* ]]
}

@test "AC-S1b: runtime usado sin ficha falla; con ficha pasa" {
  printf 'ficha: consumidor\nusa: [fantasma]\nruntime:\n  aislamiento: no_medido\n  rc_en_error: no_medido\n  senal_cuota: no_medido\n  informa_uso: no_medido\n  reanudacion: no_medido\n  limpieza: no_medido\n  flujo_llamadas: no_medido\n' > "$D/consumidor.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"consumidor: usa: runtime 'fantasma' sin ficha"* ]]
  sed -i 's/fantasma/codex/' "$D/consumidor.yaml"
  run check
  [ "$status" -eq 0 ]
}

@test "AC-S1d: valor fuera del conjunto falla" {
  sed -i 's/^  aislamiento: .*/  aislamiento: casi/' "$D/codex.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex: aislamiento: valor no permitido 'casi'"* ]]
}

@test "AC-S1d: no_fiable sin rc_deteccion falla; fiable con rc_deteccion falla" {
  write_fake
  sed -i '/rc_deteccion: {tipo/d; s/rc_deteccion: a, //; s/rc_deteccion: "1", //' "$D/fake.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"fake: rc_deteccion: obligatorio con rc_en_error: no_fiable"* ]]
  write_fake
  sed -i 's/rc_en_error: no_fiable/rc_en_error: fiable/' "$D/fake.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"fake: rc_deteccion: prohibido con rc_en_error: fiable"* ]]
}

@test "ficha medida completa pasa (control del caso negativo)" {
  write_fake
  run check
  [ "$status" -eq 0 ]
}

@test "AC-S1e: dato medido sin fuente falla; sin version_cli falla" {
  write_fake
  sed -i 's/limpieza: a, //' "$D/fake.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"fake: fuente.limpieza: obligatorio"* ]]
  write_fake
  sed -i 's/informa_uso: "1", //' "$D/fake.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"fake: version_cli.informa_uso: obligatorio"* ]]
}

@test "AC-S1e límite: todo no_medido pasa sin fuente ni version_cli" {
  run check
  [ "$status" -eq 0 ]
  ! grep -q "fuente" "$D/codex.yaml"
}

@test "AC-S1i: rc_deteccion con metacaracteres de shell o demasiado larga se rechaza" {
  for v in 'a; touch /tmp/x' 'a $(touch /tmp/x)' 'a `id`' "it's" 'a | b'; do
    write_fake
    set_det "$v"
    run check
    [ "$status" -eq 1 ]
    [[ "$output" == *"fake: rc_deteccion.valor: contiene metacaracteres"* ]]
  done
  write_fake
  L=$(printf 'a%.0s' $(seq 1 201))
  set_det "$L"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"supera 200"* ]]
  write_fake
  L=$(printf 'a%.0s' $(seq 1 200))
  set_det "$L"
  run check
  [ "$status" -eq 0 ]
}

@test "AC-S1i: el lector no ejecuta rc_deteccion (marca no aparece)" {
  M="$BATS_TEST_TMPDIR/marca"
  run py "h.detect_failure({'tipo':'literal','valor':'x; touch $M'}, 'x; touch $M'); h.detect_failure({'tipo':'patron','valor':'\$(touch $M)'}, 'a')"
  [ "$status" -eq 0 ]
  [ ! -e "$M" ]
}

@test "AC-S1g: runtime ficticio no_fiable fuerza fallo con rc 0; fiable no lo fuerza" {
  run py "
rt={'rc_en_error':'no_fiable','rc_deteccion':{'tipo':'literal','valor':'API error'}}
assert h.accept_exit(rt,0,True,'API error: 500')[0] is False
assert h.accept_exit(rt,0,True,'todo bien')[0] is True
rt2=dict(rt, rc_en_error='fiable'); del rt2['rc_deteccion']
assert h.accept_exit(rt2,0,None,'API error: 500')[0] is True
"
  [ "$status" -eq 0 ]
}

@test "AC-S1g: el invocador no lleva el nombre del runtime" {
  ! grep -qi opencode "$CHECK"
}

@test "AC-S1h: no_medido en rc_en_error no acepta rc 0 sin postcondición; rc != 0 nunca" {
  run py "
rt={'rc_en_error':'no_medido'}
assert h.accept_exit(rt,0,None)[0] is False
assert h.accept_exit(rt,0,False)[0] is False
assert h.accept_exit(rt,0,True)[0] is True
assert h.accept_exit({'rc_en_error':'fiable'},1,True)[0] is False
assert h.accept_exit({},0,None)[0] is False
"
  [ "$status" -eq 0 ]
}

@test "AC-S1h: los siete campos leen no_medido como lo desconfiado y el valor permisivo distinto" {
  run py "
nm={c:'no_medido' for c in h.FIELDS}
ok={'aislamiento':'proceso_confinado','rc_en_error':'fiable','senal_cuota':'campo_del_flujo','informa_uso':'si','reanudacion':'por_sesion','limpieza':'grupo_de_procesos','flujo_llamadas':'json'}
assert not h.confined(nm) and h.confined(ok)
assert h.accept_exit(nm,0,None)[0] is False and h.accept_exit(ok,0,None)[0] is True
assert h.quota_channel(nm)=='ninguna' and h.quota_channel(ok)=='campo_del_flujo'
assert not h.reports_usage(nm) and h.reports_usage(ok)
assert not h.can_resume(nm) and h.can_resume(ok)
assert not h.cleanup_guaranteed(nm) and h.cleanup_guaranteed(ok)
assert not h.watches_calls(nm) and h.watches_calls(ok)
assert {c:h.effective(nm,c) for c in h.FIELDS}=={'aislamiento':'ninguno','rc_en_error':'no_fiable','senal_cuota':'ninguna','informa_uso':'no','reanudacion':'no_soportada','limpieza':'ninguna','flujo_llamadas':'ninguno'}
"
  [ "$status" -eq 0 ]
}

@test "uso incorrecto o directorio inexistente: fallo cerrado" {
  run python3 -I "$CHECK" check "$BATS_TEST_TMPDIR/nada"
  [ "$status" -eq 2 ]
  run python3 -I "$CHECK"
  [ "$status" -eq 2 ]
  mkdir "$BATS_TEST_TMPDIR/vacio"
  run python3 -I "$CHECK" check "$BATS_TEST_TMPDIR/vacio"
  [ "$status" -eq 1 ]
}

@test "YAML ilegible falla, no pasa" {
  printf 'ficha: [\n' > "$D/roto.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"roto.yaml: ilegible"* ]]
}
