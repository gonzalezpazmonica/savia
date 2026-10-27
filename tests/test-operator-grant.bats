#!/usr/bin/env bats
# BATS tests for scripts/operator-grant.sh (SE-343)
# Ref: SE-343, SPEC-186, autonomous-safety.md

REAL_SCRIPT="scripts/operator-grant.sh"

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  TMP_GRANTS="$(mktemp -d -t grants.XXXXXX)"
  export SAVIA_GRANTS_DIR="$TMP_GRANTS"
  # HOME aislado: ningún default ($HOME/.savia/...) del script, ni de versiones
  # anteriores que se ejecuten con esta suite, llega al HOME real.
  REAL_HOME="$HOME"
  export HOME="$TMP_GRANTS/home"
  mkdir -p "$HOME"
  # Deterministic expected grantor, decoupled from the real operator's identity
  # (active-user.md is gitignored; never put a real personal slug in repo files).
  ACTIVE_SLUG="test-operator"
  # Fixture profile: never depends on the real (gitignored) active-user.md.
  export SAVIA_ACTIVE_USER_FILE="$TMP_GRANTS/active-user.md"
  printf 'active_slug: "%s"\n' "$ACTIVE_SLUG" > "$SAVIA_ACTIVE_USER_FILE"
  # La raíz de confianza no admite override por entorno: copia del script en un
  # repo temporal con un par de claves de prueba generado aquí (nunca una real).
  FAKE_REPO="$TMP_GRANTS/repo"
  mkdir -p "$FAKE_REPO/scripts" "$FAKE_REPO/config"
  cp "$REAL_SCRIPT" "$FAKE_REPO/scripts/"
  # El grant de merge se firma para un repositorio (remoto origin): A#1 ≠ B#1.
  git -C "$FAKE_REPO" init -q
  git -C "$FAKE_REPO" remote add origin "https://github.com/test-org/repo-a.git"
  SCRIPT="$FAKE_REPO/scripts/operator-grant.sh"
  SIGNERS="$FAKE_REPO/config/operator-grant-signers"
  KEY="$TMP_GRANTS/op-key"
  ssh-keygen -q -t ed25519 -N "" -C test -f "$KEY"
  printf '%s namespaces="savia-operator-grant" %s\n' "$ACTIVE_SLUG" "$(cut -d' ' -f1-2 "$KEY.pub")" > "$SIGNERS"
}

teardown() {
  [[ -n "$TMP_GRANTS" && -d "$TMP_GRANTS" ]] && rm -rf "$TMP_GRANTS"
  cd /
}

# La operadora firma la petición pendiente: $1 = clave, $2 = namespace.
# Deja la firma en $TMP_GRANTS/req.sig.
sign_request() {
  local key="${1:-$KEY}" ns="${2:-savia-operator-grant}" d
  d="$(mktemp -d "$TMP_GRANTS/sig.XXXXXX")"
  cp "$TMP_GRANTS/merge.request" "$d/req"
  ssh-keygen -q -Y sign -f "$key" -n "$ns" "$d/req" 2>/dev/null
  cp "$d/req.sig" "$TMP_GRANTS/req.sig"
}

# Ciclo completo: petición (exit 4) → firma de la operadora → grant.
# $2 = recurso (pr:1 por defecto).
issue_merge() {
  run bash "$SCRIPT" grant --scope merge --resource "${2:-pr:1}" --context "$1" --ttl-hours 1
  [ "$status" -eq 4 ]
  sign_request
  bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
}

# Simula el evento PreToolUse: $1 = herramienta, $2 = campo, $3 = valor, $4 = cwd.
guard_event() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{sys.argv[2]:sys.argv[3]},"cwd":sys.argv[4]}))' "$1" "$2" "$3" "${4:-$PWD}"
}

@test "script exists and is executable" {
  [[ -x "$REAL_SCRIPT" ]]
}

@test "passes bash -n syntax" {
  run bash -n "$REAL_SCRIPT"
  [ "$status" -eq 0 ]
}

# ── grant / check ──────────────────────────────────────────────────────

@test "grant creates a file and check returns 0" {
  run bash "$SCRIPT" grant --scope autonomy:overnight-sprint \
    --context "test request" --ttl-hours 1
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" check --scope autonomy:overnight-sprint
  [ "$status" -eq 0 ]
}

@test "check returns 3 when no grant" {
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 3 ]
}

@test "check returns 1 when grant expired" {
  run bash "$SCRIPT" grant --scope autonomy:overnight-sprint \
    --context "expired test" --ttl-hours 0
  # ttl 0 -> expires immediately (epoch = now). Sleep 1 to be safe.
  sleep 1
  run bash "$SCRIPT" check --scope autonomy:overnight-sprint
  [ "$status" -eq 1 ]
}

@test "grantor is active user slug, never self; merge source is the operator signature" {
  issue_merge "test"
  file="$(ls "$SAVIA_GRANTS_DIR"/merge.json)"
  grep -q "\"grantor\":\"$ACTIVE_SLUG\"" "$file"
  run grep -q '"grantor":"self"' "$file"
  [ "$status" -eq 1 ]
  grep -q '"source":"operator-signature"' "$file"
  run grep -q '"source":"express-request"' "$file"
  [ "$status" -eq 1 ]
}

@test "autonomy grants keep source express-request (no change outside merge)" {
  run bash "$SCRIPT" grant --scope autonomy:overnight-sprint --context "x" --ttl-hours 1
  [ "$status" -eq 0 ]
  grep -q '"source":"express-request"' "$SAVIA_GRANTS_DIR/autonomy:overnight-sprint.json"
}

@test "invalid scope rejected (exit 2)" {
  run bash "$SCRIPT" grant --scope autonomy:bogus --context x
  [ "$status" -eq 2 ]
}

@test "revoke removes grant and pending request (check 3)" {
  issue_merge "revoke test"
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "otra" --ttl-hours 1
  [ -e "$TMP_GRANTS/merge.request" ]
  bash "$SCRIPT" revoke --scope merge
  [ ! -e "$TMP_GRANTS/merge.request" ]
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 3 ]
}

@test "grant idempotent renews expiry" {
  bash "$SCRIPT" grant --scope autonomy:overnight-sprint --context "first" --ttl-hours 1
  bash "$SCRIPT" grant --scope autonomy:overnight-sprint --context "second" --ttl-hours 2
  run bash "$SCRIPT" check --scope autonomy:overnight-sprint
  [ "$status" -eq 0 ]
}

# ── integración con double-optin (SE-343) ───────────────────────────────

@test "double-optin passes with grant and WITHOUT env var" {
  # SE-343: emit the autonomy grant inside the test body (each test gets a
  # fresh SAVIA_GRANTS_DIR from setup). No env var needed for factor 1.
  run bash "$REAL_SCRIPT" grant --scope autonomy:overnight-sprint \
    --context "autonomous session" --ttl-hours 1
  [ "$status" -eq 0 ]
  run bash scripts/savia-double-optin-check.sh --skill overnight-sprint \
    --confirm-autonomous
  [ "$status" -eq 0 ]
}

@test "fail-closed: no resolvable operator means no grant is issued" {
  printf '# no slug\n' > "$SAVIA_ACTIVE_USER_FILE"
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "no operator"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no active operator"* ]]
  [ ! -e "$TMP_GRANTS/merge.json" ]
  [ ! -e "$TMP_GRANTS/merge.request" ]
}

@test "missing: nonexistent profile file also refuses to grant" {
  export SAVIA_ACTIVE_USER_FILE="$TMP_GRANTS/does-not-exist.md"
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "no profile"
  [ "$status" -eq 2 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "cwd-independent: grant and check work when run from another directory" {
  # Una raíz de confianza plantada en el cwd no se usa: cuenta la del repo del script.
  mkdir -p "$TMP_GRANTS/elsewhere/config"
  printf 'intruso namespaces="savia-operator-grant" ssh-ed25519 AAAA\n' > "$TMP_GRANTS/elsewhere/config/operator-grant-signers"
  cd "$TMP_GRANTS/elsewhere"
  issue_merge "cwd test"
  grep -q "\"grantor\":\"$ACTIVE_SLUG\"" "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
}

@test "empty: grant without --context is rejected" {
  run bash "$SCRIPT" grant --scope merge --resource pr:1
  [ "$status" -eq 2 ]
  [[ "$output" == *"--context required"* ]]
}

@test "reject: a grant file whose grantor is self never validates" {
  printf '{"scope":"merge","grantor":"self","source":"express-request","expires_epoch":%s}\n' "$(( $(date +%s) + 3600 ))" > "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
}

# ── P1: grant de merge firmado por la operadora (LAW-HUMAN-002) ─────────

@test "P1: grant --scope merge sin firma solo deja una petición y NO pasa check" {
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "la operadora lo pidió" --ttl-hours 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"-n savia-operator-grant"* ]]
  [ ! -e "$TMP_GRANTS/merge.json" ]
  [ -e "$TMP_GRANTS/merge.request" ]
  [ "$(stat -c %a "$TMP_GRANTS/merge.request")" = "600" ]
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 3 ]
}

@test "P1: con la firma de la operadora el grant se emite y la petición se consume" {
  issue_merge "merge #1 pedido"
  [ ! -e "$TMP_GRANTS/merge.request" ]
  grep -q 'BEGIN SSH SIGNATURE' "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
}

@test "P1: la firma también se acepta pegada por stdin (--signature -)" {
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "desde el móvil" --ttl-hours 1
  sign_request
  run bash "$SCRIPT" grant --scope merge --signature - < "$TMP_GRANTS/req.sig"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
}

@test "P1: una clave que no está en la raíz de confianza (la de un agente) no vale" {
  ssh-keygen -q -t ed25519 -N "" -C agent -f "$TMP_GRANTS/agent-key"
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "me lo firmo yo" --ttl-hours 1
  sign_request "$TMP_GRANTS/agent-key"
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
  [ "$status" -eq 1 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "P1: firma con otro namespace no vale" {
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "ns" --ttl-hours 1
  sign_request "$KEY" "git"
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
  [ "$status" -eq 1 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "P1: la firma de otra petición no vale para la nueva" {
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "merge del PR 1" --ttl-hours 1
  sign_request
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "merge de todo" --ttl-hours 1
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
  [ "$status" -eq 1 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "P1: una petición alterada antes de adjuntar la firma se rechaza" {
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "corta" --ttl-hours 1
  sign_request
  sed -i 's/"corta"/"larga"/' "$TMP_GRANTS/merge.request"
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
  [ "$status" -eq 1 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "P1: la clave registrada con otra identidad no firma por la operadora activa" {
  sed -i "s/^$ACTIVE_SLUG /otra-operadora /" "$SIGNERS"
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "identidad" --ttl-hours 1
  sign_request
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
  [ "$status" -eq 1 ]
}

@test "P1: una petición caducada no se puede firmar a posteriori" {
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "vieja" --ttl-hours 0
  sign_request
  sleep 1
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
  [ "$status" -eq 1 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "P1: --signature sin petición pendiente o fuera de merge es invocación inválida" {
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/nada.sig"
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" grant --scope autonomy:overnight-sprint --signature "$TMP_GRANTS/nada.sig"
  [ "$status" -eq 2 ]
}

@test "P1: un merge.json escrito a mano (sin firma o con firma basura) no pasa check" {
  printf '{"id":"%s","scope":"merge","resource":"pr:1","grantor":"%s","source":"operator-signature","request_context":"x","issued_at":"t","issued_epoch":%s,"expires_epoch":%s}\n' \
    "0123456789abcdef0123456789abcdef" "$ACTIVE_SLUG" "$(date +%s)" "$(( $(date +%s) + 3600 ))" > "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  python3 - "$TMP_GRANTS/merge.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
r["sig"] = "-----BEGIN SSH SIGNATURE-----\nAAAA\n-----END SSH SIGNATURE-----\n"
json.dump(r, open(sys.argv[1], "w"))
PY
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
}

@test "P1: grant alterado tras firmar, source cambiado o clave retirada no pasan check" {
  issue_merge "firmado"
  cp "$TMP_GRANTS/merge.json" "$TMP_GRANTS/orig"
  sed -i 's/"request_context":"firmado"/"request_context":"todo"/' "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  cp "$TMP_GRANTS/orig" "$TMP_GRANTS/merge.json"
  sed -i 's/"source":"operator-signature"/"source":"express-request"/' "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  # Control: el original sigue valiendo, así que los rechazos de arriba son por la alteración.
  cp "$TMP_GRANTS/orig" "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
  printf '# clave retirada\n' > "$SIGNERS"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
}

@test "P1: la raíz de confianza versionada no contiene ninguna clave (fail-closed)" {
  # Un grant firmado con la clave de prueba no vale contra el fichero del repo.
  issue_merge "contra el repo"
  run bash "$REAL_SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  run grep -vE '^[[:space:]]*(#|$)' "$BATS_TEST_DIRNAME/../config/operator-grant-signers"
  [ "$status" -eq 1 ]
}

@test "contexto con comillas produce JSON válido (sin inyección de campos)" {
  # Un contexto que intenta colar su propia caducidad no alarga un grant caducado.
  run bash "$SCRIPT" grant --scope autonomy:overnight-sprint --ttl-hours 0 \
    --context 'x","expires_epoch":9999999999,"y":"'
  sleep 1
  run bash "$SCRIPT" check --scope autonomy:overnight-sprint
  [ "$status" -eq 1 ]
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SAVIA_GRANTS_DIR/autonomy:overnight-sprint.json"
}

# ── operator-grant.sh guard (PreToolUse) ────────────────────────────────

@test "guard: veta a Write/Edit/Bash modificar la raíz de confianza" {
  run bash "$SCRIPT" guard < <(guard_event Write file_path "$SIGNERS")
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(guard_event Edit file_path "config/operator-grant-signers")
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(guard_event NotebookEdit notebook_path "$SIGNERS")
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(guard_event Bash command "echo 'x ssh-ed25519 AAAA' >> config/operator-grant-signers")
  [ "$status" -eq 2 ]
}

@test "guard: deja pasar la lectura de la clave pública y el resto de órdenes" {
  run bash "$SCRIPT" guard < <(guard_event Read file_path "$SIGNERS")
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" guard < <(guard_event Write file_path "$TMP_GRANTS/otro.txt")
  [ "$status" -eq 0 ]
  for c in 'bash scripts/operator-grant.sh grant --scope merge --resource pr:1 --context "PR 7"' \
           'bash scripts/operator-grant.sh check --scope merge' 'git status'; do
    run bash "$SCRIPT" guard < <(guard_event Bash command "$c")
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "guard: sin entrada o con entrada no JSON, bloquea (nunca 0 sin evaluar)" {
  run bash "$SCRIPT" guard < /dev/null
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard <<< "no-json"
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard <<< "[]"
  [ "$status" -eq 2 ]
}

# ── Fase 0: el control deniega (revisión de #1401, 2026-10-27) ──────────

@test "F0: el grant lleva id único, principal, scope, resource y vigencia firmados" {
  run bash "$SCRIPT" grant --scope merge --resource pr:41 --context "uno" --ttl-hours 1
  [ "$status" -eq 4 ]
  cp "$TMP_GRANTS/merge.request" "$TMP_GRANTS/req1"
  run bash "$SCRIPT" grant --scope merge --resource pr:41 --context "uno" --ttl-hours 1
  python3 - "$TMP_GRANTS/req1" "$TMP_GRANTS/merge.request" "$ACTIVE_SLUG" <<'PY'
import json, re, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
assert re.fullmatch(r"[0-9a-f]{32}", a["id"]) and a["id"] != b["id"], (a["id"], b["id"])
assert a["scope"] == "merge" and a["resource"] == "pr:41" and a["grantor"] == sys.argv[3]
assert a["repo"] == "github.com/test-org/repo-a", a["repo"]
assert isinstance(a["issued_epoch"], int) and a["expires_epoch"] > a["issued_epoch"]
PY
}

@test "F0: pedir un grant de merge sin --resource válido es invocación inválida" {
  for r in "" "*" "pr:" "main" "pr:1;rm" "PR:1"; do
    run bash "$SCRIPT" grant --scope merge --resource "$r" --context "sin recurso" --ttl-hours 1
    [ "$status" -eq 2 ]
  done
  [ ! -e "$TMP_GRANTS/merge.request" ]
}

@test "F0: check de merge sin --resource (o con comodín) no da PASS" {
  issue_merge "recurso"
  run bash "$SCRIPT" check --scope merge
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" check --scope merge --resource "*"
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
}

@test "F0: un grant firmado para un PR no vale para otro (alcance en el punto de uso)" {
  issue_merge "solo el 1" pr:1
  run bash "$SCRIPT" check --scope merge --resource pr:2
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" check --scope merge --resource task:1
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" consume --scope merge --resource pr:2
  [ "$status" -eq 1 ]
  # El intento fallido no gasta ni retira el grant legítimo.
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
}

@test "F0: replay — una copia del grant ya consumido se rechaza en check" {
  issue_merge "una vez"
  cp "$TMP_GRANTS/merge.json" "$TMP_GRANTS/copia"
  run bash "$SCRIPT" consume --scope merge --resource pr:1
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 3 ]
  cp "$TMP_GRANTS/copia" "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" consume --scope merge --resource pr:1
  [ "$status" -eq 1 ]
}

@test "F0: revocado — restaurar la copia de un grant revocado no lo revive" {
  issue_merge "revocable"
  cp "$TMP_GRANTS/merge.json" "$TMP_GRANTS/copia"
  bash "$SCRIPT" revoke --scope merge
  grep -q "revoked" "$TMP_GRANTS/merge.spent"
  cp "$TMP_GRANTS/copia" "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
}

@test "F0: un grant de merge copiado a otro scope no vale allí" {
  issue_merge "otro scope"
  cp "$TMP_GRANTS/merge.json" "$TMP_GRANTS/autonomy:overnight-sprint.json"
  run bash "$SCRIPT" check --scope autonomy:overnight-sprint
  [ "$status" -eq 1 ]
}

@test "F0: un byte cambiado en el grant tras firmar (id o recurso) se rechaza" {
  issue_merge "byte"
  cp "$TMP_GRANTS/merge.json" "$TMP_GRANTS/orig"
  sed -i 's/"resource":"pr:1"/"resource":"pr:7"/' "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:7
  [ "$status" -eq 1 ]
  cp "$TMP_GRANTS/orig" "$TMP_GRANTS/merge.json"
  python3 - "$TMP_GRANTS/merge.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
r["id"] = ("1" if r["id"][0] != "1" else "2") + r["id"][1:]
json.dump(r, open(sys.argv[1], "w"))
PY
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  cp "$TMP_GRANTS/orig" "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
}

# Reescribe la petición pendiente con vigencia de $1 segundos, en forma canónica
# (la que firma la operadora): permite probar la caducidad sin tocar el reloj.
short_request() {
  python3 - "$TMP_GRANTS/merge.request" "$1" <<'PY'
import json, sys, time
p, secs = sys.argv[1], int(sys.argv[2])
r = json.load(open(p))
r["expires_epoch"] = int(time.time()) + secs
open(p, "wb").write(json.dumps(r, sort_keys=True, ensure_ascii=True, separators=(",", ":")).encode())
PY
}

@test "F0: grant firmado y luego caducado no pasa check" {
  run bash "$SCRIPT" grant --scope merge --resource pr:1 --context "dos segundos" --ttl-hours 1
  [ "$status" -eq 4 ]
  short_request 2
  sign_request
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
  sleep 3
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
}

@test "F0: sin fichero de claves públicas o sin ssh-keygen, check no da PASS (fail-closed)" {
  issue_merge "sin clave"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
  # El script fija su PATH (SAFE_PATH); la copia de prueba lo apunta a un bin
  # con las mismas herramientas. Control positivo: con ssh-keygen enlazado da 0;
  # sin él, 1. Así lo que cambia el resultado es solo la ausencia de ssh-keygen.
  mkdir -p "$TMP_GRANTS/bin"
  for t in python3 git grep date head cat mkdir chmod rm basename dirname timeout ssh-keygen; do
    ln -s "$(command -v "$t")" "$TMP_GRANTS/bin/$t"
  done
  sed -i "s|^SAFE_PATH=.*|SAFE_PATH=\"$TMP_GRANTS/bin\"|" "$SCRIPT"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 0 ]
  unlink "$TMP_GRANTS/bin/ssh-keygen"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  mv "$SIGNERS" "$SIGNERS.off"
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
}

@test "F0: la suite no escribe fuera de su directorio temporal (HOME aislado)" {
  [[ "$HOME" == "$TMP_GRANTS"/* ]]
  [[ "$SAVIA_GRANTS_DIR" == "$TMP_GRANTS"* ]]
  # Con los defaults del script (sin SAVIA_GRANTS_DIR), todo cae bajo el HOME del test.
  tag="isolation-$$-$RANDOM$RANDOM"
  run env -u SAVIA_GRANTS_DIR bash "$SCRIPT" grant --scope merge --resource pr:1 --context "$tag" --ttl-hours 1
  [ "$status" -eq 4 ]
  grep -q "$tag" "$HOME/.savia/grants/merge.request"
  # Y nada con esa marca llegó al HOME real.
  for d in "$REAL_HOME/.savia/grants" "$REAL_HOME/.savia/grant-tickets"; do
    [[ -d "$d" ]] || continue
    run grep -rlF "$tag" "$d"
    [ "$status" -eq 1 ]
  done
}

# ── guard: entradas malformadas y rodeos de shell (revisión Codex) ──────

@test "guard: evento incompleto o con tipos erróneos bloquea con exit 2 (no 0 ni 1)" {
  for ev in '{}' '{"tool_name":"Write","tool_input":{}}' '{"tool_name":"Write","tool_input":["config/x"]}' \
            '{"tool_name":"Bash","tool_input":"echo"}' '{"tool_name":"Bash","tool_input":{}}' \
            '{"tool_input":{"command":"ls"}}' '{"tool_name":"Edit","tool_input":{"file_path":7}}'; do
    run bash "$SCRIPT" guard <<< "$ev"
    [ "$status" -eq 2 ]
  done
}

@test "guard: comillas, barras, globs y llaves que resuelven a la raíz de confianza se vetan" {
  cd "$FAKE_REPO"
  for c in "printf x >> config/operator-grant-''signers" \
           'printf x >> config/operator-grant-\signers' \
           'printf x >> config/operator-grant-signer[s]' \
           'printf x >> config/operator-grant-sig*' \
           'tee -a config/operator-grant-{signers,x}' \
           'sed -i s/a/b/ config/*' \
           "find . -name 'operator-grant-sig*' -exec sed -i s/a/b/ {} +"; do
    run bash "$SCRIPT" guard < <(guard_event Bash command "$c" "$FAKE_REPO")
    [ "$status" -eq 2 ]
  done
}

@test "guard: la copia de otro worktree también se protege; los nombres parecidos no" {
  run bash "$SCRIPT" guard < <(guard_event Write file_path "/otro/worktree/config/operator-grant-signers")
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(guard_event Write file_path "docs/operator-grant-signers-notes.md")
  [ "$status" -eq 0 ]
  cd "$FAKE_REPO"
  for c in 'ls *.md' 'echo {a,b}' 'cat scripts/*'; do
    run bash "$SCRIPT" guard < <(guard_event Bash command "$c" "$FAKE_REPO")
    [ "$status" -eq 0 ]
  done
}

# ── Segunda revisión de #1401 (Codex + security + correctness, 2026-10-27) ──

@test "guard: comillas ANSI-C, \$\"…\", continuaciones y escapes de printf que componen el nombre se vetan" {
  cd "$FAKE_REPO"
  for c in "cat /tmp/a >> config/operator-grant-s\$'\\x69'gners" \
           "cat /tmp/a >> config/operator-grant-s\$'\\151'gners" \
           "cat /tmp/a >> config/operator-grant-s\$'\\u0069'gners" \
           "tee -a config/operator-grant-s\$\"igners\"" \
           $'tee -a config/operator-grant-signer\\\ns' \
           "tee -a \"\$(printf 'config/operator-grant-s\\x69gners')\""; do
    run bash "$SCRIPT" guard < <(guard_event Bash command "$c" "$FAKE_REPO")
    [ "$status" -eq 2 ]
  done
  # Control: ANSI-C que no compone el nombre pasa.
  run bash "$SCRIPT" guard < <(guard_event Bash command "printf \$'hola\\x21\\n'" "$FAKE_REPO")
  [ "$status" -eq 0 ]
}

@test "guard: una orden que tumbaba el analizador (recursión), una explosión de llaves o una ruta con NUL salen con 2" {
  cd "$FAKE_REPO"
  run bash "$SCRIPT" guard < <(python3 -c 'import json,os; print(json.dumps({"tool_name":"Bash","cwd":os.getcwd(),"tool_input":{"command":"# "+"{x}"*1000+"\ncat /tmp/a | tee -a config/o*"}}))')
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(python3 -c 'import json,os; print(json.dumps({"tool_name":"Bash","cwd":os.getcwd(),"tool_input":{"command":"echo "+"{a,b}"*12}}))')
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(python3 -c 'import json; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":"a\u0000b"}}))')
  [ "$status" -eq 2 ]
  # Control: llaves normales y muchas llaves de una sola alternativa sin escritura pasan.
  run bash "$SCRIPT" guard < <(guard_event Bash command "echo {a,b}{c,d}" "$FAKE_REPO")
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" guard < <(python3 -c 'import json,os; print(json.dumps({"tool_name":"Bash","cwd":os.getcwd(),"tool_input":{"command":"echo "+"{x}"*1000}}))')
  [ "$status" -eq 0 ]
}

@test "guard: sin python3 (exit 127) el hook sale con 2, nunca con un fallo que Claude Code deja pasar" {
  mkdir -p "$TMP_GRANTS/nopy"
  for t in timeout cat; do ln -s "$(command -v "$t")" "$TMP_GRANTS/nopy/$t"; done
  sed -i "s|^SAFE_PATH=.*|SAFE_PATH=\"$TMP_GRANTS/nopy\"|" "$SCRIPT"
  run bash "$SCRIPT" guard < <(guard_event Bash command "ls")
  [ "$status" -eq 2 ]
  [[ "$output" == *"exit 127"* ]]
}

@test "guard: un nombre más largo es otro fichero; el nombre exacto en Bash se veta aunque sea una lectura" {
  run bash "$SCRIPT" guard < <(guard_event Bash command "echo docs/operator-grant-signers-notes.md")
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" guard < <(guard_event Bash command "git status -- config/operator-grant-signers")
  [ "$status" -eq 2 ]
}

@test "P1: un grant firmado para el repo A no vale en otro checkout B con el mismo número de PR" {
  issue_merge "solo A" pr:41
  run bash "$SCRIPT" check --scope merge --resource pr:41
  [ "$status" -eq 0 ]
  B="$TMP_GRANTS/repo-b"
  mkdir -p "$B/scripts" "$B/config"
  cp "$REAL_SCRIPT" "$B/scripts/"
  cp "$SIGNERS" "$B/config/"
  git -C "$B" init -q
  git -C "$B" remote add origin "https://github.com/test-org/repo-b.git"
  run bash "$B/scripts/operator-grant.sh" check --scope merge --resource pr:41
  [ "$status" -eq 1 ]
  run bash "$B/scripts/operator-grant.sh" consume --scope merge --resource pr:41
  [ "$status" -eq 1 ]
  # Sin remoto identificable no hay PASS, ni se puede pedir un grant.
  git -C "$B" remote remove origin
  run bash "$B/scripts/operator-grant.sh" check --scope merge --resource pr:41
  [ "$status" -eq 1 ]
  run bash "$B/scripts/operator-grant.sh" grant --scope merge --resource pr:2 --context "sin remoto"
  [ "$status" -eq 2 ]
  # El mismo repositorio con otra forma de URL (ssh, mayúsculas) sigue valiendo.
  git -C "$FAKE_REPO" remote set-url origin "git@github.com:Test-Org/repo-a.git"
  run bash "$SCRIPT" check --scope merge --resource pr:41
  [ "$status" -eq 0 ]
}

@test "P1: revocar una petición pendiente impide firmarla e incorporarla después" {
  run bash "$SCRIPT" grant --scope merge --resource pr:41 --context "pendiente" --ttl-hours 1
  [ "$status" -eq 4 ]
  sign_request
  cp "$TMP_GRANTS/merge.request" "$TMP_GRANTS/req.copia"
  run bash "$SCRIPT" revoke --scope merge
  [ "$status" -eq 0 ]
  grep -q "revoked" "$TMP_GRANTS/merge.spent"
  cp "$TMP_GRANTS/req.copia" "$TMP_GRANTS/merge.request"
  run bash "$SCRIPT" grant --scope merge --signature "$TMP_GRANTS/req.sig"
  [ "$status" -eq 1 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
  run bash "$SCRIPT" check --scope merge --resource pr:41
  [ "$status" -eq 3 ]
}

@test "P2: ni PYTHONPATH con sitecustomize ni un ssh-keygen falso en el PATH dan PASS sin firma" {
  issue_merge "entorno" pr:1
  python3 - "$TMP_GRANTS/merge.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
r["sig"] = "-----BEGIN SSH SIGNATURE-----\nAAAA\n-----END SSH SIGNATURE-----\n"
json.dump(r, open(sys.argv[1], "w"))
PY
  run bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  mkdir -p "$TMP_GRANTS/hook" "$TMP_GRANTS/fakebin"
  printf 'import subprocess\nsubprocess.run = lambda *a, **k: subprocess.CompletedProcess(a, 0, b"", b"")\n' \
    > "$TMP_GRANTS/hook/sitecustomize.py"
  run env PYTHONPATH="$TMP_GRANTS/hook" bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
  printf '#!/bin/sh\nexit 0\n' > "$TMP_GRANTS/fakebin/ssh-keygen"
  chmod +x "$TMP_GRANTS/fakebin/ssh-keygen"
  run env PATH="$TMP_GRANTS/fakebin:$PATH" bash "$SCRIPT" check --scope merge --resource pr:1
  [ "$status" -eq 1 ]
}
