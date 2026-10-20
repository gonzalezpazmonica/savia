#!/usr/bin/env bats
# SE-442 S1 — todo `uses:` externo de .github/ va fijado a un SHA de 40 hex.
# Ref: docs/specs/SE-442-ci-supply-chain-hardening.spec.md

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Imprime "fichero:linea: contenido" por cada uses: externo sin SHA de 40 hex.
unpinned() {
  local base="$1"
  find "$base/.github/workflows" "$base/.github/actions" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null \
    | sort | while read -r f; do
      grep -nE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*' "$f" \
        | grep -vE 'uses:[[:space:]]*"?\./' \
        | grep -vE 'uses:[[:space:]]*[^[:space:]#]+@[0-9a-f]{40}([[:space:]]|$)' \
        | sed "s|^|$f:|" || true
    done
}

setup() { TMP="$(mktemp -d "$ROOT/.tmp-pinned.XXXXXX")"; }
teardown() { [[ -n "${TMP:-}" && -d "$TMP" ]] && python3 -c 'import shutil,sys;shutil.rmtree(sys.argv[1])' "$TMP"; }

@test "AC1: el arbol real no contiene uses: externos sin SHA" {
  run unpinned "$ROOT"
  [ -z "$output" ]
}

@test "AC2: un uses: con tag movil falla y nombra fichero y linea" {
  mkdir -p "$TMP/.github/workflows"
  printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@v4\n' > "$TMP/.github/workflows/x.yml"
  run unpinned "$TMP"
  [[ "$output" == *"x.yml:4:"*"actions/checkout@v4"* ]]
}

@test "AC2: un uses: local no falla" {
  mkdir -p "$TMP/.github/workflows"
  printf 'jobs:\n  a:\n    steps:\n      - uses: ./.github/actions/x\n' > "$TMP/.github/workflows/x.yml"
  run unpinned "$TMP"
  [ -z "$output" ]
}

@test "un SHA con comentario de version pasa" {
  mkdir -p "$TMP/.github/workflows"
  printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2\n' > "$TMP/.github/workflows/x.yml"
  run unpinned "$TMP"
  [ -z "$output" ]
}

@test "un SHA corto de 39 hex falla" {
  mkdir -p "$TMP/.github/workflows"
  printf 'jobs:\n  a:\n    steps:\n      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af68\n' > "$TMP/.github/workflows/x.yml"
  run unpinned "$TMP"
  [ -n "$output" ]
}

@test "AC3: grep del spec no devuelve lineas" {
  run bash -c "cd '$ROOT' && grep -rE 'uses: [^./][^ ]*@' .github/workflows | grep -vE '@[0-9a-f]{40}'"
  [ -z "$output" ]
}

@test "AC4: dependabot.yml valido, github-actions semanal y agrupado en *" {
  run python3 - "$ROOT/.github/dependabot.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
u = [x for x in d["updates"] if x["package-ecosystem"] == "github-actions"]
assert u and u[0]["schedule"]["interval"] == "weekly"
assert any("*" in g.get("patterns", []) for g in u[0]["groups"].values())
PY
  [ "$status" -eq 0 ]
}

@test "AC5: codeql.yml y scorecard.yml existen y son YAML valido" {
  for f in codeql scorecard; do
    python3 -c 'import sys,yaml;yaml.safe_load(open(sys.argv[1]))' "$ROOT/.github/workflows/$f.yml"
  done
}

@test "AC5: codeql y scorecard declaran permissions por job" {
  for f in codeql scorecard; do
    grep -q '^permissions:' "$ROOT/.github/workflows/$f.yml"
    grep -q 'security-events: write' "$ROOT/.github/workflows/$f.yml"
  done
}

@test "AC6: SECURITY.md tiene las tres secciones" {
  run grep -cE '^## (Plazo de embargo|Crédito|Releases de seguridad)$' "$ROOT/SECURITY.md"
  [ "$output" -eq 3 ]
}
