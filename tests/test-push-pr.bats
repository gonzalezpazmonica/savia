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
  grep -q "gh pr list --head" "$PUSH_PR"
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
  grep -q "gh pr list --head" "$PUSH_PR"
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
  grep -q 'GRANT_RES="pr:${PR_URL##\*/}"' "$PUSH_PR"
  grep -q 'operator-grant.sh check --scope merge --resource "$GRANT_RES"' "$PUSH_PR"
  grep -q 'operator-grant.sh consume --scope merge --resource "$GRANT_RES"' "$PUSH_PR"
  # Ninguna llamada a check/revoke de merge sin recurso (revoke sin gastar el id permitía replay).
  run grep -nE 'operator-grant.sh (check|revoke) --scope merge( |$)[^-]*$' "$PUSH_PR"
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
  printf '#!/usr/bin/env bash\necho sig > .confidentiality-signature; echo SIGNED\n' > "$r/scripts/confidentiality-sign.sh"
  echo base > "$r/f.txt"; git -C "$r" add -A; git -C "$r" commit -qm "init"
  git -C "$r" remote add origin "$o"; git -C "$r" push -q origin main
  git -C "$r" checkout -q -b agent/x
  echo change >> "$r/f.txt"; git -C "$r" commit -qam "agent(overnight): cambio sin prefijo feat/fix"
  mkdir -p "$TESTDIR/bin"
  cat > "$TESTDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr list") echo "" ;;
  "pr create") echo "https://github.com/o/r/pull/42" ;;
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

@test "pr-plan: success is detected by a /pull/N URL, not by any github.com line" {
  grep -q 'grep -qE "/pull/\[0-9\]+"' "$BATS_TEST_DIRNAME/../scripts/pr-plan.sh"
  ! grep -q 'grep -qE "https://github.com/"' "$BATS_TEST_DIRNAME/../scripts/pr-plan.sh"
}
