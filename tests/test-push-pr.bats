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
  # Escáner simulado (SE-501, sin firma): CLEAN salvo que el diff de la cabeza
  # añada la marca VETADO o SCAN_RC lo fuerce. Registra cada llamada en SCAN_LOG.
  # Con --blocklist <f>, también da findings si el diff añade un término de <f> (literal). En modo
  # --pr-base emite el veredicto «Confidentiality scan (PR): PASS|FAIL» como el escáner real.
  cat > "$r/scripts/confidentiality-scan.sh" <<'SCAN'
#!/usr/bin/env bash
echo "scan $*" >> "${SCAN_LOG:-/dev/null}"
mode="" bl=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr-base) mode=base; shift 2 ;;
    --blocklist) bl="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$bl" ]] && cp "$bl" "${SCAN_BL_COPY:-/dev/null}"
if [[ -n "${SCAN_RC:-}" ]]; then exit "$SCAN_RC"; fi
added=$(git diff origin/main...HEAD 2>/dev/null | grep '^+[^+]')
if grep -q 'VETADO' <<<"$added" || { [[ -n "$bl" ]] && grep -qiF -f "$bl" <<<"$added"; }; then
  echo 'gate-result: {"result":"findings","gaps":[]}'
  [[ "$mode" == base ]] && echo "Confidentiality scan (PR): FAIL"
  exit 1
fi
echo 'gate-result: {"result":"clean","gaps":[]}'
[[ "$mode" == base ]] && echo "Confidentiality scan (PR): PASS"
exit 0
SCAN
  # Generador real y lista estática sintética: push-pr --merge los toma de origin/main.
  cp "$BATS_TEST_DIRNAME/../scripts/generate-blocklist.sh" "$r/scripts/"
  printf '# estática\ntermino-vetado-xyz\n' > "$r/scripts/confidentiality-blocklist.txt"
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
  # --json files: ficheros del PR según GitHub (GH_FILES, GH_FILES_RC); si no, el estado.
  "pr view") if [[ " $* " == *" files "* ]]; then printf '%b\n' "${GH_FILES:-f.txt}"; exit "${GH_FILES_RC:-0}"; fi
             echo "${GH_STATE:-OPEN}" ;;
  "pr merge") exit "${GH_MERGE_RC:-0}" ;;
esac
exit 0
GH
  git -C "$r" add -A; git -C "$r" commit -qm "chore: stubs"
  # Paso 1 del flujo documentado: push-pr.sh SIN --merge escanea, empuja y crea
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

@test "SE-343 flujo documentado (SE-501, sin firma): push → grant de esa cabeza → --merge mergea" {
  r=$(make_merge_repo)
  published=$(remote_head "$r")
  [ "$published" = "$(git -C "$r" rev-parse HEAD)" ]
  # SE-501: push-pr ya no firma: ni commit de firma ni fichero de firma.
  [ "$(git -C "$r" log -1 --format=%s)" = "chore: stubs" ]
  [ ! -e "$r/.confidentiality-signature" ]
  # La operadora firma el grant para la cabeza publicada.
  export SCAN_LOG="$TESTDIR/scan.log"; : > "$SCAN_LOG"
  OG_SIGNED_HEAD="$published" GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -q -- "^pr merge 42 -R .* --squash --match-head-commit $published$" "$GH_LOG"
  grep -qx "consume --scope merge --resource pr:42" "$OG_LOG"
  # rev-1472 P1-2: --merge re-escanea la cabeza; no firma ni empuja. SE-501 (seguimiento de #1472):
  # con el escáner de origin/main en modo --pr-base, nunca con el de la cabeza.
  grep -q "^scan --pr-base $(git -C "$r" rev-parse origin/main) --repo " "$SCAN_LOG"
  run grep -cx "scan --pr" "$SCAN_LOG"
  [ "$output" = "0" ]
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

@test "rev-1472 P1-2 --merge: una cabeza cuyo escaneo de confidencialidad no da CLEAN no se mergea" {
  r=$(make_merge_repo)
  echo "dato VETADO" >> "$r/f.txt"; git -C "$r" commit -qam "agent(x): cambio con dato vetado"
  git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escaneo de confidencialidad"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Un escáner que no puede medir (unknown, exit 2) tampoco deja mergear.
  git -C "$r" revert --no-edit HEAD >/dev/null; git -C "$r" push -q origin agent/x
  SCAN_RC=2 GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escaneo de confidencialidad"* ]]
  # Control: la misma cabeza, limpia, mergea sin ninguna firma versionada.
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  [ ! -e "$r/.confidentiality-signature" ]
}

@test "SE-501 seguimiento #1472 --merge: una cabeza que neutraliza su propio escáner no se mergea (escáner de origin/main)" {
  r=$(make_merge_repo)
  # La cabeza cambia el escáner para que siempre dé clean y añade un dato vetado.
  cat > "$r/scripts/confidentiality-scan.sh" <<'SCAN'
#!/usr/bin/env bash
echo "scan-pr $*" >> "${SCAN_LOG:-/dev/null}"
echo 'gate-result: {"result":"clean","gaps":[]}'
SCAN
  echo "dato VETADO" >> "$r/f.txt"
  git -C "$r" commit -qam "agent(x): escáner propio y dato vetado"; git -C "$r" push -q origin agent/x
  export SCAN_LOG="$TESTDIR/scan.log"; : > "$SCAN_LOG"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escáner de origin/main"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  run grep -c "^scan-pr" "$SCAN_LOG"     # el escáner de la cabeza no se ejecutó
  [ "$output" = "0" ]
  # Control: sin el dato vetado (mismo escáner modificado en la cabeza) sí mergea.
  sed -i '/VETADO/d' "$r/f.txt"
  git -C "$r" commit -qam "agent(x): sin dato"; git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
}

@test "SE-501 seguimiento #1472 --merge: si origin/main no trae --pr-base o no existe, no hay merge" {
  r=$(make_merge_repo)
  good=$(git -C "$r" rev-parse origin/main)
  # Base cuyo escáner no tiene el modo --pr-base (commit fuera de la rama, con plumbing).
  git -C "$r" show "$good:scripts/confidentiality-scan.sh" | sed '/--pr-base)/d' > "$TESTDIR/scan-viejo.sh"
  blob=$(git -C "$r" hash-object -w "$TESTDIR/scan-viejo.sh")
  sub=$(git -C "$r" ls-tree "$good:scripts" | awk -v b="$blob" -F'\t' '$2=="confidentiality-scan.sh"{sub(/[0-9a-f]{40}$/,b,$1)} {print $1"\t"$2}' | git -C "$r" mktree)
  tree=$(git -C "$r" ls-tree "$good" | awk -v s="$sub" -F'\t' '$2=="scripts"{sub(/[0-9a-f]{40}$/,s,$1)} {print $1"\t"$2}' | git -C "$r" mktree)
  vieja=$(git -C "$r" commit-tree "$tree" -p "$good" -m "base sin --pr-base")
  git -C "$r" update-ref refs/remotes/origin/main "$vieja"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no trae scripts/confidentiality-scan.sh con --pr-base"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Sin origin/main: tampoco.
  git -C "$r" update-ref -d refs/remotes/origin/main
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin origin/main"* ]]
  # Control: con la base buena, mergea.
  git -C "$r" update-ref refs/remotes/origin/main "$good"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
}

# alt_base <repo> <base> <ruta> [<fichero>] — commit hijo de <base> fuera de toda rama, con <ruta>
# sustituida por <fichero> o, sin él, eliminada. Imprime el SHA.
alt_base() {
  local r=$1 base=$2 path=$3 src=${4:-} idx tree
  idx="$TESTDIR/alt.index"; rm -f "$idx"
  GIT_INDEX_FILE="$idx" git -C "$r" read-tree "$base"
  if [[ -n "$src" ]]; then
    GIT_INDEX_FILE="$idx" git -C "$r" update-index --cacheinfo "100644,$(git -C "$r" hash-object -w "$src"),$path"
  else
    GIT_INDEX_FILE="$idx" git -C "$r" update-index --force-remove "$path"
  fi
  tree=$(GIT_INDEX_FILE="$idx" git -C "$r" write-tree)
  git -C "$r" commit-tree "$tree" -p "$base" -m "base alternativa"
}

# real_scanner_repo — repo de merge con el escáner, gate-result y generador reales en la base.
real_scanner_repo() {
  local r
  r=$(make_merge_repo)
  mkdir -p "$r/.claude/hooks/lib"
  cp "$BATS_TEST_DIRNAME/../scripts/confidentiality-scan.sh" "$r/scripts/"
  cp "$BATS_TEST_DIRNAME/../.claude/hooks/lib/gate-result.sh" "$r/.claude/hooks/lib/"
  git -C "$r" checkout -q main; git -C "$r" add -A; git -C "$r" commit -qm "escáner real"; git -C "$r" push -q origin main
  git -C "$r" checkout -q agent/x; git -C "$r" merge -q --no-edit main
  git -C "$r" push -q origin agent/x; git -C "$r" fetch -q origin
  echo "$r"
}

@test "rev-1488 P1-1 --merge: la blocklist incluye las fuentes locales no versionadas (projects/, CLAUDE.local.md)" {
  r=$(make_merge_repo)
  # Fuentes locales, sin versionar: el nombre privado solo se conoce aquí.
  mkdir -p "$r/projects/cliente-oculto-xyz"
  printf 'PROJECT_A_NAME = "NombreLocalOculto"\n' > "$r/CLAUDE.local.md"
  echo "nota de cliente-oculto-xyz" >> "$r/f.txt"
  git -C "$r" commit -qam "agent(x): nombre privado"; git -C "$r" push -q origin agent/x
  export SCAN_BL_COPY="$TESTDIR/bl.txt"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escaneo de confidencialidad"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  grep -qx "cliente-oculto-xyz" "$SCAN_BL_COPY"
  grep -qx "NombreLocalOculto" "$SCAN_BL_COPY"
  grep -qx "termino-vetado-xyz" "$SCAN_BL_COPY"     # la estática de la base sigue entrando
  # Revisión de #1490 (P1-1): un projects/<n> que la cabeza versiona pero la BASE no sigue siendo local y su
  # nombre sigue en la blocklist (la PR no decide qué sale de ella).
  sed -i '/cliente-oculto-xyz/d' "$r/f.txt"
  mkdir -p "$r/projects/versionado-por-pr"; echo x > "$r/projects/versionado-por-pr/README.md"
  git -C "$r" add "projects/versionado-por-pr/README.md" f.txt
  git -C "$r" commit -qm "agent(x): sin nombre privado"; git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -qx "versionado-por-pr" "$SCAN_BL_COPY"
  grep -qx "cliente-oculto-xyz" "$SCAN_BL_COPY"
}

@test "rev-1490 P1-1 --merge: forzar al índice una fuente local preexistente no la saca de la blocklist" {
  r=$(make_merge_repo)
  # Proyecto privado y CLAUDE.local.md en disco, sin versionar en la base.
  mkdir -p "$r/projects/cliente-oculto-xyz/team"
  printf '### Ana Secretisima\n' > "$r/projects/cliente-oculto-xyz/team/TEAM.md"
  printf 'PROJECT_A_NAME = "NombreLocalOculto"\n' > "$r/CLAUDE.local.md"
  export SCAN_BL_COPY="$TESTDIR/bl.txt"
  # La cabeza fuerza al índice el TEAM.md (con el nombre de la persona) y CLAUDE.local.md.
  git -C "$r" add --force projects/cliente-oculto-xyz/team/TEAM.md CLAUDE.local.md
  git -C "$r" commit -qm "agent(x): fuga forzada"; git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escaneo de confidencialidad"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  grep -qx "cliente-oculto-xyz" "$SCAN_BL_COPY"
  grep -qx "Ana Secretisima" "$SCAN_BL_COPY"
  grep -qx "NombreLocalOculto" "$SCAN_BL_COPY"
}

@test "rev-1490 P1-1 --merge negativo: un proyecto que la base ya versiona (público) no entra en la blocklist" {
  r=$(make_merge_repo)
  export SCAN_BL_COPY="$TESTDIR/bl.txt"
  # Proyecto versionado en main (la base) antes de la rama.
  git -C "$r" checkout -q main
  mkdir -p "$r/projects/publico-abc"; echo x > "$r/projects/publico-abc/README.md"
  git -C "$r" add projects/publico-abc/README.md; git -C "$r" commit -qm "proyecto público"
  git -C "$r" push -q origin main
  git -C "$r" checkout -q agent/x; git -C "$r" merge -q --no-edit main; git -C "$r" push -q origin agent/x
  git -C "$r" fetch -q origin
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  run grep -c "publico-abc" "$SCAN_BL_COPY"
  [ "$output" = "0" ]
  grep -qx "termino-vetado-xyz" "$SCAN_BL_COPY"
  # Sin duplicados (P2-3): la estática la emite el generador y la añade push-pr; aparece una vez.
  run grep -cx "termino-vetado-xyz" "$SCAN_BL_COPY"
  [ "$output" = "1" ]
}

@test "rev-1490 P2-2 --merge: interrumpido (TERM) durante la blocklist, no deja copias de fuentes locales en TMPDIR" {
  r=$(make_merge_repo)
  printf 'PROJECT_A_NAME = "NombreLocalOculto"\n' > "$r/CLAUDE.local.md"
  good=$(git -C "$r" rev-parse origin/main)
  # Generador de la base que termina el proceso de push-pr (su padre) a mitad de la generación.
  printf '#!/usr/bin/env bash\nkill -TERM "$PPID"\nsleep 1\n' > "$TESTDIR/gen-kill.sh"
  git -C "$r" update-ref refs/remotes/origin/main "$(alt_base "$r" "$good" scripts/generate-blocklist.sh "$TESTDIR/gen-kill.sh")"
  mkdir -p "$TESTDIR/tmp"
  TMPDIR="$TESTDIR/tmp" GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 143 ]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  run grep -rl "NombreLocalOculto" "$TESTDIR/tmp"
  [ "$status" -ne 0 ]
  run find "$TESTDIR/tmp" -mindepth 1
  [ -z "$output" ]
}

@test "rev-1490 P2-1 --merge con el escáner real: la blocklist local se aplica como regex (cliente_oculto_xyz)" {
  r=$(make_merge_repo)
  # El escáner, gate-result y el generador reales en la base (sustituyen al stub).
  mkdir -p "$r/.claude/hooks/lib"
  cp "$BATS_TEST_DIRNAME/../scripts/confidentiality-scan.sh" "$r/scripts/"
  cp "$BATS_TEST_DIRNAME/../.claude/hooks/lib/gate-result.sh" "$r/.claude/hooks/lib/"
  git -C "$r" checkout -q main; git -C "$r" add -A; git -C "$r" commit -qm "escáner real"; git -C "$r" push -q origin main
  git -C "$r" checkout -q agent/x; git -C "$r" merge -q --no-edit main
  git -C "$r" push -q origin agent/x; git -C "$r" fetch -q origin
  mkdir -p "$r/projects/cliente-oculto-xyz"
  # Control: sin el nombre en el diff, PASS y merge.
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # El diff menciona el proyecto con otro separador: solo lo caza el patrón regex cliente.?oculto.?xyz.
  echo "nota de cliente_oculto_xyz" >> "$r/f.txt"
  git -C "$r" commit -qam "agent(x): variante"; git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escaneo de confidencialidad"* ]]
}

@test "rev-1490 P1-1 (seguridad) --merge con el escáner real: un patrón local que empieza por «-» no desactiva el Check 1" {
  r=$(make_merge_repo)
  mkdir -p "$r/.claude/hooks/lib"
  cp "$BATS_TEST_DIRNAME/../scripts/confidentiality-scan.sh" "$r/scripts/"
  cp "$BATS_TEST_DIRNAME/../.claude/hooks/lib/gate-result.sh" "$r/.claude/hooks/lib/"
  git -C "$r" checkout -q main; git -C "$r" add -A; git -C "$r" commit -qm "escáner real"; git -C "$r" push -q origin main
  git -C "$r" checkout -q agent/x; git -C "$r" merge -q --no-edit main
  git -C "$r" push -q origin agent/x; git -C "$r" fetch -q origin
  mkdir -p "$r/projects/cliente-oculto-xyz"
  export SCAN_BL_COPY="$TESTDIR/bl.txt"
  # La PR fuerza un CLAUDE.local.md con un patrón hostil («-ave^» → grep -a -v -e "^|…») y filtra el nombre.
  printf 'PROJECT_A_NAME = "-ave^"\n' > "$r/CLAUDE.local.md"
  git -C "$r" add --force CLAUDE.local.md
  echo "nota de cliente-oculto-xyz" >> "$r/f.txt"
  git -C "$r" commit -qam "agent(x): patrón hostil"; git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empieza por «-»"* ]]
  [[ "$output" == *"no se pudo generar la blocklist local"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
}

@test "rev-1490 P2-2 --merge: el team/TEAM.md no versionado de un proyecto público sí entra en la blocklist" {
  r=$(make_merge_repo)
  export SCAN_BL_COPY="$TESTDIR/bl.txt"
  git -C "$r" checkout -q main
  mkdir -p "$r/projects/publico-abc"; echo x > "$r/projects/publico-abc/README.md"
  git -C "$r" add projects/publico-abc/README.md; git -C "$r" commit -qm "proyecto público"
  git -C "$r" push -q origin main
  git -C "$r" checkout -q agent/x; git -C "$r" merge -q --no-edit main; git -C "$r" push -q origin agent/x
  git -C "$r" fetch -q origin
  # TEAM.md local (sin versionar) dentro del proyecto público.
  mkdir -p "$r/projects/publico-abc/team"
  printf '### Ana Secretisima\n' > "$r/projects/publico-abc/team/TEAM.md"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -qx "Ana Secretisima" "$SCAN_BL_COPY"
  grep -qx "Secretisima" "$SCAN_BL_COPY"
  # Revisión de #1490 (corrección, 2.ª ronda, P1-1): el TEAM.md no hace que el proyecto público aporte su
  # nombre (ni la variante con separadores); una PR que lo mencione no da falso positivo.
  run grep -c "publico" "$SCAN_BL_COPY"
  [ "$output" = "0" ]
  # Si otra fuente local aporta ese mismo nombre (CLAUDE.local.md), sí entra.
  printf 'PROJECT_A_NAME = "publico-abc"\n' > "$r/CLAUDE.local.md"
  GH_STATE=MERGED run_merge "$r"
  grep -qx "publico-abc" "$SCAN_BL_COPY"
  grep -qx "Ana Secretisima" "$SCAN_BL_COPY"
}

@test "rev-1490 P1-1 (corrección, 2.ª ronda) --merge con el escáner real: una PR que nombra un proyecto público con TEAM.md local mergea" {
  r=$(real_scanner_repo)
  git -C "$r" checkout -q main
  mkdir -p "$r/projects/publico-abc"; echo x > "$r/projects/publico-abc/README.md"
  git -C "$r" add projects/publico-abc/README.md; git -C "$r" commit -qm "proyecto público"
  git -C "$r" push -q origin main
  git -C "$r" checkout -q agent/x; git -C "$r" merge -q --no-edit main; git -C "$r" push -q origin agent/x
  git -C "$r" fetch -q origin
  mkdir -p "$r/projects/publico-abc/team"
  printf '### Ana Secretisima\n' > "$r/projects/publico-abc/team/TEAM.md"
  echo "nota sobre publico_abc" >> "$r/f.txt"
  git -C "$r" commit -qam "agent(x): menciona el proyecto público"; git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # Negativo: la persona del TEAM.md sí bloquea.
  echo "contacto Ana Secretisima" >> "$r/f.txt"
  git -C "$r" commit -qam "agent(x): persona"; git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escaneo de confidencialidad"* ]]
}

@test "rev-1490 P1-1 (seguridad, 2.ª ronda) --merge con el escáner real: patrones locales que agrupan («0000(» … «zzzz)qqq») no anulan el Check 1" {
  r=$(real_scanner_repo)
  mkdir -p "$r/projects/cliente-oculto-xyz"
  # La PR fuerza un CLAUDE.local.md cuya unión con «|» encierra toda la blocklist en un grupo, y filtra el nombre.
  printf 'PROJECT_A_NAME = "0000("\nPROJECT_B_NAME = "zzzz)qqq"\n' > "$r/CLAUDE.local.md"
  git -C "$r" add --force CLAUDE.local.md
  echo "nota de cliente-oculto-xyz" >> "$r/f.txt"
  git -C "$r" commit -qam "agent(x): patrones de agrupación"; git -C "$r" push -q origin agent/x
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"( ) [ ] { } | o"* ]]
  [[ "$output" == *"no se pudo generar la blocklist local"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Variante con clase de caracteres, como nombres de directorio de projects/.
  git -C "$r" rm -q --cached CLAUDE.local.md; rm "$r/CLAUDE.local.md"
  git -C "$r" commit -qm "agent(x): sin CLAUDE.local.md"; git -C "$r" push -q origin agent/x
  mkdir -p "$r/projects/0000[" "$r/projects/zzzz]qqq"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"( ) [ ] { } | o"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Control: sin los patrones hostiles, el escáner real caza el nombre filtrado (hallazgo, no fallo de la lista).
  rmdir "$r/projects/0000[" "$r/projects/zzzz]qqq"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escaneo de confidencialidad"* ]]
  [[ "$output" != *"no se pudo generar la blocklist local"* ]]
  # Control: la lista estática de la base puede llevar regex con grupos; sin el nombre, mergea.
  printf 'historial.*(disciplin|sancion)\n' >> "$r/scripts/confidentiality-blocklist.txt"
  git -C "$r" checkout -q main; git -C "$r" commit -qam "estática con grupo"; git -C "$r" push -q origin main
  git -C "$r" checkout -q agent/x; git -C "$r" merge -q --no-edit main
  sed -i '/cliente-oculto-xyz/d' "$r/f.txt"
  git -C "$r" commit -qam "agent(x): sin nombre"; git -C "$r" push -q origin agent/x; git -C "$r" fetch -q origin
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# run_merge_timeout — run_merge con límite de tiempo (una fuente que cuelga cp no bloquea la suite).
run_merge_timeout() {
  export GH_LOG="$TESTDIR/gh.log" OG_LOG="$TESTDIR/og.log"
  : > "$GH_LOG"; : > "$OG_LOG"
  cd "$1"
  run timeout 20 env GH_LIST_OUT=42 PATH="$TESTDIR/bin:$PATH" bash scripts/push-pr.sh --from-pr-plan --skip-ci --skip-changelog --merge
}

@test "rev-1490 P2-2 (seguridad) --merge: una fuente local que no es fichero regular (enlace a /dev/zero, FIFO) no cuelga ni mergea" {
  r=$(make_merge_repo)
  ln -s /dev/zero "$r/CLAUDE.local.md"
  GH_STATE=MERGED run_merge_timeout "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es un fichero regular: CLAUDE.local.md"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  rm "$r/CLAUDE.local.md"
  mkdir -p "$r/projects/cliente-oculto-xyz/team"; mkfifo "$r/projects/cliente-oculto-xyz/team/TEAM.md"
  GH_STATE=MERGED run_merge_timeout "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es un fichero regular: projects/cliente-oculto-xyz/team/TEAM.md"* ]] || { echo "$output"; false; }
  # Control: un enlace a un fichero regular sí vale.
  rm "$r/projects/cliente-oculto-xyz/team/TEAM.md"
  printf '### Ana Secretisima\n' > "$TESTDIR/team-real.md"
  ln -s "$TESTDIR/team-real.md" "$r/projects/cliente-oculto-xyz/team/TEAM.md"
  export SCAN_BL_COPY="$TESTDIR/bl.txt"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -qx "Ana Secretisima" "$SCAN_BL_COPY"
}

@test "rev-1490 P2-1 (seguridad): toda fuente que lee el generador la copia local_blocklist (sin deriva)" {
  local gen="$BATS_TEST_DIRNAME/../scripts/generate-blocklist.sh" known p
  # Rutas que local_blocklist lleva al directorio aparte (fuentes locales + lo que toma de la base).
  known=$'CLAUDE.local.md\n.claude/profiles/users/*/identity.md\n.gitignore\nprojects\nprojects/*/\nprojects/*/team/TEAM.md\nscripts/confidentiality-blocklist.txt'
  run bash -c "grep -oE '\"\\\$ROOT_DIR(\"/|/)[^\" ;)]*' '$gen' | sed -E 's/^\"\\\$ROOT_DIR\"?\\///' | sort -u"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  while IFS= read -r p; do
    grep -qxF -- "$p" <<<"$known" || { echo "fuente nueva del generador sin copiar en local_blocklist: $p"; false; }
  done <<<"$output"
  # Y local_blocklist sigue copiando cada una (si se quita una, este test falla).
  for p in CLAUDE.local.md 'team/TEAM.md' 'identity.md' 'confidentiality-blocklist.txt' '.gitignore'; do
    sed -n '/^local_blocklist()/,/^}/p' "$PUSH_PR" | grep -v '^[[:space:]]*#' | grep -qF -- "$p" \
      || { echo "local_blocklist no trata (fuera de comentarios): $p"; false; }
  done
}

@test "rev-1488 P1-1 --merge: si origin/main no trae el generador de la blocklist, no hay merge" {
  r=$(make_merge_repo)
  good=$(git -C "$r" rev-parse origin/main)
  git -C "$r" update-ref refs/remotes/origin/main "$(alt_base "$r" "$good" scripts/generate-blocklist.sh)"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no se pudo generar la blocklist local"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
}

@test "rev-1488 P2-1 --merge: código 0 sin el veredicto «Confidentiality scan (PR): PASS» no mergea" {
  r=$(make_merge_repo)
  good=$(git -C "$r" rev-parse origin/main)
  # Escáner de la base con el brazo --pr-base pero que nunca emite el veredicto (sale 0).
  git -C "$r" show "$good:scripts/confidentiality-scan.sh" | sed '/Confidentiality scan (PR): PASS/d' > "$TESTDIR/scan-mudo.sh"
  git -C "$r" update-ref refs/remotes/origin/main "$(alt_base "$r" "$good" scripts/confidentiality-scan.sh "$TESTDIR/scan-mudo.sh")"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escaneo de confidencialidad"* ]]
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  # Un brazo «--pr-base)» que solo aparece en un comentario no cuenta como modo --pr-base.
  git -C "$r" show "$good:scripts/confidentiality-scan.sh" | sed 's/^    --pr-base) mode=base; shift 2 ;;/    # --pr-base) no soportado/' > "$TESTDIR/scan-coment.sh"
  git -C "$r" update-ref refs/remotes/origin/main "$(alt_base "$r" "$good" scripts/confidentiality-scan.sh "$TESTDIR/scan-coment.sh")"
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no trae scripts/confidentiality-scan.sh con --pr-base"* ]]
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

# ── Revisión de seguridad de #1401, P1-1: un PR que toca los firmantes no se autoriza ──
# El grant (simulado) es válido y el clasificador (simulado) da tier 1: lo único que
# impide el merge es que el PR cambie config/operator-grant-signers.

no_merge_done() {
  run grep -c "^pr merge" "$GH_LOG"
  [ "$output" = "0" ]
  run grep -c "^consume" "$OG_LOG"
  [ "$output" = "0" ]
}

@test "P1-1 --merge: un PR que añade una clave a los firmantes no se mergea aunque traiga grant" {
  r=$(make_merge_repo)
  mkdir -p "$r/config"
  printf 'agente namespaces="savia-operator-grant" ssh-ed25519 AAAAagente\n' > "$r/config/operator-grant-signers"
  git -C "$r" add -A; git -C "$r" commit -qm "agent: añade mi clave"
  ( cd "$r" && env -u GH_LIST_OUT GH_LOG="$TESTDIR/gh.log" PATH="$TESTDIR/bin:$PATH" \
      bash scripts/push-pr.sh --from-pr-plan --skip-ci --skip-changelog >/dev/null 2>&1 )
  [ "$(remote_head "$r")" = "$(git -C "$r" rev-parse HEAD)" ]
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"modifica config/operator-grant-signers"* ]]
  [[ "$output" == *"la operadora a mano"* ]]
  no_merge_done
}

@test "P1-1 --merge: si GitHub lista los firmantes en el PR, no se mergea aunque el diff local no los vea" {
  r=$(make_merge_repo)
  GH_FILES='f.txt\nconfig/operator-grant-signers' GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"la operadora a mano"* ]]
  no_merge_done
  # Caso negativo: un fichero de nombre parecido no bloquea.
  GH_FILES='docs/operator-grant-signers-notes.md' GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 0 ]
  grep -q "^pr merge 42" "$GH_LOG"
}

@test "P1-1 --merge: sin la lista de ficheros del PR, o sin origin/main para comparar, no hay merge" {
  r=$(make_merge_repo)
  GH_FILES_RC=1 GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lista de ficheros"* ]]
  no_merge_done
  git -C "$r" update-ref -d refs/remotes/origin/main
  GH_STATE=MERGED run_merge "$r"
  [ "$status" -eq 1 ]
  # Desde el seguimiento de #1472 el escaneo con el escáner de origin/main corta antes que la
  # comparación de firmantes: sin origin/main no hay escáner de confianza.
  [[ "$output" == *"sin origin/main"* ]]
  no_merge_done
}

@test "pr-plan: success is detected by a /pull/N URL, not by any github.com line" {
  grep -q 'grep -qE "/pull/\[0-9\]+"' "$BATS_TEST_DIRNAME/../scripts/pr-plan.sh"
  ! grep -q 'grep -qE "https://github.com/"' "$BATS_TEST_DIRNAME/../scripts/pr-plan.sh"
}
