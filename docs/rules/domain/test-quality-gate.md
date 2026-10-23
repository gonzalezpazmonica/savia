---
context_tier: L2
token_budget: 922
---

# Test Quality Gate — SLA

> Doctrine document for SE-039 Slice 3 enforcement.
> Formalizes the quality contract for `tests/*.bats` files in pm-workspace.

## SLA

**Hard floor**: every `.bats` test file MUST score ≥80 on `scripts/test-auditor.sh`.

**Soft target**: ≥95% of the suite maintains score ≥80 across all files.

**Average target**: mean score ≥85 across the whole suite.

Current baseline (2026-04-24 sweep): **232/232 = 100% compliant, average 87**.

## Enforcement layers

| Layer | Scope | Gate | Action on fail |
|---|---|---|---|
| **G6b** in `scripts/pr-plan.sh` | Changed `.bats` files in PR | `--local` pre-push | PR blocked until score ≥80 |
| `.github/workflows/bats-audit-sweep.yml` | All `.bats` files weekly | Monday 06:00 UTC cron | Workflow annotation + artifact |
| `scripts/audit-all-bats.sh` | On-demand full sweep | Manual run | Report to `output/bats-audit-sweep-YYYYMMDD.md` |
| Vacuity ratchet (SE-456) in `scripts/ci-test-quality-gate.sh` | All `.bats` files, CI | `.ci-baseline/test-vacuity.count` | CI fails if tests that cannot fail grow; a file with vacuity is not certified — see `test-evidence-criteria.md` |

## Scoring criteria (from SPEC-055)

The auditor scores 9 criteria summing to 100:

| Criterion | Max pts | What qualifies |
|---|---:|---|
| exists_executable | 8 | File exists + executable |
| safety_verification | 10 | `set -uo pipefail` check, `bash -n` syntax |
| positive_cases | 15 | Happy path tests present |
| negative_cases | 15 | Error path tests present |
| edge_cases | 10 | Tests matching `empty\|nonexistent\|large\|boundary\|null\|no.*arg\|timeout\|zero\|overflow\|max.*depth` |
| isolation | 10 | `setup()`, `teardown()`, `mktemp\|TMPDIR` |
| coverage_breadth | 5 | Tests reference most public functions in target |
| spec_reference | 10 | `SPEC-\d+`, `# Ref:`, `docs/propuestas/`, `docs/rules/` |
| assertion_quality | 9 | Assertions use `$output`, `json.load`, comparison operators |

**Threshold**: ≥80 certifies as `green`. <80 flags remediation needed.

## Remediation playbook

When a test scores below 80, apply patterns from `feedback_test_excellence_patterns.md` (memory):

1. **Add safety header** — `#!/usr/bin/env bats` + `set -uo pipefail` reference
2. **Add setup/teardown** — use `mktemp -d "$TMPDIR/..."` for isolation
3. **Add `# Ref: SPEC-XXX` comment** — references are worth up to 10 pts
4. **Add 3+ edge cases** — keywords: `empty`, `large`, `null`, `nonexistent`, `timeout`, `boundary`
5. **Add negative tests** — malformed input, missing args, unexpected types
6. **Add coverage tests** — use `grep` to verify script contains key functions/constants

## Escalation

- Single test <80: author fixes in same PR (G6b).
- Weekly sweep reports regression (any test <80): Savia assigns remediation to the PR that introduced it.
- Compliance drops below 95% soft target: audit triggers retrospective on test-generation patterns.

## History

| Date | Total | Compliant | % | Avg |
|---|---:|---:|---:|---:|
| 2026-04-24 (SE-039 Slice 1 baseline) | 232 | 232 | 100% | 87 |

## Ortogonal: mutation testing (future)

SE-035 mutation testing (Slice 2 deployed batch 18) measures test EFFECTIVENESS against code mutations. Ortogonal to this auditor which measures test FORM. Both are required for full quality signal:

- **Auditor** (this doc) — "does this test file have the right structure?"
- **Mutation testing** — "do these tests actually catch bugs?"

A test can score 100 on auditor but kill 0 mutations (zombie test). Full quality = auditor ≥80 AND mutation score ≥50%. Mutation testing integration in SE-039 Slice 4 (deferred).

## References

- SE-039 — `docs/propuestas/SE-039-test-auditor-global-sweep.md`
- SPEC-055 — `scripts/test-auditor.sh` engine (`scripts/test-auditor-engine.py`)
- SE-035 — Mutation testing (ortogonal, future integration)
- SE-456 — `docs/rules/domain/test-evidence-criteria.md` (tests que no pueden fallar)
- Memory: `feedback_test_excellence_patterns.md`
