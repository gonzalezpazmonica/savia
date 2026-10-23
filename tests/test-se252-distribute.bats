#!/usr/bin/env bats
# tests/test-se252-distribute.bats — SE-252 Bus Factor Shield
# Tests para scripts/bus-factor-distribute.sh

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DIST_SCRIPT="$REPO_ROOT/scripts/bus-factor-distribute.sh"
SCAN_SCRIPT="$REPO_ROOT/scripts/bus-factor-scan.sh"
SCAN_PY="$REPO_ROOT/scripts/bus-factor-scan.py"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DIST_SCRIPT="$REPO_ROOT/scripts/bus-factor-distribute.sh"
  SCAN_SCRIPT="$REPO_ROOT/scripts/bus-factor-scan.sh"
  SCAN_PY="$REPO_ROOT/scripts/bus-factor-scan.py"
  TEST_REPO="$BATS_TMPDIR/dist-repo-$$"
  BF_OUT="$BATS_TMPDIR/dist-bf-out-$$"
  mkdir -p "$TEST_REPO" "$BF_OUT"
  export BF_OUTPUT_DIR="$BF_OUT"
}

teardown() {
  rm -rf "$TEST_REPO" "$BF_OUT" 2>/dev/null || true
}

_setup_single_author_repo() {
  cd "$TEST_REPO"
  git init -q
  git config user.email "alice@test.com"
  git config user.name "Alice"
  mkdir -p src lib
  for i in $(seq 1 6); do
    printf "src%s\n" "$i" > "src/main.py"
    printf "lib%s\n" "$i" > "lib/utils.py"
    git add -A
    git commit -q -m "commit $i"
  done
}

_run_scan() {
  local proj_name
  proj_name="$(basename "$TEST_REPO")"
  BF_MIN_COMMITS=3 BF_OUTPUT_DIR="$BF_OUT" python3 "$SCAN_PY" \
    --project "$proj_name" \
    --output "$BF_OUT/${proj_name}.json" \
    "$TEST_REPO" 2>/dev/null
}

_inject_scan_json() {
  local proj_name
  proj_name="$(basename "$TEST_REPO")"
  local jfile="$BF_OUT/${proj_name}.json"
  python3 -c "
import json
data = {
  'generated_at': '2026-06-30T00:00:00Z',
  'project': 'test-project',
  'modules': [
    {
      'name': 'src', 'path': 'src',
      'bus_factor': 1, 'risk_level': 'CRITICAL',
      'owners': [{'dev': 'alice@test.com', 'score': 1.0, 'files_owned': 2}],
      'files': [
        {'path': 'src/main.py', 'bus_factor': 1,
         'owners': [{'dev': 'alice@test.com', 'score': 1.0, 'files_owned': 0}],
         'warnings': []},
        {'path': 'src/helper.py', 'bus_factor': 1,
         'owners': [{'dev': 'alice@test.com', 'score': 1.0, 'files_owned': 0}],
         'warnings': []}
      ],
      'warnings': []
    },
    {
      'name': 'lib', 'path': 'lib',
      'bus_factor': 2, 'risk_level': 'HIGH',
      'owners': [
        {'dev': 'alice@test.com', 'score': 0.6, 'files_owned': 1},
        {'dev': 'bob@test.com',   'score': 0.4, 'files_owned': 1}
      ],
      'files': [
        {'path': 'lib/utils.py', 'bus_factor': 2,
         'owners': [
           {'dev': 'alice@test.com', 'score': 0.6, 'files_owned': 0},
           {'dev': 'bob@test.com',   'score': 0.4, 'files_owned': 0}
         ],
         'warnings': []}
      ],
      'warnings': []
    },
    {
      'name': 'docs', 'path': 'docs',
      'bus_factor': 3, 'risk_level': 'MEDIUM',
      'owners': [
        {'dev': 'alice@test.com', 'score': 0.4, 'files_owned': 1},
        {'dev': 'bob@test.com',   'score': 0.3, 'files_owned': 1},
        {'dev': 'carol@test.com', 'score': 0.3, 'files_owned': 1}
      ],
      'files': [
        {'path': 'docs/index.md', 'bus_factor': 3,
         'owners': [
           {'dev': 'alice@test.com', 'score': 0.4, 'files_owned': 0},
           {'dev': 'bob@test.com',   'score': 0.3, 'files_owned': 0},
           {'dev': 'carol@test.com', 'score': 0.3, 'files_owned': 0}
         ],
         'warnings': []}
      ],
      'warnings': []
    }
  ],
  'summary': {'total_modules': 3, 'critical': 1, 'high': 1, 'medium': 1, 'low': 0},
  'warnings': []
}
with open('$jfile', 'w') as f:
    json.dump(data, f, indent=2)
print('injected')
" 2>/dev/null
  mkdir -p "$TEST_REPO/src" "$TEST_REPO/lib" "$TEST_REPO/docs"
}

# ── 01: script existe ─────────────────────────────────────────────────────────
@test "SE252-dist-01: bus-factor-distribute.sh existe" {
  [ -f "$DIST_SCRIPT" ]
}

# ── 02: script es invocable con bash ─────────────────────────────────────────
@test "SE252-dist-02: bus-factor-distribute.sh es invocable con bash" {
  [ -f "$DIST_SCRIPT" ]
  run bash -n "$DIST_SCRIPT"
  [ "$status" -eq 0 ]
}

# ── 03: bash -n syntax check ──────────────────────────────────────────────────
@test "SE252-dist-03: bash -n no detecta errores de sintaxis" {
  run bash -n "$DIST_SCRIPT"
  [ "$status" -eq 0 ]
}

# ── 04: sin argumentos → mensaje de uso ───────────────────────────────────────
@test "SE252-dist-04: sin argumentos imprime uso y sale con error" {
  run bash "$DIST_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Uu]sage|--project ]]
}

# ── 05: --project sin --target → error ────────────────────────────────────────
@test "SE252-dist-05: --project sin --target sale con error" {
  _setup_single_author_repo
  _run_scan
  run bash "$DIST_SCRIPT" --project "$TEST_REPO"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Ee][Rr][Rr][Oo][Rr]|--target ]]
}

# ── 06: sin JSON de scan → error claro ────────────────────────────────────────
@test "SE252-dist-06: sin JSON de scan disponible emite ERROR descriptivo" {
  _setup_single_author_repo
  run bash "$DIST_SCRIPT" --project "$TEST_REPO" --target "bob@test.com"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Ee][Rr][Rr][Oo][Rr]|scan ]]
}

# ── 07: BF_OUT vacio + project inexistente → error ───────────────────────────
@test "SE252-dist-07: BF_OUT vacio y project inexistente sale con error" {
  run bash "$DIST_SCRIPT" \
    --project "/tmp/ruta-que-no-existe-bf-$$" \
    --target "bob@test.com"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Ee][Rr][Rr][Oo][Rr]|scan ]]
}

# ── 08: JSON output es JSON válido ────────────────────────────────────────────
@test "SE252-dist-08: --format json produce JSON valido" {
  _setup_single_author_repo
  _inject_scan_json
  local outfile="$BATS_TMPDIR/dist08-$$.json"
  run bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "bob@test.com" \
    --format json \
    --output "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  run python3 -m json.tool "$outfile"
  [ "$status" -eq 0 ]
}

# ── 09: JSON contiene campo "target" ──────────────────────────────────────────
@test "SE252-dist-09: JSON output contiene campo target" {
  _setup_single_author_repo
  _inject_scan_json
  local outfile="$BATS_TMPDIR/dist09-$$.json"
  bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "bob@test.com" \
    --format json \
    --output "$outfile" 2>/dev/null
  run python3 -c "
import json
d = json.load(open('$outfile'))
assert 'target' in d, 'no target field'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 10: JSON contiene campo "plan" ────────────────────────────────────────────
@test "SE252-dist-10: JSON output contiene campo plan" {
  _setup_single_author_repo
  _inject_scan_json
  local outfile="$BATS_TMPDIR/dist10-$$.json"
  bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "bob@test.com" \
    --format json \
    --output "$outfile" 2>/dev/null
  run python3 -c "
import json
d = json.load(open('$outfile'))
assert 'plan' in d, f'no plan field, keys: {list(d.keys())}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 11: módulos ordenados CRITICAL antes que HIGH ─────────────────────────────
@test "SE252-dist-11: plan JSON ordena CRITICAL antes de HIGH" {
  _setup_single_author_repo
  _inject_scan_json
  local outfile="$BATS_TMPDIR/dist11-$$.json"
  bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "carol@test.com" \
    --format json \
    --output "$outfile" 2>/dev/null
  run python3 -c "
import json
d = json.load(open('$outfile'))
plan = d.get('plan', [])
risk_rank = {'CRITICAL':4,'HIGH':3,'MEDIUM':2,'LOW':1}
for i in range(len(plan)-1):
    r1 = risk_rank.get(plan[i]['risk_level'],0)
    r2 = risk_rank.get(plan[i+1]['risk_level'],0)
    assert r1 >= r2, f'Order error: {plan[i][\"risk_level\"]} before {plan[i+1][\"risk_level\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 12: módulos ordenados HIGH antes que MEDIUM ───────────────────────────────
@test "SE252-dist-12: plan JSON ordena HIGH antes de MEDIUM" {
  _setup_single_author_repo
  _inject_scan_json
  local outfile="$BATS_TMPDIR/dist12-$$.json"
  bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "nobody@test.com" \
    --format json \
    --output "$outfile" 2>/dev/null
  run python3 -c "
import json
d = json.load(open('$outfile'))
plan = d.get('plan', [])
risk_rank = {'CRITICAL':4,'HIGH':3,'MEDIUM':2,'LOW':1}
levels = [risk_rank.get(p['risk_level'],0) for p in plan]
assert levels == sorted(levels, reverse=True), f'Not sorted: {levels}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 13: markdown output contiene nombre de modulo ─────────────────────────────
@test "SE252-dist-13: --format markdown produce output con nombre de modulo" {
  _setup_single_author_repo
  _inject_scan_json
  run bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "carol@test.com" \
    --format markdown
  [ "$status" -eq 0 ]
  [[ "$output" == *"src"* ]] || [[ "$output" == *"lib"* ]] || [[ "$output" == *"docs"* ]]
}

# ── 14: --output flag escribe archivo ─────────────────────────────────────────
@test "SE252-dist-14: --output escribe el resultado en archivo" {
  _setup_single_author_repo
  _inject_scan_json
  local outfile="$BATS_TMPDIR/dist14-$$.md"
  run bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "carol@test.com" \
    --format markdown \
    --output "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  [ -s "$outfile" ]
}

# ── 15: archivos donde el target es owner se marcan como conocidos ─────────────
@test "SE252-dist-15: archivos donde el target es owner tienen unknown_count=0" {
  _setup_single_author_repo
  _inject_scan_json
  local outfile="$BATS_TMPDIR/dist15-$$.json"
  bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "alice@test.com" \
    --format json \
    --output "$outfile" 2>/dev/null
  run python3 -c "
import json
d = json.load(open('$outfile'))
for item in d.get('plan', []):
    if item['module'] == 'src':
        assert item['unknown_count'] == 0, f'alice deberia conocer src, unknown={item[\"unknown_count\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 16: formato por defecto es markdown ───────────────────────────────────────
@test "SE252-dist-16: formato por defecto es markdown sin --format" {
  _setup_single_author_repo
  _inject_scan_json
  run bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "carol@test.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *"#"* ]] || [[ "$output" == *"-"* ]]
}

# ── 17: campo target en JSON coincide con el dev especificado ─────────────────
@test "SE252-dist-17: campo target en JSON coincide con el dev especificado" {
  _setup_single_author_repo
  _inject_scan_json
  local outfile="$BATS_TMPDIR/dist17-$$.json"
  bash "$DIST_SCRIPT" \
    --project "$TEST_REPO" \
    --target "carol@test.com" \
    --format json \
    --output "$outfile" 2>/dev/null
  run python3 -c "
import json
d = json.load(open('$outfile'))
assert d['target'] == 'carol@test.com', f'expected carol, got {d[\"target\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── Comportamiento: plan de transferencia sobre un scan sintético ─────────────

# _mkscan <fichero> <json-modules>  (project fijo "proy", fecha fija)
_mkscan() {
  python3 - "$1" "$2" <<'PY'
import json, sys
mods = json.loads(sys.argv[2])
json.dump({"generated_at": "2026-06-30T00:00:00Z", "project": "proy", "modules": mods}, open(sys.argv[1], "w"))
PY
}

# _mod <nombre> <bf> <riesgo> <ficheros-separados-por-coma> <owners-por-fichero-separados-por-coma>
_mod() {
  python3 - "$@" <<'PY'
import json, sys
name, bf, risk, files, owners = sys.argv[1:6]
fl = [f for f in files.split(",") if f]
ow = [o for o in owners.split(",") if o]
print(json.dumps({"name": name, "path": name, "bus_factor": int(bf), "risk_level": risk,
                  "files": [{"path": f"{name}/{f}", "bus_factor": int(bf),
                             "owners": [{"dev": o, "score": 1.0, "files_owned": 0} for o in ow]} for f in fl]}))
PY
}

_dist() { bash "$DIST_SCRIPT" --project "$PROJ" --target "$1" "${@:2}" 2>/dev/null; }

_plan_field() { printf '%s' "$1" | python3 -c "import sys,json;d=json.load(sys.stdin);print($2)"; }

setup_plan() {
  PROJ="$BATS_TMPDIR/proy-$$-$BATS_TEST_NUMBER"
  mkdir -p "$PROJ"
  PROJ_NAME="$(basename "$PROJ")"
  SCAN="$BF_OUT/${PROJ_NAME}.json"
}

@test "SE252-dist: orden risk DESC, bus_factor ASC y loc ASC como desempate" {
  setup_plan
  mkdir -p "$PROJ/m-high-big" "$PROJ/m-high-small" "$PROJ/m-crit" "$PROJ/m-high-bf1"
  seq 1 50 > "$PROJ/m-high-big/a.txt"
  seq 1 5 > "$PROJ/m-high-small/a.txt"
  _mkscan "$SCAN" "[$(_mod m-high-big 2 HIGH a.py x@t), $(_mod m-high-small 2 HIGH a.py x@t), $(_mod m-crit 3 CRITICAL a.py x@t), $(_mod m-high-bf1 1 HIGH a.py x@t)]"
  out="$(_dist bob@t --format json)"
  [ "$(_plan_field "$out" "','.join(p['module'] for p in d['plan'])")" = "m-crit,m-high-bf1,m-high-small,m-high-big" ]
}

@test "SE252-dist: un nivel de riesgo desconocido queda el último (rank 0)" {
  setup_plan
  mkdir -p "$PROJ/a" "$PROJ/b"
  _mkscan "$SCAN" "[$(_mod a 1 EXTRANO f.py x@t), $(_mod b 5 LOW f.py x@t)]"
  out="$(_dist bob@t --format json)"
  [ "$(_plan_field "$out" "','.join(p['module'] for p in d['plan'])")" = "b,a" ]
  [ "$(_plan_field "$out" "d['plan'][1]['risk_rank']")" = "0" ]
}

@test "SE252-dist: unknown_files lista solo los ficheros donde el target no es owner" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$SCAN" "[$(_mod m 2 HIGH a.py,b.py x@t,bob@t), $(_mod n 2 HIGH c.py x@t)]"
  python3 - "$SCAN" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["modules"][0]["files"][1]["owners"] = [{"dev": "bob@t"}]
d["modules"][0]["files"][0]["owners"] = [{"dev": "x@t"}]
json.dump(d, open(sys.argv[1], "w"))
PY
  out="$(_dist bob@t --format json)"
  [ "$(_plan_field "$out" "[p for p in d['plan'] if p['module']=='m'][0]['unknown_files']")" = "['m/a.py']" ]
  [ "$(_plan_field "$out" "[p for p in d['plan'] if p['module']=='m'][0]['unknown_count']")" = "1" ]
  [ "$(_plan_field "$out" "[p for p in d['plan'] if p['module']=='m'][0]['total_files']")" = "2" ]
}

@test "SE252-dist: el target se compara por igualdad exacta, no por subcadena" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$SCAN" "[$(_mod m 1 HIGH a.py bobby@t)]"
  out="$(_dist bob@t --format json)"
  [ "$(_plan_field "$out" "d['plan'][0]['unknown_count']")" = "1" ]
}

@test "SE252-dist: loc cuenta saltos de línea y excluye node_modules, vendor y .git" {
  setup_plan
  mkdir -p "$PROJ/m/node_modules" "$PROJ/m/vendor" "$PROJ/m/.git" "$PROJ/m/sub"
  seq 1 7 > "$PROJ/m/a.txt"
  seq 1 3 > "$PROJ/m/sub/b.txt"
  seq 1 1000 > "$PROJ/m/node_modules/x.js"
  seq 1 1000 > "$PROJ/m/vendor/y.php"
  seq 1 1000 > "$PROJ/m/.git/z"
  _mkscan "$SCAN" "[$(_mod m 1 HIGH a.py x@t)]"
  out="$(_dist bob@t --format json)"
  [ "$(_plan_field "$out" "d['plan'][0]['loc']")" = "10" ]
}

@test "SE252-dist: módulo sin directorio en disco tiene loc 0 y no rompe el plan" {
  setup_plan
  _mkscan "$SCAN" "[$(_mod fantasma 1 HIGH a.py x@t)]"
  out="$(_dist bob@t --format json)"
  [ "$(_plan_field "$out" "d['plan'][0]['loc']")" = "0" ]
}

@test "SE252-dist: has_dome y dome_path reflejan la existencia de CONTEXT_DOME.md" {
  setup_plan
  mkdir -p "$PROJ/con" "$PROJ/sin"
  echo x > "$PROJ/con/CONTEXT_DOME.md"
  _mkscan "$SCAN" "[$(_mod con 1 HIGH a.py x@t), $(_mod sin 1 HIGH a.py x@t)]"
  out="$(_dist bob@t --format json)"
  [ "$(_plan_field "$out" "[p for p in d['plan'] if p['module']=='con'][0]['has_dome']")" = "True" ]
  [ "$(_plan_field "$out" "[p for p in d['plan'] if p['module']=='con'][0]['dome_path']")" = "$PROJ/con/CONTEXT_DOME.md" ]
  [ "$(_plan_field "$out" "[p for p in d['plan'] if p['module']=='sin'][0]['has_dome']")" = "False" ]
  [ "$(_plan_field "$out" "[p for p in d['plan'] if p['module']=='sin'][0]['dome_path']")" = "None" ]
}

@test "SE252-dist: JSON incluye project y generated_at del scan y el target pedido" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$SCAN" "[$(_mod m 1 HIGH a.py x@t)]"
  out="$(_dist bob@t --format json)"
  [ "$(_plan_field "$out" "d['project']")" = "proy" ]
  [ "$(_plan_field "$out" "d['generated_at']")" = "2026-06-30T00:00:00Z" ]
  [ "$(_plan_field "$out" "d['target']")" = "bob@t" ]
}

@test "SE252-dist: markdown numera módulos, da porcentaje de desconocidos y formatea miles" {
  setup_plan
  mkdir -p "$PROJ/grande" "$PROJ/otro"
  seq 1 1500 > "$PROJ/grande/big.txt"
  _mkscan "$SCAN" "[$(_mod grande 1 CRITICAL a.py,b.py,c.py,d.py x@t,x@t), $(_mod otro 4 LOW z.py x@t)]"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Plan de Knowledge Transfer -- bob@t"* ]]
  [[ "$output" == *"Total modulos en plan: **2**"* ]]
  [[ "$output" == *"Proyecto: **proy**"* ]]
  [[ "$output" == *"Generado: 2026-06-30T00:00:00Z"* ]]
  [[ "$output" == *"## 1. grande"* ]]
  [[ "$output" == *"## 2. otro"* ]]
  [[ "$output" == *"**Riesgo**: CRITICAL"* ]]
  [[ "$output" == *"**Archivos desconocidos**: 4/4 (100%)"* ]]
  [[ "$output" == *"**Lineas de codigo**: 1,500"* ]]
  [[ "$output" == *"*(cupula no generada aun)*"* ]]
}

@test "SE252-dist: markdown conoce el porcentaje parcial y enlaza la cúpula si existe" {
  setup_plan
  mkdir -p "$PROJ/m"
  echo x > "$PROJ/m/CONTEXT_DOME.md"
  _mkscan "$SCAN" "[$(_mod m 2 HIGH a.py,b.py,c.py,d.py bob@t)]"
  python3 - "$SCAN" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["modules"][0]["files"][0]["owners"] = [{"dev": "x@t"}]
json.dump(d, open(sys.argv[1], "w"))
PY
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t
  [[ "$output" == *"**Archivos desconocidos**: 1/4 (25%)"* ]]
  [[ "$output" == *"[CONTEXT_DOME.md]($PROJ/m/CONTEXT_DOME.md)"* ]]
  [[ "$output" != *"cupula no generada"* ]]
}

@test "SE252-dist: markdown limita la lista de estudio a 10 ficheros y avisa del tope" {
  setup_plan
  mkdir -p "$PROJ/m"
  files="$(seq -s, -f 'f%02g.py' 1 12)"
  _mkscan "$SCAN" "[$(_mod m 1 HIGH "$files" x@t)]"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t
  [[ "$output" == *"Archivos a estudiar (10 primeros):"* ]]
  [[ "$output" == *'`m/f10.py`'* ]]
  [[ "$output" != *'`m/f11.py`'* ]]
}

@test "SE252-dist: si el target conoce todo el módulo no hay sección de estudio" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$SCAN" "[$(_mod m 1 HIGH a.py bob@t)]"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t
  [[ "$output" == *"**Archivos desconocidos**: 0/1 (0%)"* ]]
  [[ "$output" != *"Archivos a estudiar"* ]]
}

@test "SE252-dist: módulo sin ficheros no divide por cero (0/0, 0%)" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$SCAN" "[$(_mod m 1 HIGH '' x@t)]"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Archivos desconocidos**: 0/0 (0%)"* ]]
}

@test "SE252-dist: formato desconocido cae a markdown en vez de fallar" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$SCAN" "[$(_mod m 1 HIGH a.py x@t)]"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t --format xml
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Plan de Knowledge Transfer -- bob@t"* ]]
}

# ── Comportamiento: selección del scan ────────────────────────────────────────

@test "SE252-dist: usa el scan más reciente con nombre <proyecto>-<fecha>.json" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$BF_OUT/${PROJ_NAME}-20260101T000000Z.json" "[$(_mod viejo 1 HIGH a.py x@t)]"
  sleep 1
  _mkscan "$BF_OUT/${PROJ_NAME}-20260102T000000Z.json" "[$(_mod nuevo 1 HIGH a.py x@t)]"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t --format json
  [[ "$output" == *"${PROJ_NAME}-20260102T000000Z.json"* ]]
  [[ "$output" == *'"module": "nuevo"'* ]]
  [[ "$output" != *'"module": "viejo"'* ]]
}

@test "SE252-dist: no usa el scan de otro proyecto con prefijo parecido (app vs app-backend)" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$BF_OUT/${PROJ_NAME}-backend.json" "[$(_mod ajeno 1 HIGH a.py x@t)]"
  _mkscan "$BF_OUT/${PROJ_NAME}-backend-20260102T000000Z.json" "[$(_mod ajeno 1 HIGH a.py x@t)]"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se encontro JSON de scan en $BF_OUT"* ]]
  [[ "$output" == *"nombres aceptados: ${PROJ_NAME}.json o ${PROJ_NAME}-<YYYYMMDD>T<HHMMSS>Z.json"* ]]
}

@test "SE252-dist: scan ilegible termina con exit 2 y el motivo, sin plan parcial" {
  setup_plan
  mkdir -p "$PROJ/m"
  echo "{no es json" > "$SCAN"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t
  [ "$status" -eq 2 ]
  [[ "$output" == *"scan JSON ilegible"* ]]
  [[ "$output" != *"# Plan de Knowledge Transfer"* ]]
}

@test "SE252-dist: con --output el plan va al fichero (creando directorios) y no a stdout" {
  setup_plan
  mkdir -p "$PROJ/m"
  _mkscan "$SCAN" "[$(_mod m 1 HIGH a.py x@t)]"
  out="$BF_OUT/sub/dir/plan.md"
  run bash "$DIST_SCRIPT" --project "$PROJ" --target bob@t --output "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan escrito en $out"* ]]
  [[ "$output" != *"# Plan de Knowledge Transfer"* ]]
  grep -q "^# Plan de Knowledge Transfer -- bob@t$" "$out"
}

# ── Comportamiento: argumentos ────────────────────────────────────────────────

@test "SE252-dist: --help sale con 1 y documenta el orden del plan" {
  run bash "$DIST_SCRIPT" --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"risk_level DESC, bus_factor ASC, loc ASC"* ]]
}

@test "SE252-dist: argumento desconocido y --project/--target ausentes nombran el problema" {
  run bash "$DIST_SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"argumento desconocido: --bogus"* ]]
  run bash "$DIST_SCRIPT" --target bob@t
  [[ "$output" == *"--project es obligatorio"* ]]
  run bash "$DIST_SCRIPT" --project /x
  [[ "$output" == *"--target es obligatorio"* ]]
}
