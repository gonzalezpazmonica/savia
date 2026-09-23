---
title: Gentle AI 3.5.0 and Gentle Shell 3.4.0 absorption
date: 2026-09-23
status: REVIEWED
scope: Savia, Savia Runtime, SaviaLabs
---

# Gentle AI 3.5.0 / Gentle Shell 3.4.0 — absorption review

## Sources and boundary

Reviewed the official release notes and linked change summaries for
[Gentle AI v3.5.0](https://github.com/Gentleman-Programming/gentle-ai/releases/tag/v3.5.0)
and [Gentle Shell v3.4.0](https://github.com/Gentleman-Programming/gentle-shell/releases/tag/v3.4.0).
This is pattern absorption, not source-code copying. Product-specific UI,
branding, package pins and provider identities do not enter Savia semantics.

## Decision matrix

| Upstream pattern | Savia decision | Destination / rationale |
|---|---|---|
| Candidate frozen once, one bounded correction, terminal acknowledgement receipt | REUSE + TIGHTEN | SE-260 already implements frozen findings, bounded correction and content receipts. Add explicit terminal state only when the review lifecycle is next revised; no second court system. |
| Typed provider refusal causes; assessment errors fail closed | ABSORB | SE-401 failure/refusal taxonomy. Transport, authority refusal, malformed envelope and unknown classification remain distinct; unassessable never means low risk. |
| `last_synced_at` only after successful sync | ABSORB | SE-398/399 evidence freshness. Failed/interrupted projection or provisioning preserves the previous successful timestamp. |
| Canonical lock around whole-state load/mutate/save | ABSORB AS AUDIT | Audit shared mutable state before adding another lock abstraction; use one lock per canonical state owner and atomic replacement beneath it. |
| Roll back host mutation when registration fails, including ambiguous landed-write errors | ABSORB | SE-399 transactional provisioning and compensation semantics. |
| Preserve custom user fields when an overlay does not explicitly own a value | ABSORB | SE-399 ownership-aware three-way reconciliation; absence is not a request to clear user configuration. |
| Atomic binary replacement | ABSORB | SE-399 install contract: verified temporary artifact plus atomic rename, never truncate destination in place. |
| Exact intended-untracked projection and explicit generated marker | ABSORB | Review/evidence projection must materialize the declared set once; generated evidence is explicit, boolean and provider-owned, with unknown fields rejected. |
| Provider resolution from the effective live selection | ABSORB | SE-396/401 adapters use effective selection and native registry; never fabricate API keys or infer provider identity from executable names. |
| Isolated home, link mode, runtime discovery and minimum-version gate | ABSORB | SE-398/399 runtime surface and bootstrap contracts; isolated is default, linking is explicit and non-mutating. |
| First-party questionnaire and interactive RPC host | ABSORB AS CONTRACT | SE-398 Human Gate projection: bounded question count, typed answers/free text, session correlation, size limits, cancellation and no authority elevation. UI implementation remains phase-gated. |
| Default-on receipt-driven review | NO NEW DEFAULT | Savia already requires governed review by risk and human gates. Existing explicit user/project choices remain authoritative; no silent setting mutation. |
| Animation, subscription usage, shell rendering, Gentle package pin | DO NOT ABSORB | Product-specific surface work without a measured Savia gap. |

## Whole-state writer audit (L14)

The repository scan found a mixed posture:

- atomic replacement exists in `goal-service.py`, `repeat-tool-guard.py`,
  `memory-graph.py`, `memory-vector.py`, `mask-reversible.py` and the automation
  store;
- atomic rename alone is insufficient for concurrent load/mutate/save: the
  automation task store and goal service have no visible cross-process
  canonical lock;
- `savia-bridge.py` serializes the in-memory known-session set, but its disk
  replacement is not atomic; per-user `sessions.json` performs an unlocked
  read/append/write;
- several registries and state machines write a complete JSON document in
  place (`slm-registry.sh`, `session-state-machine.sh`, `savia-goals.sh` and
  enterprise manifests), so interruption and lost-update risk must be assessed
  per owner rather than patched with a global lock.

Disposition: create no generic lock subsystem in this batch. The next slices
must first name each canonical state owner, concurrency model and recovery
contract, then add focused lock/atomicity tests. Highest priority is Bridge
session ownership, followed by goals/automations; generated reports are lower
risk because they are replaceable outputs.

## Resulting priority

1. Finish SE-396 human review/graduation after the local H02/H09/H10 closure.
2. Reconcile and approve the SE-401 AEK/Savia ownership boundary; typed
   failures and fail-closed assessment enter its first executable slice.
3. Feed isolated-home/RPC/freshness contracts into SE-398 F1.
4. Feed transactional install, ownership preservation and atomic replacement
   into SE-399 F1.
5. Execute the shared-state locking audit slices before enabling new concurrent
   desktop/installer writers.

No item raises autonomy or provider authority, and no upstream success claim is
treated as Savia operational evidence.
