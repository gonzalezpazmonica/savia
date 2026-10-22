#!/usr/bin/env bats
# SE-442 S3 — permisos del GITHUB_TOKEN: todo workflow declara `permissions:` a
# nivel superior, sin escritura (la escritura va por job), y CodeQL usa su config.
# Ref: docs/specs/SE-442-ci-supply-chain-hardening.spec.md

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Imprime los workflows sin bloque permissions: de nivel superior, o con escritura en él.
offenders() {
  python3 - "$1" <<'PY'
import sys, glob, yaml
for f in sorted(glob.glob(sys.argv[1] + "/.github/workflows/*.y*ml")):
    d = yaml.safe_load(open(f))
    p = d.get("permissions")
    if p is None:
        print(f"{f}: sin permissions de nivel superior")
    elif p == "write-all" or (isinstance(p, dict) and any(v == "write" for v in p.values())):
        print(f"{f}: permissions de nivel superior con escritura")
PY
}

setup() { TMP="$(mktemp -d "$ROOT/.tmp-perm.XXXXXX")"; mkdir -p "$TMP/.github/workflows"; }
teardown() { [[ -n "${TMP:-}" && -d "$TMP" ]] && python3 -c 'import shutil,sys;shutil.rmtree(sys.argv[1])' "$TMP"; }

@test "el arbol real: permissions de nivel superior presentes y sin escritura" {
  run offenders "$ROOT"
  [ -z "$output" ]
}

@test "negativo: un workflow sin permissions falla y lo nombra" {
  printf 'on: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps: []\n' > "$TMP/.github/workflows/x.yml"
  run offenders "$TMP"
  [[ "$output" == *"x.yml: sin permissions"* ]]
}

@test "negativo: escritura a nivel superior falla" {
  printf 'on: push\npermissions:\n  contents: write\njobs: {}\n' > "$TMP/.github/workflows/y.yml"
  run offenders "$TMP"
  [[ "$output" == *"y.yml: permissions de nivel superior con escritura"* ]]
}

@test "codeql.yml usa la config y esta solo excluye laboratorios vulnerables a proposito" {
  grep -q 'config-file: ./.github/codeql/codeql-config.yml' "$ROOT/.github/workflows/codeql.yml"
  run python3 -c 'import yaml,sys;print("\n".join(yaml.safe_load(open(sys.argv[1]))["paths-ignore"]))' "$ROOT/.github/codeql/codeql-config.yml"
  [ "$output" = "$(printf 'tests/pentest-lab\ntests/fixtures/security-benchmark')" ]
}
