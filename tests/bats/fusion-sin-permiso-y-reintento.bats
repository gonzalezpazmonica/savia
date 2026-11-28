#!/usr/bin/env bats
# Dos rutas de efecto del inventario del 2026-11-02 que seguían abiertas:
#   A09 — review-community.sh merge fusionaba sin permiso firmado.
#   A02 — push-pr.sh reintentaba forzando la subida ante cualquier fallo.
# Cada caso negativo tiene su contraprueba: un test que no puede fallar no vale (SE-456).
# Ref: docs/rules/domain/autonomous-safety-merge-grant.md (la fusión exige permiso expreso).

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STUB="$BATS_TEST_TMPDIR/bin"
  LOG="$BATS_TEST_TMPDIR/llamadas.log"
  mkdir -p "$STUB"
  : > "$LOG"
}

teardown() {
  # BATS_TEST_TMPDIR lo limpia bats; se vacía el directorio de programas falsos por si el test aborta a medias.
  [ -n "${STUB:-}" ] && [ -d "$STUB" ] && find "$STUB" -type f -delete
  return 0
}

# gh falso: apunta cada invocación y sale bien.
stub_gh() {
  cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$LOG"
exit 0
EOF
  chmod +x "$STUB/gh"
}

# git falso: apunta cada invocación; el primer push sale con el código y el
# texto que se le indiquen, el push forzado sale con el código de FORCE_RC.
stub_git() {  # stub_git <rc_push> <texto_push> [rc_forzado]
  cat > "$STUB/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$LOG"
case "\$*" in
  *force-with-lease*) echo "forzado"; exit ${3:-0} ;;
  push*) echo "$2"; exit $1 ;;
esac
exit 0
EOF
  chmod +x "$STUB/git"
}

# Extrae la función real de push-pr.sh y la ejecuta con el git falso.
run_push() {
  local fn
  fn="$(sed -n '/^_push_branch() {$/,/^}$/p' "$REPO_DIR/scripts/push-pr.sh")"
  [ -n "$fn" ] || { echo "no se pudo extraer _push_branch"; return 99; }
  PATH="$STUB:$PATH" bash -c "set -euo pipefail; $fn; _push_branch rama-de-prueba"
}

# ── A09 ──────────────────────────────────────────────────────────────

@test "A09 error: merge rehúsa con código 3 y no llama a gh" {
  stub_gh
  PATH="$STUB:$PATH" run bash "$REPO_DIR/scripts/review-community.sh" merge 123
  [ "$status" -eq 3 ]
  [[ "$output" == *"retirado"* ]]
  [[ "$output" == *"merge-sprint.sh"* ]]
  [ ! -s "$LOG" ]
}

@test "A09 no arg: merge sin número de PR también rehúsa con 3" {
  stub_gh
  PATH="$STUB:$PATH" run bash "$REPO_DIR/scripts/review-community.sh" merge
  [ "$status" -eq 3 ]
  [ ! -s "$LOG" ]
}

@test "A09: el guion no contiene ninguna orden de fusión" {
  run grep -nE 'gh[[:space:]]+pr[[:space:]]+merge' "$REPO_DIR/scripts/review-community.sh"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "A09 contraprueba: el detector encuentra una orden de fusión sembrada" {
  printf 'gh pr merge 7 --squash\n' > "$BATS_TEST_TMPDIR/sembrado.sh"
  run grep -nE 'gh[[:space:]]+pr[[:space:]]+merge' "$BATS_TEST_TMPDIR/sembrado.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge 7"* ]]
}

@test "A09: la orden documenta la retirada y remite al camino con permiso" {
  run grep -c 'merge-sprint.sh' "$REPO_DIR/.claude/commands/review-community.md"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run grep -c 'review-community.sh merge {pr}`$' "$REPO_DIR/.claude/commands/review-community.md"
  [ "$output" -eq 0 ]
}

# ── A02 ──────────────────────────────────────────────────────────────

@test "A02: push correcto no reintenta ni fuerza" {
  stub_git 0 "Everything up-to-date"
  run run_push
  [ "$status" -eq 0 ]
  run grep -c 'force-with-lease' "$LOG"
  [ "$output" -eq 0 ]
  run grep -c '^git push origin rama-de-prueba$' "$LOG"
  [ "$output" -eq 1 ]
}

@test "A02: rechazo por historia divergente reintenta forzando con lease" {
  stub_git 1 "! [rejected] rama-de-prueba -> rama-de-prueba (non-fast-forward)"
  run run_push
  [ "$status" -eq 0 ]
  [[ "$output" == *"historia divergente"* ]]
  run grep -c 'force-with-lease origin rama-de-prueba' "$LOG"
  [ "$output" -eq 1 ]
}

@test "A02: rechazo por «fetch first» también cuenta como historia divergente" {
  stub_git 1 "! [rejected] rama-de-prueba -> rama-de-prueba (fetch first)"
  run run_push
  [ "$status" -eq 0 ]
  run grep -c 'force-with-lease' "$LOG"
  [ "$output" -eq 1 ]
}

@test "A02 error de red: no fuerza y sale con error" {
  stub_git 128 "fatal: unable to access 'https://example.invalid/': Could not resolve host"
  run run_push
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se fuerza"* ]]
  run grep -c 'force-with-lease' "$LOG"
  [ "$output" -eq 0 ]
}

@test "A02 reject por rama protegida o hook: no fuerza" {
  stub_git 1 "remote: error: GH006: Protected branch update failed
 ! [remote rejected] rama-de-prueba -> rama-de-prueba (protected branch hook declined)"
  run run_push
  [ "$status" -eq 1 ]
  run grep -c 'force-with-lease' "$LOG"
  [ "$output" -eq 0 ]
}

@test "A02 empty: salida vacía con fallo no fuerza" {
  stub_git 1 ""
  run run_push
  [ "$status" -eq 1 ]
  run grep -c 'force-with-lease' "$LOG"
  [ "$output" -eq 0 ]
}

@test "A02 boundary: si el reintento forzado falla, el error se propaga" {
  stub_git 1 "(non-fast-forward)" 1
  run run_push
  [ "$status" -ne 0 ]
  run grep -c 'force-with-lease' "$LOG"
  [ "$output" -eq 1 ]
}

@test "A02: push-pr.sh no conserva el reintento incondicional" {
  run grep -cE 'git push origin "\$BRANCH" 2>&1 \| tail -3 \|\|' "$REPO_DIR/scripts/push-pr.sh"
  [ "$output" -eq 0 ]
  run grep -c '_push_branch "\$BRANCH" ||' "$REPO_DIR/scripts/push-pr.sh"
  [ "$output" -eq 1 ]
}
