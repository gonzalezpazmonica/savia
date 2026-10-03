#!/usr/bin/env bats
# audit: score=88 hash=6c7553fd date=2026-10-03
# test-company-messaging.bats — calibración SE-376 de la skill company-messaging
# Ref: .claude/skills/company-messaging/SKILL.md
# Ref: .claude/skills/company-messaging/references/message-schema.md
# Ref: docs/rules/domain/messaging-subject-safety.md
#
# Todo ocurre contra un remoto bare local creado con mktemp: ningún remoto
# real, ninguna clave real. HOME se aísla por usuario sintético (alice, bob).

SCRIPT="scripts/savia-branch.sh"
CRYPTO="scripts/savia-crypto.sh"
MESSAGING="scripts/savia-messaging.sh"
PRIVACY="scripts/privacy-check-company.sh"

setup_file() {
  # Las claves RSA-4096 tardan: se generan una vez por fichero.
  export KEYS_CACHE="$BATS_FILE_TMPDIR/keys"
  local h
  for h in alice bob mallory; do
    mkdir -p "$KEYS_CACHE/$h"
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
      -out "$KEYS_CACHE/$h/private.pem" 2>/dev/null
    openssl rsa -in "$KEYS_CACHE/$h/private.pem" -pubout \
      -out "$KEYS_CACHE/$h/public.pem" 2>/dev/null
  done
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
  export HOME="$TMPDIR_TEST/home"
  mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@test.local
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@test.local
  export LC_ALL=es_ES.UTF-8 LANG=es_ES.UTF-8
}

teardown() {
  [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}

# ── Helpers ──────────────────────────────────────────────────────────

# company_repo: remoto bare con main (directorio en formato tabla, como lo
# genera company-repo-templates-init.sh) y ramas exchange y user/*.
company_repo() {
  REMOTE="$TMPDIR_TEST/remote.git"
  git init -q --bare -b main "$REMOTE"
  git clone -q "$REMOTE" "$TMPDIR_TEST/seed" 2>/dev/null
  mkdir -p "$TMPDIR_TEST/seed/pubkeys"
  cat > "$TMPDIR_TEST/seed/directory.md" <<'EOF'
# Team Directory — Synthetic Org

| Handle | Name | Role | Status |
|--------|------|------|--------|
| @alice | Alice | Admin | active |
| @bob | Bob | Member | active |
| @bobby | Bobby | Member | active |
EOF
  cp "$KEYS_CACHE/bob/public.pem" "$TMPDIR_TEST/seed/pubkeys/bob.pem"
  git -C "$TMPDIR_TEST/seed" add -A
  git -C "$TMPDIR_TEST/seed" commit -q -m init
  git -C "$TMPDIR_TEST/seed" push -q origin main
  local b
  for b in exchange user/alice user/bob user/bobby; do
    bash "$REPO_ROOT/$SCRIPT" ensure-orphan "$TMPDIR_TEST/seed" "$b" >/dev/null 2>&1
  done
}

# member <handle>: clon propio + HOME propio con config y claves
member() {
  local h="$1"
  git clone -q "$REMOTE" "$TMPDIR_TEST/clone-$h" 2>/dev/null
  mkdir -p "$TMPDIR_TEST/home-$h/.pm-workspace/savia-keys"
  printf 'LOCAL_PATH=%s\nUSER_HANDLE=%s\n' "$TMPDIR_TEST/clone-$h" "$h" \
    > "$TMPDIR_TEST/home-$h/.pm-workspace/company-repo"
  if [ -d "$KEYS_CACHE/$h" ]; then
    cp "$KEYS_CACHE/$h/"*.pem "$TMPDIR_TEST/home-$h/.pm-workspace/savia-keys/"
  fi
}

# as <handle> <args...>: ejecuta savia-messaging.sh como ese miembro
as() {
  local h="$1"; shift
  HOME="$TMPDIR_TEST/home-$h" bash "$REPO_ROOT/$MESSAGING" "$@"
}

remote_files() {
  git -C "$REMOTE" ls-tree -r --name-only "$1"
}

# ── Contrato del script ──────────────────────────────────────────────

@test "savia-branch.sh y savia-crypto.sh declaran set -uo pipefail" {
  grep -q 'set -[a-z]*u[a-z]*o pipefail' "$REPO_ROOT/$SCRIPT"
  grep -q 'set -[a-z]*u[a-z]*o pipefail' "$REPO_ROOT/$CRYPTO"
  grep -q 'set -[a-z]*u[a-z]*o pipefail' "$REPO_ROOT/$MESSAGING"
}

# ── Cifrado ──────────────────────────────────────────────────────────

@test "crypto keygen: crea el par con la clave privada en 600" {
  run bash "$REPO_ROOT/$CRYPTO" keygen
  [ "$status" -eq 0 ]
  [ -f "$HOME/.pm-workspace/savia-keys/public.pem" ]
  [ "$(stat -c '%a' "$HOME/.pm-workspace/savia-keys/private.pem")" = "600" ]
}

@test "crypto keygen: rechaza sobrescribir un par existente sin --force" {
  mkdir -p "$HOME/.pm-workspace/savia-keys"
  cp "$KEYS_CACHE/alice/"*.pem "$HOME/.pm-workspace/savia-keys/"
  run bash "$REPO_ROOT/$CRYPTO" keygen
  [ "$status" -eq 1 ]
  cmp "$KEYS_CACHE/alice/private.pem" "$HOME/.pm-workspace/savia-keys/private.pem"
}

@test "crypto: ida y vuelta de un cuerpo multilínea UTF-8 en locale es_ES" {
  mkdir -p "$HOME/.pm-workspace/savia-keys"
  cp "$KEYS_CACHE/bob/"*.pem "$HOME/.pm-workspace/savia-keys/"
  local plain=$'Reunión 1,5 h con el equipo\nsegunda línea: ñandú'
  run bash "$REPO_ROOT/$CRYPTO" encrypt "$KEYS_CACHE/bob/public.pem" "$plain"
  [ "$status" -eq 0 ]
  [[ "$output" == *":::"* ]]
  [[ "$output" != *"ñandú"* ]]
  local pkg="$output"
  run bash "$REPO_ROOT/$CRYPTO" decrypt "$pkg"
  [ "$status" -eq 0 ]
  [ "$output" = "$plain" ]
}

@test "crypto: un texto con forma de opción (-n, -e) no se pierde en el cifrado (boundary)" {
  mkdir -p "$HOME/.pm-workspace/savia-keys"
  cp "$KEYS_CACHE/bob/"*.pem "$HOME/.pm-workspace/savia-keys/"
  local word pkg
  for word in "-n" "-e" "-E"; do
    pkg=$(bash "$REPO_ROOT/$CRYPTO" encrypt "$KEYS_CACHE/bob/public.pem" "$word")
    run bash "$REPO_ROOT/$CRYPTO" decrypt "$pkg"
    [ "$status" -eq 0 ]
    [ "$output" = "$word" ]
  done
}

@test "crypto: un argumento vacío cifra vacío y no lee stdin (empty)" {
  mkdir -p "$HOME/.pm-workspace/savia-keys"
  cp "$KEYS_CACHE/bob/"*.pem "$HOME/.pm-workspace/savia-keys/"
  local pkg
  pkg=$(echo "texto ajeno en stdin" | bash "$REPO_ROOT/$CRYPTO" encrypt "$KEYS_CACHE/bob/public.pem" "")
  run bash "$REPO_ROOT/$CRYPTO" decrypt "$pkg"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "crypto: cuerpo grande (200 KB) por stdin hace ida y vuelta (large)" {
  mkdir -p "$HOME/.pm-workspace/savia-keys"
  cp "$KEYS_CACHE/bob/"*.pem "$HOME/.pm-workspace/savia-keys/"
  head -c 150000 /dev/urandom | base64 > "$TMPDIR_TEST/big.txt"
  bash "$REPO_ROOT/$CRYPTO" encrypt "$KEYS_CACHE/bob/public.pem" \
    < "$TMPDIR_TEST/big.txt" > "$TMPDIR_TEST/pkg.txt"
  # El paquete supera MAX_ARG_STRLEN (128 KB): solo cabe por stdin
  [ "$(wc -c < "$TMPDIR_TEST/pkg.txt")" -gt 131072 ]
  bash "$REPO_ROOT/$CRYPTO" decrypt - < "$TMPDIR_TEST/pkg.txt" > "$TMPDIR_TEST/out.txt"
  cmp "$TMPDIR_TEST/big.txt" "$TMPDIR_TEST/out.txt"
}

@test "crypto: descifrar con la clave privada de otro falla (reject wrong key)" {
  mkdir -p "$HOME/.pm-workspace/savia-keys"
  cp "$KEYS_CACHE/mallory/"*.pem "$HOME/.pm-workspace/savia-keys/"
  local pkg
  pkg=$(bash "$REPO_ROOT/$CRYPTO" encrypt "$KEYS_CACHE/bob/public.pem" "solo para bob")
  run bash "$REPO_ROOT/$CRYPTO" decrypt "$pkg"
  [ "$status" -ne 0 ]
  [[ "$output" != *"solo para bob"* ]]
}

@test "crypto: paquete sin separador ::: es inválido (invalid)" {
  mkdir -p "$HOME/.pm-workspace/savia-keys"
  cp "$KEYS_CACHE/bob/"*.pem "$HOME/.pm-workspace/savia-keys/"
  run bash "$REPO_ROOT/$CRYPTO" decrypt "c29sbyB1bmEgcGFydGU="
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid encrypted package"* ]]
}

@test "crypto: encrypt con clave pública inexistente falla con error (missing)" {
  run bash "$REPO_ROOT/$CRYPTO" encrypt "$TMPDIR_TEST/no existe.pem" "x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Public key not found"* ]]
}

# ── Capa de ramas: escritura y push ──────────────────────────────────

@test "branch write: el fichero llega al remoto" {
  company_repo
  member alice
  run bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" exchange "pending/m1.md" "hola"
  [ "$status" -eq 0 ]
  [ "$(git -C "$REMOTE" show exchange:pending/m1.md)" = "hola" ]
}

@test "branch write: con exchange local obsoleto no pierde el mensaje del otro miembro (concurrencia)" {
  company_repo
  member alice
  member bob
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-bob" exchange "pending/de-bob.md" "b"
  run bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" exchange "pending/de-alice.md" "a"
  [ "$status" -eq 0 ]
  run remote_files exchange
  [[ "$output" == *"pending/de-bob.md"* ]]
  [[ "$output" == *"pending/de-alice.md"* ]]
}

@test "branch write: dos escrituras simultáneas acaban ambas en el remoto (concurrencia)" {
  company_repo
  member alice
  member bob
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" exchange "pending/p1.md" "1" &
  local p1=$!
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-bob" exchange "pending/p2.md" "2" &
  local p2=$!
  wait "$p1"; local s1=$?
  wait "$p2"; local s2=$?
  [ "$s1" -eq 0 ] && [ "$s2" -eq 0 ]
  run remote_files exchange
  [[ "$output" == *"pending/p1.md"* ]]
  [[ "$output" == *"pending/p2.md"* ]]
}

@test "branch write: remoto inalcanzable devuelve error, no éxito silencioso (fail)" {
  company_repo
  member alice
  git -C "$TMPDIR_TEST/clone-alice" remote set-url origin "$TMPDIR_TEST/no-existe.git"
  run bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" exchange "pending/m.md" "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"push"* ]]
}

@test "branch write: reescribir el mismo contenido es un no-op con éxito (idempotent)" {
  company_repo
  member alice
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" exchange "pending/m.md" "igual"
  local before
  before=$(git -C "$REMOTE" rev-parse exchange)
  run bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" exchange "pending/m.md" "igual"
  [ "$status" -eq 0 ]
  [ "$(git -C "$REMOTE" rev-parse exchange)" = "$before" ]
}

@test "branch write: no deja worktrees temporales registrados" {
  company_repo
  member alice
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" exchange "pending/m.md" "x"
  [ "$(git -C "$TMPDIR_TEST/clone-alice" worktree list | wc -l)" -eq 1 ]
}

@test "branch write: avanza la rama local no extraída y deja intacta la extraída (main)" {
  company_repo
  member alice
  git -C "$TMPDIR_TEST/clone-alice" branch exchange origin/exchange
  local main_before
  main_before=$(git -C "$TMPDIR_TEST/clone-alice" rev-parse main)
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" exchange "pending/m.md" "x"
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-alice" main "notes.md" "y"
  [ "$(git -C "$TMPDIR_TEST/clone-alice" rev-parse exchange)" = "$(git -C "$REMOTE" rev-parse exchange)" ]
  [ "$(git -C "$TMPDIR_TEST/clone-alice" rev-parse main)" = "$main_before" ]
  [ -z "$(git -C "$TMPDIR_TEST/clone-alice" status --porcelain)" ]
}

@test "branch write: repo sin remoto escribe en la rama local (sin origin)" {
  git init -q -b main "$TMPDIR_TEST/local"
  echo r > "$TMPDIR_TEST/local/README.md"
  git -C "$TMPDIR_TEST/local" add -A
  git -C "$TMPDIR_TEST/local" commit -q -m init
  run bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/local" main "notes/a.md" "nota"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TMPDIR_TEST/local" show main:notes/a.md)" = "nota" ]
}

@test "branch move: mueve el fichero entre carpetas en un solo commit" {
  company_repo
  member bob
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-bob" user/bob "inbox/unread/m.md" "x"
  run bash "$REPO_ROOT/$SCRIPT" move "$TMPDIR_TEST/clone-bob" user/bob "inbox/unread/m.md" "inbox/read/m.md"
  [ "$status" -eq 0 ]
  run remote_files user/bob
  [[ "$output" == *"inbox/read/m.md"* ]]
  [[ "$output" != *"inbox/unread/m.md"* ]]
}

@test "branch move: origen inexistente es error (missing source)" {
  company_repo
  member bob
  run bash "$REPO_ROOT/$SCRIPT" move "$TMPDIR_TEST/clone-bob" user/bob "inbox/unread/nada.md" "inbox/read/nada.md"
  [ "$status" -ne 0 ]
}

@test "branch ensure-orphan: push fallido devuelve error (savia-branch.sh:78 tragaba el fallo)" {
  company_repo
  member alice
  git -C "$TMPDIR_TEST/clone-alice" remote set-url origin "$TMPDIR_TEST/no-existe.git"
  run bash "$REPO_ROOT/$SCRIPT" ensure-orphan "$TMPDIR_TEST/clone-alice" team/nuevo
  [ "$status" -ne 0 ]
}

@test "branch ensure-orphan: rama local nunca publicada se publica al reintentar" {
  company_repo
  member alice
  git -C "$TMPDIR_TEST/clone-alice" branch huerfana main
  run bash "$REPO_ROOT/$SCRIPT" ensure-orphan "$TMPDIR_TEST/clone-alice" huerfana
  [ "$status" -eq 0 ]
  git -C "$REMOTE" rev-parse --verify huerfana
}

@test "branch check-permission: main solo admin; user/x solo su dueño (block)" {
  run bash "$REPO_ROOT/$SCRIPT" check-permission main bob member
  [ "$status" -eq 1 ]
  run bash "$REPO_ROOT/$SCRIPT" check-permission main alice admin
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/$SCRIPT" check-permission user/bob alice member
  [ "$status" -eq 1 ]
  run bash "$REPO_ROOT/$SCRIPT" check-permission user/bob bob member
  [ "$status" -eq 0 ]
}

# ── Mensajería de extremo a extremo ──────────────────────────────────

@test "send: resuelve @bob en el directorio en formato tabla y deja el mensaje en exchange" {
  company_repo
  member alice
  run as alice send bob "Planificación" "cuerpo uno"
  [ "$status" -eq 0 ]
  run remote_files exchange
  [[ "$output" == *pending/*.md* ]]
  run remote_files user/alice
  [[ "$output" == *"outbox/"* ]]
}

@test "send: handle desconocido o prefijo de otro (@bo no es @bob) se rechaza (reject)" {
  company_repo
  member alice
  run as alice send carol "x" "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  run as alice send bo "x" "y"
  [ "$status" -ne 0 ]
  run remote_files exchange
  [[ "$output" != *pending/* ]]
}

@test "send: handle con ruta (../x) es inválido y no escribe nada (invalid)" {
  company_repo
  member alice
  run as alice send "../bob" "x" "y"
  [ "$status" -ne 0 ]
  run remote_files exchange
  [[ "$output" != *pending/* ]]
}

@test "send: fallo de push devuelve error en vez de 'Message sent' (fail)" {
  company_repo
  member alice
  git -C "$TMPDIR_TEST/clone-alice" fetch -q origin
  git -C "$TMPDIR_TEST/clone-alice" remote set-url origin "$TMPDIR_TEST/no-existe.git"
  run as alice send bob "x" "y"
  [ "$status" -ne 0 ]
  [[ "$output" != *"Message sent"* ]]
}

@test "send: bloquea un cuerpo en claro con una clave privada (privacy block)" {
  company_repo
  member alice
  local hdr="-----BEGIN"
  run as alice send bob "x" "$hdr RSA PRIVATE KEY----- abc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Private key"* ]]
  run remote_files exchange
  [[ "$output" != *pending/* ]]
}

@test "send --encrypt: el cuerpo viaja cifrado y bob lo descifra con su clave" {
  company_repo
  member alice
  run as alice send bob "Aviso" "cifra 3,14 secreta" --encrypt
  [ "$status" -eq 0 ]
  local f body
  f=$(remote_files exchange | grep '^pending/.*\.md$' | head -1)
  body=$(git -C "$REMOTE" show "exchange:$f" | tail -1)
  [[ "$body" != *"secreta"* ]]
  member bob
  HOME="$TMPDIR_TEST/home-bob" run bash "$REPO_ROOT/$CRYPTO" decrypt "$body"
  [ "$status" -eq 0 ]
  [ "$output" = "cifra 3,14 secreta" ]
}

@test "inbox: bob ve el mensaje recibido con remitente y asunto" {
  company_repo
  member alice
  member bob
  as alice send bob "Planificación" "cuerpo"
  run as bob inbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"@alice: Planificación"* ]]
  [[ "$output" == *"Total: 1 unread"* ]]
}

@test "inbox vacío: cero mensajes sin error (empty)" {
  company_repo
  member bob
  run as bob inbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 0 unread"* ]]
}

@test "read: saca el mensaje de unread y no se vuelve a entregar desde exchange" {
  company_repo
  member alice
  member bob
  as alice send bob "Asunto" "cuerpo leído"
  as bob inbox >/dev/null
  local id
  id=$(remote_files user/bob | sed -n 's#^inbox/unread/\(.*\)\.md$#\1#p' | head -1)
  [ -n "$id" ]
  run as bob read "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cuerpo leído"* ]]
  run remote_files user/bob
  [[ "$output" == *"inbox/read/$id.md"* ]]
  [[ "$output" != *"inbox/unread/$id.md"* ]]
  run as bob inbox
  [[ "$output" == *"Total: 0 unread"* ]]
}

@test "broadcast: cada destinatario del directorio recibe su propio mensaje (sin colisión de ID)" {
  company_repo
  member alice
  run as alice broadcast "Aviso general" "texto"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Broadcast sent to 2 recipient(s)"* ]]
  local n
  n=$(remote_files exchange | grep -c '^pending/.*\.md$')
  [ "$n" -eq 2 ]
}

@test "privacy-check: detecta una clave privada en el inbox de bob estando en main" {
  company_repo
  member bob
  local hdr="-----BEGIN"
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-bob" user/bob "inbox/unread/k.md" "$hdr PRIVATE KEY-----"
  run bash "$REPO_ROOT/$PRIVACY" "$TMPDIR_TEST/clone-bob" bob
  [ "$status" -eq 1 ]
  [[ "$output" == *"Private key content"* ]]
}

@test "privacy-check: inbox limpio pasa (zero violations)" {
  company_repo
  member bob
  bash "$REPO_ROOT/$SCRIPT" write "$TMPDIR_TEST/clone-bob" user/bob "inbox/unread/ok.md" "nada sensible"
  run bash "$REPO_ROOT/$PRIVACY" "$TMPDIR_TEST/clone-bob" bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASSED"* ]]
}
