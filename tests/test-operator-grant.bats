#!/usr/bin/env bats
# BATS tests for scripts/operator-grant.sh (SE-343)
# Ref: SE-343, SPEC-186, autonomous-safety.md

SCRIPT="scripts/operator-grant.sh"

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  TMP_GRANTS="$(mktemp -d -t grants.XXXXXX)"
  export SAVIA_GRANTS_DIR="$TMP_GRANTS"
  # Deterministic expected grantor, decoupled from the real operator's identity
  # (active-user.md is gitignored; never put a real personal slug in repo files).
  ACTIVE_SLUG="test-operator"
  # Fixture profile: never depends on the real (gitignored) active-user.md.
  export SAVIA_ACTIVE_USER_FILE="$TMP_GRANTS/active-user.md"
  printf 'active_slug: "%s"\n' "$ACTIVE_SLUG" > "$SAVIA_ACTIVE_USER_FILE"
  # Clave HMAC y tickets del diálogo, aislados por test (mismos nombres que en real).
  export SAVIA_GRANT_KEY_FILE="$TMP_GRANTS/grant-keys/operator-grant.key"
  export SAVIA_GRANT_TICKETS_DIR="$TMP_GRANTS/grant-tickets"
}


# Simula la orden que ve el hook PreToolUse; $2 = permission_mode.
guard_input() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"permission_mode":sys.argv[2]}))' "$1" "${2:-default}"
}

# La operadora contesta el diálogo del arnés: el guard deja el ticket.
ask_ticket() {
  guard_input "bash scripts/operator-grant.sh grant --scope merge --context \"$1\" --ttl-hours 1" | bash "$SCRIPT" guard >/dev/null
}

teardown() {
  [[ -n "$TMP_GRANTS" && -d "$TMP_GRANTS" ]] && rm -rf "$TMP_GRANTS"
  cd /
}

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "passes bash -n syntax" {
  run bash -n "$SCRIPT"
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
  run bash "$SCRIPT" check --scope merge
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

@test "grantor is active user slug, never self; merge source is the measured channel" {
  ask_ticket "test"
  run bash "$SCRIPT" grant --scope merge --context "test" --ttl-hours 1
  [ "$status" -eq 0 ]
  file="$(ls "$SAVIA_GRANTS_DIR"/merge.json)"
  grep -q "\"grantor\":\"$ACTIVE_SLUG\"" "$file"
  ! grep -q '"grantor":"self"' "$file"
  grep -q '"source":"harness-ask"' "$file"
  ! grep -q '"source":"express-request"' "$file"
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

@test "revoke removes grant (check 3)" {
  ask_ticket "revoke test"
  bash "$SCRIPT" grant --scope merge --context "revoke test" --ttl-hours 1
  bash "$SCRIPT" revoke --scope merge
  run bash "$SCRIPT" check --scope merge
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
  run bash "$SCRIPT" grant --scope autonomy:overnight-sprint \
    --context "autonomous session" --ttl-hours 1
  [ "$status" -eq 0 ]
  run bash scripts/savia-double-optin-check.sh --skill overnight-sprint \
    --confirm-autonomous
  [ "$status" -eq 0 ]
}
@test "fail-closed: no resolvable operator means no grant is issued" {
  printf '# no slug\n' > "$SAVIA_ACTIVE_USER_FILE"
  run bash "$SCRIPT" grant --scope merge --context "no operator"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no active operator"* ]]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "missing: nonexistent profile file also refuses to grant" {
  export SAVIA_ACTIVE_USER_FILE="$TMP_GRANTS/does-not-exist.md"
  run bash "$SCRIPT" grant --scope merge --context "no profile"
  [ "$status" -eq 2 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "cwd-independent: grant and check work when run from another directory" {
  ask_ticket "cwd test"
  cd "$TMP_GRANTS"
  run bash "$BATS_TEST_DIRNAME/../scripts/operator-grant.sh" grant --scope merge --context "cwd test" --ttl-hours 1
  [ "$status" -eq 0 ]
  grep -q "\"grantor\":\"$ACTIVE_SLUG\"" "$TMP_GRANTS/merge.json"
  run bash "$BATS_TEST_DIRNAME/../scripts/operator-grant.sh" check --scope merge
  [ "$status" -eq 0 ]
}

@test "empty: grant without --context is rejected" {
  run bash "$SCRIPT" grant --scope merge
  [ "$status" -eq 2 ]
  [[ "$output" == *"--context required"* ]]
}

@test "reject: a grant file whose grantor is self never validates" {
  printf '{"scope":"merge","grantor":"self","source":"express-request","expires_epoch":%s}\n' "$(( $(date +%s) + 3600 ))" > "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge
  [ "$status" -eq 1 ]
}

# ── P1: grant de merge sin interacción humana (LAW-HUMAN-002) ───────────

@test "P1: grant --scope merge sin prueba de interacción humana NO pasa check" {
  run bash "$SCRIPT" grant --scope merge --context "la operadora lo pidió" --ttl-hours 1
  [ "$status" -eq 4 ]
  [[ "$output" == *"exige a la operadora"* ]]
  [ ! -e "$TMP_GRANTS/merge.json" ]
  run bash "$SCRIPT" check --scope merge
  [ "$status" -ne 0 ]
}

@test "P1: con el ticket del diálogo el grant se emite firmado y el ticket se consume" {
  ask_ticket "merge #1 pedido"
  [ "$(ls "$SAVIA_GRANT_TICKETS_DIR" | wc -l)" -eq 1 ]
  run bash "$SCRIPT" grant --scope merge --context "merge #1 pedido" --ttl-hours 1
  [ "$status" -eq 0 ]
  grep -qE '"sig":"[0-9a-f]{64}"' "$TMP_GRANTS/merge.json"
  [ "$(ls "$SAVIA_GRANT_TICKETS_DIR" | wc -l)" -eq 0 ]
  [ "$(stat -c %a "$SAVIA_GRANT_KEY_FILE")" = "600" ]
  run bash "$SCRIPT" check --scope merge
  [ "$status" -eq 0 ]
}

@test "P1: el ticket es de un solo uso" {
  ask_ticket "una vez"
  bash "$SCRIPT" grant --scope merge --context "una vez" --ttl-hours 1
  bash "$SCRIPT" revoke --scope merge
  run bash "$SCRIPT" grant --scope merge --context "una vez" --ttl-hours 1
  [ "$status" -eq 4 ]
}

@test "P1: un ticket de otro contexto no vale" {
  ask_ticket "merge del PR 1"
  run bash "$SCRIPT" grant --scope merge --context "merge de todo" --ttl-hours 1
  [ "$status" -eq 4 ]
  [ ! -e "$TMP_GRANTS/merge.json" ]
}

@test "P1: un ticket caducado (> 5 min) no vale y se borra" {
  ask_ticket "viejo"
  t="$(ls "$SAVIA_GRANT_TICKETS_DIR"/*.json)"
  printf '{"ts": %s}' "$(( $(date +%s) - 301 ))" > "$t"
  run bash "$SCRIPT" grant --scope merge --context "viejo" --ttl-hours 1
  [ "$status" -eq 4 ]
  [ ! -e "$t" ]
}

@test "P1: un merge.json escrito a mano (sin firma) no pasa check" {
  printf '{"scope":"merge","grantor":"%s","source":"tty","request_context":"x","issued_at":"t","expires_epoch":%s}\n' \
    "$ACTIVE_SLUG" "$(( $(date +%s) + 3600 ))" > "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge
  [ "$status" -eq 1 ]
}

@test "P1: firma con otra clave o grant alterado tras firmar no pasan check" {
  ask_ticket "firmado"
  bash "$SCRIPT" grant --scope merge --context "firmado" --ttl-hours 1
  cp "$TMP_GRANTS/merge.json" "$TMP_GRANTS/orig"
  # Alterar la caducidad invalida la firma.
  sed -i -E 's/"expires_epoch":[0-9]+/"expires_epoch":9999999999/' "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge
  [ "$status" -eq 1 ]
  # Mismo grant, otra clave en disco: tampoco.
  cp "$TMP_GRANTS/orig" "$TMP_GRANTS/merge.json"
  python3 -c 'import secrets;print(secrets.token_hex(32))' > "$SAVIA_GRANT_KEY_FILE"
  run bash "$SCRIPT" check --scope merge
  [ "$status" -eq 1 ]
}

@test "P1: source express-request ya no basta para merge aunque la firma cuadre" {
  ask_ticket "fuente"
  bash "$SCRIPT" grant --scope merge --context "fuente" --ttl-hours 1
  python3 - "$TMP_GRANTS/merge.json" "$SAVIA_GRANT_KEY_FILE" <<'PY'
import hashlib, hmac, json, sys
p, kf = sys.argv[1:3]
r = json.load(open(p)); r["source"] = "express-request"
F = ("scope", "grantor", "source", "request_context", "issued_at", "expires_epoch")
m = json.dumps({f: r.get(f) for f in F}, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
r["sig"] = hmac.new(bytes.fromhex(open(kf).read().strip()), m.encode(), hashlib.sha256).hexdigest()
json.dump(r, open(p, "w"))
PY
  run bash "$SCRIPT" check --scope merge
  [ "$status" -eq 1 ]
}

@test "P1: en la terminal de la operadora, escribir MERGE concede (source tty)" {
  command -v script >/dev/null || skip "util-linux script no disponible para simular una terminal"
  run script -qec "bash $SCRIPT grant --scope merge --context terminal --ttl-hours 1" /dev/null <<< "MERGE"
  grep -q '"source":"tty"' "$TMP_GRANTS/merge.json"
  run bash "$SCRIPT" check --scope merge
  [ "$status" -eq 0 ]
}

@test "P1: en la terminal, otra respuesta no concede" {
  command -v script >/dev/null || skip "util-linux script no disponible para simular una terminal"
  run script -qec "bash $SCRIPT grant --scope merge --context terminal --ttl-hours 1" /dev/null <<< "si"
  [ ! -e "$TMP_GRANTS/merge.json" ]
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

@test "guard: grant de merge en modo normal pide el diálogo y deja ticket" {
  run bash "$SCRIPT" guard < <(guard_input 'bash scripts/operator-grant.sh grant --scope merge --context "PR 7"')
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision": "ask"'* ]]
  [ "$(ls "$SAVIA_GRANT_TICKETS_DIR" | wc -l)" -eq 1 ]
}

@test "guard: en bypassPermissions o dontAsk deniega y no deja ticket" {
  for mode in bypassPermissions dontAsk; do
    run bash "$SCRIPT" guard < <(guard_input 'bash scripts/operator-grant.sh grant --scope merge --context "PR 7"' "$mode")
    [ "$status" -eq 2 ]
  done
  [ ! -d "$SAVIA_GRANT_TICKETS_DIR" ] || [ "$(ls "$SAVIA_GRANT_TICKETS_DIR" | wc -l)" -eq 0 ]
}

@test "guard: invocación ilegible pregunta sin dejar ticket" {
  run bash "$SCRIPT" guard < <(guard_input 'X=operator-grant.sh; eval "bash scripts/$X grant --scope merge --context y"')
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ask"'* ]]
  [ ! -d "$SAVIA_GRANT_TICKETS_DIR" ] || [ "$(ls "$SAVIA_GRANT_TICKETS_DIR" | wc -l)" -eq 0 ]
}

@test "guard: check, revoke y grants de autonomía pasan sin preguntar" {
  for c in 'bash scripts/operator-grant.sh check --scope merge' \
           'bash scripts/operator-grant.sh revoke --scope merge' \
           'bash scripts/operator-grant.sh grant --scope autonomy:overnight-sprint --context z' \
           'git status'; do
    run bash "$SCRIPT" guard < <(guard_input "$c")
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "guard: veta clave y tickets a Read, Grep sobre su carpeta madre y Bash" {
  kdir="$(dirname "$SAVIA_GRANT_KEY_FILE")"
  run bash "$SCRIPT" guard < <(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Read","tool_input":{"file_path":sys.argv[1]}}))' "$SAVIA_GRANT_KEY_FILE")
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Grep","tool_input":{"pattern":"a","path":sys.argv[1]}}))' "$TMP_GRANTS")
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1]+"/merge-x.json","content":"{}"}}))' "$SAVIA_GRANT_TICKETS_DIR")
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(guard_input "cat $kdir/*")
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard < <(guard_input 'SAVIA_GRANT_KEY_FILE=/tmp/k bash scripts/operator-grant.sh check --scope merge')
  [ "$status" -eq 2 ]
  # Negativo: una ruta ajena pasa.
  run bash "$SCRIPT" guard < <(python3 -c 'import json;print(json.dumps({"tool_name":"Read","tool_input":{"file_path":"/etc/hostname"}}))')
  [ "$status" -eq 0 ]
}

@test "guard: sin entrada o con entrada no JSON, bloquea (nunca 0 sin evaluar)" {
  run bash "$SCRIPT" guard < /dev/null
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" guard <<< "no-json"
  [ "$status" -eq 2 ]
}
