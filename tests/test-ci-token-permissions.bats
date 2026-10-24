#!/usr/bin/env bats
# SE-442 S3 — permisos del GITHUB_TOKEN: todo workflow declara `permissions:` a
# nivel superior, sin escritura (la escritura va por job), y CodeQL usa su config.
# Ref: docs/specs/SE-442-ci-supply-chain-hardening.spec.md

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Imprime los workflows sin bloque permissions: de nivel superior, o con escritura en él,
# y los jobs que escriben en GitHub (API, gh, git push) sin declarar permiso de escritura
# propio. Al final imprime "evaluados=N" para que un glob vacío no pase en falso.
offenders() {
  python3 - "$1" <<'PY'
import sys, glob, re, yaml
WRITE = re.compile(r"github\.rest\.\w+\.(create|update|delete|add|remove|merge)\w*"
                   r"|gh (pr (create|edit|comment|merge|close)|issue (create|comment|edit|close)|release create)\b"
                   r"|^\s*git push\b", re.M)
def code(steps):
    out = []
    for st in steps or []:
        out.append(str(st.get("run", "")))
        out.append(str((st.get("with") or {}).get("script", "")))
    return "\n".join(out)
def writes(p):
    return p == "write-all" or (isinstance(p, dict) and any(v == "write" for v in p.values()))
files = sorted(glob.glob(sys.argv[1] + "/.github/workflows/*.y*ml"))
for f in files:
    d = yaml.safe_load(open(f)) or {}
    p = d.get("permissions")
    if p is None:
        print(f"{f}: sin permissions de nivel superior")
    elif writes(p):
        print(f"{f}: permissions de nivel superior con escritura")
    for name, job in (d.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        if WRITE.search(code(job.get("steps"))) and not writes(job.get("permissions")):
            print(f"{f}: job {name} escribe en GitHub sin permiso de escritura propio")
print(f"evaluados={len(files)}")
PY
}

setup() { TMP="$(mktemp -d "$ROOT/.tmp-perm.XXXXXX")"; mkdir -p "$TMP/.github/workflows"; }
teardown() { [[ -n "${TMP:-}" && -d "$TMP" ]] && python3 -c 'import shutil,sys;shutil.rmtree(sys.argv[1])' "$TMP"; }

@test "el arbol real: permissions de nivel superior presentes y sin escritura" {
  run offenders "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ evaluados=([0-9]+)$ ]]
  [ "${BASH_REMATCH[1]}" -gt 0 ]
  [ "$(printf '%s\n' "$output" | grep -vc '^evaluados=')" -eq 0 ]
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
  run python3 -c 'import yaml,sys
d=yaml.safe_load(open(sys.argv[1]))
steps=[s for j in d["jobs"].values() for s in j["steps"] if str(s.get("uses","")).split("@")[0].endswith("codeql-action/init")]
print(steps[0]["with"]["config-file"])' "$ROOT/.github/workflows/codeql.yml"
  [ "$output" = "./.github/codeql/codeql-config.yml" ]
  run python3 -c 'import yaml,sys;print("\n".join(yaml.safe_load(open(sys.argv[1]))["paths-ignore"]))' "$ROOT/.github/codeql/codeql-config.yml"
  [ "$output" = "$(printf 'tests/pentest-lab/mock-*\ntests/fixtures/security-benchmark')" ]
}

@test "negativo: un job que comenta en PR sin permiso de escritura propio falla" {
  printf 'on: push\npermissions:\n  contents: read\njobs:\n  c:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/github-script@x\n        with:\n          script: await github.rest.issues.createComment({})\n' > "$TMP/.github/workflows/z.yml"
  run offenders "$TMP"
  [[ "$output" == *"z.yml: job c escribe en GitHub sin permiso"* ]]
}

@test "un job que escribe con su permiso propio no se marca" {
  printf 'on: push\npermissions:\n  contents: read\njobs:\n  c:\n    runs-on: ubuntu-latest\n    permissions:\n      issues: write\n    steps:\n      - run: gh issue create --title x\n' > "$TMP/.github/workflows/w.yml"
  run offenders "$TMP"
  [[ "$output" != *"escribe en GitHub"* ]]
}

@test "negativo: workflow vacio no rompe el analisis y se marca" {
  : > "$TMP/.github/workflows/e.yml"
  run offenders "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"e.yml: sin permissions"* ]]
}
