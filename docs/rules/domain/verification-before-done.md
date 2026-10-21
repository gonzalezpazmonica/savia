---
context_tier: L2
token_budget: 804
---

# Verification Before Done (Rule #22)

## Principle

**Default posture: NEEDS WORK** until demonstrable proof exists.
Ask: "Would a senior developer approve this in a code review?"

## Checklist Before Done

1. **Tests pass**: Run relevant test suite. Zero failures.
2. **Line count**: All modified files ≤150 lines.
3. **No PII**: Grep for personal data in all changed files.
4. **Proof of work**: Show output, screenshot, or test results.
5. **Edge cases**: Consider at least 2 edge cases.
6. **Docs updated**: If behavior changed, docs reflect it.
7. **Deliverable reopened**: A successful write does not prove the deliverable is usable. Reopen it or check it with a command (parse, render, run) before saying done.

## Evidence Required

| Task type | Minimum evidence | Format |
|---|---|---|
| Code implementation | Test output (pass/fail + count) | Terminal output |
| UI change | Screenshot before/after | PNG in output/ |
| API endpoint | curl/httpie response + status code | Terminal output |
| DB migration | Schema diff + rollback test | SQL output |
| Config change | Existing tests still pass | Test output |
| Bug fix | Regression test that reproduces bug | Test name + output |
| Performance fix | Benchmark before/after | Metrics table |
| Security fix | Scan output showing fix | Tool output |
| Documentation | Read-back verification | Cross-reference check |
| Rule/skill change | Validate with affected commands | Script output |

## Retry Policy

Aligned with `AGENT_MAX_CONSECUTIVE_FAILURES = 3` from pm-config:

| Attempt | Action | Model |
|---|---|---|
| 1 | Fix with original context | CLAUDE_MODEL_FAST |
| 2 | Fix with expanded context | CLAUDE_MODEL_MID |
| 3 | Fix with full context | CLAUDE_MODEL_AGENT |
| 4+ | **ESCALATE TO HUMAN** | — |

### Escalation Handoff

After 3 failed attempts, escalate with complete context:

```yaml
escalation:
  task: "{description}"
  attempts:
    - attempt: 1
      action: "What was tried"
      result: "Why it failed"
      evidence: "Error output"
    - attempt: 2
      ...
    - attempt: 3
      ...
  recommendation: "Suggested human action"
  files_affected: ["list of files"]
```

Uses `Escalation` template from `handoff-templates.md`.

## Verification Methods by Task Type

| Task | Verification |
|---|---|
| Script change | Run tests + manual smoke test |
| Rule/doc change | Read back + cross-reference |
| Config change | Validate with existing tests |
| New feature | New tests + integration test |
| Bug fix | Regression test that reproduces the bug |

## Retry Policy by Termination Reason (SPEC-TERMINAL-STATE-HANDOFF)

| termination_reason | Action | Rationale |
|---|---|---|
| completed | Continue to next step | Success |
| user_abort | Respect decision | User chose to stop |
| token_budget | Escalate model (FAST→MID→AGENT) | Need bigger window |
| stop_hook | Review hook, fix first | Deterministic cause |
| max_turns | Escalate to human | Task too complex |
| unrecoverable_error | Abort, log to lessons.md | Agent bug |

## Anti-Patterns

- "It should work" without running it
- Marking done before tests complete
- Skipping edge case analysis for "simple" changes
- Assuming docs are still accurate after code changes
- Escalating without context of previous attempts
- Retrying >3 times without escalation (wastes tokens)
- Providing screenshots without highlighting the change
