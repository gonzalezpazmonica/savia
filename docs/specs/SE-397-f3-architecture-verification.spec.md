---
id: SE-397-F3
parent: SE-397
status: PROPOSED
priority: P0
developer_type: agent-single
created: 2026-09-15
author: Savia
risk: L2
type: architecture-verification

depends_on:

  - SE-397-F2
  - SE-396

related_specs:

  - SE-037
  - SE-388
  - SE-390
  - SE-393
  - SE-394
  - SE-398
  - SE-399
  - SE-400

execution_scope: READ_ONLY_ARCHITECTURE_VERIFICATION

---

# SE-397 F3 — Architecture Verification

## Approval gate

This document is a proposed executable contract. Drafting and validating the
contract does not approve F3 implementation. Tests, production code, generated
reports and lifecycle updates MUST NOT be changed until both gates occur:

1. the operator explicitly accepts or records concerns for merged F2; and
2. the operator explicitly approves the exact committed revision of this F3
   document after reviewing it.

An answer to a design question, the parent F1–F10 authorization, or a request
to continue work is not approval of this revision. Any contract change after
feedback is append-only and requires fresh approval.

## 1. Problem and objective

F1 created the versioned SAM projection. F2 added declared runtime, authority,
human-gate and failure topology without claiming observation or enforcement.
The model can validate its own closed shape and freshness, but it cannot yet
show where architectural declarations agree with discovered repository facts,
which claims lack evidence, or what model elements a change can affect.

F3 adds three deterministic, report-only verification products derived from a
validated committed SAM:

- architecture drift: declared facts, discovered facts and explicit
  corroboration bindings;
- claim/evidence: statically traceable support paths and explicit gaps;
- impact: bounded graph reachability from declared verification roots.

F3 satisfies the baseline portions of parent AC11, AC15, AC16, AC33 and AC34.
It does not execute runtime discovery, infer semantics from filenames, grade
support, block changes, alter authority, create operational receipts, or
replace code review. Diagrams, operational trace and corpus, performance,
resilience, complexity and semantic substitution remain F4–F10 work.

## 2. Dependency disposition

| Dependency | F3 use | Boundary |
|---|---|---|
| SE-397 F2 | Validated schema-v2 SAM and six report-only views | Consume without changing model schema or F2 declarations |
| `.scm/registry.json` | Existing repository discovery source already projected into SAM | Never reimplement capability discovery |
| Git provenance in SAM | Existing source commit metadata | Read only; no network, fetch or branch mutation |
| SE-396 | Integrity and fail-closed constraints | Report generation cannot weaken any execution gate |
| SE-037/SE-393/SE-394 | Future receipts and operational evidence | Not ingested or upgraded in F3 |

F3 trusts no unvalidated JSON. A stale or malformed SAM, missing declaration,
unknown binding endpoint, duplicate binding or unsafe path returns exit `2`
and leaves every committed report byte-identical.

## 3. Solution and technical contract

### 3.1 Model and source-kind boundary

SAM stays at `schema_version: 2`. F3 adds no node type, relation, source kind,
top-level model field or authority concept. The only valid SAM source kinds
remain `DECLARED` and `DISCOVERED`.

F3 MUST NOT equate source presence with semantic correctness. A declared node
whose referenced file exists remains declared. A registry-derived node remains
discovered. `CORROBORATED` is a report status, never SAM provenance and never a
support or enforcement claim.

### 3.2 Verification declaration input

Create `.scm/sam-verification-declarations.json` with this closed shape:

```json
{
  "schema_version": 1,
  "bindings": [],
  "impact_roots": []
}
```

Every binding has exactly:

```json
{
  "id": "binding:example-component",
  "declared_node_id": "component:example",
  "discovered_node_id": "component/example.sh",
  "basis": "SAME_REPOSITORY_PATH"
}
```

Rules:

- lists are sorted by `id` or value and duplicate-free; `bindings` may be empty
  while `impact_roots` must be non-empty;
- binding IDs match the SAM identifier grammar and are globally unique;
- `declared_node_id` resolves to a node whose provenance kinds equal exactly
  `["DECLARED"]`;
- `discovered_node_id` resolves to a different node whose provenance kinds
  equal exactly `["DISCOVERED"]`;
- `basis` is exactly `SAME_REPOSITORY_PATH`;
- the declared node has exactly one distinct provenance source path and that
  path equals the discovered COMPONENT label and one of its provenance paths;
- both endpoints have the same node type `COMPONENT`;
- one node may occur in at most one binding.

The initial manifest contains no bindings. The current registry does not expose
a discovered node that satisfies the exact same-path rule for any declared
COMPONENT; inventing a match would manufacture evidence. A fixture contains the
example binding to verify the contract. F3 introduces no fuzzy matching, path
normalization beyond the existing safe relative-path validation, aliases,
regexes or operator-authored semantic assertions.

`impact_roots` initially equals exactly:

```text
component:sam-generator
flow:external-effect
policy:human-control
store:scm
```

Each root MUST resolve in SAM. The list is a report selection, not a criticality
or authority declaration.

### 3.3 Architecture drift report

Generate `.scm/reports/drift.json` with exactly:

```json
{
  "schema_version": 1,
  "report": "architecture-drift",
  "model_revision": "<64 lowercase hex>",
  "summary": {
    "corroborated": 0,
    "declared_only": 0,
    "discovered_only": 0,
    "mixed_unbound": 0
  },
  "items": [],
  "limitations": [
    "NO_SEMANTIC_INFERENCE",
    "REPORT_ONLY",
    "STATIC_REPOSITORY_EVIDENCE"
  ]
}
```

Every SAM node is accounted for exactly once, either as an item or as the bound
counterpart named by one item. Items are sorted by node ID and have exactly
`node_id`, `status`, `counterpart_id` and `source_paths`:

- a binding emits one item for the declared endpoint with status
  `CORROBORATED` and its discovered counterpart;
- the discovered endpoint of a binding is represented by that same item and is
  not emitted again;
- unbound nodes with only `DECLARED` provenance are `DECLARED_ONLY`;
- unbound nodes with only `DISCOVERED` provenance are `DISCOVERED_ONLY`;
- any future node with both allowed provenance kinds is `MIXED_UNBOUND`;
- `counterpart_id` is a string only for `CORROBORATED`, otherwise `null`;
- `source_paths` is the sorted union of represented endpoint provenance paths.

Summary counts equal item counts by status. No severity, pass/fail or lifecycle
decision is emitted. The report remains valid when gaps exist; invalid input,
not drift, is the error condition.

### 3.4 Claim/evidence report

Generate `.scm/reports/claim-evidence.json` with the same common fields
`schema_version`, `report`, `model_revision`, `summary`, `items` and
`limitations`. `report` is `claim-evidence`. Limitations equal exactly:

```json
["NO_RUNTIME_EVIDENCE", "REPORT_ONLY", "STATIC_GRAPH_PATHS_ONLY"]
```

Claim nodes are all nodes of type `CAPABILITY`, `POLICY` or `FLOW`, sorted by
ID. Evidence nodes are only type `EVIDENCE`. For each claim, traverse incoming
SAM edges in reverse from the claim for at most two edges. A support path is
valid only when it starts at an evidence node and every traversed relation is
in this closed sequence:

```text
EVIDENCE -DEPENDS_ON-> COMPONENT -IMPLEMENTS-> CAPABILITY
```

No other direction, relation, path length or node type is evidence in F3.
Consequently POLICY and FLOW claims are expected to report gaps until a later
approved phase introduces real evidence relationships.

Each item has exactly `claim_id`, `status`, `evidence_paths`:

- `STATIC_PATH_PRESENT` when one or more valid paths exist;
- `NO_STATIC_EVIDENCE_PATH` otherwise;
- every evidence path is an ordered array of node IDs and arrays are sorted
  lexicographically and duplicate-free.

Summary fields are exactly `claims`, `static_path_present` and
`no_static_evidence_path`, and reconcile with items. The report never emits
`VERIFIED`, `SUPPORTED`, `PASS` or `FAIL` because static topology is not proof
of behavior.

### 3.5 Impact report and query

Generate `.scm/reports/impact.json` with one item per configured impact root.
Each item has exactly `root_id`, `depth`, `upstream`, `downstream` and
`limitations`; `depth` is `2`, node lists are sorted, exclude the root, and
contain the unique nodes reachable in one or two edges:

- `upstream`: reverse traversal over all SAM relations;
- `downstream`: forward traversal over all SAM relations.

Per-item limitations equal exactly `["GRAPH_REACHABILITY_ONLY", "REPORT_ONLY"]`.
The report does not rank risk, predict file changes or assert runtime impact.

Add a read-only CLI command:

```text
python3 scripts/sam.py impact --node <SAM_ID> [--depth 1|2]
```

Default depth is `2`; other values are rejected by argparse. A known node emits
one deterministic JSON object using the same item shape and exits `0`. An
unknown well-formed node emits the existing explicit `UNKNOWN` result and exits
`0`. Invalid/stale SAM input returns `2`. The command writes no file.

### 3.6 Generation, freshness and atomicity

The existing `generate` command validates declarations and builds SAM before
building all three F3 reports. `serialized_outputs()` includes them so a single
atomic staging pass writes model, views and reports. `check` requires exact
byte equality for every generated output.

Reports use canonical sorted JSON plus one trailing newline. They contain no
timestamp, hostname, absolute path, environment value, prompt, secret, receipt
or external data. Their `model_revision` equals `.scm/sam.json`.

F3 errors add exactly:

```text
INVALID_VERIFICATION_DECLARATION
```

Existing error codes remain unchanged. Missing input uses `MISSING_INPUT`;
unknown endpoint/root, wrong provenance kind, type mismatch, unsafe source or
binding contract violation uses `INVALID_VERIFICATION_DECLARATION`.

### 3.7 Known unknowns after F3

Remove none of the F2 known unknowns. F3 reports expose static gaps but do not
resolve operational evidence, incomplete dependency/test links, runtime
observation, authority enforcement or failure-path completeness.

## 4. Business and safety rules

| ID | Rule | Required evidence/failure |
|---|---|---|
| SAM-F3-01 | Verification never grants authority or blocks execution | No policy call, enforcement result or allow/deny vocabulary |
| SAM-F3-02 | Corroboration requires an exact explicit path identity | Fuzzy, inferred or many-to-one binding rejected |
| SAM-F3-03 | Static topology is not behavioral proof | Closed statuses and mandatory limitations |
| SAM-F3-04 | Every model node is accounted for in drift | Summary and unique-item cardinality checks |
| SAM-F3-05 | Claim gaps are visible, not silently omitted | Every CAPABILITY/POLICY/FLOW has one report item |
| SAM-F3-06 | Impact is bounded deterministic reachability | Depth restricted to 1 or 2; sorted unique output |
| SAM-F3-07 | Stale/invalid inputs fail without partial writes | Exit `2` and byte-preservation assertion |
| SAM-F3-08 | F2 model and authority topology remain byte-stable | No schema/declaration change; F2 regression suite passes |

## 5. Test scenarios — tests before production code

1. Given the unchanged F2 fixture plus the valid verification declaration,
   generation produces three byte-identical reports across repeated runs.

2. Given a fixture binding satisfying exact same-path identity, drift contains
   one `CORROBORATED` item joining its declared and discovered endpoints;
   neither endpoint appears a second time.

3. Given the real repository with zero valid explicit bindings, drift reports
   zero corroborations, classifies every node as declared-only,
   discovered-only or mixed-unbound, and summary counts reconcile.

4. Given missing, duplicate, unsorted, unknown, same-kind, wrong-type,
   many-to-one or non-identical-path bindings, generation returns `2` with
   `INVALID_VERIFICATION_DECLARATION` and changes no generated file.

5. Given all CAPABILITY, POLICY and FLOW nodes, claim/evidence emits exactly one
   item per claim and never uses `VERIFIED`, `SUPPORTED`, `PASS` or `FAIL`.

6. Given `evidence:sam-contract-tests -> component:sam-generator ->
   capability:architectural-self-knowledge`, the capability has exactly one
   `STATIC_PATH_PRESENT` path; removing either edge produces a gap.

7. Given evidence connected by another relation, direction or more than two
   edges, it is not counted as a valid static evidence path.

8. Given each configured impact root, the report equals independent bounded
   breadth-first traversal at depth two, excludes the root and has sorted unique
   upstream/downstream IDs.

9. Given `impact --node flow:external-effect --depth 1`, CLI output contains
   only direct incident neighbors, writes nothing and exits `0`; an unknown
   well-formed node returns explicit `UNKNOWN`.

10. Given a stale or malformed SAM/report/declaration, `check`, `impact` and
    `generate` fail closed as applicable and preserve committed report bytes.

11. Given real-repository generation, SAM revision and all F1/F2 view bytes are
    unchanged except for expected provenance changes caused by this approved
    spec/code input; capability registry remains byte-identical and fresh.

12. Given exact F3 changes, security review finds zero executable authority
    calls, external reads, secrets, telemetry, receipts or blocking decisions.

## 6. Files in scope after approval

| Path | Change |
|---|---|
| `.scm/sam-verification-declarations.json` | Create closed F3 binding/root input |
| `.scm/reports/{drift,claim-evidence,impact}.json` | Create deterministic report-only outputs |
| `.scm/sam.json` | Regenerate only for provenance freshness if inputs change its revision |
| `.scm/views/*.json` | Regenerate only to share the resulting model revision |
| `scripts/sam_model.py` | Add declaration validation and pure report builders |
| `scripts/sam.py` | Add read-only impact command; include reports in atomic generation/check |
| `tests/fixtures/sam/**` | Extend isolated fixture with verification declarations |
| `tests/test_sam.py` | Add unit/adversarial F3 tests before production changes |
| `tests/test-se397-sam.bats` | Add real-repository F3 acceptance tests first |
| `docs/specs/SE-397-f3-architecture-verification.spec.md` | Append approval/review/implementation evidence |
| `docs/specs/SE-397-f2-runtime-authority-model.spec.md` | Append F3 handoff only after implementation |
| `docs/propuestas/planning-state.json` | Keep SE-397 `IMPLEMENTING`; add F3 evidence only |
| `docs/propuestas/LOG.md` | Append F3 lifecycle entry |
| `docs/ROADMAP.md` | Mark F3 pending review; never mark SE-397 complete |
| `CHANGELOG.md` | Add F3 entry if required by current release policy |
| `.confidentiality-signature` | Final isolated PR-signing commit only |

No other path is authorized. Additional paths require an append-only revision
and fresh approval before modification.

## 7. Validation commands

```bash
python3 -m unittest tests/test_sam.py -v
bats tests/test-se397-sam.bats
python3 scripts/generate-capability-map.py --check
python3 scripts/sam.py check
python3 scripts/sam.py impact --node flow:external-effect --depth 1
python3 scripts/sam.py impact --node component:sam-generator
bash scripts/spec-opencode-plan-audit.sh
bash scripts/roadmap.sh validate
bash scripts/validate-ci-local.sh
```

Before production edits: observe the F3 tests red, scan staged content for
secrets and verify scope. Human code review remains mandatory before merge.

## 8. Rollback

Revert the F3 implementation commits. This removes the verification input,
three reports and `impact` command while restoring F2 generated artifacts.
Canonical policy, authority, capability registry, receipts and enforcement are
unchanged; no migration or external recovery is required.

## 9. Effort and implementation state

| Dimension | Estimate |
|---|---|
| Agent effort | 6–8 hours |
| Human equivalent | 3–5 days |
| Human review | 60–90 minutes |
| Context risk | high |
| Agent capable | yes, serial TDD because model/report generation overlaps |
| Fallback | human resumes from approved contract and red tests |

Implementation state: `PROPOSED_PENDING_F2_REVIEW_AND_EXPLICIT_APPROVAL`.

## 10. Acceptance checklist

- [ ] Operator explicitly reviewed merged F2.
- [ ] Operator explicitly approved this exact committed F3 revision.
- [ ] Every F3 production behavior was preceded by an observed red test.
- [ ] Drift accounts for every SAM node without semantic inference.
- [ ] Every claim is reported and static evidence gaps remain explicit.
- [ ] Impact results are deterministic, bounded and report-only.
- [ ] Existing authority, registry and F2 topology remain unchanged.
- [ ] All specified tests and local CI pass.
- [ ] SE-397 remains `IMPLEMENTING`; F4–F10 remain pending.
- [ ] Human code review occurs before merge.

## 11. Open decisions

None inside this minimal F3 contract. Drift severity, blocking policy,
runtime observations, receipt ingestion, semantic code analysis, support
graduation, transitive depth above two and file-level PR prediction belong to
later phases and require independent approval.

## OpenCode Implementation Plan

### Bindings touched

| Component | Claude Code | OpenCode v1.14 |
|---|---|---|
| SAM Python CLI | `python3 scripts/sam.py` | Same frontend-neutral CLI |
| Generated reports | Read-only `.scm/reports/*.json` | Same files and schema |
| Runtime hooks | None | None |

### Verification protocol

- [ ] The same CLI commands and fixture corpus pass outside either frontend.
- [ ] Unit and BATS tests cover report generation, freshness and read-only query.
- [ ] No frontend hook, plugin binding or settings change is introduced.

### Portability classification

- [x] **DUAL_BINDING**: both frontends invoke the same Python CLI and consume
  identical JSON; F3 adds no frontend-specific binding.
- [ ] **PURE_BASH**
- [ ] **SINGLE_BINDING_DEFERRED**
- [ ] **CLAUDE_CODE_ONLY**
