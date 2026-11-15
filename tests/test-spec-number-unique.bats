#!/usr/bin/env bats
# Dos specs no pueden compartir numero (caso origen: dos SE-334, resuelto
# renumerando la de telemetria a SE-534). Complementa scripts/spec-id-duplicates-check.sh,
# que ademas marca como duplicadas las familias SE-396/SE-397 (sub-specs a01, f1...).
# Regla: cada docs/specs/<PREFIJO>-<N>-*.spec.md es raiz de su numero salvo que su
# nombre sea una sub-spec (<PREFIJO>-<N>-<letra><digitos>-...). Duplicado historico
# congelado: SE-260 (par exacto); un tercer fichero o cualquier otro numero falla.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FROZEN="SE-260: SE-260-blast-radius.spec.md|SE-260-gentle-patterns.spec.md"

# $1 = raiz del repo. Imprime "ID: a|b" por cada numero con mas de una spec raiz.
dups() {
  local root="$1" f b id
  declare -A seen=()
  for f in "$root"/docs/specs/*.spec.md; do
    [[ -e "$f" ]] || continue
    b=$(basename "$f")
    [[ "$b" =~ ^([A-Z]+-[0-9]+)-(.+)$ ]] || continue
    id="${BASH_REMATCH[1]}"
    [[ "${BASH_REMATCH[2]}" =~ ^[A-Za-z][0-9]+[a-z]?- ]] && continue
    seen[$id]+="${seen[$id]:+|}$b"
  done
  for id in "${!seen[@]}"; do
    [[ "${seen[$id]}" == *"|"* ]] && echo "$id: $(tr '|' '\n' <<<"${seen[$id]}" | sort | paste -sd '|' -)"
  done | sort
  return 0
}

mkfix() { mkdir -p "$BATS_TEST_TMPDIR/$1/docs/specs"; echo "$BATS_TEST_TMPDIR/$1"; }

@test "repo real: ningun numero de spec compartido salvo el congelado SE-260" {
  run dups "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "$FROZEN" ]
}

@test "SE-334 queda solo en Vaults y la telemetria vive en SE-534" {
  [ -f "$REPO_ROOT/docs/specs/SE-334-vaults-scl-criteria-hardening.spec.md" ]
  [ ! -e "$REPO_ROOT/docs/specs/SE-334-telemetry-intelligence.spec.md" ]
  [ -f "$REPO_ROOT/docs/specs/SE-534-telemetry-intelligence.spec.md" ]
}

@test "negativo: dos specs raiz con el mismo numero se detectan" {
  local r; r=$(mkfix dup)
  : > "$r/docs/specs/SE-900-alfa.spec.md"; : > "$r/docs/specs/SE-900-beta.spec.md"
  run dups "$r"
  [ "$output" = "SE-900: SE-900-alfa.spec.md|SE-900-beta.spec.md" ]
}

@test "negativo: SE-260 con un tercer fichero ya no coincide con el congelado" {
  local r; r=$(mkfix tercero)
  : > "$r/docs/specs/SE-260-blast-radius.spec.md"; : > "$r/docs/specs/SE-260-gentle-patterns.spec.md"
  : > "$r/docs/specs/SE-260-otra.spec.md"
  run dups "$r"
  [ "$output" != "$FROZEN" ]
  [[ "$output" == *"SE-260-otra.spec.md"* ]]
}

@test "limite: raiz + sub-specs de la misma familia no son duplicado" {
  local r; r=$(mkfix familia)
  : > "$r/docs/specs/SE-901-raiz.spec.md"; : > "$r/docs/specs/SE-901-a01-parte.spec.md"
  : > "$r/docs/specs/SE-901-f5a-otra.spec.md"
  run dups "$r"
  [ -z "$output" ]
}

@test "limite: numeros distintos con prefijo comun no colisionan (SE-90 vs SE-900)" {
  local r; r=$(mkfix prefijo)
  : > "$r/docs/specs/SE-90-x.spec.md"; : > "$r/docs/specs/SE-900-y.spec.md"
  run dups "$r"
  [ -z "$output" ]
}
