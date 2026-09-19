---
id: SE-397-F4
parent: SE-397
status: APPROVED
priority: P0
developer_type: agent-single
created: 2026-09-16
author: Savia
risk: L2
type: operational-observability

depends_on:

  - SE-397-F3
  - SE-037
  - SE-313
  - SE-393
  - SE-394
  - SE-396

execution_scope: LOCAL_REPORT_ONLY_OPERATIONAL_TRACE

---

# SE-397 F4 — Operational Trace

## Approval gate

This document is a proposed executable contract. Drafting and validating it
does not approve implementation. Tests, runtime instrumentation, schemas,
generated observations and lifecycle state MUST NOT change until both gates
occur:

1. the operator explicitly accepts or records concerns for merged F3; and
2. the operator explicitly approves the exact committed revision of this F4
   document after reviewing it.

A request to continue, an answer to a design question, parent authorization or
approval of another phase is not approval of this revision. Any contract change
after feedback is append-only and requires fresh approval.

## 1. Problem and objective

F1-F3 created a deterministic, declared/discovered, report-only architecture
model. Savia also has local telemetry, W3C trace identifiers, hook latency
benchmarks, dual-cli execution value objects and receipts. Those assets are
fragmented and do not prove which SAM flow a concrete operation traversed.

F4 adds a separate observation layer that can answer, for a bounded local
operation:

- which committed SAM revision and declared `flow:*` it references;

- which ordered architecture nodes were actually reported by its segments;

- what duration each reported segment and the whole operation had;

- whether decision, execution and evidence phases were observed, absent or
  inconsistent;

- which parts remain `UNKNOWN` rather than being inferred.

F4 also reconciles SE-037 by measuring one controlled end-to-end local corpus
in addition to its per-hook benchmarks. It satisfies the baseline portions of
parent AC20 and AC21. It does not optimize the hot path, instrument every
frontend, certify receipts, ingest prompts, export telemetry, graduate support,
or make trace presence an authorization condition. Those boundaries remain
F5-F10 work.

## 2. Existing assets and disposition

| Asset | F4 use | Limitation preserved |
|---|---|---|
| `.scm/sam.json` | Validated architecture and model revision | Architecture remains declared/discovered, not observational |
| `.scm/sam-runtime-declarations.json` | Closed six-flow vocabulary | A trace cannot create a flow or authority edge |
| `config/telemetry-schema.json` | Existing `savia.event/1.0` envelope | Legacy events without F4 fields remain valid but unlinked |
| `scripts/otel-emit.sh` | Local append-only event transport | Transport is not validation, evidence or authority |
| `scripts/savia-trace.sh` | W3C trace/span propagation | Trace identifiers alone do not prove causal completeness |
| SE-037 benchmark tools | Per-hook timing and actual hook execution | Per-hook latency is not end-to-end operation latency |
| dual-cli schema-v2 receipts | Optional correlated decision/execution facts | Receipt input is validated, never trusted by presence |

F4 MUST reuse these assets. It MUST NOT create another telemetry transport,
receipt system, policy engine, runtime supervisor or authoritative database.

## 3. Architecture boundary

SAM remains schema version 2. F4 adds no SAM node, relation, source kind,
authority, risk or human-gate semantics. Observations live outside `.scm` and
reference a validated committed SAM by its 64-hex `model_revision`.

```text
SAM (committed, deterministic, descriptive)
                  ^
                  | model_revision + node IDs
                  |
Operational Trace (local, variable, observational, non-authoritative)
```

No observation can add, remove or rewrite an architecture path. Every reported
node ID MUST already exist in the referenced SAM. Unknown, stale or malformed
references fail validation; absent segments remain explicit gaps.

## 4. Event contract

### 4.1 Envelope extension

Extend `config/telemetry-schema.json` without breaking existing
`savia.event/1.0` producers. Add three event names:

```text
operation.started
operation.segment
operation.completed
```

For these names only, JSON Schema conditionals require this exact F4 payload.
Existing envelope fields `schema`, `ts`, `event`, `trace_id`, `span_id` and
optional `parent_span_id` remain unchanged.

| Field | Type | Rules |
|---|---|---|
| `operation_id` | string | 32 lowercase hex; opaque and local |
| `request_id` | string or null | Optional dual-cli correlation identifier |
| `flow_id` | string | one of the six committed F2 `flow:*` IDs |
| `model_revision` | string | 64 lowercase hex equal to committed SAM |
| `frontend_id` | string | identifier, maximum 64 characters |
| `phase` | string | closed enum below; segment only |
| `architecture_node_id` | string | existing SAM node; segment only |
| `sequence` | integer | zero for started, 1..N for segments, N+1 for completed |
| `duration_ms` | integer | non-negative; segment/completed only |
| `outcome` | string | `success`, `failure`, `partial`, `blocked`, `unknown` |
| `evidence_ref` | string or null | safe repo-relative/output-relative reference; no content |

The closed phase order is:

```text
INTENT, CONTEXT, ROUTING, GOVERNANCE, EXECUTION, EVIDENCE, RESULT
```

Every F4 event requires operation, nullable request, flow, model and frontend
identity. `operation.started` additionally requires sequence `0` and outcome
`unknown`. `operation.segment` requires phase, architecture node, positive
sequence, duration and optional evidence reference. `operation.completed`
requires the final sequence, total duration and final outcome, with no phase or
architecture node.

Unknown fields are rejected for F4 events even though legacy telemetry events
remain extensible. Prompt text, tool arguments, command bodies, environment
values, absolute paths, usernames, hostnames, secrets and raw outputs are
forbidden.

### 4.2 Emitter behavior

`scripts/otel-emit.sh` remains non-blocking for legacy events. For F4 events it
MUST validate the completed object before append. Invalid F4 input returns `2`,
writes no byte and prints `INVALID_OPERATION_EVENT`. Disk failure remains
non-blocking and returns `0` with no authority effect, preserving the telemetry
contract.

`SAVIA_TELEMETRY_REDACT=1` reduces F4 events to the legacy minimal envelope.
Such events are intentionally unusable for operational reconstruction and are
counted as `REDACTED_UNLINKABLE`, never inferred.

## 5. Operational trace projection

### 5.1 Read-only CLI

Add:

```text
python3 scripts/sam.py trace --events <jsonl> [--receipts <directory>]
python3 scripts/sam.py baseline --events <jsonl> [--receipts <directory>]
```

Both commands are read-only and write canonical JSON to stdout. Input paths
must be explicit regular files/directories within repository root or `output/`;
symlinks, FIFOs, devices, path escape and files over 16 MiB are rejected.
`--receipts` is optional and reads only `*.json` regular files, sorted by path,
with the same size and path rules.

`trace` emits one object:

```json
{
  "schema_version": 1,
  "report": "operational-trace",
  "model_revision": "<64 hex>",
  "summary": {
    "operations": 0,
    "complete": 0,
    "partial": 0,
    "redacted_unlinkable": 0
  },
  "operations": [],
  "limitations": [
    "LOCAL_OBSERVATIONS_ONLY",
    "NO_CAUSAL_INFERENCE",
    "NO_AUTHORITY_EFFECT",
    "PARTIAL_FRONTEND_COVERAGE",
    "SELF_REPORTED_LOCAL_EVENTS"
  ]
}
```

Each operation has exactly:

```json
{
  "operation_id": "<32 hex>",
  "request_id": null,
  "trace_id": "<32 hex>",
  "flow_id": "flow:read",
  "frontend_id": "fixture",
  "status": "COMPLETE",
  "outcome": "success",
  "duration_ms": 0,
  "architecture_path": [],
  "segments": [],
  "receipt_status": "NOT_PROVIDED",
  "gaps": []
}
```

Operations sort by `operation_id`; segments sort by sequence. Architecture path
is the ordered, duplicate-preserving list of segment node IDs. The tool does
not compute missing nodes by graph traversal.

### 5.2 Completeness and failure rules

An operation is `COMPLETE` only when it has exactly one start and completion,
strictly increasing contiguous sequences, one or more segments, matching
operation/request/trace/flow/model/frontend fields, nondecreasing timestamps,
segment durations whose sum does not exceed total duration, and a terminal
outcome other than `unknown`.

Otherwise it is `PARTIAL` with sorted gap codes from this closed set:

```text
MISSING_START
MISSING_COMPLETION
MISSING_SEGMENT
SEQUENCE_GAP
IDENTITY_CONFLICT
TIME_ORDER_CONFLICT
DURATION_CONFLICT
UNKNOWN_ARCHITECTURE_NODE
STALE_MODEL_REVISION
REDACTED_UNLINKABLE
RECEIPT_NOT_FOUND
RECEIPT_INVALID
RECEIPT_CONFLICT
```

Malformed JSON, duplicate JSON keys, invalid F4 event shape, unsafe path or a
line over 1 MiB returns exit `2` with `INVALID_OPERATION_TRACE`; stdout remains
empty. Incomplete but well-formed observations return exit `0` and remain
visible as partial data.

### 5.3 Optional receipt correlation

When `evidence_ref` points to a supplied schema-v2 dual-cli receipt, validate it
with the existing contract. `request_id`, frontend, decision/execution outcome
and model-independent context must not conflict with the operation. Valid
correlation yields `VALID_CORRELATED`; absence yields `NOT_PROVIDED` or
`NOT_FOUND`; malformed/conflicting receipts produce explicit gaps.

Schema-v1 receipts and arbitrary evidence files cannot upgrade receipt status.
F4 does not certify that an effect happened and does not translate receipt
presence into `VERIFIED_OPERATIONAL` or `SUPPORTED`.

## 6. Baseline and SE-037 reconciliation

`baseline` consumes the same validated operations and emits:

```json
{
  "schema_version": 1,
  "report": "operational-baseline",
  "model_revision": "<64 hex>",
  "corpus_revision": "<sha256>",
  "summary": {
    "operations": 0,
    "complete": 0,
    "coverage": "PARTIAL"
  },
  "by_flow": [],
  "by_phase": [],
  "gaps": [],
  "limitations": [
    "CONTROLLED_LOCAL_CORPUS",
    "NO_PRODUCTION_SLO",
    "NO_CROSS_FRONTEND_EQUIVALENCE",
    "REPORT_ONLY"
  ]
}
```

For groups with at least one valid duration, report integer `count`, `min_ms`,
`p50_ms`, `p95_ms`, `p99_ms` and `max_ms` using nearest-rank percentiles.
Groups are sorted by flow/phase ID. No threshold or PASS/FAIL is emitted.

Add a controlled local corpus runner for READ and SAFE_BASH only. It executes
real repository code and registered hook paths against fixture inputs with
network disabled, temporary output paths and no workspace mutation. It emits
F4 events to a caller-provided JSONL path. Tests MUST prove that the measured
command actually ran and that an empty/no-op corpus cannot produce a baseline.

SE-037 remains authority for per-hook latency. F4 adds end-to-end segment and
operation observations; it neither changes the 20 ms critical-hook SLA nor
claims that the controlled corpus represents production latency.

## 7. Privacy, storage and lifecycle

- Live F4 events append only to gitignored `output/telemetry-events.jsonl` or a
  caller-provided path under `output/`.

- One-off baselines belong under `output/se397-f4/`; tests use temporary paths.

- No live trace, baseline, receipt or session identifier is committed.

- Fixtures contain only synthetic IDs, generic frontend names and deterministic
  timestamps.

- Retention and OTLP export remain governed by existing telemetry policy; F4
  enables neither export nor additional retention.

- Parsing is local and deterministic; no network, MCP, model call or secret
  lookup occurs.

## 8. Business and safety rules

| ID | Rule | Required evidence/failure |
|---|---|---|
| SAM-F4-01 | Observation never grants authority | No allow/deny decision or SAM mutation |
| SAM-F4-02 | Architecture and observations remain separate | SAM schema/version unchanged; outputs reference revision |
| SAM-F4-03 | No causal inference from gaps | Missing segments produce explicit gap codes |
| SAM-F4-04 | Only existing nodes form architecture paths | Unknown node is partial/invalid as specified |
| SAM-F4-05 | Redaction wins over completeness | Redacted event remains unlinkable |
| SAM-F4-06 | Invalid input cannot yield a baseline | Exit 2 or zero-operation error; no PASS vocabulary |
| SAM-F4-07 | Receipt presence is not operational proof | Closed correlation statuses and limitations |
| SAM-F4-08 | Baseline cannot become an SLO | Report-only output without thresholds |
| SAM-F4-09 | External effects are excluded from corpus | READ and SAFE_BASH only; network disabled |
| SAM-F4-10 | Telemetry failure cannot alter execution | Existing non-blocking transport semantics preserved |

## 9. Test scenarios — tests before production code

1. Given a complete synthetic READ operation, `trace` returns one complete
   operation with the exact reported architecture path and no inferred node.

2. Given shuffled input lines, canonical output remains byte-identical because
   operation and segment ordering is explicit.

3. Given missing start/completion, sequence gaps or identity conflicts, the
   operation remains visible as `PARTIAL` with exact gap codes.

4. Given malformed JSON, duplicate keys, oversized lines, unsafe paths or an
   unknown F4 field, the command exits `2` and writes no stdout report.

5. Given a stale SAM revision or unknown architecture node, no observation is
   promoted to complete.

6. Given redaction mode, emission writes no F4 payload and reconstruction counts
   the event as unlinkable without exposing identity.

7. Given a valid correlated schema-v2 receipt, receipt status is
   `VALID_CORRELATED`; schema v1, missing and contradictory receipts never
   produce that status.

8. Given durations `[1, 2, 3, 4, 100]`, baseline nearest-rank p50/p95/p99 are
   `3/100/100`; grouping is deterministic.

9. Given zero complete operations, baseline exits `2` with
   `INSUFFICIENT_OPERATIONAL_EVIDENCE` rather than reporting success.

10. Given the controlled READ/SAFE_BASH runner, at least one real command and
    one registered hook path are observed; network and workspace writes remain
    absent.

11. Given the same corpus twice, semantic fields and corpus revision match;
    measured durations may differ and are never committed as golden values.

12. Given exact F4 changes, F1-F3 SAM generation/check, security scan and local
    CI remain green with no authority, effect or export regression.

## 10. Files in scope after approval

| Path | Change |
|---|---|
| `config/telemetry-schema.json` | Add strict conditional F4 event contract |
| `scripts/otel-emit.sh` | Validate F4 events before local append |
| `scripts/sam_trace.py` | Add pure trace validation, projection and baseline builders |
| `scripts/sam.py` | Add read-only `trace` and `baseline` commands |
| `scripts/se397-f4-corpus.sh` | Add isolated READ/SAFE_BASH corpus runner |
| `tests/fixtures/sam/trace/**` | Add synthetic valid/adversarial event and receipt fixtures |
| `tests/test_sam_trace.py` | Add unit and adversarial trace tests first |
| `tests/test-se397-sam.bats` | Add CLI, corpus and F1-F3 regression tests first |
| `docs/specs/SE-397-f4-operational-trace.spec.md` | Append approval/review/implementation evidence |
| `docs/specs/SE-397-f3-architecture-verification.spec.md` | Append F4 handoff only after implementation |
| `docs/propuestas/planning-state.json` | Keep SE-397 `IMPLEMENTING`; record F4 state/evidence |
| `docs/propuestas/LOG.md` | Append F4 lifecycle entry |
| `docs/ROADMAP.md` | Record F4 pending review; never mark SE-397 complete |
| `CHANGELOG.d/se397-f4-operational-trace.md` | Add implementation fragment |
| `.confidentiality-signature` | Final isolated PR-signing commit only |

No settings, hook registration, OTLP endpoint, external integration, SAM
declaration/model/report, policy, authority or receipt writer is in scope.
Additional paths require append-only revision and fresh approval.

## 11. Validation commands

```bash
python3 -m unittest tests/test_sam_trace.py -v
python3 -m unittest tests/test_sam.py -v
bats tests/test-se397-sam.bats
bats tests/test-otel-emit.bats tests/test-savia-trace.bats
python3 scripts/sam.py check
python3 scripts/generate-capability-map.py --check
bash scripts/spec-opencode-plan-audit.sh
bash scripts/roadmap.sh validate
bash scripts/validate-ci-local.sh
```

Before production edits: observe F4 tests red, scan staged content for secrets
and verify exact path scope. Human code review remains mandatory before merge.

## 12. Rollback

Revert F4 implementation commits. This removes F4 event validation, read-only
projection/baseline commands and the controlled corpus runner. Existing legacy
telemetry, W3C propagation, SE-037 benchmarks, dual-cli receipts and F1-F3 SAM
remain unchanged. Local `output/` traces can be deleted independently because
they are non-authoritative and gitignored.

## 13. Effort and implementation state

| Dimension | Estimate |
|---|---|
| Agent effort | 8-12 hours |
| Human equivalent | 4-6 days |
| Human review | 90-120 minutes |
| Context risk | high |
| Agent capable | yes, serial TDD because emitter/parser contracts overlap |
| Fallback | human resumes from approved contract and red tests |

Implementation state: `PROPOSED_PENDING_F3_REVIEW_AND_EXPLICIT_APPROVAL`.

## 14. Acceptance checklist

- [ ] Operator explicitly reviewed merged F3.
- [ ] Operator explicitly approved this exact committed F4 revision.
- [ ] Every F4 production behavior was preceded by an observed red test.
- [ ] SAM schema/version and authority topology remain unchanged.
- [ ] Complete traces contain only reported, existing SAM nodes.
- [ ] Partial/redacted/invalid observations remain explicit.
- [ ] Controlled corpus executes real local paths without external effects.
- [ ] Baseline reports distribution data without PASS/FAIL or SLO claims.
- [ ] Existing telemetry, receipt and F1-F3 regressions pass.
- [ ] SE-397 remains `IMPLEMENTING`; F5-F10 remain pending.
- [ ] Human code review occurs before merge.

## 15. Open decisions

None inside this minimal F4 contract. Instrumenting native frontend calls,
cross-frontend coverage, production SLOs, hot-path optimization, automatic
receipt capture, external effects, richer context metrics and operational
graduation belong to F5-F10 and require independent evidence and approval.

## OpenCode Implementation Plan

### Bindings touched

| Component | Claude Code | OpenCode v1.14 |
|---|---|---|
| Local telemetry transport | Existing `otel-emit.sh` | Same frontend-neutral script when invoked |
| Trace projection | `python3 scripts/sam.py trace` | Same CLI and JSON contract |
| Controlled corpus | Direct local runner | Same runner; no frontend hook assumption |
| Native tool-call instrumentation | Not added | Not added |

### Verification protocol

- [ ] The same fixture corpus and trace CLI pass outside either frontend.

- [ ] Native frontend coverage remains explicitly partial.

- [ ] No frontend settings, plugin or hook-registration change is introduced.

### Portability classification

- [x] **DUAL_BINDING**: core validation/projection is frontend-neutral; native
  coverage is explicitly deferred rather than simulated.

- [ ] **PURE_BASH**

- [ ] **SINGLE_BINDING_DEFERRED**

- [ ] **CLAUDE_CODE_ONLY**

## 16. Approval evidence — append only

### 16.1 Operator approval of revision `823cd67b`

- On 2026-09-19 the operator explicitly stated: “Acepto F3 mergeado y apruebo
  implementar SE-397 F4 revisión 823cd67b”.
- This satisfies both approval gates for the original Section 10 scope.
- Publication, push, merge and any scope beyond that section remain excluded.

## 17. Proposed derived-artifact scope correction — pending approval

Implementation exposed a contradiction in the approved contract. The required
`scripts/se397-f4-corpus.sh` is automatically indexed by the committed
Capability Map, while every committed F4 source changes SAM provenance. The
Section 11 freshness checks therefore cannot pass without regenerating derived
artifacts that Section 10 omitted and then explicitly excluded.

Proposed additional paths, generated only by existing deterministic tools:

- `.scm/INDEX.scm`, `.scm/resources.json`, `.scm/registry.json` and
  `.scm/categories/*.scm` via `generate-capability-map.py`;
- `.scm/sam.json`, `.scm/views/*.json` and `.scm/reports/*.json` via `sam.py
  generate` after the Capability Map is fresh.

This correction does not add declarations, nodes, relations, authority,
policy, observations or manual content to `.scm`; it refreshes provenance and
the generated index only. Regeneration remains blocked until the operator
explicitly approves the exact committed revision containing this appendix.

## 18. Corrected-scope approval and implementation evidence — append only

### 18.1 Operator approval

- The operator explicitly approved revision `0eec646e` on 2026-09-19 for the
  `.scm` paths enumerated in Section 17.
- Publication, push and merge remain excluded; human code review is pending.

### 18.2 TDD and implementation result

- RED evidence included the absent F4 schema, incorrect nullable/hex emitter
  typing, cross-event schema leakage, stale-source trace rejection and absent
  controlled corpus; each behavior was made green as a vertical slice.
- `trace` validates committed SAM structure without conflating observation
  projection with working-tree freshness; `sam.py check` remains the separate
  freshness gate.
- The controlled corpus executes a real SAM READ, the registered
  `validate-bash-global.sh` hook and a fixed SAFE_BASH command with temporary
  outputs and no network-capable or workspace-writing command path.
- Deterministic regeneration added only `se397-f4-corpus` to the Capability
  Map and its capability/component nodes to SAM: 1466 resources, 2964 nodes,
  zero removed nodes and no authority change.

### 18.3 Verification result

- 17/17 F4 unit tests and 21/21 F1–F3 unit tests pass.
- 9/9 SAM BATS and 17/17 telemetry/trace BATS pass.
- `sam.py check`, Capability Map freshness, OpenCode plan audit and roadmap
  validation pass.
- Local CI reports 6 passed, 0 failed and 2 advisory warnings.
- Implementation state: `IMPLEMENTED_PENDING_HUMAN_REVIEW`; F5–F10 remain
  pending and no SLO, support graduation, export or enforcement was added.
