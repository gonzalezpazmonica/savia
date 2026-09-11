#!/usr/bin/env bash
# pr-plan-gates.sh — Gate functions for pr-plan.sh (sourced, not executed)
set -uo pipefail

g0() {
  [[ ! -f "$FAILURE_FILE" ]] && return
  local info; info=$(python3 -c "import json;d=json.load(open('$FAILURE_FILE'));print(d['failed_file'],d['ts'],d['gate'])" 2>/dev/null) || { rm -f "$FAILURE_FILE"; return; }
  local ff ts gate; read -r ff ts gate <<< "$info"
  [[ -z "$ff" || "$ff" == "unknown" ]] && { rm -f "$FAILURE_FILE"; return; }
  local file_ts; file_ts=$(git log -1 --format=%cI -- "$ff" 2>/dev/null) || file_ts=""
  if [[ -n "$file_ts" && -n "$ts" ]] && [[ "$file_ts" < "$ts" ]]; then
    FAILED_FILE="$ff"
    echo "FAIL: Previous $gate failure — fix $ff before retrying"; return
  fi
  echo "resolved — $ff modified"; rm -f "$FAILURE_FILE"
}

# Content-bound receipt verification gate.
# Ref: docs/specs/SE-260-gentle-patterns.spec.md (S4, AC-4.7)
# If a receipt v2 exists for this branch and its content hasn't changed,
# skip content gates. If receipt is stale (content changed), full plan required.
g0b() {
  local receipt_script="$ROOT/scripts/receipt-v2.sh"
  [[ ! -x "$receipt_script" ]] && return  # no receipt script, pass through
  local result
  result=$(bash "$receipt_script" verify --branch "$BRANCH" 2>&1) || true
  if echo "$result" | grep -q "RECEIPT VALID"; then
    echo "PASS: receipt v2 valid — skipping content re-review"
    RECEIPT_VALID=true
    return
  elif echo "$result" | grep -q "RECEIPT STALE"; then
    echo "FAIL: receipt v2 stale — content changed, full plan required"
    FAILED_FILE="receipt-v2"
  elif echo "$result" | grep -q "no receipt found"; then
    return  # no receipt = normal flow
  fi
}

gate() {
  local id="$1" name="$2"; shift 2
  [[ -n "$STOPPED" ]] && return
  printf '  %-4s %-28s ...\n' "$id" "$name"
  local t0=$SECONDS
  local result; result=$("$@" 2>&1) || true
  local dt=$(( SECONDS - t0 ))
  local timing=""; (( dt > 2 )) && timing=" ${dt}s"
  if echo "$result" | grep -q "^FAIL:"; then
    sep "$id" "$name" "FAIL${timing}"; FAIL=$((FAIL+1))
    STOPPED="$id: $(echo "$result" | sed 's/^FAIL://')"
    record_failure "$id" "$(echo "$result" | sed 's/^FAIL://')" "${FAILED_FILE:-unknown}"
    FAILED_FILE=""
  elif echo "$result" | grep -q "^WARN:"; then
    sep "$id" "$name" "WARN ($(echo "$result" | sed 's/^WARN://'))${timing}"
    WARN=$((WARN+1))
  else
    sep "$id" "$name" "PASS${result:+ ($result)}${timing}"; PASS=$((PASS+1))
  fi
}

g1() {
  [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]] && echo "FAIL: Switch to feature branch" && return
  echo "$BRANCH"
}
g2() {
  [[ -n "$(git diff --name-only 2>/dev/null)" ]] && echo "FAIL: Commit or stash changes first" && return
}
g3() {
  local marker; marker="<""<""<""<""<""<""<"
  local c; c=$(grep -rln "^${marker}" --include='*.md' --include='*.sh' --include='*.py' --include='*.json' . 2>/dev/null | grep -v '.git/' | grep -v 'worktrees/' | head -5) || true
  [[ -n "$c" ]] && echo "FAIL: Merge conflicts in: $c" && return
}
_resolve_changelog_conflict() {
  local mv; mv=$(git show origin/main:CHANGELOG.md 2>/dev/null | grep -oP '## \[\K[0-9.]+' | head -1) || true
  [[ -z "$mv" ]] && { sed -i '/^<<<<<<< HEAD$/d; /^=======$/d; /^>>>>>>> origin\/main$/d' CHANGELOG.md; return; }
  git show origin/main:CHANGELOG.md > /tmp/_cl_base.md 2>/dev/null || true
  local my_entry=""
  my_entry=$(sed -n "1,/^## \[$mv\]/{ /^## \[$mv\]/d; p; }" CHANGELOG.md \
    | sed '/^<<<<<<</d; /^=======/d; /^>>>>>>>/d' \
    | sed '/^# Changelog/d; /^$/d; /^All notable/d; /^The format/d; /adheres to/d' || true)
  if [[ -z "$my_entry" ]]; then
    sed -i '/^<<<<<<< HEAD$/d; /^=======$/d; /^>>>>>>> origin\/main$/d' CHANGELOG.md; return
  fi
  local header_end
  header_end=$(grep -n '^## \[' /tmp/_cl_base.md | head -1 | cut -d: -f1) || header_end=8
  header_end=$((header_end - 1))
  head -"$header_end" /tmp/_cl_base.md > /tmp/_cl_new.md
  echo "" >> /tmp/_cl_new.md
  echo "$my_entry" >> /tmp/_cl_new.md
  tail -n +"$((header_end + 1))" /tmp/_cl_base.md >> /tmp/_cl_new.md
  local lv; lv=$(echo "$my_entry" | grep -oP '## \[\K[0-9.]+' | head -1) || true
  if [[ -n "$lv" ]]; then
    local prev
    prev=$(git tag --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]' | head -2 | tail -1 | sed 's/^v//') || true
    [[ -z "$prev" ]] && prev=$(echo "$lv" | awk -F. '{ m=$2-1; if(m<0){m=0}; printf "%d.%d.0", $1, m }')
    local repo_url
    repo_url=$(git remote get-url origin 2>/dev/null \
      | sed 's/\.git$//; s|git@github.com:|https://github.com/|; s|https://[^@]*@|https://|') || repo_url=""
    if [[ -n "$repo_url" ]]; then
      local link="[$lv]: $repo_url/compare/v$prev...v$lv"
      local link_line; link_line=$(grep -n "^\[$mv\]:" /tmp/_cl_new.md | head -1 | cut -d: -f1) || true
      [[ -n "$link_line" ]] && sed -i "${link_line}i\\$link" /tmp/_cl_new.md
    fi
  fi
  cp /tmp/_cl_new.md CHANGELOG.md
  rm -f /tmp/_cl_base.md /tmp/_cl_new.md
}

_resolve_signature_conflict() {
  rm -f .confidentiality-signature
  git rm .confidentiality-signature 2>/dev/null || true
}

g4() {
  git fetch origin main --quiet 2>/dev/null || true
  if git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
    echo "0 behind"; return
  fi
  trap 'rm -f /tmp/_cl_base.md /tmp/_cl_new.md' RETURN
  git merge origin/main --no-ff --no-edit 2>&1 >/dev/null || true
  local hard_conflicts
  hard_conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null \
    | grep -vE '^CHANGELOG\.md$|\.confidentiality-signature$' | head -5) || true
  if [[ -n "$hard_conflicts" ]]; then
    git merge --abort 2>/dev/null || true
    echo "FAIL: Merge conflicts in: $hard_conflicts"; return
  fi
  if grep -q '^<<<<<<<' CHANGELOG.md 2>/dev/null; then
    _resolve_changelog_conflict
    git add CHANGELOG.md
  fi
  if git diff --name-only --diff-filter=U 2>/dev/null | grep -q '\.confidentiality-signature'; then
    _resolve_signature_conflict
  fi
  local remaining; remaining=$(git diff --name-only --diff-filter=U 2>/dev/null) || true
  if [[ -n "$remaining" ]]; then
    git merge --abort 2>/dev/null || true
    echo "FAIL: Unresolved conflicts: $remaining"; return
  fi
  git commit --no-edit 2>/dev/null || true
  echo "auto-merged"
}
g5() {
  local all; all=$(git diff origin/main..HEAD --name-only 2>/dev/null) || true
  local non_md; non_md=$(echo "$all" | grep -vE '\.md$' | grep -v '^$' || true)
  [[ -z "$non_md" ]] && echo "skipped (docs-only)" && return
  # High-impact paths: any change in these dirs requires CHANGELOG update.
  # Includes: all .claude/ infrastructure, scripts/, .scm/, .opencode/,
  # .github/workflows/, CLAUDE.md. Commands dir (.opencode/commands/) was
  # previously missing — fixed 2026-05-02 after PR #749 G8 CI failure.
  local hi; hi=$(echo "$all" | grep -E '^(\.claude/|scripts/|\.scm/|\.opencode/|\.github/workflows/|CLAUDE\.md)' || true)
  [[ -z "$hi" ]] && echo "skipped (no high-impact paths)" && return

  # Accept CHANGELOG.d/*.md fragment as valid changelog entry (zero-conflict
  # pattern — see CHANGELOG.d/README.md). If the PR adds a fragment, skip
  # the top-version check; release consolidates fragments into CHANGELOG.md.
  local frag; frag=$(echo "$all" | grep -E '^CHANGELOG\.d/.+\.md$' | grep -v 'README\.md$' || true)
  if [[ -n "$frag" ]]; then
    local frag_count; frag_count=$(echo "$frag" | wc -l)
    echo "skipped (fragment pattern: $frag_count CHANGELOG.d/ file(s))"
    return
  fi

  local lv; lv=$(grep -oP '## \[\K[0-9.]+' CHANGELOG.md 2>/dev/null | head -1)
  local mv; mv=$(git show origin/main:CHANGELOG.md 2>/dev/null | grep -oP '## \[\K[0-9.]+' | head -1) || true
  [[ "$lv" == "$mv" ]] && { FAILED_FILE="CHANGELOG.md"; echo "FAIL: CHANGELOG not updated (both $lv) — use scripts/changelog-fragment.sh or bump top version"; return; }
  local era; era=$(sed -n "/## \[$lv\]/,/## \[/p" CHANGELOG.md | grep -ci 'era ' || true)
  [[ "$era" -eq 0 ]] && { FAILED_FILE="CHANGELOG.md"; echo "FAIL: CHANGELOG v$lv missing Era reference (add 'Era NNN' to description)"; return; }
  # G5.5 — PR queue: enforce lv > max_claimed (Era 210+219).
  if command -v gh >/dev/null 2>&1 && [[ "${PR_PLAN_SKIP_QUEUE_CHECK:-0}" != "1" ]]; then
    local repo; repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || repo=""
    if [[ -n "$repo" ]]; then
      local prs; prs=$(gh pr list --state open --json number,headRefName --jq '.[] | [.number, .headRefName] | @tsv' 2>/dev/null) || prs=""
      local claimed_list="" max_claimed="$mv"
      while IFS=$'\t' read -r pr_num pr_branch; do
        [[ -z "$pr_branch" || "$pr_branch" == "$BRANCH" ]] && continue
        local other_v
        other_v=$(gh api "repos/$repo/contents/CHANGELOG.md?ref=$pr_branch" --jq '.content' 2>/dev/null \
          | base64 -d 2>/dev/null | grep -oP '^## \[\K[0-9.]+' | head -1) || other_v=""
        [[ -z "$other_v" ]] && continue
        claimed_list="$claimed_list $other_v(#$pr_num)"
        if [[ -z "$max_claimed" ]] || \
           [[ "$(printf '%s\n%s\n' "$max_claimed" "$other_v" | sort -V | tail -1)" == "$other_v" ]]; then
          max_claimed="$other_v"
        fi
      done <<< "$prs"
      if [[ -n "$max_claimed" ]] && [[ "$lv" == "$max_claimed" || \
         "$(printf '%s\n%s\n' "$lv" "$max_claimed" | sort -V | tail -1)" != "$lv" ]]; then
        FAILED_FILE="CHANGELOG.md"
        local suggested; suggested=$(echo "$max_claimed" | awk -F. '{ printf "%d.%d.0\n", $1, $2+1 }')
        echo "FAIL: version $lv <= max in queue $max_claimed${claimed_list:+ (claimed:$claimed_list)} — bump to $suggested"
        return
      fi
    fi
  fi
  echo "v$lv"
}
# G5b — Extended CI checks (runs the same 6 checks CI runs: skills frontmatter,
# rule deps, hook safety flags, agent file size, doc link validation, CHANGELOG
# version reference links). Catches CI failures that would otherwise require a
# push + failed CI run + re-push cycle. ~2s. SPEC-031 slice 3 v2 lesson.
g5b() {
  [[ ! -x scripts/ci-extended-checks.sh ]] && { echo "WARN: ci-extended-checks.sh missing or not executable"; return; }
  local out; out=$(bash scripts/ci-extended-checks.sh 2>&1) || true
  local fail_count; fail_count=$(echo "$out" | grep -oP '[0-9]+(?= failed)' | head -1) || fail_count=""
  if [[ -n "$fail_count" ]] && [[ "$fail_count" =~ ^[0-9]+$ ]] && [[ "$fail_count" -gt 0 ]]; then
    local first_fail; first_fail=$(echo "$out" | grep '❌' | head -1 | sed 's/^[[:space:]]*❌[[:space:]]*//')
    FAILED_FILE="CHANGELOG.md"
    echo "FAIL: $fail_count extended-checks failed (first: $first_fail)"
    return
  fi
  echo "6 checks pass"
}

# G6b — Test Quality Gate for CHANGED test files only. Runs the SPEC-055
# auditor (80-point threshold) on every *.bats added/modified in the PR.
# Skipped if no test files changed. Keeps costs low (~2-5s per file) while
# preventing the classic "push + CI fails on low-score test" loop.
g6b() {
  [[ ! -x scripts/test-auditor.sh ]] && { echo "WARN: test-auditor.sh missing"; return; }
  local changed; changed=$(git diff origin/main..HEAD --name-only --diff-filter=AM 2>/dev/null | grep -E '^tests/.*\.bats$' || true)
  [[ -z "$changed" ]] && { echo "skipped (no *.bats changed)"; return; }
  local low=""
  while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    local score; score=$(bash scripts/test-auditor.sh "$f" 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo 0)
    if [[ -n "$score" ]] && [[ "$score" -lt 80 ]]; then
      low="${low} ${f}=${score}"
    fi
  done <<< "$changed"
  if [[ -n "$low" ]]; then
    FAILED_FILE=$(echo "$low" | awk '{print $1}' | cut -d= -f1)
    echo "FAIL: test quality below 80:${low}"
    return
  fi
  local n; n=$(echo "$changed" | wc -l)
  echo "$n file(s) ≥80"
}

g6() {
  command -v bats >/dev/null 2>&1 || { echo "WARN: bats not installed"; return; }
  # Windows Git Bash: BATS has path issues, degrade to WARN
  [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] && { echo "WARN: Windows — BATS deferred to CI"; return; }
  # Some hook tests legitimately exercise branch switching, whose production
  # hook clears this per-branch ephemeral file. G11 still needs the caller's
  # original summary after G6, so isolate it from suite side effects.
  local summary_snapshot=""
  if [[ -f "$ROOT/.pr-summary.md" ]]; then
    summary_snapshot=$(mktemp)
    cp "$ROOT/.pr-summary.md" "$summary_snapshot"
  fi
  local -a suite_files=()
  if [[ -n "${PR_PLAN_BATS_FILES:-}" ]]; then
    read -r -a suite_files <<< "$PR_PLAN_BATS_FILES"
  else
    local base_ref="${PR_PLAN_BASE_REF:-origin/main}"
    mapfile -t suite_files < <(git diff "$base_ref"..HEAD --name-only --diff-filter=AM 2>/dev/null \
      | grep -E '^tests/.*\.bats$' || true)
  fi
  if [[ "${#suite_files[@]}" -eq 0 ]]; then
    if [[ -n "$summary_snapshot" ]]; then
      rm -f "$summary_snapshot"
    fi
    echo "WARN: no changed BATS suites; deferred to CI impact selection"
    return
  fi
  local out suite_status
  out=$(timeout 300 bats "${suite_files[@]}" 2>&1)
  suite_status=$?
  if [[ -n "$summary_snapshot" ]]; then
    cp "$summary_snapshot" "$ROOT/.pr-summary.md"
    rm -f "$summary_snapshot"
  fi
  local fails; fails=$(echo "$out" | grep '❌' | sed 's/.*❌ //' | tr '\n' ', ' | sed 's/, $//') || true
  if [[ "$suite_status" -eq 124 ]]; then
    echo "FAIL: BATS suite timed out after 300s"
    return
  fi
  if [[ "$suite_status" -ne 0 ]]; then
    if [[ -n "$fails" ]]; then
      echo "FAIL: $fails"
    else
      echo "FAIL: BATS suite runner exited with exit $suite_status"
    fi
    return
  fi
  [[ -n "$fails" ]] && echo "FAIL: $fails" && return
  if ! grep -qE '^1\.\.[0-9]+' <<< "$out"; then
    echo "FAIL: BATS completed without a TAP completion plan"
    return
  fi
  echo "${#suite_files[@]}/${#suite_files[@]} changed suites"
}
g7() {
  local out; out=$(bash scripts/confidentiality-scan.sh --pr 2>&1) || true
  echo "$out" | grep -q "BLOCKED" && { echo "FAIL: $(echo "$out" | grep 'FAIL ' | head -3 | tr '\n' '; ')"; return; }
  echo "0 violations"
}
g8() {
  local nf; nf=$(git diff origin/main..HEAD --diff-filter=A --name-only 2>/dev/null) || true
  local need=false
  echo "$nf" | grep -qE '^\.claude/(commands|skills|agents)/' && need=true
  $need && ! echo "$nf" | grep -q 'README.md' && { echo "WARN: new components, README not updated"; return; }
}
g9() {
  local safe='^(_|team-|savia-web$|savia-mobile-android$|savia-monitor$|savia-vaults$|pm-workspace$|proyecto-alpha$|proyecto-beta$|sala-reservas$|example$|test$|demo$|sample$|template$)'
  local names; names=$(ls -d projects/*/ 2>/dev/null | xargs -I{} basename {} | grep -vE "$safe") || true
  [[ -z "$names" ]] && return
  # Only scan ADDED lines in the diff, not full file content
  local added; added=$(git diff origin/main..HEAD | grep '^+' | grep -v '^+++' || true)
  [[ -z "$added" ]] && return
  local leaks=""
  for n in $names; do
    echo "$added" | grep -q "$n" && leaks="$leaks $n in diff;"
  done
  [[ -n "$leaks" ]] && echo "FAIL: Private data:$leaks"
}
g10() {
  local out; out=$(bash scripts/validate-ci-local.sh 2>&1) || true
  echo "$out" | grep -q "safe to push" || { echo "FAIL: CI issues (run validate-ci-local.sh)"; return; }
}
# G_SUMMARY: PR natural-language summary required (rule pr-natural-language-summary.md)
g_summary() {
  local f="$ROOT/.pr-summary.md"
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing .pr-summary.md (write a non-technical paragraph for the PR — see docs/rules/domain/pr-natural-language-summary.md)"
    return
  fi
  local size; size=$(wc -c < "$f" | tr -d ' ')
  if [[ "$size" -lt 300 ]]; then
    echo "FAIL: .pr-summary.md too short ($size chars, min 300)"
    return
  fi
  if ! grep -q '^## Qué hace este PR (en lenguaje no técnico)' "$f"; then
    echo "FAIL: .pr-summary.md missing required heading '## Qué hace este PR (en lenguaje no técnico)'"
    return
  fi
}
# G_OPENCODE_PLAN: G12 — every spec APPROVED post-2026-04-26 must include OpenCode Implementation Plan.
# Rule: docs/rules/domain/spec-opencode-implementation-plan.md
g_opencode_plan() {
  if ! git diff origin/main..HEAD --name-only 2>/dev/null | grep -qE '^docs/propuestas/(SE|SPEC)-.*\.md$'; then
    return
  fi
  if ! bash "$ROOT/scripts/spec-opencode-plan-audit.sh" >/dev/null 2>&1; then
    local out; out=$(bash "$ROOT/scripts/spec-opencode-plan-audit.sh" 2>&1 || true)
    echo "FAIL: spec-opencode-plan audit"
    echo "$out" | tail -10
    return
  fi
}
g11() {
  local stat_line
  if ! git rev-parse origin/main >/dev/null 2>&1; then
    echo "WARN: Review level: unknown (origin/main unreachable)"; return
  fi
  stat_line=$(git diff origin/main..HEAD --stat 2>/dev/null | tail -1) || true
  if [[ -z "$stat_line" ]]; then
    echo "0 lines — nothing to review"; return
  fi
  local ins; ins=$(echo "$stat_line" | grep -oP '[0-9]+(?= insertion)' || echo 0)
  local dels; dels=$(echo "$stat_line" | grep -oP '[0-9]+(?= deletion)' || echo 0)
  local size=$(( ${ins:-0} + ${dels:-0} ))
  [[ $size -eq 0 ]] && { echo "0 lines — nothing to review"; return; }
  local size_tier=""
  if [[ $size -lt 50 ]]; then size_tier="XS"
  elif [[ $size -le 300 ]]; then size_tier="STANDARD"
  elif [[ $size -le 1000 ]]; then size_tier="ENHANCED"
  else size_tier="FULL"; fi
  local risk_tier="" risk_score="" escalated=""
  if [[ -f "output/risk-score.json" ]]; then
    risk_score=$(jq -r '.score // empty' output/risk-score.json 2>/dev/null) || true
    if [[ -n "$risk_score" ]] && [[ "$risk_score" =~ ^[0-9]+$ ]]; then
      if [[ $risk_score -le 25 ]]; then risk_tier="XS"
      elif [[ $risk_score -le 50 ]]; then risk_tier="STANDARD"
      elif [[ $risk_score -le 75 ]]; then risk_tier="ENHANCED"
      else risk_tier="FULL"; fi
    fi
  fi
  local eff="$size_tier"
  if [[ -n "$risk_tier" ]]; then
    local -A rank=([XS]=0 [STANDARD]=1 [ENHANCED]=2 [FULL]=3)
    if [[ ${rank[$risk_tier]:-0} -gt ${rank[$size_tier]:-0} ]]; then
      eff="$risk_tier"
      escalated=", risk score $risk_score escalated from $size_tier"
    fi
  fi
  case "$eff" in
    XS)       echo "XS ($size lines${escalated}) — quick lint" ;;
    STANDARD) echo "WARN: Review level: STANDARD ($size lines${escalated}) — 1 reviewer recommended" ;;
    ENHANCED) echo "WARN: Review level: ENHANCED ($size lines${escalated}) — 2 reviewers + architect recommended" ;;
    FULL)     echo "WARN: Review level: FULL ($size lines${escalated}) — consensus panel recommended. Consider splitting." ;;
  esac
}

# G13_SCOPE_TRACE: every changed file in the PR must trace to either
#   (a) the spec referenced in .pr-summary.md / commit / branch name (token overlap or path prefix),
#   (b) a hard-coded whitelist (CHANGELOG.*, .scm/, .confidentiality-signature, .pr-summary.md),
#   (c) an explicit `Scope-trace: skip — <reason ≥10 chars>` override in .pr-summary.md.
# Spec: SE-079 (docs/propuestas/SE-079-pr-plan-scope-trace-gate.md).
# Pattern: Genesis B9 GOAL STEWARD + B8 ATTENTION ANCHOR
# (docs/rules/domain/attention-anchor.md, SE-080).
g13_scope_trace() {
  if ! git rev-parse origin/main >/dev/null 2>&1; then
    echo "WARN: skipped (origin/main unreachable)"; return
  fi
  local files; files=$(git diff origin/main..HEAD --name-only 2>/dev/null | grep -v '^$') || true
  [[ -z "$files" ]] && { echo "skipped (no changes)"; return; }

  # Skip override — explicit user opt-out with a reason
  local summary="$ROOT/.pr-summary.md"
  if [[ -f "$summary" ]]; then
    local skip_line; skip_line=$(grep -E '^Scope-trace: skip' "$summary" || true)
    if [[ -n "$skip_line" ]]; then
      local reason; reason=$(echo "$skip_line" | sed -E 's/^Scope-trace: skip[[:space:]]*[—-]?[[:space:]]*//')
      if [[ "${#reason}" -ge 10 ]]; then
        echo "skipped via override — ${reason:0:60}"; return
      fi
      echo "FAIL: Scope-trace skip reason too short (${#reason} chars, min 10)"; return
    fi
  fi

  # Detect spec ids — collect ALL refs from summary + commits + branch.
  # A multi-spec PR (e.g. a sprint batch) is allowed: a file matches if it
  # traces to ANY of the referenced specs. Single-spec PRs still benefit
  # from the same code path with a one-element list.
  local spec_ids=""
  if [[ -f "$summary" ]]; then
    spec_ids=$(grep -oE '\b(SE|SPEC)-[0-9]+\b' "$summary" 2>/dev/null || true)
  fi
  spec_ids="${spec_ids}"$'\n'"$(git log origin/main..HEAD --format=%B 2>/dev/null | grep -oE '\b(SE|SPEC)-[0-9]+\b' || true)"
  local branch_id; branch_id=$(echo "$BRANCH" | grep -oE '\b(se|spec)-?[0-9]+\b' | head -1 | tr '[:lower:]' '[:upper:]' | sed 's/-\?\([0-9]\)/-\1/' || true)
  [[ -n "$branch_id" ]] && spec_ids="${spec_ids}"$'\n'"${branch_id}"
  spec_ids=$(echo "$spec_ids" | grep -E '^(SE|SPEC)-[0-9]+$' | sort -u)

  if [[ -z "$spec_ids" ]]; then
    echo "WARN: B8 attention-anchor missing — no spec ref in .pr-summary.md, commits, or branch (gate skipped)"; return
  fi

  # Locate spec files for every ref (silently skip missing ones)
  local spec_files=""
  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    local f; f=$(find "$ROOT/docs/propuestas" -maxdepth 1 -type f -name "${sid}*.md" 2>/dev/null | head -1)
    [[ -n "$f" ]] && spec_files="${spec_files}${f}"$'\n'
  done <<< "$spec_ids"
  spec_files=$(echo "$spec_files" | grep -v '^$' || true)

  if [[ -z "$spec_files" ]]; then
    local first_id; first_id=$(echo "$spec_ids" | head -1)
    echo "WARN: B8 attention-anchor weak — spec ${first_id} referenced but file not found in docs/propuestas/ (gate skipped)"; return
  fi

  # Pull AC tokens (lowercase, length ≥ 4) from ALL referenced specs.
  # `-` MUST be last in the tr complement set to avoid reverse-range error.
  local ac_tokens=""
  while IFS= read -r sf; do
    [[ -z "$sf" ]] && continue
    local toks; toks=$(grep -E '^- \[[ x]\] AC-' "$sf" 2>/dev/null \
      | tr '[:upper:]' '[:lower:]' \
      | tr -c '[:alnum:]_\n-' ' ' \
      | tr ' ' '\n' \
      | awk 'length($0) >= 4')
    ac_tokens="${ac_tokens}${toks}"$'\n'
  done <<< "$spec_files"
  ac_tokens=$(echo "$ac_tokens" | grep -v '^$' | sort -u)

  # Pull explicit path mentions from ALL referenced spec bodies
  local path_hints=""
  while IFS= read -r sf; do
    [[ -z "$sf" ]] && continue
    local hints; hints=$(grep -oE '[a-zA-Z0-9_./-]+\.(sh|py|md|bats|json|yaml|yml|ts|tsx|js)' "$sf" 2>/dev/null)
    path_hints="${path_hints}${hints}"$'\n'
  done <<< "$spec_files"
  path_hints=$(echo "$path_hints" | grep -v '^$' | sort -u)

  # Build a list of "self-spec paths" — multi-spec PRs touch many spec files
  local spec_self_globs=""
  while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    spec_self_globs="${spec_self_globs}docs/propuestas/${sid}-"$'\n'
  done <<< "$spec_ids"

  local unmatched=() unmatched_count=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      CHANGELOG.md|CHANGELOG.d/*|.scm/*|.confidentiality-signature|.pr-summary.md) continue ;;
    esac
    # Self-spec match — touching a referenced spec's own .md file is in-scope
    local self_match=0
    while IFS= read -r prefix; do
      [[ -z "$prefix" ]] && continue
      [[ "$f" == "${prefix}"* ]] && { self_match=1; break; }
    done <<< "$spec_self_globs"
    [[ "$self_match" -eq 1 ]] && continue
    # Path hint match across all spec bodies
    if [[ -n "$path_hints" ]] && echo "$path_hints" | grep -Fxq "$f"; then continue; fi
    # Token overlap. Try the whole basename first ("pr-plan" matching the
    # AC mention `pr-plan.sh`); fall back to per-token split for multi-word
    # names; finally try substring match so a token like "queue" hits
    # "queue-manager" in the AC text.
    local base; base=$(basename "$f" | sed -E 's/\.[a-z]+$//' | tr '[:upper:]' '[:lower:]')
    local matched=0
    if [[ -n "$ac_tokens" ]]; then
      if echo "$ac_tokens" | grep -Fxq "$base"; then
        matched=1
      else
        for tok in $(echo "$base" | tr '_-' '\n\n' | awk 'length($0) >= 4'); do
          if echo "$ac_tokens" | grep -Fxq "$tok" || echo "$ac_tokens" | grep -Fq "$tok"; then
            matched=1; break
          fi
        done
      fi
    fi
    if [[ "$matched" -eq 0 ]]; then
      unmatched_count=$((unmatched_count + 1))
      [[ "${#unmatched[@]}" -lt 10 ]] && unmatched+=("$f")
    fi
  done <<< "$files"

  local id_list; id_list=$(echo "$spec_ids" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
  if [[ "$unmatched_count" -gt 0 ]]; then
    {
      echo "FAIL: ${unmatched_count} file(s) do not trace to any AC of {${id_list}}:"
      for f in "${unmatched[@]}"; do echo "  - $f → NO MATCH"; done
      [[ "$unmatched_count" -gt "${#unmatched[@]}" ]] && echo "  … ($((unmatched_count - ${#unmatched[@]})) more)"
      echo "  resolve: add the file to a relevant AC, or override via 'Scope-trace: skip — <reason ≥10 chars>' in .pr-summary.md"
    }
    return
  fi
  echo "B8 attention-anchor present (${id_list})"
}

# G14_SKILL_CATALOG: every SKILL.md added or modified in the PR must pass
# the SE-084 catalog audit (frontmatter / Use-when trigger / size limits).
# Skipped if no SKILL.md changed. WARN-severity (skill-long, missing-use-when)
# does not block; FAIL-severity (missing-frontmatter, missing-name, missing-description,
# description-too-short, skill-overlong) blocks. Reference: SE-084 Slice 2.
g14_skill_catalog() {
  local auditor="scripts/skill-catalog-audit.sh"
  if [[ ! -x "$auditor" ]]; then
    echo "WARN: $auditor missing or not executable (SE-084 Slice 1 not yet on this branch)"
    return
  fi

  # Files added or modified in the PR, restricted to SKILL.md under .opencode/skills/
  local skills
  skills=$(git diff origin/main..HEAD --name-only --diff-filter=AM 2>/dev/null \
           | grep -E '^\.opencode/skills/[^/]+/SKILL\.md$' || true)
  if [[ -z "$skills" ]]; then
    echo "skipped (no SKILL.md changed)"
    return
  fi

  local fail_count=0 warn_count=0
  declare -a fail_skills=()
  while IFS= read -r skill_md; do
    local skill_dir; skill_dir=$(dirname "$skill_md")
    local out
    out=$(bash "$auditor" --json --skill "$skill_dir" 2>&1) || true
    # JSON shape: {"skill_count":1,"warn":N,"fail":M,"tsv":"..."}
    local f w
    f=$(echo "$out" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('fail',0))" 2>/dev/null || echo 0)
    w=$(echo "$out" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('warn',0))" 2>/dev/null || echo 0)
    fail_count=$((fail_count + f))
    warn_count=$((warn_count + w))
    [[ "$f" -gt 0 ]] && fail_skills+=("$skill_md")
  done <<< "$skills"

  local count; count=$(echo "$skills" | wc -l | tr -d ' ')
  if [[ "$fail_count" -gt 0 ]]; then
    {
      echo "FAIL: ${fail_count} fail-severity issue(s) across ${#fail_skills[@]} modified skill(s):"
      for s in "${fail_skills[@]}"; do echo "  - $s"; done
      echo "  resolve: see docs/rules/domain/skill-catalog-discipline.md"
      echo "  detail:  bash $auditor --report --skill .opencode/skills/<name>"
    }
    return
  fi
  echo "${count} skill(s) audited — fail=${fail_count} warn=${warn_count}"
}

# ── G-pre-push: CI Reliability Gate (SPEC-SE-012, advisory) ─────────────────
# Runs ci-reliability-gate.sh before push to surface common CI failure causes.
# Non-blocking by design: failures emit WARN (never FAIL) so they do not stop
# the pipeline. The operator decides whether to address them before pushing.
g_pre_push_reliability() {
  local gate_script="${BASH_SOURCE%/*}/ci-reliability-gate.sh"
  if [[ ! -f "$gate_script" ]]; then
    echo "WARN: ci-reliability-gate.sh not found — install SPEC-SE-012"
    return
  fi
  if [[ ! -x "$gate_script" ]]; then
    chmod +x "$gate_script" 2>/dev/null || true
  fi
  local out
  out=$(bash "$gate_script" --json 2>/dev/null) || true
  if [[ -z "$out" ]]; then
    echo "WARN: ci-reliability-gate.sh produced no output"
    return
  fi
  local all_passed
  all_passed=$(echo "$out" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('all_passed','true'))" 2>/dev/null || echo "true")
  if [[ "$all_passed" == "True" || "$all_passed" == "true" ]]; then
    echo "all 8 CI checks passed"
    return
  fi
  # Build a concise list of failing check names for the WARN message
  local failing
  failing=$(echo "$out" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
names = [c['name'] for c in d.get('checks', []) if not c.get('passed', True)]
print(', '.join(names))
" 2>/dev/null || echo "unknown")
  echo "WARN: CI reliability issues detected: $failing — run 'bash scripts/ci-reliability-gate.sh' for details"
}

# ── G16 — Eval-lint golden sets (SE-316 S3) ────────────────────────────────
# Corrida solo si el PR toca tests/evals/ o config/eval-case.schema.json.
# Blocking: golden sets rotos degradan la confianza de los tribunales.
g16_eval_lint() {
  local linter="scripts/eval-lint.sh"
  if [[ ! -f "$linter" ]]; then
    echo "WARN: eval-lint.sh missing (SE-316 not installed)"
    return
  fi

  local changed
  changed=$(git diff origin/main..HEAD --name-only --diff-filter=AM 2>/dev/null \
            | grep -E '^tests/evals/|^config/eval-case\.schema\.json$' || true)
  if [[ -z "$changed" ]]; then
    echo "skipped (no eval golden sets changed)"
    return
  fi

  local out
  out=$(bash "$linter" --check tests/evals 2>&1)
  local code=$?
  if [[ $code -eq 0 ]]; then
    echo "$out"
  else
    echo "FAIL: $out"
  fi
}


# ── G17 — Scope Creep (SE-315 S3) ─────────────────────────────────────────
# Report-only: detecta diffs fuera del alcance declarado de la spec referenciada.
# Nunca bloquea (AC-S2.4); emite veredicto y recomendación. Se calibra antes
# de promover a bloqueante. Ref: docs/propuestas/SE-315-scope-creep-gate.md.
g17_scope_creep() {
  local checker="scripts/scope-creep-check.sh"
  local declarer="scripts/scope-declare.sh"
  local resolver="$ROOT/scripts/spec-resolve.sh"
  if [[ ! -f "$checker" || ! -f "$declarer" || ! -f "$resolver" ]]; then
    echo "WARN: scope-creep scripts missing (SE-315 not installed)"
    return
  fi

  # Localiza la spec que motiva el PR: del summary, commits o branch.
  local spec_file=""
  local sid=""
  sid=$(grep -oE '\b(SE|SPEC)-[0-9]+' .pr-summary.md 2>/dev/null | head -1)
  [[ -z "$sid" ]] && sid=$(git log origin/main..HEAD --format=%B 2>/dev/null | grep -oE '\b(SE|SPEC)-[0-9]+\b' | head -1)
  [[ -z "$sid" ]] && sid=$(echo "$BRANCH" | grep -oE '\b(se|spec)-?[0-9]+\b' | head -1 | tr '[:lower:]' '[:upper:]' | sed 's/-\?\([0-9]\)/-\1/')
  if [[ -z "$sid" ]]; then
    echo "WARN: no spec ref en summary/commits/branch (gate skipped)"
    return
  fi
  local resolution
  resolution=$(bash "$resolver" --root "$ROOT" --id "$sid" 2>&1)
  local resolution_status=$?
  if [[ $resolution_status -ne 0 ]]; then
    echo "WARN: ${resolution} (gate skipped)"
    return
  fi
  spec_file="$resolution"

  local verdict
  verdict=$(bash "$checker" --spec "$spec_file" --base origin/main --head HEAD --verdict 2>&1)
  case "$verdict" in
    IN_SCOPE) echo "PASS: scope alineado con ${sid} (IN_SCOPE)" ;;
    NO_DECLARED)
      echo "WARN: spec ${sid} no declara paths — revisión manual recomendada" ;;
    *)
      local extra; extra=$(bash "$checker" --spec "$spec_file" --base origin/main --head HEAD --files-unrelated 2>/dev/null | head -5 | paste -sd' ' -)
      echo "WARN: ${verdict} — ficheros fuera de alcance de ${sid}: ${extra:-ver detalles}"
      ;;
  esac
}

# ── G18 — Incident RCA eval (SE-323 S3) ─────────────────────────────────────
# Report-only: ejecuta la suite sintética de RCA (rca-eval-runner.sh) y reporta
# el score. Nunca bloquea (gate de calidad, no de seguridad); emite WARN si
# el score baja del umbral 80 para que se revise antes del merge. Ref:
# docs/propuestas/SE-323-incident-rca-agent.md.
g18_incident_rca_eval() {
  local runner="scripts/rca-eval-runner.sh"
  local cases="tests/evals/incident-rca/rca-cases.jsonl"
  if [[ ! -f "$runner" || ! -f "$cases" ]]; then
    echo "WARN: rca-eval-runner/cases missing (SE-323 not installed)"
    return
  fi
  local out
  out=$(bash "$runner" --json 2>&1)
  local score verdict
  score=$(echo "$out" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['score'])" 2>/dev/null)
  verdict=$(echo "$out" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['verdict'])" 2>/dev/null)
  if [[ "$score" -ge 80 ]]; then
    echo "PASS: RCA eval suite score=${score}/100 (gate >= 80)"
  else
    echo "WARN: RCA eval suite score=${score}/100 < 80 — revisar antes del merge"
  fi
}
