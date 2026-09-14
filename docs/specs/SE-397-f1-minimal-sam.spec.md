---
id: SE-397-F1
parent: SE-397
status: APPROVED
priority: P0
developer_type: agent-single
created: 2026-09-13
risk: L2
type: architecture-baseline
depends_on:
  - SE-397-F0
  - SE-031
  - SE-375
related_specs:
  - SE-037
  - SE-378
  - SE-390
  - SE-393
  - SE-394
  - SE-396
  - SE-398
  - SE-399
  - SE-400
execution_scope: READ_ONLY_DERIVED_ARCHITECTURE
---

# SE-397 F1 — Minimal Savia Architecture Model

## Approval gate

This delta spec is the executable contract required by the approved F0 before
functional F1 work. It has not yet been approved. No production code, generated
SAM artifact or test implementation may be added until the operator explicitly
approves this exact revision.

## 1. Context and objective

SE-397 F0 concluded `GO_WITH_CONCERNS`: Savia has reusable capability, policy,
identity and evidence sources, but no single machine-readable architectural
projection. F1 will create a deterministic, versioned and queryable projection
under `.scm/`. It will reference existing sources and preserve their authority;
it will not become a policy engine, evidence store, runtime observer or execution
gate.

F1 satisfies only the F1 portions of parent AC03–AC08, AC13–AC14, AC17, AC34
and AC37–AC40. Parent AC09–AC12 and AC15–AC33 remain explicitly pending.

## 2. Dependency disposition

| Dependency | F1 use | Gate |
|---|---|---|
| SE-031 deterministic artifacts | Canonical JSON, sorted records, content-derived revision, no generated timestamp | Hard dependency |
| SE-375 `.scm/registry.json` | Existing capability catalogue; consumed by reference, never replaced | Hard dependency; stale/malformed registry makes `check` fail |
| SE-390 identity | Existing identity documents are referenced by declared SYSTEM nodes | Hard reference; SAM cannot change identity |
| `laws/index.yaml` and `laws/*.md` | Existing policy identifiers/documents referenced by declared POLICY nodes | Hard reference; policy text is never copied |
| SE-396 | Defines execution-integrity limits; F1 records no runtime, authority or operational evidence | Parallel constraint, not a functional blocker for read-only F1 |
| SE-037, SE-393, SE-394 | Future runtime/evidence inputs | Deferred to F2–F4; no synthetic upgrade in F1 |
| SE-398, SE-399, SE-400 | Future consumers of SAM runtime/surface/install/kernel views | Must consume F1 later; cannot expand F1 schema implicitly |

If a dependency is missing, stale, malformed or outside the repository root,
generation/checking fails closed. It never silently drops the affected record or
changes authority.

## 3. Technical contract

### 3.1 Files and commands

The implementation SHALL expose one standard-library-only CLI:

```text
python3 scripts/sam.py generate [--root PATH]
python3 scripts/sam.py check [--root PATH]
python3 scripts/sam.py query --node NODE_ID [--root PATH]
```

- `generate` validates all inputs, then atomically writes `.scm/sam.json` and
  the three files below `.scm/views/`. Exit `0` on success, `2` on invalid input.
- `check` regenerates entirely in a temporary directory and compares bytes with
  committed generated files. It never writes below `--root`. Exit `0` when
  fresh, `1` when stale, `2` when input or committed output is missing/corrupt.
- `query` validates the committed model and returns one JSON object on stdout.
  Known nodes return `{"status":"FOUND","node":{...},"edges":[...]}`.
  Unknown IDs return `{"status":"UNKNOWN","node":null,"edges":[]}` and
  exit `0`; absence is explicit and is never represented as `FOUND` or `PASS`.
- Diagnostics go to stderr. No command reads network, user memory, Vaults,
  telemetry, secrets or files outside `--root`.

Production functions in `scripts/sam_model.py` SHALL have these interfaces:

```python
def build_model(root: pathlib.Path) -> dict: ...
def validate_model(model: object, root: pathlib.Path) -> dict: ...
def build_views(model: dict) -> dict[str, dict]: ...
def query_node(model: dict, node_id: str) -> dict: ...
def canonical_json(value: object) -> bytes: ...
```

`validate_model` returns the same validated object without mutating its input and
raises `SamValidationError(code: str, path: str)` for any contract violation.
Allowed error codes are exactly `INVALID_TOP_LEVEL`, `UNKNOWN_FIELD`,
`INVALID_ID`, `DUPLICATE_ID`, `DUPLICATE_EDGE`, `DANGLING_EDGE`,
`UNKNOWN_NODE_TYPE`, `UNKNOWN_RELATION`, `UNSUPPORTED_SOURCE_KIND`,
`MISSING_INPUT`, `PATH_OUTSIDE_ROOT`, `STALE_CAPABILITY_MAP`,
`INVALID_REGISTRY`, `INVALID_MODEL`, and `WRITE_FAILED`.

### 3.2 Declared input

`.scm/sam-declarations.json` is a small declaration manifest, not a generated
view and not an authority source. It contains only identifiers, labels, types,
relations and repository-relative references to existing canonical sources. It
MUST NOT copy policy text, approval decisions, receipts, memory or telemetry.

The manifest top level is exactly:

```json
{
  "schema_version": 1,
  "nodes": [],
  "edges": []
}
```

Declared node fields are exactly `id`, `type`, `label`, `source_paths`.
Declared edge fields are exactly `source`, `relation`, `target`, `source_paths`.
`source_paths` is a non-empty, sorted, duplicate-free list of relative POSIX
paths. Absolute paths, `..`, empty paths, missing targets and symlinks resolving
outside the root are rejected.

The initial manifest MUST contain at least one node of every F1 type:
`SYSTEM`, `SUBSYSTEM`, `COMPONENT`, `CAPABILITY`, `POLICY`, `ADAPTER`,
`FRONTEND`, `STORE`, `EVIDENCE`. It may use only these relations:
`CONTAINS`, `IMPLEMENTS`, `USES`, `DEPENDS_ON`, `ENFORCES`, `PRODUCES`,
`REQUIRES_AUTHORITY`.

### 3.3 Generated model

`.scm/sam.schema.json` is a JSON Schema Draft 2020-12 description. Runtime
validation is implemented with the Python standard library and MUST enforce the
same closed contract (`additionalProperties: false` at every object level).

`.scm/sam.json` top-level fields are exactly:

```text
schema_version: integer, exactly 1
model_id: string, exactly "savia-architecture-model"
model_revision: lowercase sha256 hex, 64 chars
inputs: sorted list<InputRecord>
nodes: sorted list<Node>
edges: sorted list<Edge>
known_unknowns: sorted list<string>
```

`model_revision` is sha256 over canonical JSON of `inputs`, `nodes`, `edges`
and `known_unknowns`; it does not hash itself. Generated output contains no wall
clock timestamp, absolute path or machine-specific value.

`InputRecord` fields are exactly `path`, `sha256`, `source_commit`, `status`.
`status` is `PRESENT`. `source_commit` is the last Git commit affecting the path,
or `NOT_AVAILABLE` in an isolated non-Git fixture. It never means verification.
Real-repository generation uses two serial commits: first commit declarations,
schema, code and tests; then generate and commit the derived model/views. This
prevents a newly tracked declaration from producing an immediately stale
`NOT_AVAILABLE` source commit and avoids any self-referential artifact hash.

`Node` fields are exactly `id`, `type`, `label`, `provenance`. `Edge` fields are
exactly `source`, `relation`, `target`, `provenance`. `provenance` is a sorted,
non-empty list of records with exactly `source_kind`, `source_path`, `sha256`,
`source_commit`. Allowed source kinds in F1 are only `DECLARED` and
`DISCOVERED`; `INFERRED` and every `VERIFIED_*` state are rejected.

IDs are unique non-empty case-sensitive strings matching
`^[A-Za-z][A-Za-z0-9._:/-]{2,255}$`. Every edge endpoint must exist. Duplicate edges
by `(source, relation, target)` are rejected. Records are sorted by ID or the
edge tuple; provenance and inputs are sorted by path then source kind.

### 3.4 Capability reuse

The generator consumes `.scm/registry.json` only after
`python3 scripts/generate-capability-map.py --check` reports `FRESH`.
For every registry capability it emits:

- one `CAPABILITY` node with ID `capability/<registry id>` and `DISCOVERED`
  provenance referencing both `.scm/registry.json` and the registry `source`;
- one `COMPONENT` node with ID derived losslessly from the source path;
- one `COMPONENT --IMPLEMENTS--> CAPABILITY` edge.

It does not reinterpret `risk_level`, `frontend_support`, status, intents,
dependencies or tests in F1. Empty `depends_on` and `tests` therefore remain
known gaps, not evidence of no dependency or complete testing. The model includes
the known unknowns `CAPABILITY_DEPENDENCIES_INCOMPLETE`,
`CAPABILITY_TEST_LINKS_INCOMPLETE`, `RUNTIME_ARCHITECTURE_NOT_MODELLED`, and
`OPERATIONAL_EVIDENCE_NOT_MODELLED`.

### 3.5 Views

The generator writes deterministic closed JSON views containing exactly
`schema_version`, `view`, `model_revision`, `node_ids`, `edge_ids`, and
`limitations`:

- `.scm/views/foundation.json`: SYSTEM, POLICY, EVIDENCE and edges between
  selected nodes.
- `.scm/views/capabilities.json`: CAPABILITY, COMPONENT and their IMPLEMENTS,
  USES or DEPENDS_ON edges.
- `.scm/views/structural.json`: SYSTEM, SUBSYSTEM, COMPONENT, ADAPTER,
  FRONTEND, STORE and edges between selected nodes.

`edge_ids` are canonical `source|relation|target` strings. Every view states
`GENERATED_FROM_SAM` and `REPORT_ONLY` in `limitations`. Views never contain
copied policy content or a claim of operational support.

## 4. Business and safety rules

| ID | Rule | Required failure |
|---|---|---|
| SAM-01 | SAM is derived; existing policy, planning, evidence and memory remain authoritative | No mutation outside `.scm/sam.json` and `.scm/views/` |
| SAM-02 | Unknown and missing security/authority information fails safe | `SamValidationError("MISSING_INPUT", path)` / exit 2 |
| SAM-03 | Declared and discovered provenance remain distinguishable | Reject unsupported or upgraded source kind |
| SAM-04 | No source can escape repository root | `PATH_OUTSIDE_ROOT` / exit 2 |
| SAM-05 | Identical inputs produce byte-identical outputs | Determinism test across two directories |
| SAM-06 | Corrupt generated output cannot be queried as valid | `INVALID_MODEL` / exit 2 |
| SAM-07 | F1 cannot grant authority or claim runtime/evidence graduation | Forbidden fields/relations/source kinds rejected |
| SAM-08 | Existing `.scm` capability outputs remain byte-identical | Pre/post hashes of INDEX, registry, resources and categories match |

## 5. Test scenarios — tests must be written before production code

1. Given a valid isolated fixture with Git history, two `generate` runs in
   separate copies produce byte-identical model and view files.
2. Given the real repository with fresh capability map, `check` returns `0` and
   every registry capability has one capability node and one implementing edge.
3. Given a declared node source path that is missing, absolute, contains `..` or
   escapes through a symlink, generation returns `2` and writes no output.
4. Given duplicate IDs, duplicate edges, dangling endpoints, unknown types,
   relations, fields or source kinds, validation raises the exact documented
   error and never partially writes.
5. Given a changed source byte, `check` returns `1` until `generate` updates the
   model revision; reverting the byte restores the prior revision.
6. Given corrupt `sam.json`, `query` returns `2`; given a syntactically valid but
   unknown node ID, it returns explicit `UNKNOWN` with exit `0`.
7. Given an attempted `VERIFIED_STATIC` claim in declarations/generated input,
   validation rejects it; F1 cannot self-upgrade evidence.
8. Given generation on the real repository, hashes of every pre-existing `.scm`
   file except new SAM paths are unchanged.
9. Given the three generated views, all selected node/edge IDs exist in SAM,
   all model revisions match and output contains both required limitations.
10. Given a stale or malformed `.scm/registry.json`, `check` and `generate` fail
    closed without rewriting the capability map.

## 6. Files to create or modify after approval

| Path | Change |
|---|---|
| `.scm/sam.schema.json` | Create closed machine-readable schema |
| `.scm/sam-declarations.json` | Create minimal reference-only declaration input |
| `.scm/sam.json` | Create deterministic generated model |
| `.scm/views/foundation.json` | Create generated Foundation view |
| `.scm/views/capabilities.json` | Create generated Capability view |
| `.scm/views/structural.json` | Create generated Structural view |
| `scripts/sam_model.py` | Create pure build/validation/query library |
| `scripts/sam.py` | Create CLI adapter |
| `tests/fixtures/sam/**` | Create valid and invalid isolated inputs |
| `tests/test_sam.py` | Create unit and corruption/security tests first |
| `tests/test-se397-sam.bats` | Create CLI/real-repository acceptance wrapper first |
| `docs/specs/SE-397-f1-minimal-sam.spec.md` | Append implementation evidence; never rewrite approval history |
| `docs/specs/SE-397-f0-architectural-reconciliation.md` | Append F1 handoff only after implementation |
| `docs/propuestas/planning-state.json` | Keep SE-397 `IMPLEMENTING`; add F1 evidence only |
| `docs/propuestas/LOG.md` | Append F1 review entry |
| `docs/ROADMAP.md` | Mark F1 implemented, never SE-397 complete |
| `CHANGELOG.md` | Add an unreleased SE-397 F1 entry if CI policy requires it |

No other file is in scope. If implementation requires another path, stop and
amend this delta spec for a fresh explicit approval.

## 7. Validation commands

```bash
python3 -m unittest tests/test_sam.py -v
bats tests/test-se397-sam.bats
python3 scripts/generate-capability-map.py --check
python3 scripts/sam.py check
bash scripts/validate-ci-local.sh
```

Before commit: run the workspace secret scan, regenerate only managed indexes
that their canonical checks prove stale, and verify the staged diff contains no
project/private paths or absolute machine paths.

## 8. Rollback

Delete only the new SAM files and revert the four explicitly listed planning/
documentation edits. No migration or data recovery is required because F1 has
no runtime consumer, no database, no external write and no authority effect.
If SAM is missing or corrupt, queries return an error/UNKNOWN; all existing Savia
capabilities continue unchanged.

## 9. Effort and implementation state

| Dimension | Estimate |
|---|---|
| Agent effort | 4–6 hours |
| Human equivalent | 2–3 days |
| Human review | 60–90 minutes |
| Context risk | high |
| Agent capable | yes, one serial implementation due shared schema/model/tests |
| Fallback | human resumes from approved contract and red tests |

Implementation state: `NOT_STARTED_PENDING_EXPLICIT_APPROVAL`.

## 10. Acceptance checklist

- [ ] Operator explicitly approved this exact delta spec after reading it.
- [ ] Every production behavior was preceded by a corresponding test observed red.
- [ ] All F1 commands and schemas match this contract.
- [ ] Real `.scm` capability layer is reused without mutation or duplication.
- [ ] Every modeled datum has declared/discovered provenance.
- [ ] No runtime, authority, trust, operational evidence or support claim added.
- [ ] All specified tests and local CI pass.
- [ ] SE-397 remains `IMPLEMENTING`; F2–F10 remain pending.
- [ ] Human code review occurs before merge.

## 11. Open decisions

None inside F1. Any request to add runtime traces, drift severity, enforcement,
SQLite, MCP/API exposure, Mermaid generation, authority evaluation or frontend
support claims belongs to a later delta spec and requires its own gate.

## 12. Approval record — append only

- Contract revision approved: commit `70131682`.
- Operator response: `si` on 2026-09-13, in direct response to the explicit
  question asking approval of revision `70131682` for tests and implementation.
- Scope authorized: tests and implementation of this F1 contract only.
- Implementation state after approval: `APPROVED_NOT_STARTED`.

## 13. Implementation evidence — append only

- F1 implementation commit: `82fa911a`.
- Red gate observed before production code: unit import failed with
  `ModuleNotFoundError: sam_model`; BATS failed because CLI, schema and committed
  projection did not exist.
- Generated projection: 2,939 nodes, 1,473 edges and 1,474 source inputs;
  deterministic revision `b6a566107ddc` (short form).
- Unit gate: 11/11 tests pass, including malformed types, path escape,
  corruption, stale inputs and forbidden evidence graduation.
- Acceptance gate: 5/5 BATS tests pass.
- JSON Schema gate: Draft 2020-12 schema and generated model validate.
- Capability dependency: existing `.scm/registry.json` remains `SCM: FRESH`;
  F1 consumes it without rewriting it.
- Scope result: no runtime, SQLite, authority decision, telemetry, memory or
  frontend-support claim was added. F2–F10 remain pending.
- F1 implementation state: `IMPLEMENTED_PENDING_HUMAN_REVIEW`.

## 14. F2 handoff — append only

- F1 was merged in PR #1123 and remains the immutable foundation declaration
  schema (`schema_version: 1`).
- F2 extends the generated model and views to schema v2 through the independent
  `.scm/sam-runtime-declarations.json`; it does not rewrite F1 declarations.
- F2 implementation commit: `799485fc`; review evidence lives in
  `docs/specs/SE-397-f2-runtime-authority-model.spec.md`.
