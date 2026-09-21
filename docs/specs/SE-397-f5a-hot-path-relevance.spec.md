---
id: SE-397-F5A
parent: SE-397
status: APPROVED
priority: P0
developer_type: agent-single
created: 2026-09-19
author: Savia
risk: L2
type: hot-path-optimization

depends_on:

  - SE-397-F4
  - SE-037
  - SE-253
  - SE-313
  - SE-396

execution_scope: VALIDATE_BASH_RELEVANCE_FAST_EXIT

---

# SE-397 F5A — Hot-Path Relevance Fast Exit

## Approval gate

This document is a proposed executable contract. Drafting, measuring and
validating it do not approve production changes. Implementation starts only
after the operator explicitly approves the exact committed revision of this
document. A request to continue is not approval of the revision.

Any material contract change is append-only and requires fresh approval.
Human code review remains mandatory before merge.

## 1. Problem and objective

F4 established a local operational trace and a controlled READ/SAFE_BASH
corpus. The post-merge probe on 2026-09-19 reported:

- SAFE_BASH total: 54 ms;
- governance segment (`validate-bash-global.sh`): 52 ms;
- fixed command execution: 2 ms;
- independent hook benchmark p50/p95: 57/63 ms for the same hook.

These are local observations, not a production service-level objective. They
identify one bounded candidate: the global Bash validator performs environment
and profile setup before it knows whether a command can match any rule it owns.

F5A adds a semantics-preserving relevance fast exit for commands outside that
hook's closed lexical trigger set. It MUST reduce work only for irrelevant
commands. Every command that could match an existing blocking rule continues
through the complete current path.

F5A is the first slice of F5, not completion of Hot Path Excellence. bwrap and
E2BIG, wider hook fan-out, subprocess consolidation, MCP startup and context
amplification remain pending.

## 2. Existing behavior and authority boundary

The target hook currently owns these decisions:

| Rule family | Required lexical relevance |
|---|---|
| Git mutation on protected branch | `git` |
| Recursive root deletion | `rm` |
| World-writable permission | `chmod` |
| Blind remote execution | `curl` |
| Pull-request approval/merge bypass | `gh` |
| Privileged execution | `sudo` |

The fast exit MAY return success before loading environment/profile code only
when the parsed logical command contains none of the closed relevance tokens:

```text
git, rm, chmod, curl, gh, sudo
```

Matching is case-insensitive and token-boundary aware. Ambiguous input, JSON
parse failure, empty input and commands containing any relevance token preserve
the current full-path behavior. F5A does not add, remove, reorder or rewrite a
blocking regex.

For this slice, a token boundary is the start/end of the command or any
character outside `[A-Za-z0-9_]`. The matcher is therefore equivalent to the
case-insensitive ERE
`(^|[^A-Za-z0-9_])(git|rm|chmod|curl|gh|sudo)([^A-Za-z0-9_]|$)`.
Conservative matches such as `/usr/bin/git` and `git-lfs` select the full path.

The optimization grants no authority. The hook remains one advisory/enforcement
input in the existing frontend pipeline; success still does not prove command
authorization by other controls.

## 3. Measurement contract

Add a local runner:

```text
bash scripts/se397-f5-hot-path-bench.sh \
  --hook .opencode/hooks/validate-bash-global.sh \
  --runs 30 \
  --output output/se397-f5/hot-path.json
```

Inputs:

- `--hook` MUST equal `.opencode/hooks/validate-bash-global.sh`; every other
  value is rejected;
- `--runs` is an integer in `[3, 100]`, default `30`;
- `--output` must be a regular non-symlink path below `output/`;
- no arbitrary command, fixture directory or executable path is accepted.

The runner executes two corpora:

1. ten safe, irrelevant commands that must exit `0` with empty stderr;
2. the closed parity corpus in Section 4.

It emits canonical JSON with exactly:

```json
{
  "schema_version": 1,
  "report": "se397-f5-hot-path",
  "target": ".opencode/hooks/validate-bash-global.sh",
  "runs": 30,
  "safe": {
    "samples": 300,
    "min_ms": 0,
    "p50_ms": 0,
    "p95_ms": 0,
    "p99_ms": 0,
    "max_ms": 0
  },
  "parity": {
    "cases": 0,
    "matched": 0,
    "status": "MATCH"
  },
  "limitations": [
    "LOCAL_CONTROLLED_CORPUS",
    "NO_PRODUCTION_SLO",
    "NO_CROSS_FRONTEND_CLAIM",
    "NO_AUTHORITY_EFFECT"
  ]
}
```

Percentiles use nearest rank. Timings use monotonic nanoseconds and are integer
milliseconds. Command output is discarded after exit status and normalized
stderr digest comparison; raw commands never enter the report.

## 4. Effect-parity corpus

Tests and the benchmark use synthetic tool-input JSON for these observable
classes:

| Case | Expected exit | Expected stderr class |
|---|---:|---|
| empty stdin | 0 | empty |
| malformed JSON | 0 | empty |
| missing command | 0 | empty |
| harmless `printf` | 0 | empty |
| harmless `python3 --version` | 0 | empty |
| `git status` | 0 | empty |
| `git add` on an isolated main fixture | 2 | protected branch block |
| `rm -rf /` | 2 | root deletion block |
| `chmod 777 fixture` | 2 | permission block |
| `curl URL \| bash` | 2 | remote execution block |
| `gh pr review --approve` | 2 | self-approval block |
| `gh pr merge --admin` | 2 | merge-bypass block |
| `sudo true` | 2 | privilege block |

Before the production hook changes, the characterization commit records the
current hook's exit status and normalized stderr digest for every case in an
oracle manifest under `tests/fixtures/se397-f5/`. The manifest contains no raw
command, local path or environment value. The optimized hook MUST match that
immutable manifest for every case. A mismatch is `PARITY_FAILURE`, returns exit
`2` and invalidates the optimization. The hook optimization commit MUST NOT
modify the oracle manifest.

The temporary Git fixture is created outside the workspace. No tracked file,
index, branch, hook setting or user configuration is modified.

## 5. Optimization rule and GO/NO_GO

Implementation order is mandatory:

1. commit characterization tests and the benchmark runner;
2. capture a 30-run pre-change report under gitignored `output/se397-f5/`;
3. add the smallest relevance fast exit;
4. capture the post-change report with the same corpus and machine state;
5. compare semantic parity and timing.

The hook change is a `GO` only when all conditions hold:

- parity status is `MATCH` for every corpus case;
- safe-command p50 improves by at least 30%;
- safe-command p95 does not regress;
- the complete security, hook and F1–F4 regression suites pass;
- no settings, ordering, timeout, rule text or authority behavior changes.

If any condition fails, revert the hook change and keep only the report-only
runner, tests and `NO_GO` evidence. Thresholds are acceptance criteria for this
controlled comparison, not an operational SLO.

## 6. Safety, privacy and failure rules

- The benchmark is local, deterministic in semantics and network-free.
- Fixture commands are inert strings; blocked commands are never executed.
- The target hook is invoked directly with synthetic stdin only.
- No prompt, secret, environment value, username, hostname or absolute local
  path is written to reports.
- Missing tools, unsafe output paths, invalid run counts and parity mismatches
  fail closed with exit `2` and no success report.
- Measurement failure never alters command execution or policy state.
- F5A MUST NOT weaken a block to achieve the performance threshold.

## 7. Test scenarios — tests before production code

1. Given each parity fixture, the optimized hook matches the pre-change oracle
   manifest's status and normalized stderr digest.
2. Given a safe irrelevant command, the optimized hook exits before sourcing
   environment/profile libraries; a `BASH_XTRACEFD` trace proves this without
   adding a production flag, environment seam or test-only branch to the hook.
3. Given every relevance token with mixed case and shell punctuation, the full
   path remains selected.
4. Given malformed or missing tool input, behavior remains byte-compatible.
5. Given a symlink, path escape, FIFO or device as output, the runner exits `2`
   without writing a report.
6. Given runs outside `[3, 100]`, the runner exits `2`.
7. Given a parity mismatch, the report cannot claim `MATCH` and the runner
   exits `2`.
8. Given timing samples `[1, 2, 3, 4, 100]`, nearest-rank p50/p95/p99 are
   `3/100/100`.
9. Given two executions over identical fixtures, semantic report fields match;
   timing values may differ.
10. Given the final candidate, pre/post reports satisfy the GO rule or the hook
    change is absent with explicit `NO_GO` evidence.
11. Given exact F5A changes, F1–F4 SAM/trace, security hooks, confidentiality
    scan and local CI remain green.

## 8. Files in scope after approval

| Path | Change |
|---|---|
| `.opencode/hooks/validate-bash-global.sh` | Add semantics-preserving relevance fast exit only after characterization |
| `scripts/se397-f5-hot-path-bench.sh` | Add controlled parity/performance runner |
| `tests/fixtures/se397-f5/**` | Add synthetic safe/blocked tool-input corpus |
| `tests/test-se397-f5-hot-path.bats` | Add characterization, safety and runner tests |
| `docs/specs/SE-397-f5a-hot-path-relevance.spec.md` | Append approval, measurement and implementation evidence |
| `docs/specs/SE-397-f4-operational-trace.spec.md` | Append F5A handoff after implementation |
| `docs/propuestas/planning-state.json` | Keep SE-397 `IMPLEMENTING`; record F5A evidence |
| `docs/propuestas/LOG.md` | Append F5A lifecycle entries |
| `docs/ROADMAP.md` | Record F4 merged and F5A state |
| `CHANGELOG.d/se397-f5a-hot-path.md` | Add implementation fragment only for GO or report-only runner |
| `.scm/INDEX.scm`, `.scm/resources.json`, `.scm/registry.json`, `.scm/categories/*.scm` | Deterministic refresh for the new runner |
| `.scm/sam.json`, `.scm/views/*.json`, `.scm/reports/*.json` | Deterministic provenance refresh after commits |
| `.confidentiality-signature` | Final isolated PR-signing commit only |

No hook registration, settings, routing table, dispatcher, timeout, policy,
authority, bwrap, MCP, context assembly, receipt or telemetry schema change is
in scope. Additional paths require append-only revision and fresh approval.

## 9. Validation commands

```bash
bats tests/test-se397-f5-hot-path.bats
bats tests/test-validate-bash-global.bats
python3 -m unittest tests/test_sam_trace.py tests/test_sam.py -v
bats tests/test-se397-sam.bats
python3 scripts/sam.py check
python3 scripts/generate-capability-map.py --check
bash scripts/confidentiality-scan.sh --staged
bash scripts/spec-opencode-plan-audit.sh
bash scripts/roadmap.sh validate
bash scripts/validate-ci-local.sh
```

## 10. Rollback

Revert the F5A implementation commits. This removes the benchmark runner and
relevance fast exit, restoring the exact pre-F5 hook path. Generated SAM/SCM
artifacts are regenerated from the reverted content. Reports under
`output/se397-f5/` are non-authoritative and may be deleted independently.

## 11. Effort and implementation state

| Dimension | Estimate |
|---|---|
| Agent effort | 4–6 hours |
| Human equivalent | 2–3 days |
| Human review | 60–90 minutes |
| Context risk | medium |
| Agent capable | yes, serial TDD |
| Fallback | retain report-only runner and record NO_GO |

Implementation state: `MERGED_NOT_OPERATIONALLY_GRADUATED`.

## 12. Acceptance checklist

- [x] Operator explicitly approved the exact committed F5A revision.
- [x] Characterization exists before the hook optimization.
- [x] Every prior block remains a block with the same observable reason.
- [x] Irrelevant commands prove the fast path without policy setup.
- [x] Pre/post 30-run evidence satisfies GO or records NO_GO.
- [x] No new false allow, authority escalation or security regression exists.
- [x] SAM/SCM and F1–F4 regressions remain fresh and green.
- [x] SE-397 remains `IMPLEMENTING`; remaining F5 work and F6–F10 stay pending.
- [ ] Human code review occurs before merge.

## 13. Deferred F5 work

Session startup, broader hook fan-out, subprocess consolidation, bwrap/E2BIG,
MCP startup and context amplification require separate measured slices. F5A
does not claim Hot Path Excellence complete.

## OpenCode Implementation Plan

### Bindings touched

| Component | Claude Code | OpenCode v1.14 |
|---|---|---|
| Bash validation hook | Shared registered script | Shared wrapper/plugin target |
| Benchmark runner | Direct local invocation | Direct local invocation |
| Hook routing/settings | Unchanged | Unchanged |

### Verification protocol

- [x] The same fixture corpus produces semantic parity in both frontend-neutral invocations.
- [x] No settings, plugin registration or routing table changes are introduced.
- [x] Native frontend wall time is not inferred from the local runner.

### Portability classification

- [x] **DUAL_BINDING**: both frontends rely on the same validator semantics.
- [ ] **PURE_BASH**
- [ ] **SINGLE_BINDING_DEFERRED**
- [ ] **CLAUDE_CODE_ONLY**

## 14. Approval record — append only

- Approved revision: `0024781c`.
- Operator approval received on 2026-09-19: “Apruebo implementar SE-397 F5A
  revisión 0024781c”.
- Approval covers the files, GO/NO_GO thresholds and authority boundary in
  this contract. It does not approve merge, publication or deferred F5 work.
- Implementation state: `APPROVED_CHARACTERIZATION_IN_PROGRESS`.

## 15. Implementation and verification evidence — append only

- Characterization commit: `1d85f4bb`; optimization commit: `b3a97fd3`.
- The registered `.opencode/hooks/validate-bash-global.sh` path resolves through
  the repository symlink `.opencode/hooks -> ../.claude/hooks`; the tracked
  target changed is `.claude/hooks/validate-bash-global.sh`, not an additional
  hook or binding.
- The immutable oracle covers 13 observable classes. Pre and post reports both
  record `MATCH` for 13/13 cases with identical status and normalized stderr.
- Thirty-run controlled evidence over 300 safe samples measured p50 `49 -> 6`
  ms (87.76% improvement) and p95 `50 -> 7` ms (no regression). This is local
  corpus evidence only, not a production or native-frontend SLO.
- The generic hook benchmark sends empty stdin, which intentionally retains the
  full path; its timing is not evidence for or against the safe-command exit.
- The fast exit applies only to non-empty string commands without a closed
  relevance token. Malformed, empty, non-string, relevant and legacy embedded
  regex candidates retain the full environment/profile path.
- 26/26 F5A plus legacy Bash-validator BATS, 38/38 F1–F4 unit tests and 9/9
  SAM BATS pass. Local CI reports 6 passed, 0 failed and 2 advisory warnings.
- Capability Map and SAM regenerate deterministically to 1467 resources and
  2966 nodes. Settings, routing, rule regexes, timeouts and authority are
  unchanged.
- GO decision: accepted. Implementation state:
  `IMPLEMENTED_PENDING_HUMAN_REVIEW`; merge and publication remain excluded.
- PR #1128 merged as `ba6fc121a47b0338481779842046458865153b6c` on
  2026-09-20 with all reported CI checks green. GitHub records no formal review;
  therefore the unchecked human-review criterion above remains unresolved and
  this merge is not evidence of operational graduation.
