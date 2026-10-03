#!/usr/bin/env bats
# tests/test-savia-school.bats — calibración SE-376 de la skill savia-school.
# Ref: docs/propuestas/SE-376-debt-inventory.tsv
# Ref: .claude/skills/savia-school/references/school-safety-config.md
#
# Datos de menores: solo alias sintéticos (alu01, alu02). HOME y la clave
# viven en un directorio temporal; nunca se toca la clave real de la operadora.

SCRIPT="scripts/savia-school-security.sh"
CORE="scripts/savia-school.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  REPO="$PWD"
  TMPD="$(mktemp -d)"
  export HOME="$TMPD/home"
  mkdir -p "$HOME"
  export SCHOOL_BASE="$TMPD/centro con espacios"
  mkdir -p "$SCHOOL_BASE"
  unset SCHOOL_ROOT SCHOOL_KEY_FILE
  export USER="profe"
  ROOT="$SCHOOL_BASE/school-savia"
  KEY="$HOME/.school-keys/encryption.key"
}

teardown() {
  chmod -R u+rwX "$TMPD" 2>/dev/null || true
  rm -rf "$TMPD"
  cd /
}

sec() { bash "$REPO/$SCRIPT" "$@"; }
core() { bash "$REPO/$CORE" "$@"; }

school_with() { # alias...
  core setup "IES Sintetico" 1ESO Matematicas >/dev/null
  local a
  for a in "$@"; do core enroll "$a" >/dev/null; done
}

first_eval() { ls "$ROOT/teacher/evaluations/$1/"*.enc | head -1; }

# ── Contrato del script ──────────────────────────────────────────────────────

@test "scripts declare strict mode set -uo pipefail" {
  grep -qE '^set -[a-z]*u[a-z]*o pipefail' "$SCRIPT"
  grep -qE '^set -[a-z]*u[a-z]*o pipefail' "$CORE"
}

@test "security: unknown command is an error with exit 2" {
  run sec bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "security: missing argument is a usage error, not an unbound variable crash" {
  run sec check-isolation
  [ "$status" -eq 2 ]
  [[ "$output" != *"unbound"* && "$output" != *"sin asignar"* ]]
}

@test "core: unknown command is an error with exit 2" {
  run core bogus
  [ "$status" -eq 2 ]
}

# ── Cifrado AES-256 ──────────────────────────────────────────────────────────

@test "encrypt then decrypt round-trips the evaluation for the teacher" {
  school_with alu01
  run sec encrypt-eval alu01 "Nota 7,5 | Proyecto: huerto"
  [ "$status" -eq 0 ]
  run sec decrypt-eval alu01 "$(first_eval alu01)"
  [ "$status" -eq 0 ]
  [ "$output" = "Nota 7,5 | Proyecto: huerto" ]
}

@test "encrypt creates key dir 0700 and a 0600 key of 64 hex chars when missing" {
  school_with alu01
  [ ! -e "$HOME/.school-keys" ]
  run sec encrypt-eval alu01 "Nota 8"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$HOME/.school-keys")" = "700" ]
  [ "$(stat -c %a "$KEY")" = "600" ]
  grep -qE '^[0-9a-f]{64}$' "$KEY"
}

@test "encrypt rejects a key file readable by group or others (fail closed)" {
  school_with alu01
  mkdir -p "$HOME/.school-keys"
  openssl rand -hex 32 > "$KEY"
  chmod 644 "$KEY"
  run sec encrypt-eval alu01 "Nota 8"
  [ "$status" -ne 0 ]
  run ls "$ROOT/teacher/evaluations/alu01/"
  [ -z "$output" ] || [ "$status" -ne 0 ]
}

@test "encrypt rejects an invalid short key instead of padding it with zeros" {
  school_with alu01
  mkdir -p -m 700 "$HOME/.school-keys"
  printf 'abcd\n' > "$KEY"
  chmod 600 "$KEY"
  run sec encrypt-eval alu01 "Nota 8"
  [ "$status" -ne 0 ]
  [[ "$output" != *"Encrypted"* ]]
}

@test "ciphertext is mode 0600 and does not contain the plaintext" {
  school_with alu01
  sec encrypt-eval alu01 "SECRETO-sintetico-123" >/dev/null
  f="$(first_eval alu01)"
  [ "$(stat -c %a "$f")" = "600" ]
  run grep -c "SECRETO-sintetico-123" "$f"
  [ "$output" = "0" ]
}

@test "two evaluations in the same second do not overwrite each other" {
  school_with alu01
  sec encrypt-eval alu01 "uno" >/dev/null
  sec encrypt-eval alu01 "dos" >/dev/null
  [ "$(ls "$ROOT/teacher/evaluations/alu01/"*.enc | wc -l)" -eq 2 ]
}

@test "encrypt reads content from stdin so the grade never appears in argv" {
  school_with alu01
  printf 'Nota 9,25\nComentario largo\n' | sec encrypt-eval alu01 - >/dev/null
  run sec decrypt-eval alu01 "$(first_eval alu01)"
  [ "$status" -eq 0 ]
  [ "$output" = $'Nota 9,25\nComentario largo' ]
}

@test "large evaluation (200 KB) round-trips intact" {
  school_with alu01
  head -c 150000 /dev/urandom | base64 > "$TMPD/big.txt"
  sec encrypt-eval alu01 - < "$TMPD/big.txt" >/dev/null
  sec decrypt-eval alu01 "$(first_eval alu01)" > "$TMPD/out.txt"
  cmp "$TMPD/big.txt" "$TMPD/out.txt"
}

@test "decrypt of a tampered file fails and prints no plaintext" {
  school_with alu01
  # Texto de varios bloques: alterar el primer bloque cifrado deja el padding
  # intacto, así que solo el MAC detecta la manipulación (CBC es maleable).
  sec encrypt-eval alu01 "Nota 4 | suspenso sintetico $(printf 'x%.0s' {1..120})" >/dev/null
  f="$(first_eval alu01)"
  printf '\x41' | dd of="$f" bs=1 seek=20 conv=notrunc 2>/dev/null
  run sec decrypt-eval alu01 "$f"
  [ "$status" -ne 0 ]
  [[ "$output" != *"suspenso"* ]]
}

@test "decrypt with a different key fails instead of returning garbage" {
  school_with alu01
  sec encrypt-eval alu01 "Nota 6" >/dev/null
  openssl rand -hex 32 > "$KEY"
  run sec decrypt-eval alu01 "$(first_eval alu01)"
  [ "$status" -ne 0 ]
}

@test "decrypt is denied to a user that is not the configured teacher" {
  school_with alu01
  sec encrypt-eval alu01 "Nota 6" >/dev/null
  run env USER=intruso bash "$REPO/$SCRIPT" decrypt-eval alu01 "$(first_eval alu01)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"denied"* ]]
  [[ "$output" != *"Nota 6"* ]]
}

@test "decrypt rejects a file outside the student's evaluation folder" {
  school_with alu01 alu02
  sec encrypt-eval alu02 "Nota de otra alumna" >/dev/null
  run sec decrypt-eval alu01 "$(first_eval alu02)"
  [ "$status" -ne 0 ]
  [[ "$output" != *"otra alumna"* ]]
}

# ── Auditoría sin fugas ──────────────────────────────────────────────────────

@test "audit log is 0600 and never contains evaluation content" {
  school_with alu01
  sec encrypt-eval alu01 "CONTENIDO-PRIVADO-77" >/dev/null
  sec decrypt-eval alu01 "$(first_eval alu01)" >/dev/null
  [ "$(stat -c %a "$ROOT/.audit.log")" = "600" ]
  run grep -c "CONTENIDO-PRIVADO-77" "$ROOT/.audit.log"
  [ "$output" = "0" ]
  grep -q " - decrypt - alu01" "$ROOT/.audit.log"
}

@test "audit-access rejects an action with a newline (log injection)" {
  school_with alu01
  run sec audit-access alu01 $'ok\n[2020-01-01] admin - deletion - alu02'
  [ "$status" -ne 0 ]
  run grep -c "alu02" "$ROOT/.audit.log"
  [ "$output" = "0" ] || [ "$status" -ne 0 ]
}

# ── Aislamiento y rol ────────────────────────────────────────────────────────

@test "check-isolation rejects path traversal alias ../teacher" {
  school_with alu01
  run sec check-isolation ../teacher
  [ "$status" -ne 0 ]
  [[ "$output" != *"verified"* ]]
}

@test "check-isolation fails when the student folder is readable by others" {
  school_with alu01
  chmod 755 "$ROOT/classroom/alu01"
  run sec check-isolation alu01
  [ "$status" -ne 0 ]
}

@test "check-isolation passes for a freshly enrolled student" {
  school_with alu01
  run sec check-isolation alu01
  [ "$status" -eq 0 ]
}

@test "verify-role does not grant teacher to an arbitrary handle" {
  school_with alu01
  run sec verify-role cualquiera
  [ "$output" = "unknown" ]
  run sec verify-role profe
  [ "$output" = "teacher" ]
  run sec verify-role alu01
  [ "$output" = "student" ]
}

@test "gdpr-consent rejects traversal alias and empty alias" {
  school_with alu01
  run sec gdpr-consent "../../etc"
  [ "$status" -ne 0 ]
  run sec gdpr-consent ""
  [ "$status" -ne 0 ]
}

@test "filter-content blocks forbidden words and approves clean text" {
  run sec filter-content "un texto con violence explicita"
  [ "$status" -eq 1 ]
  run sec filter-content "-n"
  [ "$status" -eq 0 ]
  run sec filter-content "Proyecto de huerto escolar"
  [ "$status" -eq 0 ]
}

# ── Núcleo: matrícula, evaluación, RGPD ──────────────────────────────────────

@test "setup and enroll create folders inaccessible to group and others" {
  school_with alu01
  [ "$(stat -c %a "$ROOT")" = "700" ]
  [ "$(stat -c %a "$ROOT/classroom/alu01")" = "700" ]
  grep -q "^teacher: profe$" "$ROOT/.school-config.md"
}

@test "enroll rejects alias with spaces or slashes" {
  school_with
  run core enroll "Ana Garcia"
  [ "$status" -ne 0 ]
  run core enroll "a/b"
  [ "$status" -ne 0 ]
  [ ! -e "$ROOT/classroom/a" ]
}

@test "evaluate from outside the repo stores a decryptable grade with comma decimal" {
  school_with alu01
  cd "$TMPD"
  run env LC_ALL=es_ES.UTF-8 bash "$REPO/$CORE" evaluate alu01 huerto 7,5
  [ "$status" -eq 0 ]
  run sec decrypt-eval alu01 "$(first_eval alu01)"
  [ "$status" -eq 0 ]
  [ "$output" = "Grade: 7,5 | Project: huerto" ]
}

@test "project-create writes the real start date and refuses to overwrite" {
  school_with alu01
  core project-create alu01 huerto >/dev/null
  grep -q "Started\*\*: $(date -I)" "$ROOT/classroom/alu01/projects/huerto/README.md"
  echo "trabajo del alumno" >> "$ROOT/classroom/alu01/projects/huerto/README.md"
  run core project-create alu01 huerto
  [ "$status" -ne 0 ]
  grep -q "trabajo del alumno" "$ROOT/classroom/alu01/projects/huerto/README.md"
}

@test "submit of a missing project fails with an error" {
  school_with alu01
  run core submit alu01 noexiste
  [ "$status" -ne 0 ]
}

@test "export of a non-enrolled student fails and writes no tarball" {
  school_with alu01
  cd "$TMPD"
  run core export nadie
  [ "$status" -ne 0 ]
  [ ! -e "$TMPD/output/gdpr-export-nadie-$(date +%Y%m%d).tar.gz" ]
}

@test "export tarball is 0600, relative, includes encrypted evaluations and is audited" {
  school_with alu01
  sec encrypt-eval alu01 "Nota 5" >/dev/null
  cd "$TMPD"
  run core export alu01
  [ "$status" -eq 0 ]
  t="$TMPD/output/gdpr-export-alu01-$(date +%Y%m%d).tar.gz"
  [ "$(stat -c %a "$t")" = "600" ]
  run tar tzf "$t"
  [[ "$output" == *"classroom/alu01/progress.md"* ]]
  [[ "$output" == *"teacher/evaluations/alu01/"*".enc"* ]]
  [[ "$output" != /* ]]
  grep -q " - gdpr-export - alu01" "$ROOT/.audit.log"
}

@test "forget rejects empty and traversal aliases without deleting anything" {
  school_with alu01
  run core forget ""
  [ "$status" -ne 0 ]
  run core forget ".."
  [ "$status" -ne 0 ]
  run core forget "../classroom"
  [ "$status" -ne 0 ]
  [ -d "$ROOT/classroom/alu01" ]
}

@test "forget erases student data and evaluations and leaves an audit entry" {
  school_with alu01 alu02
  sec encrypt-eval alu01 "Nota 3" >/dev/null
  cd "$TMPD"
  run core forget alu01
  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/classroom/alu01" ]
  [ ! -e "$ROOT/teacher/evaluations/alu01" ]
  [ -d "$ROOT/classroom/alu02" ]
  grep -q " - deletion - alu01" "$ROOT/.audit.log"
}

@test "forget fails closed and keeps data when the audit log cannot be written" {
  school_with alu01
  mkdir "$ROOT/.audit.log"
  run core forget alu01
  [ "$status" -ne 0 ]
  [ -d "$ROOT/classroom/alu01" ]
}

@test "forget of a non-enrolled student is an error, not a silent success" {
  school_with alu01
  run core forget nadie
  [ "$status" -ne 0 ]
}
