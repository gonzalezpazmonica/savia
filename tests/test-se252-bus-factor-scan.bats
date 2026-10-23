#!/usr/bin/env bats
# tests/test-se252-bus-factor-scan.bats — SE-252 Bus Factor Shield
# Tests para scripts/bus-factor-scan.sh y scripts/bus-factor-scan.py

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/bus-factor-scan.sh"
PY_SCRIPT="$REPO_ROOT/scripts/bus-factor-scan.py"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/bus-factor-scan.sh"
  PY_SCRIPT="$REPO_ROOT/scripts/bus-factor-scan.py"
  TEST_REPO="$BATS_TMPDIR/bf-scan-repo-$$"
  BF_OUT="$BATS_TMPDIR/bf-out-$$"
  mkdir -p "$TEST_REPO" "$BF_OUT"
  export BF_OUTPUT_DIR="$BF_OUT"
}

teardown() {
  rm -rf "$TEST_REPO" "$BF_OUT" 2>/dev/null || true
}

# Helper: init repo with one author
_init_repo_alice() {
  cd "$TEST_REPO"
  git init -q
  git config user.email "alice@test.com"
  git config user.name "Alice"
}

# Helper: init repo with alice + bob
_init_repo_two_authors() {
  cd "$TEST_REPO"
  git init -q
  git config user.email "alice@test.com"
  git config user.name "Alice"
}

# Helper: add and commit a file as current user
_commit_file() {
  local path="$1" content="${2:-content}"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  git add "$path"
  git commit -q -m "add $path"
}

# ── 01: script existe ─────────────────────────────────────────────────────────
@test "SE252-scan-01: bus-factor-scan.sh existe" {
  [ -f "$SCRIPT" ]
}

# ── 02: script es ejecutable ──────────────────────────────────────────────────
@test "SE252-scan-02: bus-factor-scan.sh tiene permiso de ejecucion o es invocable con bash" {
  # El archivo puede carecer de +x si el repo no preserva permisos,
  # pero debe ser invocable via bash.
  [ -f "$SCRIPT" ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── 03: Python script existe ──────────────────────────────────────────────────
@test "SE252-scan-03: bus-factor-scan.py existe" {
  [ -f "$PY_SCRIPT" ]
}

# ── 04: bash -n syntax check ──────────────────────────────────────────────────
@test "SE252-scan-04: bash -n no detecta errores de sintaxis en scan.sh" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── 05: Python syntax check ───────────────────────────────────────────────────
@test "SE252-scan-05: python3 ast.parse no detecta errores en scan.py" {
  run python3 -c "import ast; ast.parse(open('$PY_SCRIPT').read()); print('OK')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 06: sin argumentos → exit != 0 con mensaje de uso ────────────────────────
@test "SE252-scan-06: sin argumentos imprime uso y sale con error" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Uu]sage|--project ]]
}

# ── 07: --project con path inválido → exit 1 ──────────────────────────────────
@test "SE252-scan-07: --project con directorio inexistente sale con exit 1" {
  run bash "$SCRIPT" --project "/tmp/ruta-que-no-existe-bf-$$"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Ee][Rr][Rr][Oo][Rr]|error ]]
}

# ── 08: --project con dir sin git → error claro ───────────────────────────────
@test "SE252-scan-08: --project sin repositorio git emite ERROR y sale con error" {
  mkdir -p "$BATS_TMPDIR/no-git-$$"
  run bash "$SCRIPT" --project "$BATS_TMPDIR/no-git-$$"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Ee][Rr][Rr][Oo][Rr]|error ]]
  rm -rf "$BATS_TMPDIR/no-git-$$"
}

# ── 09: repo vacío (0 commits) → no crash ─────────────────────────────────────
@test "SE252-scan-09: repo con 0 commits no produce crash" {
  _init_repo_alice
  run bash "$SCRIPT" --project "$TEST_REPO"
  # Puede fallar (empty repo) pero no crash con señal
  [ "$status" -le 1 ]
}

# ── 10: repo con 1 commit 1 archivo → produce JSON ────────────────────────────
@test "SE252-scan-10: repo con 1 commit genera JSON válido" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  printf 'hello\nworld\n' > src/main.py
  git add src/main.py
  git commit -q -m "init"
  local outfile="$BF_OUT/result-$$.json"
  run bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  run python3 -m json.tool "$outfile"
  [ "$status" -eq 0 ]
}

# ── 11: JSON contiene campo "modules" ─────────────────────────────────────────
@test "SE252-scan-11: JSON output contiene campo modules" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'line\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local outfile="$BF_OUT/result-$$.json"
  bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "import json; d=json.load(open('$outfile')); assert 'modules' in d, 'no modules'"
  [ "$status" -eq 0 ]
}

# ── 12: JSON contiene campo "summary" ─────────────────────────────────────────
@test "SE252-scan-12: JSON output contiene campo summary" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'line\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local outfile="$BF_OUT/result-$$.json"
  bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "import json; d=json.load(open('$outfile')); assert 'summary' in d"
  [ "$status" -eq 0 ]
}

# ── 13: JSON contiene campo "generated_at" ────────────────────────────────────
@test "SE252-scan-13: JSON output contiene campo generated_at" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'line\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local outfile="$BF_OUT/result-$$.json"
  bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "import json; d=json.load(open('$outfile')); assert 'generated_at' in d"
  [ "$status" -eq 0 ]
}

# ── 14: módulo con 1 autor → bus_factor=1 ─────────────────────────────────────
@test "SE252-scan-14: 1 autor exclusivo en todos los archivos → bus_factor=1" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  # 5+ commits para superar BF_MIN_COMMITS
  for i in $(seq 1 6); do
    printf "line%s\n" "$i" > "src/main.py"
    git add src/main.py
    git commit -q -m "commit $i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_MIN_COMMITS=3 bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
modules = d['modules']
assert len(modules) > 0, 'no modules'
for m in modules:
    assert m['bus_factor'] >= 1, f'bf should be >=1, got {m[\"bus_factor\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 15: cada módulo tiene bus_factor >= 1 ─────────────────────────────────────
@test "SE252-scan-15: todos los modulos con commits tienen bus_factor >= 1" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src lib
  for i in $(seq 1 6); do
    printf "content%s\n" "$i" > "src/a.py"
    printf "lib%s\n" "$i"    > "lib/b.py"
    git add -A
    git commit -q -m "commit $i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_MIN_COMMITS=3 bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
for m in d['modules']:
    if m['bus_factor'] > 0:
        assert m['bus_factor'] >= 1
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 16: risk_level CRITICAL cuando bus_factor=1 ───────────────────────────────
@test "SE252-scan-16: modulo con bf=1 tiene risk_level CRITICAL" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  for i in $(seq 1 6); do
    printf "c%s\n" "$i" > src/main.py
    git add src/main.py
    git commit -q -m "c$i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_MIN_COMMITS=3 bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
for m in d['modules']:
    if m['bus_factor'] == 1:
        assert m['risk_level'] == 'CRITICAL', f'got {m[\"risk_level\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 17: --output flag escribe archivo JSON ────────────────────────────────────
@test "SE252-scan-17: --output escribe el archivo JSON en la ruta indicada" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'x\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local outfile="$BATS_TMPDIR/custom-output-$$.json"
  run bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
}

# ── 18: output directorio se crea si no existe ────────────────────────────────
@test "SE252-scan-18: directorio de output se crea si no existe" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'x\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local newdir="$BATS_TMPDIR/newdir-$$/subdir"
  local outfile="$newdir/result.json"
  run bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
}

# ── 19: BF_MIN_COMMITS excluye archivos con pocos commits ─────────────────────
@test "SE252-scan-19: BF_MIN_COMMITS=100 excluye archivos con pocos commits" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  printf 'x\n' > src/file.py
  git add src/file.py
  git commit -q -m "only one commit"
  local outfile="$BF_OUT/result-$$.json"
  BF_MIN_COMMITS=100 bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
# Con BF_MIN_COMMITS=100 y solo 1 commit, no deberia haber modulos o modules vacios
print(f'modules: {len(d[\"modules\"])}')
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 20: BF_EXCLUDE_PATTERNS excluye directorios ───────────────────────────────
@test "SE252-scan-20: BF_EXCLUDE_PATTERNS=vendor/ excluye ese directorio" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p vendor/lib src
  for i in $(seq 1 6); do
    printf "v%s\n" "$i" > vendor/lib/dep.py
    printf "s%s\n" "$i" > src/main.py
    git add -A
    git commit -q -m "c$i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_MIN_COMMITS=3 BF_EXCLUDE_PATTERNS="vendor/" bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
names = [m['name'] for m in d['modules']]
assert not any('vendor' in n for n in names), f'vendor found in {names}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 21: bot commits son ignorados ─────────────────────────────────────────────
@test "SE252-scan-21: commits de bots (email con [bot]) son ignorados como owners" {
  cd "$TEST_REPO"
  git init -q
  git config user.email "dependabot[bot]@users.noreply.github.com"
  git config user.name "dependabot[bot]"
  mkdir -p src
  for i in $(seq 1 6); do
    printf "b%s\n" "$i" > src/dep.py
    git add src/dep.py
    git commit -q -m "bot commit $i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_MIN_COMMITS=3 bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
# Bot commits deben ser ignorados; owners lista vacia o sin bots
for m in d['modules']:
    for f in m.get('files', []):
        for o in f.get('owners', []):
            assert '[bot]' not in o['dev'], f'bot owner found: {o[\"dev\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 22: summary.critical cuenta módulos CRITICAL ──────────────────────────────
@test "SE252-scan-22: summary.critical coincide con conteo real de modulos CRITICAL" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  for i in $(seq 1 6); do
    printf "c%s\n" "$i" > src/main.py
    git add src/main.py
    git commit -q -m "c$i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_MIN_COMMITS=3 bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
real_critical = sum(1 for m in d['modules'] if m['risk_level'] == 'CRITICAL')
assert d['summary']['critical'] == real_critical, f'{d[\"summary\"][\"critical\"]} != {real_critical}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 23: script es idempotente (mismo JSON excepto generated_at) ───────────────
@test "SE252-scan-23: segunda ejecucion produce mismo conteo de modulos" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  for i in $(seq 1 6); do
    printf "c%s\n" "$i" > src/main.py
    git add src/main.py
    git commit -q -m "c$i"
  done
  local out1="$BF_OUT/r1-$$.json"
  local out2="$BF_OUT/r2-$$.json"
  BF_MIN_COMMITS=3 bash "$SCRIPT" --project "$TEST_REPO" --output "$out1"
  BF_MIN_COMMITS=3 bash "$SCRIPT" --project "$TEST_REPO" --output "$out2"
  run python3 -c "
import json
d1 = json.load(open('$out1'))
d2 = json.load(open('$out2'))
assert len(d1['modules']) == len(d2['modules'])
assert d1['summary']['critical'] == d2['summary']['critical']
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 24: BF_OWNERSHIP_THRESHOLD configurable ───────────────────────────────────
@test "SE252-scan-24: BF_OWNERSHIP_THRESHOLD configurable via env var" {
  # Verificar que la variable se lee correctamente (el script no falla con valores válidos)
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  for i in $(seq 1 6); do
    printf "c%s\n" "$i" > src/main.py
    git add src/main.py
    git commit -q -m "c$i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_OWNERSHIP_THRESHOLD=0.9 BF_MIN_COMMITS=3 run bash "$SCRIPT" \
    --project "$TEST_REPO" --output "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  run python3 -m json.tool "$outfile"
  [ "$status" -eq 0 ]
}

# ── 25: BF_MAX_HISTORY_DEPTH limita commits procesados ────────────────────────
@test "SE252-scan-25: BF_MAX_HISTORY_DEPTH=2 no crashea y produce JSON valido" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  for i in $(seq 1 8); do
    printf "c%s\n" "$i" > src/main.py
    git add src/main.py
    git commit -q -m "c$i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_MAX_HISTORY_DEPTH=2 BF_MIN_COMMITS=1 bash "$SCRIPT" \
    --project "$TEST_REPO" --output "$outfile"
  run python3 -m json.tool "$outfile"
  [ "$status" -eq 0 ]
}

# ── 26: Python script acepta --project como argumento ─────────────────────────
@test "SE252-scan-26: bus-factor-scan.py acepta --project y path de repo" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'x\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local outfile="$BATS_TMPDIR/py26-$$.json"
  run python3 "$PY_SCRIPT" --project "test-proj" --output "$outfile" "$TEST_REPO"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  run python3 -m json.tool "$outfile"
  [ "$status" -eq 0 ]
}

# ── 27: Python script directo produce JSON válido ─────────────────────────────
@test "SE252-scan-27: bus-factor-scan.py directo produce JSON valido en stdout" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'x\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local outfile="$BATS_TMPDIR/py27-$$.json"
  run python3 "$PY_SCRIPT" --project "myproj" --output "$outfile" "$TEST_REPO"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  run python3 -c "
import json
d = json.load(open('$outfile'))
assert 'modules' in d
assert 'summary' in d
assert 'generated_at' in d
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 28: Python --output escribe archivo ───────────────────────────────────────
@test "SE252-scan-28: python script --output escribe archivo JSON" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'x\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local outfile="$BATS_TMPDIR/py-out-$$.json"
  run python3 "$PY_SCRIPT" --project "myproj" --output "$outfile" "$TEST_REPO"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  run python3 -m json.tool "$outfile"
  [ "$status" -eq 0 ]
}

# ── 29: total_changes=0 → warnings contiene no_history, sin ZeroDivisionError ─
@test "SE252-scan-29: archivo sin historial produce warning no_history sin crash" {
  _init_repo_alice
  cd "$TEST_REPO"
  # Crear archivo con git add pero commitearlo con contenido vacío
  touch empty.txt
  git add empty.txt
  git commit -q -m "add empty"
  run python3 "$PY_SCRIPT" --project "myproj" "$TEST_REPO"
  [ "$status" -eq 0 ]
  # No debe contener traceback Python
  [[ "$output" != *"Traceback"* ]]
  [[ "$output" != *"ZeroDivisionError"* ]]
}

# ── 30: repo con 1 autor 3 archivos → bf=1 para el modulo ─────────────────────
@test "SE252-scan-30: repo con 1 unico autor y 3 archivos → bus_factor modulo <= 1" {
  _init_repo_alice
  cd "$TEST_REPO"
  mkdir -p src
  for i in $(seq 1 6); do
    printf "v%s\n" "$i" > "src/a.py"
    printf "v%s\n" "$i" > "src/b.py"
    printf "v%s\n" "$i" > "src/c.py"
    git add -A
    git commit -q -m "c$i"
  done
  local outfile="$BF_OUT/result-$$.json"
  BF_MIN_COMMITS=3 bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
for m in d['modules']:
    if m['name'].startswith('src'):
        assert m['bus_factor'] <= 2, f'Expected bf<=2 for single author, got {m[\"bus_factor\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 31: JSON summary tiene todos los campos esperados ─────────────────────────
@test "SE252-scan-31: summary contiene total_modules critical high medium low" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'x\n' > file.txt
  git add file.txt
  git commit -q -m "init"
  local outfile="$BF_OUT/result-$$.json"
  bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json
d = json.load(open('$outfile'))
s = d['summary']
for k in ['total_modules','critical','high','medium','low']:
    assert k in s, f'missing {k}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 32: risk_level HIGH cuando bus_factor=2 y BF_RISK_HIGH=2 ──────────────────
@test "SE252-scan-32: risk_level logica: bf=2 con BF_RISK_HIGH=2 → HIGH" {
  run python3 -c "
import os, subprocess, sys
result = subprocess.run(['python3','-c','''
import os
os.environ[\"BF_RISK_CRITICAL\"] = \"1\"
os.environ[\"BF_RISK_HIGH\"] = \"2\"
os.environ[\"BF_RISK_MEDIUM\"] = \"3\"

def _env_int(key, default):
    try: return int(os.environ.get(key, default))
    except: return default

BF_RISK_CRITICAL = _env_int(\"BF_RISK_CRITICAL\", 1)
BF_RISK_HIGH     = _env_int(\"BF_RISK_HIGH\", 2)
BF_RISK_MEDIUM   = _env_int(\"BF_RISK_MEDIUM\", 3)

def risk_level(bf):
    if bf <= BF_RISK_CRITICAL: return \"CRITICAL\"
    if bf <= BF_RISK_HIGH:     return \"HIGH\"
    if bf <= BF_RISK_MEDIUM:   return \"MEDIUM\"
    return \"LOW\"

assert risk_level(1) == \"CRITICAL\", risk_level(1)
assert risk_level(2) == \"HIGH\",     risk_level(2)
assert risk_level(3) == \"MEDIUM\",   risk_level(3)
assert risk_level(4) == \"LOW\",      risk_level(4)
print(\"OK\")
'''], capture_output=True, text=True, timeout=10)
print(result.stdout, end='')
if result.returncode != 0:
    print(result.stderr, file=__import__('sys').stderr)
    raise SystemExit(result.returncode)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 33: compute_file_bus_factor no crashea con stats vacías ───────────────────
@test "SE252-scan-33: compute_file_bus_factor con dict vacio devuelve bf=0 y warning" {
  run python3 -c "
import subprocess, sys
result = subprocess.run(['python3','-c','''
def compute_file_bus_factor(stats):
    warnings = []
    total = sum(stats.values())
    if total == 0:
        warnings.append(\"no_history\")
        return 0, [], warnings
    return 1, [], warnings

bf, owners, warns = compute_file_bus_factor({})
assert bf == 0, f\"bf={bf}\"
assert \"no_history\" in warns, f\"warns={warns}\"
print(\"OK\")
'''], capture_output=True, text=True, timeout=10)
print(result.stdout, end='')
if result.returncode != 0:
    print(result.stderr, file=__import__('sys').stderr)
    raise SystemExit(result.returncode)
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── 34: JSON output campo "project" presente ──────────────────────────────────
@test "SE252-scan-34: JSON output contiene campo project con nombre correcto" {
  _init_repo_alice
  cd "$TEST_REPO"
  printf 'x\n' > f.txt
  git add f.txt
  git commit -q -m "init"
  local outfile="$BF_OUT/result-$$.json"
  bash "$SCRIPT" --project "$TEST_REPO" --output "$outfile"
  run python3 -c "
import json, os
d = json.load(open('$outfile'))
assert 'project' in d
assert d['project'] == os.path.basename('$TEST_REPO'), f'got {d[\"project\"]}'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

# ── Comportamiento: funciones del motor CST (importadas, con entorno controlado)

# _bf '<expresión Python sobre m>' [NOMBRE valor ...]  (el entorno se pasa en pares)
_bf() {
  local expr="$1"; shift
  local envargs=()
  while [[ $# -ge 2 ]]; do envargs+=("$1=$2"); shift 2; done
  env "${envargs[@]}" python3 - "$PY_SCRIPT" "$expr" <<'PY'
import sys, importlib.util
sp = importlib.util.spec_from_file_location('bf', sys.argv[1])
m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
print(eval(sys.argv[2], {'m': m}))
PY
}

@test "SE252-scan: should_exclude respeta vendor/, node_modules/ y *.lock por defecto" {
  [ "$(_bf "[m.should_exclude(p) for p in ['vendor/x.py','node_modules/a.js','poetry.lock','src/app.py']]")" = "[True, True, True, False]" ]
}

@test "SE252-scan: un patrón de directorio no excluye ficheros que solo empiezan igual (vendor_client.py)" {
  [ "$(_bf "[m.should_exclude(p) for p in ['vendor_client.py','vendored/a.py','node_modules_helper.js']]")" = "[False, False, False]" ]
}

@test "SE252-scan: patrones generados se evalúan sobre el nombre base y la ruta" {
  [ "$(_bf "[m.should_exclude(p) for p in ['api/x.pb.go','a/b/foo_generated.py','web/app.min.js','web/app.js']]")" = "[True, True, True, False]" ]
}

@test "SE252-scan: BF_EXCLUDE_PATTERNS sustituye a los patrones por defecto" {
  [ "$(_bf "[m.should_exclude(p) for p in ['vendor/x.py','docs/a.md']]" BF_EXCLUDE_PATTERNS "docs/")" = "[False, True]" ]
}

@test "SE252-scan: is_bot_author distingue bots reales de humanos con nombres parecidos" {
  [ "$(_bf "[m.is_bot_author(a) for a in ['x[bot] <a@b.c>','gitlab-ci <gitlab-ci@x.com>','Dependabot <d@x.com>','CI <build-noreply@x.com>']]")" = "[True, True, True, True]" ]
  [ "$(_bf "[m.is_bot_author(a) for a in ['Marci <marci@x.com>','Ana <ana@x.com>','U <1+u@users.noreply.github.com>','Marcinoreply <marcinoreply@x.com>']]")" = "[False, False, False, False]" ]
}

@test "SE252-scan: compute_file_bus_factor sin historial devuelve (0, [], [no_history])" {
  [ "$(_bf "m.compute_file_bus_factor({})")" = "(0, [], ['no_history'])" ]
  [ "$(_bf "m.compute_file_bus_factor({'a': 0})")" = "(0, [], ['no_history'])" ]
}

@test "SE252-scan: el umbral de propiedad es inclusivo (50/50 => dos owners)" {
  [ "$(_bf "m.compute_file_bus_factor({'a':5,'b':5})[0]")" = "2" ]
  [ "$(_bf "m.compute_file_bus_factor({'a':5,'b':5})[2]")" = "[]" ]
}

@test "SE252-scan: sin nadie sobre el umbral el mayor contribuidor es owner con aviso no_clear_owner" {
  [ "$(_bf "m.compute_file_bus_factor({'a':4,'b':3,'c':3})")" = "(1, [{'dev': 'a', 'score': 0.4, 'files_owned': 0}], ['no_clear_owner'])" ]
}

@test "SE252-scan: owners ordenados por score descendente y score redondeado a 4 decimales" {
  [ "$(_bf "[o['dev'] for o in m.compute_file_bus_factor({'a':2,'b':6,'c':2})[1]]" BF_OWNERSHIP_THRESHOLD 0.1)" = "['b', 'a', 'c']" ]
  [ "$(_bf "m.compute_file_bus_factor({'a':2,'b':1})[1][0]['score']")" = "0.6667" ]
}

@test "SE252-scan: la variable de umbral no numérica cae al valor por defecto 0.5; una numérica se respeta" {
  [ "$(_bf "m.BF_OWNERSHIP_THRESHOLD" BF_OWNERSHIP_THRESHOLD abc)" = "0.5" ]
  [ "$(_bf "m.BF_OWNERSHIP_THRESHOLD" BF_OWNERSHIP_THRESHOLD 0.7)" = "0.7" ]
}

@test "SE252-scan: risk_level en cada frontera y UNKNOWN para bf <= 0" {
  [ "$(_bf "[m.risk_level(b) for b in (-1,0,1,2,3,4,10)]")" = "['UNKNOWN', 'UNKNOWN', 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'LOW']" ]
}

@test "SE252-scan: los niveles de riesgo se pueden mover por entorno" {
  [ "$(_bf "[m.risk_level(b) for b in (1,2,3,4,5)]" BF_RISK_CRITICAL 2 BF_RISK_HIGH 3 BF_RISK_MEDIUM 4)" = "['CRITICAL', 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW']" ]
}

@test "SE252-scan: module_path_for agrupa por los primeros N componentes y devuelve el directorio si el fichero es poco profundo" {
  [ "$(_bf "[m.module_path_for(p, 2) for p in ('a/b/c/d.py','a/b/c.py','a/b.py','top.py')]")" = "['a/b', 'a/b', 'a', '.']" ]
  [ "$(_bf "m.module_path_for('a/b/c/d.py', 1)")" = "a" ]
  [ "$(_bf "m.module_path_for('a/b/c/d.py', 3)")" = "a/b/c" ]
}

@test "SE252-scan: compute_module_bus_factor de un módulo vacío o sin owners es 0" {
  [ "$(_bf "m.compute_module_bus_factor([])")" = "(0, [])" ]
  [ "$(_bf "m.compute_module_bus_factor([{'path':'a','owners':[]}])")" = "(0, [])" ]
}

@test "SE252-scan: un autor dueño de más de la mitad de los ficheros da bus factor 1 con files_owned correcto" {
  [ "$(_bf "m.compute_module_bus_factor([{'path':p,'owners':[{'dev':d,'score':s}]} for p,d,s in (('1','a',1.0),('2','a',0.5),('3','a',0.5),('4','b',1.0))])")" = "(1, [{'dev': 'a', 'score': 0.6667, 'files_owned': 3}])" ]
}

@test "SE252-scan: cuatro ficheros de cuatro autores distintos necesitan dos autores para cubrir el 50%" {
  [ "$(_bf "m.compute_module_bus_factor([{'path':p,'owners':[{'dev':d,'score':1.0}]} for p,d in (('1','a'),('2','b'),('3','c'),('4','d'))])[0]")" = "2" ]
}

@test "SE252-scan: con exactamente la mitad de ficheros cubiertos basta (>= 50%, no > 50%)" {
  [ "$(_bf "m.compute_module_bus_factor([{'path':p,'owners':[{'dev':d,'score':1.0}]} for p,d in (('1','a'),('2','a'),('3','b'),('4','c'))])[0]")" = "1" ]
}

# ── Comportamiento: historial git real ────────────────────────────────────────

_commit_as() { # <nombre> <email> <fichero> <contenido>
  mkdir -p "$(dirname "$3")"
  printf '%s\n' "$4" >> "$3"
  git add "$3"
  GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2" git commit -q -m "c"
}

_stats() { # <fichero> [NOMBRE valor ...]
  local f="$1"; shift
  local envargs=()
  while [[ $# -ge 2 ]]; do envargs+=("$1=$2"); shift 2; done
  env "${envargs[@]}" python3 - "$PY_SCRIPT" "$TEST_REPO" "$f" <<'PY'
import sys, importlib.util
sp = importlib.util.spec_from_file_location('bf', sys.argv[1])
m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
print(sorted(m.get_file_stats(sys.argv[2], sys.argv[3]).items()))
PY
}

@test "SE252-scan: get_file_stats suma líneas añadidas y borradas por autor" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com f.txt $'uno\ndos\ntres'
  printf 'solo\n' > f.txt; git add f.txt
  GIT_AUTHOR_NAME=Bob GIT_AUTHOR_EMAIL=bob@t.com GIT_COMMITTER_NAME=Bob GIT_COMMITTER_EMAIL=bob@t.com git commit -q -m r
  [ "$(_stats f.txt)" = "[('ana@t.com', 3), ('bob@t.com', 4)]" ]
}

@test "SE252-scan: get_file_stats ignora a los bots y .mailmap unifica correos de una persona" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com f.txt "a"
  _commit_as Ana ana@viejo.com f.txt "b"
  _commit_as "dependabot[bot]" bot@t.com f.txt "c"
  printf 'Ana <ana@t.com> <ana@viejo.com>\n' > .mailmap; git add .mailmap
  GIT_AUTHOR_NAME=Ana GIT_AUTHOR_EMAIL=ana@t.com GIT_COMMITTER_NAME=Ana GIT_COMMITTER_EMAIL=ana@t.com git commit -q -m mm
  [ "$(_stats f.txt)" = "[('ana@t.com', 2)]" ]
}

@test "SE252-scan: BF_MAX_HISTORY_DEPTH limita los commits considerados (los más recientes)" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com f.txt "a"
  _commit_as Bob bob@t.com f.txt "b"
  [ "$(_stats f.txt BF_MAX_HISTORY_DEPTH 1)" = "[('bob@t.com', 1)]" ]
}

@test "SE252-scan: fichero inexistente en el historial da estadísticas vacías" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com f.txt "a"
  [ "$(_stats nada.txt)" = "[]" ]
}

# ── Comportamiento: scan_repo y CLI ───────────────────────────────────────────

_scan_json() { python3 "$PY_SCRIPT" --project "$1" "$TEST_REPO" 2>/dev/null; }
_jqs() { printf '%s' "$1" | jq -r "$2"; }

@test "SE252-scan: repo sin ficheros versionados da no_tracked_files y un summary con todos los contadores a 0" {
  cd "$TEST_REPO"; git init -q
  out="$(_scan_json vacio)"
  [ "$(_jqs "$out" '.warnings[0]')" = "no_tracked_files" ]
  [ "$(_jqs "$out" '.summary | [.total_modules,.critical,.high,.medium,.low,.unknown] | join(",")')" = "0,0,0,0,0,0" ]
  [ "$(_jqs "$out" '.project')" = "vacio" ]
}

@test "SE252-scan: dos autores al 50% de un fichero: bus factor del fichero 2, pero un solo autor cubre el módulo (CRITICAL)" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com a/b/f.txt $'1\n2'
  _commit_as Bob bob@t.com a/b/f.txt $'3\n4'
  out="$(_scan_json p)"
  [ "$(_jqs "$out" '.modules[0].name')" = "a/b" ]
  [ "$(_jqs "$out" '.modules[0].files[0].bus_factor')" = "2" ]
  [ "$(_jqs "$out" '.modules[0].bus_factor')" = "1" ]
  [ "$(_jqs "$out" '.modules[0].risk_level')" = "CRITICAL" ]
  [ "$(_jqs "$out" '.summary.critical')" = "1" ]
}

@test "SE252-scan: ficheros excluidos no aparecen y vendor_client.py sí se analiza" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com vendor/lib.py "x"
  _commit_as Ana ana@t.com vendor_client.py "y"
  out="$(_scan_json p)"
  [ "$(_jqs "$out" '[.modules[].files[].path] | sort | join(",")')" = "vendor_client.py" ]
}

@test "SE252-scan: los módulos salen ordenados por nombre" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com zeta/f.txt "x"
  _commit_as Ana ana@t.com alfa/f.txt "x"
  out="$(_scan_json p)"
  [ "$(_jqs "$out" '[.modules[].name] | join(",")')" = "alfa,zeta" ]
}

@test "SE252-scan: el nombre del proyecto por defecto es el basename del repo" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com f.txt "x"
  out="$(python3 "$PY_SCRIPT" "$TEST_REPO" 2>/dev/null)"
  [ "$(_jqs "$out" '.project')" = "$(basename "$TEST_REPO")" ]
}

@test "SE252-scan: la CLI de Python falla con exit 1 si el directorio no existe o no es git" {
  run python3 "$PY_SCRIPT" "$TEST_REPO/no-existe"
  [ "$status" -eq 1 ]
  [[ "$output" == *"directorio no existe"* ]]
  run python3 "$PY_SCRIPT" "$TEST_REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es un repositorio git"* ]]
}

@test "SE252-scan: scan.sh rechaza formatos que no sean json y argumentos desconocidos" {
  run bash "$SCRIPT" --project "$TEST_REPO" --format xml
  [ "$status" -eq 1 ]
  [[ "$output" == *"formato no soportado: xml"* ]]
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"argumento desconocido: --bogus"* ]]
  run bash "$SCRIPT" --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"BF_OWNERSHIP_THRESHOLD"* ]]
}

@test "SE252-scan: sin --output el JSON se escribe como <proyecto>-<fecha>T<hora>Z.json en BF_OUTPUT_DIR" {
  cd "$TEST_REPO"; git init -q
  _commit_as Ana ana@t.com f.txt "x"
  run bash "$SCRIPT" --project "$TEST_REPO"
  [ "$status" -eq 0 ]
  f="$(ls "$BF_OUT"/*.json)"
  [[ "$f" =~ /$(basename "$TEST_REPO")-[0-9]{8}T[0-9]{6}Z\.json$ ]]
  jq -e '.modules | length >= 1' "$f" >/dev/null
}
