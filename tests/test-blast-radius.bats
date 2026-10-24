#!/usr/bin/env bats
# tests/test-blast-radius.bats — SE-318: Blast-radius pre-commit (S1-S3).
# Ref: docs/propuestas/SE-318-blast-radius-precommit.md (AC-S1, AC-S2, AC-S3)

BLAST="scripts/blast-radius.sh"
HOOK=".claude/hooks/blast-radius-hook.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPD="${BATS_TEST_TMPDIR}"
  mkdir -p "$TMPD"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR" 2>/dev/null || true
  cd /
}

# ── Fixture: mini-repo git con símbolos y callers ──────────────────────────
make_repo() { # dir
  local repo="$1"
  mkdir -p "$repo"
  ( cd "$repo" && git init -q && git config user.email "test@example.com" && git config user.name "Test" )
  cat > "$repo/lib.py" <<'EOF'
def public_api(x):
    return x * 2

def helper():
    return public_api(1)
EOF
  cat > "$repo/app.py" <<'EOF'
from lib import public_api

def main():
    return public_api(5)
EOF
  cat > "$repo/other.py" <<'EOF'
def standalone():
    return 42
EOF
  ( cd "$repo" && git add . && git commit -qm "init" )
}

# ── S1: consulta de símbolo ────────────────────────────────────────────────

@test "S1.1: blast-radius.sh existe, es ejecutable y usa pipefail" {
  [[ -f "$BLAST" ]]
  [[ -x "$BLAST" ]]
  run grep -c 'set -uo pipefail' "$BLAST"
  [[ "$output" -ge 1 ]]
}

@test "AC-S1.1: símbolo con 3 callers directos los lista en direct" {
  local repo="$TMPD/repo1"
  make_repo "$repo"
  run bash -c "cd '$repo' && bash '$BATS_TEST_DIRNAME/../scripts/blast-radius.sh' --symbol public_api"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'lib.py' in d['direct'], d
assert 'app.py' in d['direct'], d
assert d['total'] >= 2, d
"
}

@test "AC-S1.3: símbolo inexistente -> {symbol:null, files:{}}, exit 0" {
  local repo="$TMPD/repo2"
  make_repo "$repo"
  run bash -c "cd '$repo' && bash '$BATS_TEST_DIRNAME/../scripts/blast-radius.sh' --symbol zzz_never_defined_9876"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['total'] == 0, d
assert d['files'] == {}, d
"
}

# ── S2: modo diff ───────────────────────────────────────────────────────────

@test "AC-S2.1: diff que modifica 2 símbolos agrega ambos" {
  local repo="$TMPD/repo3"
  make_repo "$repo"
  # nuevo símbolo + modificación de otro
  cat >> "$repo/lib.py" <<'EOF'

def new_symbol():
    return helper()
EOF
  ( cd "$repo" && git add lib.py && git commit -qm "add new_symbol" )
  run bash -c "cd '$repo' && bash '$BATS_TEST_DIRNAME/../scripts/blast-radius.sh' --diff HEAD~1..HEAD"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'new_symbol' in d['symbols'], d
assert d['mode'] == 'diff', d
"
}

@test "AC-S2.2: diff sin símbolos detectables -> reporte vacío, exit 0" {
  local repo="$TMPD/repo4"
  make_repo "$repo"
  echo "comment only" >> "$repo/app.py"
  ( cd "$repo" && git add app.py && git commit -qm "noop" )
  run bash -c "cd '$repo' && bash '$BATS_TEST_DIRNAME/../scripts/blast-radius.sh' --diff HEAD~1..HEAD"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['total'] == 0, d
"
}

# ── S3: integración ─────────────────────────────────────────────────────────

@test "AC-S3.1: hook pre-write muestra AFFECTED sin bloquear (exit 0)" {
  local repo="$TMPD/repo5"
  make_repo "$repo"
  run bash -c "cd '$repo' && SAVIA_BLAST_RADIUS=on bash '$BATS_TEST_DIRNAME/../.claude/hooks/blast-radius-hook.sh' --file lib.py"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"AFFECTED"* ]]
}

@test "AC-S3.1b: hook con switch off no hace nada (Rule #19)" {
  local repo="$TMPD/repo6"
  make_repo "$repo"
  run bash -c "cd '$repo' && bash '$BATS_TEST_DIRNAME/../.claude/hooks/blast-radius-hook.sh' --file lib.py"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "AC-S3.3: blast.radius aparece en telemetry-events.jsonl" {
  local repo="$TMPD/repo7"
  make_repo "$repo"
  run bash -c "cd '$repo' && SAVIA_TELEMETRY_FILE='$TMPD/tl.jsonl' bash '$BATS_TEST_DIRNAME/../scripts/blast-radius.sh' --symbol public_api"
  [[ -f "$TMPD/tl.jsonl" ]]
  run grep -c 'blast.radius' "$TMPD/tl.jsonl"
  [[ "$output" -ge 1 ]]
}

# ── Seguridad ───────────────────────────────────────────────────────────────

@test "S5.1: no introduce secrets ni IPs internas" {
  run grep -rnE "AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32,}|192\.168\.|10\.([0-9]{1,3}\.){2}" scripts/blast-radius.sh .claude/hooks/blast-radius-hook.sh
  [[ -z "$output" ]]
}

# ── Hook pre-write: interruptor, filtros de ruta, extraccion de simbolos y mensajes ────────

# hookenv: arbol temporal con el hook, un blast-radius simulado y un repo git con un fichero de ejemplo
hookenv() {
  H="$BATS_TEST_TMPDIR/h"; mkdir -p "$H/.claude/hooks" "$H/scripts" "$H/repo"
  cp "$BATS_TEST_DIRNAME/../.claude/hooks/blast-radius-hook.sh" "$H/.claude/hooks/"
  BLASTLOG="$H/blast.log"; : > "$BLASTLOG"
  cat > "$H/scripts/blast-radius.sh" <<EOS
#!/usr/bin/env bash
echo "\$2" >> "$BLASTLOG"
case "\$2" in
  alfa) echo '{"total": 3}' ;;
  gamma) echo '{"total": 5}' ;;
  uno) echo '{"total": 1}' ;;
  roto) echo 'esto no es json' ;;
  *) echo '{"total": 0}' ;;
esac
EOS
  chmod +x "$H/scripts/blast-radius.sh"
  ( cd "$H/repo" && git init -q && git config user.email t@example.com && git config user.name T )
  printf 'def alfa():\n    return 1\n\ndef beta():\n    return 2\n' > "$H/repo/lib.py"
  ( cd "$H/repo" && git add . && git commit -qm init )
}
# runhook <args...>: ejecuta el hook dentro del repo de ejemplo con el interruptor encendido; stdin vacio
runhook() { ( cd "$H/repo" && SAVIA_BLAST_RADIUS=on bash "$H/.claude/hooks/blast-radius-hook.sh" "$@" 2>&1 </dev/null ); }

@test "hook: solo el valor exacto on activa el interruptor" {
  hookenv
  for v in "" off ON 1 true yes; do
    out=$( cd "$H/repo" && SAVIA_BLAST_RADIUS="$v" bash "$H/.claude/hooks/blast-radius-hook.sh" --file lib.py 2>&1 </dev/null )
    [ -z "$out" ] || { echo "activo con '$v'"; return 1; }
  done
  out=$( cd "$H/repo" && bash "$H/.claude/hooks/blast-radius-hook.sh" --file lib.py 2>&1 </dev/null )
  [ -z "$out" ]
}

@test "hook: avisa solo de los simbolos con dependientes y con su recuento" {
  hookenv
  run runhook --file lib.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"AFFECTED: 'alfa' → 3 fichero(s) dependientes"* ]]
  [[ "$output" != *"'beta'"* ]]
  [[ "$output" != *"usa 'scripts/blast-radius.sh --diff"* ]]
}

@test "hook: consulta blast-radius una vez por cada simbolo definido en el fichero" {
  hookenv
  runhook --file lib.py >/dev/null
  [ "$(sort "$BLASTLOG" | tr '\n' ' ')" = "alfa beta " ]
}

@test "hook: sin simbolos con dependientes muestra la sugerencia de --diff" {
  hookenv
  printf 'def beta():\n    return 2\n' > "$H/repo/solo.py"; ( cd "$H/repo" && git add solo.py && git commit -qm s )
  run runhook --file solo.py
  [ "$status" -eq 0 ]
  [ "$output" = "AFFECTED: usa 'scripts/blast-radius.sh --diff origin/main..HEAD' para ver el impacto del cambio (SE-318)" ]
}

@test "hook: reconoce definiciones de varios lenguajes" {
  hookenv
  cat > "$H/repo/multi.js" <<'EOS'
function gamma() {}
class Delta {}
EOS
  printf 'func epsilon() {}\nfn zeta() {}\nsub eta { }\nfoo_sh() {\n  :\n}\n' > "$H/repo/multi.go"
  ( cd "$H/repo" && git add . && git commit -qm m )
  runhook --file multi.js >/dev/null
  runhook --file multi.go >/dev/null
  for s in gamma Delta epsilon zeta eta foo_sh; do
    grep -qx "$s" "$BLASTLOG" || { echo "no consulto $s"; return 1; }
  done
}

@test "hook: varios simbolos con dependientes producen un aviso por simbolo" {
  hookenv
  printf 'def alfa():\n    pass\n\ndef gamma():\n    pass\n' > "$H/repo/dos.py"; ( cd "$H/repo" && git add . && git commit -qm d )
  run runhook --file dos.py
  [[ "$output" == *"'alfa' → 3 fichero(s)"* ]]
  [[ "$output" == *"'gamma' → 5 fichero(s)"* ]]
  [ "$(grep -c '^AFFECTED' <<< "$output")" -eq 2 ]
}

@test "hook: un fichero que no existe sigue dando la sugerencia y no consulta simbolos" {
  hookenv
  run runhook --file no_existe.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"usa 'scripts/blast-radius.sh --diff"* ]]
  [ ! -s "$BLASTLOG" ]
}

@test "hook: extensiones que no son de codigo se ignoran en silencio" {
  hookenv
  for f in notas.md datos.json texto.txt Makefile imagen.png; do
    : > "$H/repo/$f"
    run runhook --file "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "avisa con $f"; return 1; }
  done
}

@test "hook: todas las extensiones de codigo declaradas se procesan" {
  hookenv
  for e in sh py ts js tsx jsx java cs go rb php rs vue svelte c cpp h hpp; do
    run runhook --file "x.$e"
    [[ "$output" == *"AFFECTED"* ]] || { echo "ignora .$e"; return 1; }
  done
}

@test "hook: rutas bajo /tmp, /var y /etc se ignoran aunque sean de codigo" {
  hookenv
  for p in /tmp/x.py /var/x.py /etc/x.py; do
    run runhook --file "$p"
    [ -z "$output" ] || { echo "avisa con $p"; return 1; }
  done
}

@test "hook: lee file_path, filePath y path del JSON de stdin" {
  hookenv
  for k in file_path filePath path; do
    out=$( cd "$H/repo" && printf '{"tool_input":{"%s":"lib.py"}}' "$k" | SAVIA_BLAST_RADIUS=on bash "$H/.claude/hooks/blast-radius-hook.sh" 2>&1 )
    [[ "$out" == *"'alfa' → 3"* ]] || { echo "no lee $k"; return 1; }
  done
}

@test "hook: JSON sin ruta, JSON roto o stdin vacio no avisan" {
  hookenv
  for in in '{"tool_input":{}}' 'no es json' ''; do
    out=$( cd "$H/repo" && printf '%s' "$in" | SAVIA_BLAST_RADIUS=on bash "$H/.claude/hooks/blast-radius-hook.sh" 2>&1 )
    [ -z "$out" ] || { echo "avisa con '$in'"; return 1; }
  done
}

@test "hook: --file tiene prioridad sobre stdin" {
  hookenv
  out=$( cd "$H/repo" && printf '{"tool_input":{"file_path":"otro.py"}}' | SAVIA_BLAST_RADIUS=on bash "$H/.claude/hooks/blast-radius-hook.sh" --file lib.py 2>&1 )
  [[ "$out" == *"'alfa'"* ]]
}

@test "hook: fuera de un repo git no hace nada" {
  hookenv
  mkdir -p "$H/sin-git"; printf 'def alfa():\n  pass\n' > "$H/sin-git/lib.py"
  out=$( cd "$H/sin-git" && GIT_CEILING_DIRECTORIES="$H" SAVIA_BLAST_RADIUS=on bash "$H/.claude/hooks/blast-radius-hook.sh" --file lib.py 2>&1 </dev/null )
  [ -z "$out" ]
}

@test "hook: nunca bloquea, ni con una respuesta no JSON de blast-radius ni con blast-radius roto" {
  hookenv
  printf 'def roto():\n  pass\n' > "$H/repo/r.py"; ( cd "$H/repo" && git add . && git commit -qm r )
  run runhook --file r.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"usa 'scripts/blast-radius.sh --diff"* ]]
  printf '#!/usr/bin/env bash\nexit 7\n' > "$H/scripts/blast-radius.sh"
  run runhook --file lib.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"usa 'scripts/blast-radius.sh --diff"* ]]
}

@test "hook: el aviso va a stderr, no a stdout" {
  hookenv
  out=$( cd "$H/repo" && SAVIA_BLAST_RADIUS=on bash "$H/.claude/hooks/blast-radius-hook.sh" --file lib.py 2>/dev/null </dev/null )
  [ -z "$out" ]
}

@test "hook: un solo fichero dependiente tambien se avisa" {
  hookenv
  printf 'def uno():\n    pass\n' > "$H/repo/uno.py"; ( cd "$H/repo" && git add . && git commit -qm u )
  run runhook --file uno.py
  [[ "$output" == *"AFFECTED: 'uno' → 1 fichero(s) dependientes"* ]]
  [[ "$output" != *"usa 'scripts/blast-radius.sh --diff"* ]]
}

@test "hook: una ruta absoluta dentro del repo se relativiza antes de consultar git" {
  hookenv
  # las rutas bajo /tmp, /var y /etc se ignoran por diseño: el repo vive en /dev/shm
  [ -d /dev/shm ] && [ -w /dev/shm ] || skip "sin /dev/shm escribible"
  ABS=$(mktemp -d -p /dev/shm)
  ( cd "$ABS" && git init -q && git config user.email t@example.com && git config user.name T \
    && printf 'def alfa():\n    pass\n' > lib.py && git add . && git commit -qm i )
  out=$( cd "$ABS" && SAVIA_BLAST_RADIUS=on bash "$H/.claude/hooks/blast-radius-hook.sh" --file "$ABS/lib.py" 2>&1 </dev/null )
  rm -r -f "$ABS"
  [[ "$out" == *"AFFECTED: 'alfa' → 3 fichero(s) dependientes"* ]]
}
