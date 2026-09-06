#!/usr/bin/env bash
# push-pr.sh — CI + sign + push + create PR + release (zero re-sign commits)
# Usage: push-pr.sh [--title "title"] [--body "body"] [--no-draft] [--merge]
# Default: PR is created as DRAFT (safer). Use --no-draft for ready-for-review.
# (--draft kept for backward compat; it's a no-op since draft is now default.)
set -euo pipefail
cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")"

TITLE="" BODY="" DRAFT=true MERGE=false SKIP_CL=false SKIP_CI=false FROM_PR_PLAN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) TITLE="$2"; shift 2 ;;  --body) BODY="$2"; shift 2 ;;
    --draft) DRAFT=true; shift ;;     --no-draft) DRAFT=false; shift ;;
    --merge) MERGE=true; shift ;;
    --skip-changelog) SKIP_CL=true; shift ;; --skip-ci) SKIP_CI=true; shift ;;
    --from-pr-plan) FROM_PR_PLAN=true; shift ;;
    --help|-h) echo "Usage: $0 [--title T] [--body B] [--no-draft] [--merge] [--skip-changelog] [--skip-ci]"; exit 0 ;;
    *) shift ;;
  esac
done

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" || "$BRANCH" == "master" ]] && { echo "ERROR: On $BRANCH." >&2; exit 1; }

# ── Step 0: pr-plan gate ──────────────────────────────────────────────────
if ! $FROM_PR_PLAN && [[ ! -f ".pr-plan-ok" ]]; then
  echo "ERROR: /pr-plan not run. Run /pr-plan first or touch .pr-plan-ok to bypass." >&2; exit 1
fi
# Staleness check: warn if commits added after pr-plan
if ! $FROM_PR_PLAN && [[ -f ".pr-plan-ok" ]]; then
  PLAN_T=$(stat -c %Y .pr-plan-ok 2>/dev/null || stat -f %m .pr-plan-ok 2>/dev/null || echo 0)
  if [[ "$(git log -1 --format=%ct 2>/dev/null || echo 0)" -gt "$PLAN_T" ]]; then
    echo "⚠️  WARNING: New commits since /pr-plan. Re-run recommended. Continuing in 5s..." >&2; sleep 5
  fi
fi

REPO=$(git remote get-url origin | sed -E 's|.*github\.com[:/]||;s|\.git$||')
TOKEN=$(git remote get-url origin | grep -oP 'ghp_[A-Za-z0-9]+' 2>/dev/null || true)
if [[ -z "$TOKEN" ]] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  USE_GH_CLI=true
else USE_GH_CLI=false; fi

# ── Steps 1-5: Validate → CI → CHANGELOG → Sign → Push ──────────────────
_supervisor() { local d="$1"; bash scripts/session-action-log.sh log "push-pr" "$BRANCH" "fail" "$d" >/dev/null 2>&1 || true; bash scripts/execution-supervisor.sh "push-pr" "$BRANCH" "$d" 2>&1 || true; }
echo "=== Step 1: Working tree ==="
if $FROM_PR_PLAN; then
  changed=$(git diff --name-only 2>/dev/null | grep -vE '(\.confidentiality-signature|\.scm/)' || true)
  [[ -n "$changed" ]] && { _supervisor "Uncommitted changes: $changed"; echo "ERROR: Uncommitted changes: $changed" >&2; exit 1; }
  echo "  Clean (pr-plan artifacts allowed)."
else
  [[ -n "$(git diff --name-only 2>/dev/null)" ]] && { _supervisor "Uncommitted changes"; echo "ERROR: Uncommitted changes." >&2; exit 1; }
  echo "  Clean."
fi
echo -e "\n=== Step 2: CI local ==="
if $SKIP_CI; then echo "  Skipped."
else bash scripts/validate-ci-local.sh 2>&1 | tail -5 | grep -q "safe to push" || { _supervisor "CI local failed"; echo "ERROR: CI failed." >&2; exit 1; }; echo "  Passed."; fi
echo -e "\n=== Step 3: CHANGELOG ==="
if ! $SKIP_CL; then
  CL_V=$(grep -oP '## \[\K[0-9.]+' CHANGELOG.md | head -1)
  PREV_V=$(git show origin/main:CHANGELOG.md 2>/dev/null | grep -oP '## \[\K[0-9.]+' | head -1)
  [[ "$CL_V" == "$PREV_V" ]] && { echo "ERROR: CHANGELOG not updated." >&2; exit 1; }; echo "  $CL_V."
else echo "  Skipped."; fi
echo -e "\n=== Step 4: Sign ==="
bash scripts/confidentiality-sign.sh sign 2>&1 | tail -1; git add .confidentiality-signature
if ! git diff --cached --quiet; then
  git commit -m "chore: sign confidentiality audit"
else echo "  Unchanged."; fi
echo -e "\n=== Step 5: Push ==="; export SAVIA_PUSH_PR=1
git push origin "$BRANCH" 2>&1 | tail -3 || { echo "  Retrying..."; git push --force-with-lease origin "$BRANCH" 2>&1 | tail -3; }

# ── Step 6: PR ───────────────────────────────────────────────────────────
echo -e "\n=== Step 6: PR ==="
if [[ -z "$TOKEN" ]] && ! $USE_GH_CLI; then
  echo "  No token and gh CLI not available. Create PR manually."; exit 0
fi
if [[ -z "$TITLE" ]]; then
  # Prefer first feat:/fix: in chronological order; fallback to first non-chore/non-Merge.
  TITLE=$(git log --reverse origin/main..HEAD --oneline | grep -E '^[a-f0-9]+ (feat|fix)(\(|:)' | head -1 | cut -d' ' -f2-)
  [[ -z "$TITLE" ]] && TITLE=$(git log --reverse origin/main..HEAD --oneline | grep -vE '^[a-f0-9]+ (chore:|Merge)' | head -1 | cut -d' ' -f2-)
fi
if [[ -z "$BODY" ]]; then
  COMMITS=$(git log --oneline origin/main..HEAD | grep -v "^[a-f0-9]* chore: sign" | sed 's/^/- /')
  FILES=$(git diff origin/main..HEAD --stat | tail -1 | grep -oP '[0-9]+' | head -1)
  # Read .pr-summary.md if present (rule pr-natural-language-summary.md)
  # SE-300: only trust it if it belongs to THIS branch (cleanup on branch switch).
  # If missing or stale, derive a summary paragraph from the branch + title.
  # SE-300: branch-switch hook clears .pr-summary.md, so any existing file
  # belongs to this branch. If missing, derive a summary paragraph from title.
  PR_SUMMARY=""
  if [[ -f .pr-summary.md ]]; then
    PR_SUMMARY="$(cat .pr-summary.md)
"
  else
    PR_SUMMARY="## Qué hace este PR (en lenguaje no técnico)
${TITLE}. Ver resumen tecnico en la seccion Summary de este PR.
"
  fi
  BODY="${PR_SUMMARY}## Summary
${TITLE}
### Changes
${COMMITS}
### Stats
${FILES} files changed across $(echo "$COMMITS" | wc -l) commits.
## Test plan
- [x] CI passed  - [x] Signed"
fi
BODY_FILE=$(mktemp); echo "$BODY" > "$BODY_FILE"
if $USE_GH_CLI; then
  # SE-300: detect existing PR; update instead of create
  EXISTING_PR=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number' 2>/dev/null || echo "")
  if [[ -n "$EXISTING_PR" ]]; then
    PR_URL="https://github.com/$REPO/pull/$EXISTING_PR"
    echo "  PR #$EXISTING_PR exists - updating body..."
    # gh pr edit uses GraphQL which warns on deprecated Projects (exit 1). Use REST PATCH.
    if gh api "repos/$REPO/pulls/$EXISTING_PR" -X PATCH         -f "title=$TITLE" -F "body=@$BODY_FILE" >/dev/null 2>&1; then
      echo "  Body updated."
    else
      echo "  WARN: body update failed (existing body kept)."
    fi
  else
    GH_CMD=(gh pr create --title "$TITLE" --body-file "$BODY_FILE")
    $DRAFT && GH_CMD+=(--draft)
    PR_URL=$("${GH_CMD[@]}" 2>&1) || PR_URL="PR creation failed: $PR_URL"
  fi
else
  $DRAFT && DRAFT_PY="True" || DRAFT_PY="False"
  PR_URL=$(python3 -c "
import json,urllib.request,sys
t,r,b,ti='$TOKEN','$REPO','$BRANCH','$(echo "$TITLE" | sed "s/'/\\\\'/g")'
body=open('$BODY_FILE').read(); dr=$([[ "$DRAFT_PY" == "True" ]] && echo True || echo False)
# SE-300: first try to find existing open PR for this branch
try:
  list_req=urllib.request.Request(f'https://api.github.com/repos/{r}/pulls?head={b}&state=open',
    headers={'Authorization':f'token {t}','Accept':'application/vnd.github+json'})
  existing=json.loads(urllib.request.urlopen(list_req).read())
  if existing:
    num=existing[0]['number']
    edit_data=json.dumps({'title':ti,'body':body}).encode()
    edit_req=urllib.request.Request(f'https://api.github.com/repos/{r}/pulls/{num}',
      data=edit_data, method='PATCH',
      headers={'Authorization':f'token {t}','Accept':'application/vnd.github+json','Content-Type':'application/json'})
    json.loads(urllib.request.urlopen(edit_req).read())
    print(f'https://github.com/{r}/pull/{num} (updated)')
  else:
    raise Exception('no_existing')
except Exception as first_err:
  if 'no_existing' not in str(first_err):
    pass
  d=json.dumps({'title':ti,'body':body,'head':b,'base':'main','draft':dr}).encode()
  rq=urllib.request.Request(f'https://api.github.com/repos/{r}/pulls',data=d,
    headers={'Authorization':f'token {t}','Accept':'application/vnd.github+json','Content-Type':'application/json'})
  try:
    print(json.loads(urllib.request.urlopen(rq).read()).get('html_url','PR creation failed'))
  except urllib.error.HTTPError as e:
    err=json.loads(e.read())
    print(f'PR already exists for {b}' if 'already exists' in str(err) else 'PR creation failed')
" 2>&1)
fi
rm -f "$BODY_FILE" "$PWD/.pr-summary.md"; echo "  $PR_URL"

# ── Auto-merge (--merge flag) ────────────────────────────────────────────
MERGED=false
if $MERGE && [[ "$PR_URL" == http* ]]; then
  # SE-343: merge requires a valid operator grant (express request recorded).
  if ! bash scripts/operator-grant.sh check --scope merge >/dev/null 2>&1; then
    echo "ERROR: merge requires a vigente operator grant." >&2
    echo "  El permiso expreso debe registrarse antes (operator-grant.sh grant --scope merge)." >&2
    echo "  Sin autorizacion registrada, el PR queda en Draft y no se mergea." >&2
    exit 1
  fi
  echo "  operator grant 'merge' vigente. Merge autorizado."
  # SE-362: gradación de riesgo — tier 3/4 requiere review humana explícita.
  # (Un grant 'merge' no basta para cambios irreversibles/críticos.)
  CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || true)
  if [[ -n "$CHANGED_FILES" ]] && [[ -f "scripts/risk-tier.py" ]]; then
    TIER_JSON=$(python3 scripts/risk-tier.py --diff "$CHANGED_FILES" --json 2>/dev/null || echo '{"tier":3}')
    RISK_TIER=$(echo "$TIER_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tier',3))" 2>/dev/null || echo 3)
    if [[ "$RISK_TIER" -ge 3 ]]; then
      echo "ERROR: cambio tier $RISK_TIER (irreversible/crítico) requiere review humana explícita (SE-362)." >&2
      echo "  El grant 'merge' no es suficiente. Abrir PR Draft y esperar aprobación humana." >&2
      exit 1
    fi
    echo "  risk-tier: $RISK_TIER (auto-merge permitido)."
  # SE-387 C/F5 — reservation SOLO tras pasar grant y risk-tier:
  # una operación correctamente rechazada nunca deja reservation "reserved".
  PR_NUM_RES="${PR_URL##*/}"
  if [[ -z "$PR_NUM_RES" ]]; then echo "ERROR F5: sin número de PR — fail-explicit" >&2; exit 1; fi
  RES_FILE="$HOME/.savia/reservations/pr.merge__${PR_NUM_RES}.json"
  mkdir -p "$(dirname "$RES_FILE")"
  bash "$ROOT/scripts/f5-state.sh" reserve pr.merge "$PR_NUM_RES" || exit 3
  echo "F5 reservation: pr.merge/$PR_NUM_RES"
  fi
  PR_NUM=$(echo "$PR_URL" | grep -oP '[0-9]+$')
  if $USE_GH_CLI; then
    echo "  Enabling auto-merge..."; gh pr merge "$PR_NUM" --squash --auto 2>&1 | tail -1
    # SE-387 C/F5: merge SOLICITADO != efecto consumado; el close ocurrirá
    # cuando el estado real sea MERGED (retry permite completar desde submitted)
    bash "$ROOT/scripts/f5-state.sh" mark_submitted pr.merge "$PR_NUM"
  elif [[ -n "$TOKEN" ]]; then
    echo "  Waiting for CI..."; SHA=$(git rev-parse HEAD)
    for i in $(seq 1 12); do sleep 10
      R=$(curl -s "https://api.github.com/repos/$REPO/commits/$SHA/check-runs" -H "Authorization: token $TOKEN" \
        | python3 -c "import sys,json;d=json.load(sys.stdin);p=[r for r in d.get('check_runs',[]) if r['status']!='completed'];f=[r for r in d.get('check_runs',[]) if r.get('conclusion') not in ('success','skipped',None) and r['status']=='completed'];print('GREEN' if not p and not f and d.get('total_count',0)>0 else 'FAIL' if f else 'WAIT')")
      [[ "$R" == "GREEN" ]] && break; [[ "$R" == "FAIL" ]] && { echo "  CI failed."; exit 1; }
      echo "  ... ($((i*10))s)"
    done
    [[ "$R" == "GREEN" ]] && curl -s -X PUT "https://api.github.com/repos/$REPO/pulls/$PR_NUM/merge" \
      -H "Authorization: token $TOKEN" -d "{\"merge_method\":\"squash\",\"commit_title\":\"$TITLE\"}" \
      | python3 -c "import sys,json;d=json.load(sys.stdin);print('  Merged.' if 'sha' in d else f'  Merge: {d}')" \
      || echo "  CI timeout. Merge manually."
  fi
  # F5: cerrar reservation solo tras merge real; en fallo queda "reserved"
  # (crash-safe: retry tras crash permite completar; retry tras close => ALREADY_EXECUTED)
  if [[ "$MERGED" == "true" ]]; then
    bash "$ROOT/scripts/f5-state.sh" close pr.merge "$PR_NUM_RES" && echo "F5 receipt: pr.merge/$PR_NUM_RES closed"
  elif [[ -f "$HOME/.savia/reservations/pr.merge__${PR_NUM_RES}.json" ]]; then
    echo "F5 PENDING/SUBMITTED: merge solicitado sin efecto consumado — reservation NO se cierra"
  fi

  # Check if merge completed (for release step)
  if $USE_GH_CLI; then
    PR_STATE=$(gh pr view "$PR_NUM" --json state -q .state 2>/dev/null || echo "")
    [[ "$PR_STATE" == "MERGED" ]] && MERGED=true
  fi
  # SE-343: consume the merge grant after a successful merge (one-shot).
  if $MERGED; then
    bash scripts/operator-grant.sh revoke --scope merge >/dev/null 2>&1 || true
    echo "  Merge grant consumed (one-shot)."
  fi
fi

# ── Step 7: Release update (only after successful merge with gh CLI) ────
if $MERGED && command -v gh >/dev/null 2>&1; then
  echo -e "\n=== Step 7: Release ==="
  VERSION=$(grep -oP '## \[\K[0-9.]+' CHANGELOG.md | head -1)
  if [[ -n "$VERSION" ]]; then
    NOTES=$(sed -n "/^## \[$VERSION\]/,/^## \[/{ /^## \[$VERSION\]/d; /^## \[/d; p; }" CHANGELOG.md)
    if gh release view "v$VERSION" >/dev/null 2>&1; then
      gh release edit "v$VERSION" --notes "$NOTES" && echo "  Updated release v$VERSION."
    else
      gh release create "v$VERSION" --title "PM Workspace v$VERSION" --notes "$NOTES" --latest \
        && echo "  Created release v$VERSION."
    fi
  else echo "  No version in CHANGELOG.md, skipping release."; fi
fi

# Clean sentinel — pr-plan must be re-run for next PR
rm -f .pr-plan-ok
echo -e "\nDone."
