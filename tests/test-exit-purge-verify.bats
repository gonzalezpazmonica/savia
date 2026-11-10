#!/usr/bin/env bats
# tests/test-exit-purge-verify.bats — SE-272 S5 / SE-376 (S03u)
# Comportamiento de scripts/exit-purge-verify.sh: tras olvidar un engagement,
# «CLEAN» solo si no queda ninguna referencia viva fuera de las rutas permitidas.
# El script deriva ROOT de su propia ubicación: se copia a un árbol aislado.

SRC="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/scripts/exit-purge-verify.sh"

setup() {
  WS="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$WS/scripts" "$WS/docs" "$WS/output" "$WS/vendor"
  cp "$SRC" "$WS/scripts/exit-purge-verify.sh"
  S="$WS/scripts/exit-purge-verify.sh"
  echo "contenido neutro" > "$WS/docs/readme.md"
}

verify() { run bash "$S" verify --engagement "$@"; }

@test "clean workspace reports CLEAN and exits 0" {
  verify acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: CLEAN"* ]]
  [[ "$output" == *"Violations:       0"* ]]
}

@test "a living reference in docs reports DIRTY with exit 1 and names the file" {
  echo "notas del cliente acme" > "$WS/docs/notes.md"
  verify acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"RESULT: DIRTY — 1 living reference"* ]]
  [[ "$output" == *"[VIOLATION] docs/notes.md:1"* ]]
}

@test "a file named exit-* outside the exit scripts is not hidden (no false CLEAN)" {
  echo "plan de salida de acme" > "$WS/docs/exit-notes.md"
  verify acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[VIOLATION] docs/exit-notes.md:1"* ]]
}

@test "a path that merely contains audit-trail is a violation, not an allowed reference" {
  echo "acme" > "$WS/docs/audit-trail-acme.md"
  verify acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[VIOLATION] docs/audit-trail-acme.md:1"* ]]
  [[ "$output" != *"[ALLOWED]"* ]]
}

@test "the documented allowed paths count as allowed and keep the result CLEAN" {
  mkdir -p "$WS/.savia-tombstones" "$WS/output/exit-packages/acme" "$WS/output/exit-drills"
  echo '{"engagement":"acme"}' > "$WS/.savia-tombstones/acme.json"
  echo '{"e":"acme"}' > "$WS/output/audit-trail.jsonl"
  echo "acme" > "$WS/output/exit-packages/acme/00-index.md"
  echo "acme" > "$WS/output/exit-drills/drill.md"
  verify acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"Allowed references: 4"* ]]
  [[ "$output" == *"Violations:       0"* ]]
}

@test "the exit package of another engagement is not an allowed place for this one" {
  mkdir -p "$WS/output/exit-packages/otro"
  echo "acme" > "$WS/output/exit-packages/otro/x.md"
  verify acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[VIOLATION] output/exit-packages/otro/x.md:1"* ]]
}

@test "a nested audit-trail.jsonl outside output/ is a violation" {
  mkdir -p "$WS/projects/x"
  echo '{"e":"acme"}' > "$WS/projects/x/audit-trail.jsonl"
  verify acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"[VIOLATION] projects/x/audit-trail.jsonl:1"* ]]
}

@test "--exclude-dir drops matches under that directory" {
  echo "acme" > "$WS/vendor/lib.txt"
  verify acme
  [ "$status" -eq 1 ]
  verify acme --exclude-dir vendor
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: CLEAN"* ]]
}

@test "--exclude-dir is a path prefix: a sibling with the same prefix is still checked" {
  mkdir -p "$WS/vendor2"
  echo "acme" > "$WS/vendor2/lib.txt"
  verify acme --exclude-dir vendor
  [ "$status" -eq 1 ]
  [[ "$output" == *"[VIOLATION] vendor2/lib.txt:1"* ]]
}

@test "a hyphenated engagement is also found written with spaces" {
  echo "reunión con acme corp" > "$WS/docs/n.md"
  verify acme-corp
  [ "$status" -eq 1 ]
  [[ "$output" == *"[VIOLATION] docs/n.md:1"* ]]
}

@test "the engagement name is a literal, not a regex (a.c does not match abc)" {
  echo "abc" > "$WS/docs/n.md"
  verify a.c
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: CLEAN"* ]]
}

@test "an unreadable directory fails closed: exit 2 and never CLEAN" {
  mkdir -p "$WS/locked"
  echo "acme" > "$WS/locked/x.md"
  chmod 000 "$WS/locked"
  verify acme
  chmod 755 "$WS/locked"
  [ "$status" -eq 2 ]
  [[ "$output" != *"RESULT: CLEAN"* ]]
  [[ "$output" == *"RESULT: UNKNOWN"* ]]
}

@test "missing --engagement is a usage error with exit 2" {
  run bash "$S" verify
  [ "$status" -eq 2 ]
  [[ "$output" == *"--engagement required"* ]]
}

@test "an engagement name with quotes or slashes is rejected before any work" {
  run bash "$S" verify --engagement "../etc"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid engagement name"* ]]
  run bash "$S" tombstone --engagement "x'y"
  [ "$status" -eq 2 ]
  [ ! -e "$WS/.savia-tombstones/x'y.json" ]
}

@test "tombstone does not execute code embedded in the engagement name" {
  cd "$WS"
  run bash "$S" tombstone --engagement "x'+__import__('os').system('touch PWNED')+'"
  [ "$status" -eq 2 ]
  [ ! -e "$WS/PWNED" ]
}

@test "tombstone on a clean workspace records verified and exits 0" {
  run bash "$S" tombstone --engagement acme
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["engagement"], d["verification_status"])' "$WS/.savia-tombstones/acme.json"
  [ "$output" = "acme verified" ]
}

@test "tombstone with living references is not marked verified and exits 1" {
  echo "acme" > "$WS/docs/notes.md"
  run bash "$S" tombstone --engagement acme
  [ "$status" -eq 1 ]
  run python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verification_status"])' "$WS/.savia-tombstones/acme.json"
  [ "$output" = "dirty" ]
}

@test "unknown subcommand exits 1 and --help exits 0" {
  run bash "$S" bogus
  [ "$status" -eq 1 ]
  run bash "$S" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
