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
