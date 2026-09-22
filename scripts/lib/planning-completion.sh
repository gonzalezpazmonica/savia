#!/usr/bin/env bash
# Shared completion-evidence validation for SE-396 P01.

planning_completion_shape_valid() {
  local completion="$1"
  jq -e '
    type == "object" and
    (.merge_pr | type == "number" and . > 0 and . == floor) and
    (.acceptance_evidence | type == "array" and length > 0) and
    all(.acceptance_evidence[];
      type == "object" and
      (.criterion | type == "string" and length > 0) and
      (.file | type == "string" and length > 0))
  ' <<<"$completion" >/dev/null 2>&1
}

planning_evidence_file_valid() {
  local root="$1" reference="$2" part root_real file_real
  local -a parts
  [[ -n "$reference" && "$reference" != /* ]] || return 1
  IFS='/' read -r -a parts <<<"$reference"
  for part in "${parts[@]}"; do
    [[ "$part" != ".." ]] || return 1
  done
  root_real=$(realpath -e -- "$root") || return 1
  file_real=$(realpath -e -- "$root/$reference") || return 1
  [[ "$file_real" == "$root_real/"* && -f "$file_real" ]]
}

planning_acceptance_evidence_valid() {
  local root="$1" completion="$2" reference
  planning_completion_shape_valid "$completion" || return 1
  while IFS= read -r reference; do
    planning_evidence_file_valid "$root" "$reference" || return 1
  done < <(jq -r '.acceptance_evidence[].file' <<<"$completion")
}

planning_human_review_approved() {
  local completion="$1"
  jq -e '
    (.human_review | type == "object") and
    (.human_review.status == "APPROVED") and
    (.human_review.evidence | type == "string" and length > 0)
  ' <<<"$completion" >/dev/null 2>&1
}

planning_pr_merged() {
  local root="$1" main_ref="$2" pr="$3"
  git -C "$root" log --format='%s' "$main_ref" -200 2>/dev/null |
    grep -Eq "(^|[^0-9])#${pr}([^0-9]|$)"
}
