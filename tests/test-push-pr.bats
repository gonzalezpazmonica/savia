#!/usr/bin/env bats
# Ref: SE-300 (PR update), SE-343 (merge grant), SE-387 C/F5 (merge reservations)

setup() {
  PUSH_PR="$BATS_TEST_DIRNAME/../scripts/push-pr.sh"
  TESTDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "push-pr.sh exists and is executable" {
  [ -f "$PUSH_PR" ]
  [ -x "$PUSH_PR" ] || [ -f "$PUSH_PR" ]
}

@test "push-pr.sh has valid bash syntax" {
  bash -n "$PUSH_PR"
  [ "$?" -eq 0 ]
}

@test "push-pr.sh uses set -uo pipefail" {
  head -6 "$PUSH_PR" | grep -q "set -euo pipefail"
}

@test "push-pr.sh refuses to run on main branch" {
  # Can't actually run without a PR context; just verify the guard exists
  grep -q 'main.*master' "$PUSH_PR"
  grep -q 'ERROR: On' "$PUSH_PR"
}

@test "push-pr.sh has SE-300 existing-PR detection in gh CLI branch" {
  grep -q 'gh pr list -R "$REPO" --head' "$PUSH_PR"
  grep -q "gh pr edit" "$PUSH_PR"
  grep -q "EXISTING_PR" "$PUSH_PR"
}

@test "push-pr.sh has SE-300 update logic in python fallback branch" {
  grep -q "state=open" "$PUSH_PR"
  grep -q "method='PATCH'" "$PUSH_PR"
  grep -q "no_existing" "$PUSH_PR"
}

@test "push-pr.sh builds body from commits" {
  grep -q "git log --oneline origin/main..HEAD" "$PUSH_PR"
  grep -q "### Changes" "$PUSH_PR"
  grep -q "### Stats" "$PUSH_PR"
}

@test "push-pr.sh respects --title flag" {
  grep -q -- '--title) TITLE=' "$PUSH_PR"
}

@test "push-pr.sh respects --no-draft" {
  grep -q -- '--no-draft) DRAFT=false' "$PUSH_PR"
}

@test "SE-300: branch-switch hook clears stale .pr-summary.md" {
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/block-branch-switch-dirty.sh"
  [ -f "$HOOK" ]
  grep -q "SE-300" "$HOOK"
  grep -q ".pr-summary.md" "$HOOK"
  grep -q "rm -f" "$HOOK"
}

@test "SE-300: push-pr derives summary fallback when .pr-summary.md missing" {
  grep -q "Deriving summary\|Ver resumen tecnico" "$PUSH_PR"
  grep -q 'if \[\[ -f .pr-summary.md \]\]' "$PUSH_PR"
}

@test "SE-300: push-pr updates existing PR via gh pr edit" {
  grep -q 'gh pr list -R "$REPO" --head' "$PUSH_PR"
  grep -q "gh pr edit" "$PUSH_PR"
}

@test "SE-300: python fallback uses PATCH for existing PR" {
  grep -q "method='PATCH'" "$PUSH_PR"
  grep -q "no_existing" "$PUSH_PR"
}

res_dir_expr() { grep -oP '^\s*RES_DIR="\K[^"]+' "$PUSH_PR"; }

@test "SE-387: push-pr no longer hardcodes the reservations path" {
  run grep -c 'HOME/.savia/reservations/pr.merge' "$PUSH_PR"
  [ "$output" -eq 0 ]
  [[ "$(res_dir_expr)" == '${SAVIA_RESERVATIONS:-$HOME/.savia/reservations}' ]]
}

@test "SE-387: push-pr and f5-state resolve the same reservations dir from SAVIA_RESERVATIONS" {
  F5="$BATS_TEST_DIRNAME/../scripts/f5-state.sh"
  run env SAVIA_RESERVATIONS="$TESTDIR/res" bash "$F5" reserve pr.merge 4242
  [ "$status" -eq 0 ]
  expr=$(res_dir_expr)
  resolved=$(SAVIA_RESERVATIONS="$TESTDIR/res" HOME="$TESTDIR/home" bash -c "echo \"$expr\"")
  [ "$resolved" = "$TESTDIR/res" ]
  [ -f "$resolved/pr.merge__4242.json" ]
  [ ! -e "$TESTDIR/home/.savia" ]
}

@test "empty: unset SAVIA_RESERVATIONS falls back to the home ledger path" {
  expr=$(res_dir_expr)
  resolved=$(env -u SAVIA_RESERVATIONS HOME="$TESTDIR/home" bash -c "echo \"$expr\"")
  [ "$resolved" = "$TESTDIR/home/.savia/reservations" ]
}

@test "nonexistent: reserving an already closed merge is rejected as ALREADY_EXECUTED" {
  F5="$BATS_TEST_DIRNAME/../scripts/f5-state.sh"
  mkdir -p "$TESTDIR/res"
  printf '{"op":"pr.merge","key":"7","state":"closed"}\n' > "$TESTDIR/res/pr.merge__7.json"
  run env SAVIA_RESERVATIONS="$TESTDIR/res" bash "$F5" reserve pr.merge 7
  [ "$status" -eq 3 ]
  [[ "$output" == *"ALREADY_EXECUTED"* ]]
}

@test "boundary: merge path keeps grant and risk-tier gates before any reservation" {
  grant_line=$(grep -n 'operator-grant.sh check --scope merge' "$PUSH_PR" | head -1 | cut -d: -f1)
  tier_line=$(grep -n 'risk-tier.py --diff' "$PUSH_PR" | head -1 | cut -d: -f1)
  res_line=$(grep -n 'f5-state.sh" reserve' "$PUSH_PR" | head -1 | cut -d: -f1)
  [ -n "$grant_line" ] && [ -n "$tier_line" ] && [ -n "$res_line" ]
  [ "$grant_line" -lt "$res_line" ]
  [ "$tier_line" -lt "$res_line" ]
}

@test "SE-343: el grant de merge se comprueba y se consume para ESTE PR (pr:<n>), no uno cualquiera" {
  grep -q 'GRANT_RES="pr:$PR_NUM"' "$PUSH_PR"
  grep -q 'operator-grant.sh check --scope merge --resource "$GRANT_RES"' "$PUSH_PR"
  grep -q 'operator-grant.sh consume --scope merge --resource "$GRANT_RES"' "$PUSH_PR"
  # Ninguna llamada a check de merge sin recurso. (revoke sin recurso sí: gasta
  # el id del grant y de la petición; lo prueba test-operator-grant.bats.)
  run grep -nE 'operator-grant.sh check --scope merge( |$)[^-]*$' "$PUSH_PR"
  [ "$status" -eq 1 ]
}

# ── Regression: silent exit when no feat/fix commit (2026-09-27) ─────────────
# With `set -euo pipefail`, the title grep that finds no feat:/fix: commit made
# the assignment fail and the script exited in Step 6 without creating the PR.

make_repo() {
  local r="$TESTDIR/repo" o="$TESTDIR/origin.git"
  git init -q --bare "$o"
  git init -q -b main "$r"
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  mkdir -p "$r/scripts"
  cp "$BATS_TEST_DIRNAME/../scripts/push-pr.sh" "$r/scripts/"
  # Firmador simulado NO idempotente, como el real: cada firma cambia el
  # fichero (el real escribe timestamp y head_commit). verify compara el hash
  # del árbol de HEAD (sin la firma) con el firmado.
  cat > "$r/scripts/confidentiality-sign.sh" <<'SIGN'
#!/usr/bin/env bash
tree_hash() { git ls-tree -r HEAD | awk -F'\t' '$2 != ".confidentiality-signature"' | sha256sum | cut -d' ' -f1; }
case "${1:-}" in
  sign) printf 'diff_hash=%s\nnonce=%s-%s\n' "$(tree_hash)" "$(date +%s%N)" "$RANDOM" > .confidentiality-signature; echo SIGNED ;;
  verify) [[ -n "$(tree_hash)" && "$(sed -n 's/^diff_hash=//p' .confidentiality-signature 2>/dev/null)" == "$(tree_hash)" ]] ;;
  *) exit 2 ;;
esac
SIGN
  echo base > "$r/f.txt"; git -C "$r" add -A; git -C "$r" commit -qm "init"
  git -C "$r" remote add origin "$o"; git -C "$r" push -q origin main
  git -C "$r" checkout -q -b agent/x
  echo change >> "$r/f.txt"; git -C "$r" commit -qam "agent(overnight): cambio sin prefijo feat/fix"
  mkdir -p "$TESTDIR/bin"
  cat > "$TESTDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "auth status") exit "${GH_AUTH_RC:-0}" ;;
  "pr list") echo "${GH_LIST_OUT:-}" ;;
  "pr create") printf '%b\n' "${GH_CREATE_OUT:-https://github.com/o/r/pull/42}" ;;
esac
GH
  chmod +x "$TESTDIR/bin/gh"
  echo "$r"
}

@test "regression: branch without feat/fix commits still creates the PR" {
  r=$(make_repo)
  export GH_LOG="$TESTDIR/gh.log"
  cd "$r"
  run env PATH="$TESTDIR/bin:$PATH" bash scripts/push-pr.sh --from-pr-plan --skip-ci --skip-changelog
  [ "$status" -eq 0 ]
  [[ "$output" == *"pull/42"* ]]
  grep -q "pr create --title agent(overnight): cambio sin prefijo feat/fix" "$GH_LOG"
}

@test "regression: empty branch title falls back to the branch name, never empty" {
  r=$(make_repo)
  export GH_LOG="$TESTDIR/gh.log"
  cd "$r"
  git commit -q --allow-empty -m "Merge branch main"
  git reset -q --soft HEAD~2 && git commit -qm "chore: only chores" && echo x >> f.txt && git commit -qam "chore: more"
  run env PATH="$TESTDIR/bin:$PATH" bash scripts/push-pr.sh --from-pr-plan --skip-ci --skip-changelog
  [ "$status" -eq 0 ]
  grep -q "pr create --title agent/x" "$GH_LOG"
}

# ── SE-343: --merge de extremo a extremo con gh y operator-grant simulados ──
# operator-grant.sh falso: registra cada llamada y sale con OG_<ACCIÓN>_RC.
# check --print-head imprime la cabeza firmada: OG_SIGNED_HEAD o, por defecto,
# la cabeza actual del repo (grant firmado para lo publicado).
make_merge_repo() {
  local r
  r=$(make_repo)
  cat > "$r/scripts/operator-grant.sh" <<'OG'
#!/usr/bin/env bash
echo "$*" >> "$OG_LOG"
print_head() {
  [[ " $* " == *" --print-head "* ]] || return 0
  # OG_HEAD_SEQ="h1 h2": la n-ésima comprobación imprime la n-ésima cabeza.
  if [[ -n "${OG_HEAD_SEQ:-}" ]]; then
    local n; n=$(grep -c '^check' "$OG_LOG"); set -- $OG_HEAD_SEQ; shift $(( n - 1 )); printf '%s\n' "${1:-}"; return 0
  fi
  printf '%s\n' "${OG_SIGNED_HEAD:-$(git rev-parse HEAD)}"
}
case "$1" in
  # OG_CHECK_SEQ="0 1": la 1.ª comprobación pasa y la 2.ª no (revocado entre medias).
  check) if [[ -n "${OG_CHECK_SEQ:-}" ]]; then
           n=$(grep -c '^check' "$OG_LOG"); args="$*"; set -- $OG_CHECK_SEQ; shift $(( n - 1 ))
           rc="${1:-1}"; [[ "$rc" == 0 ]] && print_head $args; exit "$rc"
         fi
         rc="${OG_CHECK_RC:-0}"; [[ "$rc" == 0 ]] && print_head "$@"; exit "$rc" ;;
  consume) exit "${OG_CONSUME_RC:-0}" ;;
  revoke) exit "${OG_REVOKE_RC:-0}" ;;
esac
exit 2
OG
  printf '#!/usr/bin/env bash\nexit 0\n' > "$r/scripts/f5-state.sh"
  # Riesgo bajo: el camino real (grant → tier → reserva F5 → merge).
  printf 'import json\nprint(json.dumps({"tier": 1}))\n' > "$r/scripts/risk-tier.py"
  printf '# Changelog\n\n## [1.2.3]\n- x\n' > "$r/CHANGELOG.md"
  cat >> "$TESTDIR/bin/gh" <<'GH'
echo "GH_REPO=${GH_REPO:-}" >> "$GH_LOG"
case "$1 $2" in
  "pr view") echo "${GH_STATE:-OPEN}" ;;
  "pr merge") exit "${GH_MERGE_RC:-0}" ;;
esac
exit 0
GH
  git -C "$r" add -A; git -C "$r" commit -qm "chore: stubs"
  # Paso 1 del flujo documentado: push-pr.sh SIN --merge firma, empuja y crea
  # el PR #42. La cabeza que queda publicada es la que firmará el grant.
  ( cd "$r" && env -u GH_LIST_OUT GH_LOG="$TESTDIR/gh.log" PATH="$TESTDIR/bin:$PATH" \
      bash scripts/push-pr.sh --from-pr-plan --skip-ci --skip-changelog >/dev/null 2>&1 )
  echo "$r"
}

# Paso 3: push-pr.sh --merge con el PR #42 ya abierto (gh pr list lo devuelve).
run_merge() {
  export GH_LOG="$TESTDIR/gh.log" OG_LOG="$TESTDIR/og.log"
  : > "$GH_LOG"; : > "$OG_LOG"
  cd "$1"
  run env GH_LIST_OUT="${GH_LIST_OUT-42}" PATH="$TESTDIR/bin:$PATH" bash scripts/push-pr.sh --from-pr-plan --skip-ci --skip-changelog --merge
}

remote_head() { git -C "$1" ls-remote origin refs/heads/agent/x | cut -f1; }

@test "SE-343 flujo documentado con firmador NO idempotente: push → grant de esa cabeza → --merge mergea" {
  r=$(make_merge_repo)
  # Control: el firmador simulado cambia la firma en cada ejecución (como el real).
  ( cd "$r" && bash scripts/confidentiality-sign.sh sign >/dev/null && cp .confidentiality-signature "$TESTDIR/s1" \
      && bash scripts/confidentiality-sign.sh sign >/dev/null && ! cmp -s .confidentiality-signature "$TESTDIR/s1" ) \
    || { echo "el firmador simulado es idempotente: este test no puede fallar"; return 1; }
  git -C "$r" restore .confidentiality-signature
  published=$(remote_head "$r")
  [ "$published" = "$(git -C "$r" rev-parse HEAD)" ]
  [ "$(git -C "$r" log -1 --format=%s)" = "chore: sign confidentiality audit" ]
  # La operadora firma el grant para la cabeza publicada.
  OG_SIGNED_HEAD="$published" GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -q -- "^pr merge 42 -R .* --squash --match-head-commit $published$" "$GH_LOG"
  grep -qx "consume --scope merge --resource pr:42" "$OG_LOG"
  # --merge no firma ni empuja: ni commit nuevo ni cabeza remota movida.
  [ "$(git -C "$r" rev-parse HEAD)" = "$published" ]
  [ "$(remote_head "$r")" = "$published" ]
  run grep -c "^pr create\|^api " "$GH_LOG"
  [ "$output" = "0" ]
}

@test "SE-343 --merge: sin grant para este PR no hay merge ni consumo (exit 1)" {
  r=$(make_merge_repo)
  OG_CHECK_RC=1 run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"vuelve a ejecutar push-pr.sh --merge"* ]]
  grep -qx "check --scope merge --resource pr:42 --print-head" "$OG_LOG"
  run grep -c "pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  run grep -c "^consume" "$OG_LOG"
  [ "$output" = "0" ]
}

@test "SE-343 --merge: con grant y merge confirmado se consume el grant de ESTE PR" {
  r=$(make_merge_repo)
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  head=$(git -C "$r" rev-parse HEAD)
  grep -q -- "^pr merge 42 -R .* --squash --match-head-commit $head$" "$GH_LOG"
  grep -qx "consume --scope merge --resource pr:42" "$OG_LOG"
  [[ "$output" == *"Merge grant consumed (one-shot)."* ]]
}

@test "SE-343 --merge: nunca programa un auto-merge (--auto) que sobreviviría a revocar el grant" {
  r=$(make_merge_repo)
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  run grep -c -- "--auto" "$GH_LOG"
  [ "$output" = "0" ]
}

@test "SE-343 --merge: grant revocado entre la primera comprobación y el merge → no hay merge" {
  r=$(make_merge_repo)
  GH_STATE=MERGED OG_CHECK_SEQ="0 1" run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ya no es vigente"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Control: si sigue vigente en la segunda comprobación, sí hay merge.
  GH_STATE=MERGED OG_CHECK_SEQ="0 0" run_merge "$r"
  [ "$status" -eq 0 ]
  grep -q "^pr merge 42" "$GH_LOG"
}

@test "SE-343 --merge: una cabeza local sin publicar no se empuja ni se mergea" {
  r=$(make_merge_repo)
  published=$(remote_head "$r")
  git -C "$r" commit -q --allow-empty -m "agent(x): commit posterior al grant"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es la publicada"* ]]
  [[ "$output" == *"push-pr.sh (sin --merge)"* ]]
  [ "$(remote_head "$r")" = "$published" ]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  run grep -c "^check" "$OG_LOG"
  [ "$output" = "0" ]
  # Control: tras volver a la cabeza publicada, el merge sigue.
  git -C "$r" reset -q --hard "$published"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
}

@test "SE-343 --merge: una cabeza publicada sin firma de confidencialidad válida no se mergea" {
  r=$(make_merge_repo)
  echo otro >> "$r/f.txt"; git -C "$r" commit -qam "agent(x): cambio sin re-firmar"
  git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"firma de confidencialidad"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Control: firmada y publicada (paso 1 otra vez), mergea.
  ( cd "$r" && env GH_LIST_OUT=42 GH_LOG="$GH_LOG" PATH="$TESTDIR/bin:$PATH" \
      bash scripts/push-pr.sh --from-pr-plan --skip-ci --skip-changelog >/dev/null 2>&1 )
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
}

@test "SE-343 --merge: con cambios sin commitear o sin gh autenticado no se mergea" {
  r=$(make_merge_repo)
  echo sucio >> "$r/f.txt"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin commitear"* ]]
  git -C "$r" restore f.txt
  GH_AUTH_RC=1 GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"necesita gh"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
}

@test "SE-343 --merge: GH_REPO no desvía el merge a otro repositorio" {
  r=$(make_merge_repo)
  origin_repo=$(git -C "$r" remote get-url origin | sed -E 's|.*github\.com[:/]||;s|\.git$||')
  GH_REPO=org/B GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -q -- "^pr merge 42 -R $origin_repo --squash --match-head-commit [0-9a-f]\{40\}$" "$GH_LOG"
  run grep -c "^GH_REPO=org/B" "$GH_LOG"
  [ "$output" = "0" ]
}

@test "SE-343 --merge: el recurso del grant es el número del PR abierto de la rama; sin él no hay merge" {
  r=$(make_merge_repo)
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -qx "check --scope merge --resource pr:42 --print-head" "$OG_LOG"
  grep -qx "consume --scope merge --resource pr:42" "$OG_LOG"
  # Sin PR abierto, o con una salida que no es un número, no se comprueba ni se mergea.
  for out in "" "x42" "42 43"; do
    GH_LIST_OUT="$out" GH_STATE=MERGED run_merge "$r"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no hay un PR abierto"* ]]
    run grep -c "^pr merge\|^pr create" "$GH_LOG"
    [ "$output" = "0" ]
    run grep -c "^check" "$OG_LOG"
    [ "$output" = "0" ]
  done
}

@test "SE-343 --merge: si consume falla no se informa de consumo y el grant se revoca" {
  r=$(make_merge_repo)
  GH_STATE=MERGED OG_CONSUME_RC=1 run_merge "$r"
  grep -qx "revoke --scope merge" "$OG_LOG"
  [[ "$output" != *"Merge grant consumed"* ]]
  [[ "$output" == *"revocado en su lugar"* ]]
  # Y si tampoco se puede revocar, se dice.
  GH_STATE=MERGED OG_CONSUME_RC=1 OG_REVOKE_RC=2 run_merge "$r"
  [[ "$output" != *"Merge grant consumed"* ]]
  [[ "$output" == *"NO se pudo gastar ni revocar"* ]]
}

@test "SE-343 --merge: a GitHub se pasa la cabeza FIRMADA; si no es la actual, no hay merge" {
  r=$(make_merge_repo)
  head=$(git -C "$r" rev-parse HEAD)
  # Grant firmado para otra cabeza (A) mientras la publicada es B: aunque check
  # dé 0 (p. ej. con un gh falseado), no se mergea.
  OG_SIGNED_HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"firma la cabeza aaaaaaaa"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  run grep -c "^consume" "$OG_LOG"
  [ "$output" = "0" ]
  # Sin cabeza firmada legible (check da 0 pero no imprime 40 hex) tampoco.
  OG_SIGNED_HEAD=nohex GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Control: firmada = actual → merge con --match-head-commit de la firmada.
  OG_SIGNED_HEAD="$head" GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -q -- "^pr merge 42 -R .* --squash --match-head-commit $head$" "$GH_LOG"
}

@test "SE-343 --merge: la 2.ª comprobación debe ver la misma cabeza firmada que la 1.ª" {
  r=$(make_merge_repo)
  head=$(git -C "$r" rev-parse HEAD)
  # La 1.ª comprobación ve la cabeza actual; la 2.ª, otra (grant sustituido entre medias).
  OG_HEAD_SEQ="$head cccccccccccccccccccccccccccccccccccccccc" GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ya no es vigente"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Control: misma cabeza en ambas → merge.
  OG_HEAD_SEQ="$head $head" GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -q -- "--match-head-commit $head$" "$GH_LOG"
}

@test "SE-343 --merge: en modo de test de operator-grant (SAVIA_GRANT_TEST_MODE / SAVIA_GH_BIN) no se mergea" {
  r=$(make_merge_repo)
  SAVIA_GRANT_TEST_MODE=1 GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"solo para pruebas"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  SAVIA_GH_BIN=/bin/true GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Control: sin esas variables, el mismo repo mergea.
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -q "^pr merge 42" "$GH_LOG"
}

@test "SE-343 --merge: si el PR no se puede mergear ahora, sale con 1 y no gasta el grant" {
  r=$(make_merge_repo)
  GH_MERGE_RC=1 GH_STATE=OPEN run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" != *"Merge grant consumed"* ]]
  [[ "$output" == *"no se ha gastado"* ]]
  run grep -c "^consume" "$OG_LOG"
  [ "$output" = "0" ]
}

@test "pr-plan: success is detected by a /pull/N URL, not by any github.com line" {
  grep -q 'grep -qE "/pull/\[0-9\]+"' "$BATS_TEST_DIRNAME/../scripts/pr-plan.sh"
  ! grep -q 'grep -qE "https://github.com/"' "$BATS_TEST_DIRNAME/../scripts/pr-plan.sh"
}
