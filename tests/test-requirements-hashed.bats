#!/usr/bin/env bats
# SE-442 S5 — requisitos de Python con hashes.
# Ref: docs/specs/SE-442-ci-supply-chain-hardening.spec.md

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LOCKS=(
  "scripts/requirements-memory.lock.txt"
  ".github/requirements/ci-pytest.lock.txt"
  ".github/requirements/pip-audit.lock.txt"
)

# Imprime "linea:requisito" por cada requisito del lock sin --hash=sha256.
unhashed() {
  python3 - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split("\n")
i = 0
while i < len(lines):
    ln = lines[i]
    if re.match(r"[A-Za-z0-9]", ln):
        start, block = i, [ln]
        while block[-1].rstrip().endswith("\\") and i + 1 < len(lines):
            i += 1
            block.append(lines[i])
        if not any("--hash=sha256:" in b for b in block):
            print(f"{start + 1}:{ln}")
    i += 1
PY
}

setup() { TMP="$(mktemp -d "$ROOT/.tmp-hashed.XXXXXX")"; }
teardown() { [[ -n "${TMP:-}" && -d "$TMP" ]] && python3 -c 'import shutil,sys;shutil.rmtree(sys.argv[1])' "$TMP"; }

@test "AC8: los locks reales llevan hash en cada requisito" {
  for l in "${LOCKS[@]}"; do
    [ -f "$ROOT/$l" ]
    run unhashed "$ROOT/$l"
    [ -z "$output" ]
  done
}

@test "AC9: una linea sin hash en un fixture falla y nombra la linea" {
  printf 'foo==1.0 \\\n    --hash=sha256:aa\nbar==2.0\n' > "$TMP/lock.txt"
  run unhashed "$TMP/lock.txt"
  [[ "$output" == "3:bar==2.0" ]]
}

@test "AC8: install-memory-deps.sh instala con --require-hashes y --only-binary" {
  run grep -c -- '--require-hashes' "$ROOT/scripts/install-memory-deps.sh"
  [ "$output" -ge 1 ]
  grep -q -- '--only-binary=:all:' "$ROOT/scripts/install-memory-deps.sh"
  grep -q 'requirements-memory.lock.txt' "$ROOT/scripts/install-memory-deps.sh"
}

@test "AC9: ningun pip install de workflows sin hashes salvo excepciones registradas" {
  # Excepciones: evals-ci.yaml (el fallo se tolera a proposito, `|| true`) y la
  # plantilla pr-agent-review.yml (version parametrizada por el consumidor).
  run bash -c "cd '$ROOT' && grep -rnE 'pip3? install|-m pip install' .github/workflows \
    | grep -vE 'require-hashes|evals-ci\.yaml|templates/pr-agent-review\.yml'"
  [ -z "$output" ]
}

# ── Comportamiento discriminante (S03 calidad) ───────────────────────────────

INSTALL="scripts/install-memory-deps.sh"

# 64 hex para fixtures de hash.
H64() { printf '%s' "$1" | head -c1 | python3 -c 'import sys; print(sys.stdin.read()*64, end="")'; }

# Entorno simulado: un "python del sistema" que crea un venv cuyo python registra
# cada invocación, sin instalar nada.
mk_fake_python() {
  FAKE="$TMP/fake"; mkdir -p "$FAKE"
  cat > "$FAKE/syspython" <<'EOF'
#!/usr/bin/env bash
# python del sistema simulado: solo entiende `-m venv DIR`
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  mkdir -p "$3/bin"
  cat > "$3/bin/python" <<'INNER'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
if [[ -n "${FAKE_FAIL_ON:-}" && "$*" == *"$FAKE_FAIL_ON"* ]]; then exit 1; fi
exit 0
INNER
  chmod +x "$3/bin/python"
  [[ -n "${FAKE_NO_VENV_PYTHON:-}" ]] && unlink "$3/bin/python"
  exit 0
fi
exit 0
EOF
  chmod +x "$FAKE/syspython"
  export FAKE_LOG="$TMP/log.txt"; : > "$FAKE_LOG"
  export SAVIA_SYSTEM_PYTHON="$FAKE/syspython" SAVIA_VENV_DIR="$TMP/venv"
}

@test "unhashed: comments, empty lines and options (--index-url) are ignored" {
  printf '# comentario\n\n--index-url https://example.invalid/simple\n  # via x\n' > "$TMP/l.txt"
  run unhashed "$TMP/l.txt"
  [ -z "$output" ]
}

@test "unhashed: acepta un requisito con varias líneas de hash y marcador de entorno" {
  printf 'foo==1.0 ; sys_platform != "win32" \\\n    --hash=sha256:%s \\\n    --hash=sha256:%s\n    # via bar\n' "$(H64 a)" "$(H64 b)" > "$TMP/l.txt"
  run unhashed "$TMP/l.txt"
  [ -z "$output" ]
}

@test "unhashed: señala solo el requisito sin hash entre varios (línea exacta)" {
  printf 'a==1 \\\n    --hash=sha256:%s\nb==2\nc==3 \\\n    --hash=sha256:%s\n' "$(H64 a)" "$(H64 c)" > "$TMP/l.txt"
  run unhashed "$TMP/l.txt"
  [ "$output" = "3:b==2" ]
}

@test "unhashed: una línea de continuación sin hash tras la barra también falla" {
  printf 'a==1 \\\n    --no-binary\n' > "$TMP/l.txt"
  run unhashed "$TMP/l.txt"
  [ "$output" = "1:a==1 \\" ]
}

@test "unhashed: an empty lock has no unhashed requirements" {
  : > "$TMP/l.txt"
  run unhashed "$TMP/l.txt"
  [ -z "$output" ]
}

@test "los locks reales fijan cada requisito con == (sin rangos)" {
  for l in "${LOCKS[@]}"; do
    run bash -c "grep -hE '^[A-Za-z0-9]' '$ROOT/$l' | grep -v '=='"
    [ -z "$output" ]
  done
}

@test "los locks reales no tienen hashes malformados (sha256 de 64 hex)" {
  for l in "${LOCKS[@]}"; do
    run bash -c "grep -ho -- '--hash=sha256:[^ ]*' '$ROOT/$l' | grep -vE '^--hash=sha256:[0-9a-f]{64}\$'"
    [ -z "$output" ]
  done
}

@test "install: pip se invoca con require-hashes, solo binarios, índice CPU de torch y el lock" {
  mk_fake_python
  run bash "$ROOT/$INSTALL"
  [ "$status" -eq 0 ]
  line="$(grep -- '-m pip install --require-hashes' "$FAKE_LOG")"
  [[ "$line" == *"--only-binary=:all:"* ]]
  [[ "$line" == *"--extra-index-url https://download.pytorch.org/whl/cpu"* ]]
  [[ "$line" == *"-r $ROOT/scripts/requirements-memory.lock.txt"* ]]
}

@test "install: orden upgrade pip → install con hashes → pip check → verificación de torch sin CUDA" {
  mk_fake_python
  run bash "$ROOT/$INSTALL"
  [ "$status" -eq 0 ]
  [[ "$(sed -n 1p "$FAKE_LOG")" == "-m pip install --upgrade pip" ]]
  [[ "$(sed -n 2p "$FAKE_LOG")" == "-m pip install --require-hashes"* ]]
  [[ "$(sed -n 3p "$FAKE_LOG")" == "-m pip check" ]]
  [[ "$(sed -n 4p "$FAKE_LOG")" == *"assert not torch.cuda.is_available()"* ]]
  [[ "$output" == *"Memory dependencies installed: $TMP/venv/bin/python"* ]]
}

@test "install: si pip falla en la instalación con hashes aborta sin pip check ni mensaje de éxito" {
  mk_fake_python
  FAKE_FAIL_ON="--require-hashes" run bash "$ROOT/$INSTALL"
  [ "$status" -ne 0 ]
  [[ "$output" != *"installed"* ]]
  ! grep -q -- '-m pip check' "$FAKE_LOG"
}

@test "install: si falla la verificación de CUDA/torch sale con error sin anunciar éxito" {
  mk_fake_python
  FAKE_FAIL_ON="torch.cuda" run bash "$ROOT/$INSTALL"
  [ "$status" -ne 0 ]
  [[ "$output" != *"installed"* ]]
}

@test "install: nonexistent system python fails with ERROR and creates no venv" {
  SAVIA_SYSTEM_PYTHON="$TMP/no-existe" SAVIA_VENV_DIR="$TMP/venv" run bash "$ROOT/$INSTALL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: Python 3 not found"* ]]
  [[ ! -e "$TMP/venv" ]]
}

@test "install: venv sin python ejecutable falla con ERROR" {
  mk_fake_python
  FAKE_NO_VENV_PYTHON=1 run bash "$ROOT/$INSTALL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"venv Python not found"* ]]
}

@test "install: el venv por defecto está bajo ~/.savia y no en el repo" {
  grep -q 'VENV_DIR="${SAVIA_VENV_DIR:-$HOME/.savia/venv}"' "$ROOT/$INSTALL"
}

@test "install: usa modo estricto de bash (set -euo pipefail)" {
  grep -q '^set -euo pipefail' "$ROOT/$INSTALL"
}
