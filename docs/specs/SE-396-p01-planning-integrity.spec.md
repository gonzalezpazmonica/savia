---
spec_id: SE-396-P01
title: Planning integrity and evidence-bound graduation
status: APPROVED
implementation_state: IMPLEMENTED_PENDING_HUMAN_REVIEW
parent: SE-396
approval: "Inherited from SE-396 approval recorded in planning-state.json"
date: 2026-09-21
---

# SE-396 P01 — Planning integrity and evidence-bound graduation

## Objective

Close H11 without introducing a second planning or evidence ledger. The canonical
`docs/propuestas/planning-state.json` remains authoritative. New completions must
bind a merged PR to explicit acceptance-criterion evidence and a separate human
review before the initiative can be represented as `IMPLEMENTED`.

## Contract

`planning-state.json` declares `completion_contract_floor`. Initiatives whose
numeric SE identifier is at or above that floor use this optional structure while
they are in progress and require it when implemented:

```json
{
  "completion": {
    "merge_pr": 1234,
    "acceptance_evidence": [
      {"criterion": "AC-01", "file": "tests/example.bats"}
    ],
    "human_review": {
      "status": "APPROVED",
      "evidence": "review or approval reference"
    }
  }
}
```

Rules:

1. `merge_pr` is a positive integer and must identify a merge reachable from the
   configured main ref.
2. `acceptance_evidence` is a non-empty array. Every entry has a non-empty
   `criterion` and a safe repo-relative existing `file`; absolute paths and `..`
   traversal and symlink escapes are invalid.
3. `human_review.status` must equal `APPROVED` and its `evidence` must be non-empty
   before an initiative at or above the migration floor may be `IMPLEMENTED`.
4. For an `IMPLEMENTING` initiative, a verified merge plus valid AC evidence only
   yields `NEEDS_HUMAN_REVIEW`. The checker never mutates planning state.
5. Free-text `evidence` remains narrative/provenance and is never parsed as the
   completion authority for initiatives governed by this contract.
6. Initiatives below `completion_contract_floor` are legacy state and are not
   retroactively reclassified.

## CLI behavior

`bash scripts/planning-transition.sh check SE-NNN`:

- exit `0`, `NEEDS_HUMAN_REVIEW`, only when status is `IMPLEMENTING`, the
  structured PR is merged, and every acceptance reference is valid;
- exit `1`, `NOT_READY: ...`, for missing/malformed completion data, absent merge,
  unsafe/missing evidence files, or any non-`IMPLEMENTING` status;
- never writes `planning-state.json`, a spec, or `LOG.md`.

`bash scripts/roadmap.sh validate` additionally rejects governed `IMPLEMENTED`
initiatives without valid completion data and explicit approved human review.

## Acceptance criteria

- **AC-01:** A merged PR without structured AC evidence cannot become ready.
- **AC-02:** Missing, absolute, traversal, or escaping-symlink evidence references
  fail closed.
- **AC-03:** A merged PR with valid AC evidence yields only
  `NEEDS_HUMAN_REVIEW` and leaves canonical state byte-identical.
- **AC-04:** A governed `IMPLEMENTED` initiative without approved human review
  makes `roadmap validate` fail.
- **AC-05:** A governed `IMPLEMENTED` initiative with valid merge metadata, AC
  evidence, a PR reachable from main, and approved human review passes validation.
- **AC-06:** YAML and Markdown spec-status drift and omitted-spec coverage remain
  enforced by the existing validator tests.
- **AC-07:** The repository's current planning state validates after adding the
  migration boundary; no legacy initiative is silently reclassified.

## Test plan

- `bats tests/test-planning-transition.bats`
- `bats tests/test-roadmap-validate.bats`
- `bash scripts/roadmap.sh validate`
- `git diff --check`

## Non-goals

- Automatic transition to `IMPLEMENTED`.
- Authenticating the external human-review system.
- Replacing `LOG.md`, receipts, or the planning-state authority.
- Implementing SE-401/I2E runtime contracts.
