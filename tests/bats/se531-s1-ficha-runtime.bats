#!/usr/bin/env bats
# SE-531 S1 — ficha de runtime: esquema, validador fail-closed y lectores.
# Ref: SE-531 S1 (AC-S1b..S1i)
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

# R(**kw): bloque runtime completo y válido (no_medido + overrides; fuente/version_cli para lo medido)
PYPRE="
import sys; sys.path.insert(0, '$REPO_ROOT/scripts'); import harness_ficha as h
def R(**kw):
    rt = {c: 'no_medido' for c in h.FIELDS}; rt.update(kw)
    med = [c for c in kw if c in h.FIELDS and kw[c] != 'no_medido'] + (['rc_deteccion'] if 'rc_deteccion' in kw else [])
    if med:
        rt['fuente'] = {c: 'f' for c in med}; rt['version_cli'] = {c: '1' for c in med}
    return rt
"
py() { python3 -I -c "$PYPRE
$1"; }

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
  for v in 'a; touch /tmp/x' 'a $(touch /tmp/x)' 'a `id`' "it's" 'a | b' 'a & b' 'a > b' 'a < b' 'a\\b' 'a\nb' 'a\rb'; do
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

@test "AC-S1i: el lector no ejecuta nada: toda vía de ejecución de subprocess/os/builtins revienta si se usa" {
  run py "
import subprocess, os, builtins
def boom(*a, **k): raise AssertionError('ejecución')
names = [(subprocess, n) for n in ('run','Popen','call','check_call','check_output','getoutput','getstatusoutput')]
names += [(os, n) for n in dir(os) if n.startswith(('exec','spawn','posix_spawn','fork','popen','system'))]
names += [(builtins, n) for n in ('eval','exec','__import__')]
assert len(names) > 15, names
for o, n in names:
    setattr(o, n, boom)
lit={'tipo':'literal','valor':'touch marca'}
pat={'tipo':'patron','valor':'^touch .marca'}
assert h.detect_failure(lit, 'x touch marca y') is True
assert h.detect_failure(pat, 'touch /marca') is True
assert h.accept_exit(R(rc_en_error='no_fiable',rc_deteccion=lit), 0, True, 'touch marca')[0] is False
assert h.accept_exit(R(rc_en_error='no_fiable',rc_deteccion=pat), 0, True, 'limpio')[0] is True
"
  [ "$status" -eq 0 ]
}

@test "AC-S1i: el módulo no importa subprocess/os/shlex ni llama eval/exec/system" {
  run python3 -I -c "
import ast, sys
t = ast.parse(open('$CHECK').read())
P = ('subprocess','os','shlex','ctypes','importlib','runpy','pty')
bad = [a.name for n in ast.walk(t) if isinstance(n, ast.Import) for a in n.names if a.name.split('.')[0] in P]
bad += [n.module for n in ast.walk(t) if isinstance(n, ast.ImportFrom) and (n.module or '').split('.')[0] in P]
bad += [n.func.id for n in ast.walk(t) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in ('eval','exec','compile','__import__')]
print(bad); sys.exit(1 if bad else 0)
"
  [ "$status" -eq 0 ]
}

@test "ReDoS: patrón con grupos o cuantificadores se rechaza; patrón lineal pasa y es rápido" {
  for v in '(a+)+b' '^a*' '^a+' '^a?' '^a{2}' '^(ab)' '^[^a]b'; do
    write_fake
    python3 -I -c 'import sys; p=sys.argv[1]; t=open(p).read().replace("{tipo: literal, valor: \"API error\"}", "{tipo: patron, valor: \"%s\"}" % sys.argv[2]); open(p,"w").write(t)' "$D/fake.yaml" "$v"
    run check
    [ "$status" -eq 1 ]
    [[ "$output" == *"fake: rc_deteccion.valor: patrón con grupos, cuantificadores o clases negadas"* ]]
  done
  run py "
import time
rt=R(rc_en_error='no_fiable',rc_deteccion={'tipo':'patron','valor':'^API [a-z]rror.'})
t=time.time(); r=h.accept_exit(rt,0,True,'a'*2000000); assert time.time()-t < 5, 'lento'
assert r[0] is True
"
  [ "$status" -eq 0 ]
}

@test "ReDoS O(n·m): patrón sin ancla '^' se rechaza; el peor caso anclado es lineal en la salida" {
  write_fake
  python3 -I -c 'import sys; p=sys.argv[1]; t=open(p).read().replace("{tipo: literal, valor: \"API error\"}", "{tipo: patron, valor: \"%s\"}" % sys.argv[2]); open(p,"w").write(t)' "$D/fake.yaml" "API err.r"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"fake: rc_deteccion.valor: un patrón debe empezar por '^'"* ]]
  run py "
import time
assert h._check_deteccion('x', {'tipo':'patron','valor':'[a-z]'*39+'b'}), 'sin ancla debe rechazarse'
assert h._check_deteccion('x', {'tipo':'literal','valor':'a\x01b'}), 'control debe rechazarse'
w=R(rc_en_error='no_fiable',rc_deteccion={'tipo':'patron','valor':'^'+'a'*198+'b'})
t=time.time(); r=h.accept_exit(w,0,True,('a'*199+'\n')*100000); dt=time.time()-t
assert r[0] is True and dt < 5, dt
w2=R(rc_en_error='no_fiable',rc_deteccion={'tipo':'patron','valor':'^'+'[a-z]'*39+'b'})
t=time.time(); r=h.accept_exit(w2,0,True,'\n'*20000000); dt=time.time()-t
assert r[0] is True and dt < 5, dt
"
  [ "$status" -eq 0 ]
}

@test "patrón: '^' ancla al inicio de cada línea (error en una línea intermedia se detecta)" {
  run py "
rp=R(rc_en_error='no_fiable',rc_deteccion={'tipo':'patron','valor':'^API err.r'})
assert h.accept_exit(rp,0,True,'arranque\nprogreso\nAPI error 500\nfin')[0] is False
assert h.accept_exit(rp,0,True,'arranque\nla API error no empieza la línea\nfin')[0] is True
"
  [ "$status" -eq 0 ]
}

@test "fail-closed: regla inaplicable (inválida, salida no texto, ReDoS) no acepta rc 0" {
  run py "
ok={'tipo':'literal','valor':'API error'}
rt=R(rc_en_error='no_fiable',rc_deteccion=ok)
assert h.accept_exit(rt,0,True,None)[0] is False
assert h.accept_exit(rt,0,True)[0] is False          # salida omitida: la regla no se puede aplicar
assert h.accept_exit(rt,0,True,'')[0] is True        # salida vacía explícita: limpia
assert h.accept_exit(rt,0,True,b'API error')[0] is False
assert h.accept_exit(dict(rt,rc_deteccion={'tipo':'literal','valor':'a; b'}),0,True,'x')[0] is False
assert h.accept_exit(dict(rt,rc_deteccion={'tipo':'patron','valor':'(a+)+b'}),0,True,'aaaa')[0] is False
assert h.accept_exit(dict(rt,rc_deteccion='texto'),0,True,'x')[0] is False
assert h.accept_exit(rt,0,True,'limpio')[0] is True
"
  [ "$status" -eq 0 ]
}

@test "detección escanea la salida completa: error en cabeza, medio o cola; por encima del tope se rechaza" {
  run py "
rt=R(rc_en_error='no_fiable',rc_deteccion={'tipo':'literal','valor':'API error'})
rp=R(rc_en_error='no_fiable',rc_deteccion={'tipo':'patron','valor':'^API err.r'})
x='x'*3000000
assert h.accept_exit(rt,0,True,x+'API error')[0] is False
assert h.accept_exit(rt,0,True,'API error'+x)[0] is False
assert h.accept_exit(rt,0,True,x+'API error'+x)[0] is False   # medio: el truncado lo perdía
assert h.accept_exit(rt,0,True,x)[0] is True
assert h.accept_exit(rp,0,True,'API error'+x)[0] is False
h.SCAN_MAX=1000
assert h.accept_exit(rt,0,True,'x'*1001)[0] is False          # tope duro: inaplicable = rechazo
assert h.accept_exit(rt,0,True,'x'*1000)[0] is True
"
  [ "$status" -eq 0 ]
}

@test "accept_exit: rc no entero o booleano se rechaza; regla None o con rc fiable se rechaza" {
  run py "
rt=R(rc_en_error='no_fiable',rc_deteccion={'tipo':'literal','valor':'API error'})
for rc in (0.0, False, True, '0', None, 1):
    assert h.accept_exit(rt,rc,True,'ok')[0] is False, rc
assert h.accept_exit(dict(rt,rc_deteccion=None),0,True,'ok')[0] is False
assert h.accept_exit(R(rc_en_error='fiable',rc_deteccion=rt['rc_deteccion']),0,True,'ok')[0] is False
assert h.accept_exit(R(rc_en_error='fiable'),0,False,'ok')[0] is True
assert h.accept_exit(rt,0,True,'ok')[0] is True
"
  [ "$status" -eq 0 ]
}

@test "clave de primer nivel desconocida (typo de usa) falla" {
  sed -i 's/^ficha: codex/ficha: codex\nusas: [claude-code]/' "$D/codex.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex.yaml: clave de primer nivel desconocida ['usas']"* ]]
}

@test "claves duplicadas en una ficha fallan" {
  sed -i 's/^  rc_en_error: .*/&\n  rc_en_error: fiable/' "$D/codex.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex.yaml: ilegible"*"clave duplicada 'rc_en_error'"* ]]
}

@test "informa_uso: no sin comillas y \"no\" son el mismo texto; yes/on/off/true no se aceptan" {
  sed -i 's/^  informa_uso: .*/  informa_uso: no/' "$D/codex.yaml"
  sed -i 's/^  informa_uso: .*/  informa_uso: "no"/' "$D/opencode.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex: fuente.informa_uso: obligatorio para un dato medido"* ]]
  [[ "$output" == *"opencode: fuente.informa_uso: obligatorio para un dato medido"* ]]
  [[ "$output" != *"valor no permitido"* ]]
  for v in yes on off true false; do
    cp "$REPO_ROOT"/contracts/runtime/*.yaml "$D/"
    sed -i "s/^  informa_uso: .*/  informa_uso: $v/" "$D/codex.yaml"
    run check
    [ "$status" -eq 1 ]
    [[ "$output" == *"codex: informa_uso: valor no permitido '$v'"* ]]
  done
  run py "assert h.effective({'informa_uso': True},'informa_uso')=='no' and not h.reports_usage({'informa_uso': True})"
  [ "$status" -eq 0 ]
}

@test "clave no escalar o anidamiento profundo: error nombrado, sin traza, y las demás fichas se validan" {
  printf 'ficha: rara\n? [a, b]\n: 1\n' > "$D/rara.yaml"
  python3 -I -c 'import sys; open(sys.argv[1],"w").write("ficha: honda\nusa: " + "["*20000 + "]"*20000 + "\n")' "$D/honda.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"rara.yaml: ilegible: clave no admitida"* ]]
  [[ "$output" == *"honda.yaml: ilegible: anidamiento demasiado profundo"* ]]
  [[ "$output" == *"fichas=4 errores=2"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "accept_exit: ficha sin validar (incompleta o con valores inválidos) no acepta rc 0" {
  run py "
assert h.accept_exit({'rc_en_error':'fiable'},0,True,'ok')[0] is False
assert h.accept_exit(R(rc_en_error='fiable', aislamiento='casi'),0,True,'ok')[0] is False
f=R(rc_en_error='fiable'); del f['fuente']
assert h.accept_exit(f,0,True,'ok')[0] is False
assert h.accept_exit(R(rc_en_error='fiable'),0,True,'ok')[0] is True
"
  [ "$status" -eq 0 ]
}

@test "ficha: el id debe coincidir con el nombre del fichero" {
  sed -i 's/^ficha: codex/ficha: yema/' "$D/codex.yaml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex.yaml: ficha: el id 'yema' no coincide"* ]]
}

@test "fichas con extensión .yml se rechazan (no se ignoran en silencio)" {
  cp "$D/codex.yaml" "$D/otra.yml"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"otra.yml: extensión .yml no admitida"* ]]
}

@test "AC-S1g: runtime ficticio no_fiable fuerza fallo con rc 0; fiable no lo fuerza" {
  run py "
rt=R(rc_en_error='no_fiable',rc_deteccion={'tipo':'literal','valor':'API error'})
assert h.accept_exit(rt,0,True,'API error: 500')[0] is False
assert h.accept_exit(rt,0,True,'todo bien')[0] is True
rt2=dict(rt, rc_en_error='fiable'); del rt2['rc_deteccion']
assert h.accept_exit(rt2,0,None,'API error: 500')[0] is True
"
  [ "$status" -eq 0 ]
}

@test "AC-S1g: el invocador no lleva el nombre de ningún runtime con ficha" {
  ids=()
  for f in "$REPO_ROOT"/contracts/runtime/*.yaml; do ids+=("$(basename "$f" .yaml)"); done
  [ "${#ids[@]}" -ge 4 ]
  for id in "${ids[@]}" claude; do
    run grep -qi -- "$id" "$CHECK"
    [ "$status" -eq 1 ]
  done
}

@test "AC-S1h: no_medido en rc_en_error no acepta rc 0 sin postcondición; rc != 0 nunca" {
  run py "
rt=R()
assert h.accept_exit(rt,0,None)[0] is False
assert h.accept_exit(rt,0,False)[0] is False
assert h.accept_exit(rt,0,True)[0] is True
assert h.accept_exit(R(rc_en_error='fiable'),1,True)[0] is False
assert h.accept_exit({},0,None)[0] is False
"
  [ "$status" -eq 0 ]
}

@test "AC-S1h: los siete campos leen no_medido como lo desconfiado y el valor permisivo distinto" {
  run py "
nm={c:'no_medido' for c in h.FIELDS}
ok=R(aislamiento='proceso_confinado',rc_en_error='fiable',senal_cuota='campo_del_flujo',informa_uso='si',reanudacion='por_sesion',limpieza='grupo_de_procesos',flujo_llamadas='json')
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
