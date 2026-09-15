---
id: SE-397-F2
parent: SE-397
status: APPROVED
priority: P0
developer_type: agent-single
created: 2026-09-14
risk: L2
type: architecture-runtime-authority-baseline

depends_on:

  - SE-397-F1
  - SE-390
  - SE-393
  - SE-396

related_specs:

  - SE-037
  - SE-388
  - SE-394
  - SE-398
  - SE-399
  - SE-400

execution_scope: READ_ONLY_DECLARED_RUNTIME_AUTHORITY

---

# SE-397 F2 — Runtime & Authority Model

## Approval gate

This delta spec is the executable F2 phase contract. Parent approval authorizes
F2 only subject to its phase gate; it does not approve an unspecified design.
No F2 tests, production code, declarations or generated artifacts may be added
until the operator explicitly approves the exact committed revision of this
document.

Because F2 models authority and failure paths, a security review is mandatory
after approval and before the TDD red gate. A finding that could create a false
allow, imply enforcement, or misstate human authority blocks implementation and
requires an append-only spec revision plus fresh approval.

## 1. Context and objective

F1 established a deterministic, versioned, read-only SAM with declared and
discovered provenance. It deliberately left runtime architecture and authority
paths unknown. F2 adds a conservative declared model for the six parent golden
flows: `READ`, `EDIT`, `WRITE`, `BASH`, `MCP`, and `EXTERNAL_EFFECT`.

F2 represents effects, risk classification, execution authority, human gates
and failure/degradation states as referenced architectural facts. It does not
observe executions, decide permissions, enforce policy, issue approvals,
generate receipts, inspect secrets, or claim frontend/runtime support.

F2 satisfies the baseline portions of parent AC09, AC10, AC12, AC13, AC17,
AC34, AC36–AC40. Evidence View (AC11), drift/impact (AC15–AC16), diagrams
(AC18), operational corpus/trace (AC19–AC29), complexity (AC30–AC32), and
claim/evidence consistency (AC33/AC35) remain pending.

## 2. Dependency disposition

| Dependency | F2 use | Boundary |
|---|---|---|
| SE-397 F1 | Existing SAM, validation, provenance and query contract | Extend; never create a parallel model |
| `scripts/dual-cli/autonomy.py` | Declared L0–L2 execution ceiling, explicit human gates and unknown fail-safe | Reference only; SAM does not call `decide` |
| `scripts/dual-cli/contracts.py` | Runtime states, human decision authority and external-effect intent vocabulary | Reference only; schema validation is not operational evidence |
| `scripts/dual-cli/runtime.py` | Fail-closed runtime and explicit unimplemented/uncertified gaps | Reference only; experimental runtime remains uncertified |
| `laws/human-control.md` | Human authority invariant | Canonical authority remains outside SAM |
| `docs/rules/domain/autonomous-safety.md` | Cross-frontend autonomy boundary | Reference only; no frontend support claim |
| `contracts/capabilities/*.yaml` | Existing effect/human-gate declarations | Representative source references only; no YAML ingestion in F2 |
| SE-396 | Integrity and effect safety constraints | Hard safety dependency; F2 cannot graduate its runtime evidence |

Missing, malformed, stale or out-of-root inputs fail closed. F2 never fills a
gap with a permissive default. The known mismatch that abstract `WRITE`,
`BASH`, and `MCP` do not map to one invariant executable action remains
`DYNAMIC/POLICY_DEPENDENT`, not `L0–L2 PROCEED`.

## 3. Technical contract

### 3.1 Schema evolution

SAM model and generated views advance from `schema_version: 1` to
`schema_version: 2`. This is an intentional closed-schema break because F2
adds node types and relations. F1 declarations remain independently versioned
at declaration schema `1`.

New allowed node types are exactly:

```text
FLOW EFFECT RISK AUTHORITY HUMAN_GATE FAILURE_STATE
```

F1 node types remain allowed. New allowed relations are exactly:

```text
HAS_EFFECT HAS_RISK HAS_EXECUTION_AUTHORITY REQUIRES_HUMAN GATES DEGRADES_TO
```

F1 relations remain allowed. `ALLOWS`, `DENIES`, `VERIFIES`, `OBSERVES`,
`GRANTS_AUTHORITY`, and every unspecified type/relation remain forbidden.
Source kinds remain exactly `DECLARED` and `DISCOVERED`; F2 cannot emit
`OBSERVED`, `INFERRED`, or any `VERIFIED_*` value.

The top-level model fields and record shapes remain exactly those of F1. The
model revision remains sha256 over canonical `inputs`, `nodes`, `edges`, and
`known_unknowns`. No timestamp, absolute path or machine value enters SAM.

### 3.2 Runtime declaration input

Create `.scm/sam-runtime-declarations.json` with exactly:

```json
{
  "schema_version": 1,
  "golden_flows": [],
  "nodes": [],
  "edges": []
}
```

`golden_flows` is a sorted, duplicate-free list and MUST equal exactly:

```text
flow:bash
flow:edit
flow:external-effect
flow:mcp
flow:read
flow:write
```

Node and edge declaration fields remain exactly the F1 shapes. Source paths
retain all F1 path constraints. Runtime declarations may use all F1/F2 types
and relations but MUST NOT redefine an F1 declared or discovered node ID.

For every golden flow the declaration validator requires:

- exactly one outgoing `HAS_EFFECT` edge to an `EFFECT` node;
- exactly one outgoing `HAS_RISK` edge to a `RISK` node;
- exactly one outgoing `HAS_EXECUTION_AUTHORITY` edge to an `AUTHORITY` node;
- exactly one incoming `GATES` edge from a `HUMAN_GATE` node;
- at least one outgoing `DEGRADES_TO` edge to a `FAILURE_STATE` node.

`flow:external-effect` additionally requires exactly one outgoing
`REQUIRES_HUMAN` edge to `authority:human-decision`. The other flows MUST NOT
use `REQUIRES_HUMAN` to claim a universal human gate; their gate disposition
is represented explicitly by the selected `HUMAN_GATE` node.

### 3.3 Closed golden-flow matrix

The initial runtime declarations encode exactly this conservative matrix:

| Flow | Effect node | Risk node | Gate node | Failure state |
|---|---|---|---|---|
| `flow:read` | `effect:local-read` | `risk:L0` | `human-gate:not-required-within-approved-scope` | `failure:blocked` |
| `flow:edit` | `effect:workspace-mutation` | `risk:L1` | `human-gate:not-required-within-approved-scope` | `failure:needs-human` |
| `flow:write` | `effect:workspace-mutation` | `risk:context-dependent` | `human-gate:policy-dependent` | `failure:needs-human` |
| `flow:bash` | `effect:context-dependent` | `risk:context-dependent` | `human-gate:policy-dependent` | `failure:unknown-effect` |
| `flow:mcp` | `effect:context-dependent` | `risk:context-dependent` | `human-gate:policy-dependent` | `failure:unavailable` |
| `flow:external-effect` | `effect:external` | `risk:human-review-required` | `human-gate:required` | `failure:unknown-effect` |

All six flows point via `HAS_EXECUTION_AUTHORITY` to
`authority:delegated-execution-only`. This records that execution may be
delegated but decision authority is not. `flow:external-effect` also points via
`REQUIRES_HUMAN` to `authority:human-decision`.

The qualified `not-required-within-approved-scope` node MUST reference both
the autonomy policy implementation and its canonical rule. It never means
unscoped, irreversible, external, above-L2, secret, product or architecture
choices can proceed without a human.

The runtime manifest contains exactly these 23 nodes. Labels and sorted
`source_paths` are contractual:

| ID | Type | Label | `source_paths` |
|---|---|---|---|
| `flow:read` | FLOW | `READ` | `docs/specs/SE-397-savia-architectural-self-knowledge.spec.md`, `scripts/dual-cli/autonomy.py` |
| `flow:edit` | FLOW | `EDIT` | `docs/specs/SE-397-savia-architectural-self-knowledge.spec.md`, `scripts/dual-cli/autonomy.py` |
| `flow:write` | FLOW | `WRITE` | `docs/rules/domain/autonomous-safety.md`, `docs/specs/SE-397-savia-architectural-self-knowledge.spec.md`, `scripts/dual-cli/autonomy.py` |
| `flow:bash` | FLOW | `BASH` | `docs/rules/domain/autonomous-safety.md`, `docs/specs/SE-397-savia-architectural-self-knowledge.spec.md`, `scripts/dual-cli/autonomy.py` |
| `flow:mcp` | FLOW | `MCP` | `docs/rules/domain/autonomous-safety.md`, `docs/specs/SE-397-savia-architectural-self-knowledge.spec.md`, `scripts/dual-cli/contracts.py` |
| `flow:external-effect` | FLOW | `EXTERNAL_EFFECT` | `docs/specs/SE-397-savia-architectural-self-knowledge.spec.md`, `laws/human-control.md`, `scripts/dual-cli/autonomy.py` |
| `effect:local-read` | EFFECT | `Local read` | `scripts/dual-cli/autonomy.py` |
| `effect:workspace-mutation` | EFFECT | `Workspace mutation` | `docs/rules/domain/autonomous-safety.md`, `scripts/dual-cli/autonomy.py` |
| `effect:context-dependent` | EFFECT | `Context-dependent effect` | `docs/rules/domain/autonomous-safety.md`, `docs/specs/SE-397-savia-architectural-self-knowledge.spec.md` |
| `effect:external` | EFFECT | `External effect` | `laws/human-control.md`, `scripts/dual-cli/autonomy.py` |
| `risk:L0` | RISK | `L0` | `scripts/dual-cli/autonomy.py` |
| `risk:L1` | RISK | `L1` | `scripts/dual-cli/autonomy.py` |
| `risk:context-dependent` | RISK | `Context-dependent risk` | `docs/rules/domain/autonomous-safety.md`, `scripts/dual-cli/autonomy.py` |
| `risk:human-review-required` | RISK | `Human review required` | `laws/human-control.md`, `scripts/dual-cli/autonomy.py` |
| `authority:delegated-execution-only` | AUTHORITY | `Delegated execution only` | `docs/rules/domain/autonomous-safety.md`, `scripts/dual-cli/autonomy.py` |
| `authority:human-decision` | AUTHORITY | `Human decision authority` | `laws/human-control.md`, `scripts/dual-cli/autonomy.py` |
| `human-gate:not-required-within-approved-scope` | HUMAN_GATE | `Not required within approved L0-L2 scope` | `docs/rules/domain/autonomous-safety.md`, `scripts/dual-cli/autonomy.py` |
| `human-gate:policy-dependent` | HUMAN_GATE | `Policy dependent` | `docs/rules/domain/autonomous-safety.md`, `scripts/dual-cli/autonomy.py` |
| `human-gate:required` | HUMAN_GATE | `Human gate required` | `laws/human-control.md`, `scripts/dual-cli/autonomy.py` |
| `failure:blocked` | FAILURE_STATE | `Blocked` | `scripts/dual-cli/contracts.py`, `scripts/dual-cli/runtime.py` |
| `failure:needs-human` | FAILURE_STATE | `Needs human` | `scripts/dual-cli/autonomy.py`, `scripts/dual-cli/contracts.py` |
| `failure:unknown-effect` | FAILURE_STATE | `Unknown effect` | `docs/rules/domain/autonomous-safety.md`, `scripts/dual-cli/contracts.py` |
| `failure:unavailable` | FAILURE_STATE | `Unavailable` | `scripts/dual-cli/runtime.py` |

The manifest contains exactly the 30 classification edges implied by the five
matrix relationships for each of six flows, plus the one external-effect
`REQUIRES_HUMAN` edge. For every edge, `source_paths` MUST equal the sorted,
duplicate-free union of its source-node and target-node `source_paths`. Extra
runtime edges, even with an allowed relation, fail as
`INVALID_RUNTIME_DECLARATION`. This makes both topology and provenance
deterministic without copying source content.

### 3.4 Generated views

F2 adds exactly three deterministic files using the unchanged closed view
shape (`schema_version`, `view`, `model_revision`, `node_ids`, `edge_ids`,
`limitations`):

- `.scm/views/runtime.json`: FLOW, EFFECT, RISK, AUTHORITY, HUMAN_GATE and
  FAILURE_STATE nodes plus edges whose endpoints are selected;

- `.scm/views/authority.json`: FLOW, AUTHORITY, HUMAN_GATE and POLICY nodes;

- `.scm/views/failure.json`: FLOW and FAILURE_STATE nodes.

Their `limitations` value is exactly sorted as:

```json
["DECLARED_NOT_OBSERVED", "GENERATED_FROM_SAM", "REPORT_ONLY"]
```

F1 views remain generated and report-only. All six views use schema version 2
and the same model revision. No view contains copied policy text, decisions,
receipts, prompts, telemetry or runtime observations.

### 3.5 CLI behavior

The F1 commands and exit codes remain unchanged. No new executable authority
command is introduced. Querying `flow:<name>` through the existing
`query --node` interface returns the flow node and its direct classification
edges. Unknown flows return the existing explicit `UNKNOWN` response with exit
`0`; malformed or stale model input returns exit `2`.

Runtime declaration violations raise only existing F1 error codes plus exactly:

```text
INVALID_RUNTIME_DECLARATION
INCOMPLETE_FLOW
```

An unsupported field/type/relation keeps the corresponding F1 error. Duplicate
IDs/edges across the two manifests fail with `DUPLICATE_ID`/`DUPLICATE_EDGE`.

### 3.6 Known unknowns after F2

Replace `RUNTIME_ARCHITECTURE_NOT_MODELLED` with these sorted entries:

```text
AUTHORITY_PATHS_DECLARED_NOT_ENFORCED
CAPABILITY_DEPENDENCIES_INCOMPLETE
CAPABILITY_TEST_LINKS_INCOMPLETE
FAILURE_PATHS_INCOMPLETE
OPERATIONAL_EVIDENCE_NOT_MODELLED
RUNTIME_ARCHITECTURE_DECLARED_NOT_OBSERVED
```

Absence of the old marker is valid only when all runtime declaration invariants
and all three F2 views validate.

## 4. Business and safety rules

| ID | Rule | Required evidence/failure |
|---|---|---|
| SAM-F2-01 | SAM describes authority; it never grants or evaluates it | Forbidden grant/allow/deny types or relations rejected |
| SAM-F2-02 | External effects always retain explicit human decision authority | Missing/wrong `REQUIRES_HUMAN` → `INCOMPLETE_FLOW` |
| SAM-F2-03 | Abstract/dynamic flows never default to low risk or no gate | Exact matrix validation → `INCOMPLETE_FLOW` |
| SAM-F2-04 | Declared runtime is not observed runtime | Only DECLARED/DISCOVERED; limitations include `DECLARED_NOT_OBSERVED` |
| SAM-F2-05 | Every golden flow is fully classified | Cardinality and endpoint-type checks |
| SAM-F2-06 | Missing authority/security input fails closed | `MISSING_INPUT` / exit `2`, no partial writes |
| SAM-F2-07 | F1 capability registry remains authoritative and byte-stable | Existing SCM freshness/preservation tests pass |
| SAM-F2-08 | Model v1 cannot be mistaken for complete F2 | v1 generated model rejected after upgrade |
| SAM-F2-09 | No command reads external state or writes outside generated SAM paths | Mutation-boundary test |
| SAM-F2-10 | F2 creates zero new false allows or authority escalation | Security review + adversarial tests |

## 5. Test scenarios — tests before production code

1. Given the upgraded fixture, generation produces a valid schema-v2 model and
   six byte-identical views across repeated runs.

2. Given the real repository, every golden flow has exactly one effect, risk,
   execution-authority and gate classification plus at least one failure edge.

3. Given `flow:external-effect`, query returns both delegated execution and the
   required human-decision edge; removing or redirecting the human edge fails
   with `INCOMPLETE_FLOW` and writes no output.

4. Given WRITE, BASH or MCP, replacing context-dependent/policy-dependent nodes
   with L0/L1 or no-human-required classification fails closed.

5. Given a missing, absolute, `..` or escaping-symlink runtime source, generate
   returns `2` and leaves every committed SAM/view byte unchanged.

6. Given a duplicate ID/edge across F1 and F2 declarations, generation raises
   the exact duplicate error.

7. Given `OBSERVED`, `INFERRED`, `VERIFIED_STATIC`, `ALLOWS`, `DENIES`, or an
   unknown field in model/declarations, validation rejects it.

8. Given a committed schema-v1 SAM, `check`/`query` reject it as stale/invalid;
   generation produces schema v2 without mutating F1 source declarations.

9. Given runtime/authority/failure views, every referenced ID exists in SAM,
   every revision matches, and every F2 view has all three limitations.

10. Given the real repo before/after generation, every pre-existing `.scm`
    capability artifact remains byte-identical and `SCM: FRESH`.

11. Given the existing query command and `flow:read`, response is `FOUND` with
    only direct incident edges; an unknown flow returns explicit `UNKNOWN`.

12. Given exact F2 changes, security review and adversarial tests find zero
    executable policy calls, external reads, secret reads, authority writes or
    new allow decisions.

## 6. Files in scope after approval

| Path | Change |
|---|---|
| `.scm/sam-runtime-declarations.json` | Create closed reference-only F2 input |
| `.scm/sam.schema.json` | Upgrade generated model schema to v2 |
| `.scm/sam.json` | Regenerate deterministic v2 model |
| `.scm/views/{foundation,capabilities,structural}.json` | Regenerate existing views at v2 |
| `.scm/views/{runtime,authority,failure}.json` | Create F2 report-only views |
| `scripts/sam_model.py` | Extend closed types, loader, flow invariants and views |
| `scripts/sam.py` | Preserve CLI contract; only version/error plumbing if required |
| `tests/fixtures/sam/**` | Extend isolated fixture with F2 declarations |
| `tests/test_sam.py` | Add unit/adversarial F2 tests before production changes |
| `tests/test-se397-sam.bats` | Add real-repository F2 acceptance tests first |
| `docs/specs/SE-397-f2-runtime-authority-model.spec.md` | Append approval/security/implementation evidence |
| `docs/specs/SE-397-f1-minimal-sam.spec.md` | Append F2 handoff after implementation |
| `docs/propuestas/planning-state.json` | Keep SE-397 `IMPLEMENTING`; add F2 evidence only |
| `docs/propuestas/LOG.md` | Append F2 review entry |
| `docs/ROADMAP.md` | Mark F2 pending review; never mark SE-397 complete |
| `CHANGELOG.md` | Add F2 unreleased entry if required by current policy |
| `.confidentiality-signature` | Final isolated PR-signing commit only |

No other path is authorized. If implementation requires another path, append a
contract revision, show the exact change and request fresh approval before
touching it.

## 7. Validation commands

```bash
python3 -m unittest tests/test_sam.py -v
bats tests/test-se397-sam.bats
python3 scripts/generate-capability-map.py --check
python3 scripts/sam.py check
python3 scripts/sam.py query --node flow:external-effect
bash scripts/roadmap.sh validate
bash scripts/validate-ci-local.sh
```

Before the implementation commit: run the mandatory authority/security review,
observe the F2 tests red, scan staged content for secrets and verify scope. Use
the F1 two-commit provenance protocol: commit schema/declarations/code/tests
before regenerating model/views, then commit derived artifacts and evidence.

## 8. Rollback

Revert the F2 commits. This removes the runtime declaration and three F2 views,
restores schema/model/view version 1 and returns F1 known unknowns. Canonical
policy, dual-cli, capability contracts, receipts and enforcement are untouched;
no migration, external recovery or authority rollback is required.

## 9. Effort and implementation state

| Dimension | Estimate |
|---|---|
| Agent effort | 5–7 hours |
| Human equivalent | 3–4 days |
| Human review | 60–90 minutes |
| Context risk | high |
| Agent capable | yes, serial implementation because schema/model/tests overlap |
| Fallback | human resumes from approved contract and red tests |

Implementation state: `APPROVED_PENDING_TDD_RED`.

## 10. Acceptance checklist

- [ ] Operator explicitly approved this exact committed F2 revision.
- [ ] Mandatory authority/security review has no blocking finding.
- [ ] Every F2 production behavior was preceded by an observed red test.
- [ ] All six golden flows satisfy the closed matrix and cardinality rules.
- [ ] External effects retain explicit human decision authority.
- [ ] Dynamic flows never silently become low-risk or ungated.
- [ ] All F2 views are derived, report-only and declared-not-observed.
- [ ] Existing capability registry and authority sources remain unchanged.
- [ ] All specified tests and local CI pass.
- [ ] SE-397 remains `IMPLEMENTING`; F3–F10 remain pending.
- [ ] Human code review occurs before merge.

## 11. Open decisions

None inside this minimal F2 contract. Runtime observation, receipts, evidence
graduation, enforcement, per-frontend support, path ordering beyond direct
classification, automatic YAML ingestion, drift severity and MCP/API exposure
belong to later phases and require their own phase gate.

## 12. Approval and authority/security review evidence

### 12.1 Operator approval

- Approved revision: `cf3ffadc`.
- Approval: operator response `si` on 2026-09-14, directly following the exact
  revision and F2-only scope request.
- Authorized scope: the tests, implementation, generated artifacts and evidence
  enumerated in section 6; no F3+ work, publication, push or merge.

### 12.2 Mandatory pre-implementation review

Verdict: `APPROVED_WITH_CONSTRAINTS`.

The review compared this contract with `scripts/dual-cli/autonomy.py`,
`scripts/dual-cli/contracts.py`, `scripts/dual-cli/runtime.py`,
`laws/human-control.md` and
`docs/rules/domain/autonomous-safety.md`. The referenced files exist, are
repository-relative N1 material, and the contract introduces no secret, PII,
internal-infrastructure or absolute-path disclosure.

No blocking authority escalation was found. The implementation remains approved
only while all of these constraints hold:

- SAM remains read-only, report-only and never calls policy/authority decision
  code or emits an operational receipt.
- Every flow points to delegated execution only; the external-effect flow also
  retains explicit human decision authority.
- Dynamic WRITE, BASH and MCP classifications remain context/policy dependent
  and cannot acquire a permissive default.
- `ALLOWS`, `DENIES`, `VERIFIES`, `OBSERVES` and `GRANTS_AUTHORITY` remain
  rejected vocabulary.
- Missing, malformed or stale authority inputs fail closed without partial
  generated writes.

The security review authorizes entry into the TDD red gate; it does not
authorize publication or any external effect.

## 13. Implementation evidence — append only

- Implementation commit: `799485fc` (schema, declaration, code and tests before
  generated artifacts).
- Acceptance assertion correction: `144696d2` aligns BATS with the CLI's valid
  spaced JSON serialization; it changes no production behavior.
- Fail-closed hardening: `b491a7f9` prevents a recomputed model revision from
  silently deleting contractual known unknowns; its focused test was observed
  red before the validator change.
- Red gate observed before production changes: 8/16 unit tests failed on the
  absent schema-v2/runtime behavior while all remaining F1 tests passed; 5/6
  BATS scenarios failed on the absent manifest, views, freshness and query.
- Green unit gate: 17/17 tests pass, including authority removal, permissive
  dynamic-flow substitutions, cross-manifest duplicates, path escape, stale v1
  model and forbidden relation cases.
- Generated projection: 2,962 nodes, 1,504 edges and 1,479 source inputs;
  deterministic revision `50b9e717bf4e` (short form).
- Runtime closure: exactly 23 declared runtime nodes, 31 classification edges,
  six golden flows and three new declared-not-observed/report-only views.
- Authority result: every flow retains delegated execution only;
  `flow:external-effect` additionally requires `authority:human-decision`.
- Validation result: 6/6 BATS, capability freshness, SAM freshness, Draft
  2020-12 JSON Schema, planning/roadmap and local CI pass. Local CI reports two
  advisory warnings (broad secret-pattern heuristic and coherence advisory);
  staged gitleaks, confidentiality and sovereignty gates remain clean.
- Scope result: no policy call, enforcement, receipt, telemetry, secret read,
  external read/write or support claim was introduced. F3–F10 remain pending.
- F2 implementation state: `IMPLEMENTED_PENDING_HUMAN_REVIEW`.

## 14. Post-merge provenance repair — append only

- Review date: 2026-09-16.
- Finding: after the F2 squash merge, `scripts/sam.py check` reported
  `STALE (.scm/sam.json)` because Git rewrote the commit IDs for unchanged
  source paths. The input SHA-256 values and source bytes were unchanged; the
  failure was provenance instability, not model drift.
- Correction: when an existing generated input has the same current SHA-256,
  generation preserves its recorded `source_commit` only when that commit is
  also resolvable with the same content (or the historical commit is no longer
  available after a rewrite); changed content still receives the current
  repository commit. This keeps provenance descriptive while making the
  projection stable across squash/rebase history rewrites.
- Regression evidence: `tests/test_sam.py` now reproduces an implementation
  commit followed by `git commit --amend` and proves `check` remains fresh.
- Validation: 18/18 unit tests, 6/6 F2 BATS, `SCM: FRESH (1465 resources)` and
  `SAM: FRESH (2962 nodes)`.
- Scope: no authority, policy, runtime, registry or generated topology changed;
  F3 remains pending implementation and review.
