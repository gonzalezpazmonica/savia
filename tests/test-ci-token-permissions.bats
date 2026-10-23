#!/usr/bin/env bats
# Scorecard TokenPermissions (alertas #65-#70): el GITHUB_TOKEN arranca en solo
# lectura en cada workflow; la escritura se concede solo al job que la usa.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Imprime "fichero: motivo" por cada workflow con permisos de nivel superior
# ausentes o con alguna escritura.
toplevel_violations() {
  python3 - "$1" <<'PY'
import glob, sys, yaml
for f in sorted(glob.glob(sys.argv[1] + "/.github/workflows/*.y*ml")):
    perms = (yaml.safe_load(open(f)) or {}).get("permissions", "MISSING")
    if perms == "MISSING":
        print(f"{f}: sin permissions de nivel superior")
    elif isinstance(perms, str) and perms != "read-all":
        print(f"{f}: permissions={perms}")
    elif isinstance(perms, dict) and "write" in perms.values():
        print(f"{f}: escritura de nivel superior {perms}")
PY
}

setup() { TMP="$(mktemp -d "$ROOT/.tmp-tokperm.XXXXXX")"; mkdir -p "$TMP/.github/workflows"; }
teardown() { [[ -n "${TMP:-}" && -d "$TMP" ]] && python3 -c 'import shutil,sys;shutil.rmtree(sys.argv[1])' "$TMP"; }

@test "el arbol real: ningun workflow da escritura de nivel superior ni omite permissions" {
  run toplevel_violations "$ROOT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "negativo: contents: write de nivel superior se detecta" {
  printf 'permissions:\n  contents: write\njobs:\n  a:\n    runs-on: x\n' > "$TMP/.github/workflows/w.yml"
  run toplevel_violations "$TMP"
  [[ "$output" == *"w.yml: escritura de nivel superior"* ]]
}

@test "negativo: workflow sin permissions se detecta" {
  printf 'jobs:\n  a:\n    runs-on: x\n' > "$TMP/.github/workflows/w.yml"
  run toplevel_violations "$TMP"
  [[ "$output" == *"w.yml: sin permissions"* ]]
}

@test "negativo: write-all se detecta" {
  printf 'permissions: write-all\njobs:\n  a:\n    runs-on: x\n' > "$TMP/.github/workflows/w.yml"
  run toplevel_violations "$TMP"
  [[ "$output" == *"permissions=write-all"* ]]
}

@test "positivo: lectura arriba y escritura en el job pasa" {
  printf 'permissions:\n  contents: read\njobs:\n  a:\n    permissions:\n      contents: write\n    runs-on: x\n' > "$TMP/.github/workflows/w.yml"
  run toplevel_violations "$TMP"
  [ -z "$output" ]
}
