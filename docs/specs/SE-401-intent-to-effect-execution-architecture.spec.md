---
status: PROPOSED
priority: P0
developer_type: agent-team
created: 2026-09-21
date: 2026-09-21
scope: "Savia Runtime + AEK semantic/governance layer"
architecture_type: "provider-agnostic, model-agnostic, execution-system-agnostic"
related_specs: [SE-386, SE-393, SE-394, SE-396, SE-397, SE-400]
risk: L4
---

# SE-401 — Intent-to-Effect Execution Architecture (I2E)

## 1. Motivation and objective

Most agentic runtimes collapse context, model, tool call and result into one
loop. That lets reasoning resemble authorization, lets confidence resemble
permission, makes one component propose/execute/evaluate, confuses tool success
with effect success, leaks provider behavior into architecture and leaves weak
audit trails.

Savia and AEK SHALL instead model a governed transformation:

```text
Intent → Reasoning → Decision → Authority → Execution
       → Effect → Verification → Evidence → State Transition
```

The primary objective is to separate reasoning, decision, authority, execution,
verification, evidence and state transition into explicit, replaceable
responsibilities. The architecture SHALL NOT depend on a model, inference
provider, agent framework or decision technology.

## 2. Architectural principle and responsibility split

The core invariant is:

```text
Reasoning ≠ Decision ≠ Authority ≠ Execution ≠ Verification
```

A provider MAY implement several capabilities internally, but the runtime SHALL
preserve their logical boundaries. Models, humans, rules, algorithms and
external systems are providers behind explicit interfaces, never stable semantic
architecture.

```text
AEK                                    SAVIA
Principal, Intent, Capability          Reasoning, Planning, Decision
Authority, Policy, Context             Authorization, Execution, Verification
Effect, Evidence                       Recovery, State transition, Receipts
                    ↓
PROVIDERS: LLMs, small models, rules, algorithms, optimizers, humans,
           APIs, MCP, CLI, workflows, enterprise systems, infrastructure
```

AEK SHALL govern transformation of Intent into verifiable Effects. Savia SHALL
provide the governed execution runtime.

## 3. Constitutional invariants

- **I2E-INV-001 — Decision does not imply authority.**
  `Decision(action) != Authorization(action)`. No selected action executes
  before independent authority evaluation.
- **I2E-INV-002 — Confidence does not imply authority.** Confidence,
  probability, consensus or certainty SHALL NEVER elevate authority.
- **I2E-INV-003 — Execution does not imply success.**
  `execution_completed != effect_verified`.
- **I2E-INV-004 — Authority belongs to the action/effect boundary.** Evaluate
  principal, capability, action, target, expected effect, environment, policy,
  risk and current state. Authority is not intrinsic to an agent.
- **I2E-INV-005 — Effects are first-class.** Different tools MAY implement the
  same semantic effect, such as `ProductionDeploymentEffect`.
- **I2E-INV-006 — Verification is independent.** Executor testimony alone is
  insufficient whenever risk or policy requires independent evidence.
- **I2E-INV-007 — Provider independence.** Provider-specific identifiers MAY
  live in adapters or opaque metadata but SHALL NOT become semantic dependencies.
- **I2E-INV-008 — Evidence over hidden reasoning.** Auditability SHALL NOT rely
  on private chain-of-thought. Evidence SHOULD contain input state, context refs,
  candidates, decision, rationale summary where available, authority evaluation,
  execution receipt, observed effect, verification, transition and provenance.

## 4. Canonical lifecycle

```text
INTENT → CONTEXT + STATE → REASONING → CANDIDATE ACTIONS → DECISION
       → AUTHORITY EVALUATION
           ├─ DENY ─────────────→ EVIDENCE → STOP / REPLAN
           ├─ REQUIRE APPROVAL ─→ APPROVAL GATE
           └─ AUTHORIZED ACTION → EXECUTION → OBSERVED EFFECT
                                → VERIFICATION → EVIDENCE → STATE UPDATE
                                  ├─ CONTINUE  ├─ RETRY   ├─ REPLAN
                                  ├─ ESCALATE  ├─ RECOVER └─ STOP
```

## 5. Semantic domain model

### 5.1 Intent

```yaml
Intent:
  id: string
  principal: PrincipalRef
  objective: string
  constraints: []
  success_conditions: []
  risk_context: optional
  provenance: Provenance
```

Intent describes the outcome, not the mechanism. Prefer “deploy release 4.2.1
while preserving availability SLO” over “run kubectl apply”.

### 5.2 CandidateAction

```yaml
CandidateAction:
  id: string
  capability: CapabilityRef
  parameters: object
  target: optional
  expected_effect: EffectDescriptor
  estimated_risk: optional
  preconditions: []
  evidence_refs: []
```

A candidate is never directly executable.

### 5.3 EffectDescriptor

```yaml
EffectDescriptor:
  effect_type: string
  target: optional
  expected_state_delta: object
  invariants: []
  verification_requirements: []
```

Tools remain implementation details beneath Effect whenever feasible.

## 6. Runtime artifacts and contracts

`ReasoningResult`, `Plan`, `CandidateAction`, `Decision`,
`AuthorizationResult`, `AuthorizedAction`, `ExecutionReceipt`,
`ObservedEffect`, `VerificationResult`, `StateTransition` and
`RecoveryDecision` are runtime artifacts. They SHALL NOT automatically become
AEK constitutional primitives.

### 6.1 Reasoning

```text
Reasoner.reason(intent, context, state, constraints) -> ReasoningResult
```

`ReasoningResult` contains observations, hypotheses, constraints, candidate
actions, uncertainties, evidence refs and optional opaque provider metadata.
A reasoner MAY be an LLM, small model, rules engine, symbolic planner, search,
optimizer, classifier, workflow, human or ensemble. Mechanism is not assumed.

### 6.2 Decision

```text
DecisionProvider.decide(intent, state, candidates, constraints) -> Decision
```

Decision contains selected candidate ref, alternatives, optional confidence and
uncertainty, rationale summary, evidence refs and opaque provider metadata.
Rules, heuristics, statistics, optimization, models, humans and ensembles MAY be
swapped without changing downstream authority semantics.

Savia SHOULD expose a `DecisionRouter` across deterministic rules, heuristics,
classifiers, optimization, reasoning models, ensembles and humans. Routing MAY
use risk, cost, latency, determinism, regulation, sensitivity, availability and
historical performance, but SHALL NOT grant authority.

Fast and slow paths SHALL emit the same Decision contract:

```text
FAST: State → rule/classifier/light inference → Decision → Authority
SLOW: State + Context → planner/deliberation → Candidates → Decision → Authority
```

### 6.3 Authority

```text
AuthorityEngine.authorize(
  principal, capability, action, expected_effect, context, state, policy
) -> AuthorizationResult
```

```yaml
AuthorizationResult:
  status: AUTHORIZED | DENIED | REQUIRES_APPROVAL |
          REQUIRES_DUAL_CONTROL | REQUIRES_EVIDENCE
  authority_tier: string
  policy_refs: []
  conditions: []
  expires_at: optional
  receipt_id: string
```

Authority SHOULD be deterministic where practical. Probabilistic intelligence
MAY assist policy interpretation but SHALL NOT override deterministic limits.

### 6.4 AuthorizedAction and execution

```yaml
AuthorizedAction:
  candidate_action: CandidateAction
  authorization_receipt: AuthorizationReceipt
  preconditions: []
  expected_effect: EffectDescriptor
  recovery_policy: optional
```

Only AuthorizedAction reaches an executor when authority is required.

```text
Executor.execute(authorized_action) -> ExecutionReceipt
```

```yaml
ExecutionReceipt:
  action_id: string
  executor: string
  started_at: timestamp
  completed_at: optional
  transport_status: string
  external_refs: []
  output_refs: []
  errors: []
```

Executors include APIs, CLIs, MCP, scripts, workflows, CI/CD, operators, cloud
control planes, databases, enterprise apps, humans or other runtimes. A receipt
describes execution activity, never effect realization.

### 6.5 Verification

```text
Verifier.verify(expected_effect, execution_receipt, observed_state, policy)
  -> VerificationResult
```

```yaml
VerificationResult:
  status: VERIFIED | PARTIALLY_VERIFIED | FAILED | UNKNOWN
  observations: []
  mismatches: []
  evidence_refs: []
  confidence: optional
```

Risk-sensitive verification SHOULD use sources independent from the executor.

### 6.6 Evidence

```yaml
EvidenceRecord:
  execution_id: string
  intent_ref: string
  principal_ref: string
  state_digest_before: string
  context_refs: []
  reasoning_ref: optional
  candidate_actions: []
  decision_ref: string
  authorization_ref: string
  execution_ref: optional
  expected_effect: object
  verification_ref: optional
  state_digest_after: optional
  provenance: object
  timestamp: timestamp
```

Evidence SHALL reconstruct what was requested/known, alternatives, selection,
permission, execution, change, verification and next transition.

### 6.7 State transition

Verification feeds `CONTINUE`, `RETRY`, `REPLAN`, `ESCALATE`, `RECOVER`,
`STOP_SUCCESS`, `STOP_FAILURE` or `WAIT`. Retry is never the implicit default.

## 7. Retry, recovery and re-authorization

Retry SHALL account for remaining budget, changed-outcome probability, state
degradation, side effects, idempotency, new evidence, failure class and authority.
Do not retry when another attempt is unlikely to help or may degrade state.

Recovery resumes only from verified state:

1. inspect immutable events/evidence;
2. locate latest verified checkpoint;
3. reconstruct observed current state;
4. re-anchor intent;
5. replan;
6. re-evaluate authority;
7. resume through normal I2E.

Recovered execution never inherits stale authorization. Re-evaluate whenever
state, target, effect, principal, capability, parameters, environment, risk,
policy, validity interval or replanned action materially changes.

## 8. Human and machine providers

Humans are first-class providers and MAY reason, decide, authorize, execute or
verify through the same contracts. Providers MAY suggest risk, candidates,
effects, recovery, decisions or verification hypotheses. Governance alone
determines whether suggestions affect execution. Providers cannot self-elevate
risk tier, authority tier, exemption, privilege or permission.

## 9. Capabilities and provider adapters

Every CandidateAction references a registered capability describing semantic
action, parameters, possible effects, risk, authority, executor providers,
verification and idempotency/recovery semantics. Tool names stay below this
abstraction.

Provider-specific packages live behind adapters:

```text
runtime/
  reasoning/{contracts,router,providers}
  decision/{contracts,router,providers}
  authority/{contracts,engine}
  execution/{contracts,providers}
  verification/{contracts,providers}
  evidence/
  state/
  recovery/
```

Dependencies point inward. `OpenAIReasoner implements Reasoner` is allowed;
`Reasoner depends on OpenAIReasoner` is forbidden. Provider descriptors expose
ID, role, determinism/probability, latency/cost, evidence/confidence support and
optional maximum risk. Descriptors are operational metadata, never authority.

## 10. Flow Mesh, nesting and recursive governance

An AEK flow mesh is a graph of I2E executions. Edges SHOULD carry verified
effects, state, evidence refs, delegated intent, scoped authority and capability
availability—not implicit conversation alone.

An execution MAY produce subordinate intents (build, validate, deploy, verify).
Delegation preserves principal provenance, limits, parent intent, expected effect
and evidence chain. Every child repeats Intent → Reasoning → Decision → Authority
→ Execution → Verification → Evidence. Parent authorization is scoped and never
implicitly inherited.

## 11. Observability, security and determinism

Metrics SHOULD separate decision quality, execution reliability, verification
outcomes and authority constraints. Track executions, decisions/provider,
denials, approvals, execution/verification failures, reversals, retries, replans,
recoveries, escalations, provider latency/cost and effect success rate.

The runtime SHALL prevent raw model output, candidate action or decision from
reaching privileged execution; stale authorization reaching an executor; and
unverified execution becoming success. Privileged paths require valid authority
receipts. High-risk effects SHOULD use cryptographically verifiable or
append-only receipts where feasible.

Policy MAY restrict provider kinds for deterministic/regulatory needs. For L4,
policy MAY allow only deterministic or human decision providers and forbid a
single probabilistic provider. Probabilistic systems may still propose while
deterministic governance controls execution.

## 12. Failure taxonomy

The runtime SHOULD distinguish `REASONING_FAILURE`, `NO_VALID_CANDIDATE`,
`DECISION_FAILURE`, `AUTHORITY_DENIED`, `APPROVAL_TIMEOUT`, `EXECUTION_FAILURE`,
`EFFECT_MISMATCH`, `VERIFICATION_FAILURE`, `STATE_CONFLICT`, `POLICY_VIOLATION`,
`RECOVERY_REQUIRED` and `PROVIDER_UNAVAILABLE`; never collapse all into
`agent_failed`.

## 13. Minimal API surface

```text
Reasoner.reason(Intent, Context, State) -> ReasoningResult
DecisionProvider.decide(Intent, State, CandidateAction[]) -> Decision
AuthorityEngine.authorize(Principal, CandidateAction, Context, State)
  -> AuthorizationResult
Executor.execute(AuthorizedAction) -> ExecutionReceipt
Verifier.verify(ExpectedEffect, ObservedState, ExecutionReceipt)
  -> VerificationResult
EvidenceStore.append(EvidenceRecord)
StateManager.transition(State, VerificationResult, Decision) -> StateTransition
```

## 14. Initial Savia migration

1. Introduce semantic contracts and receipts.
2. Wrap existing Savia behavior as legacy providers.
3. Insert explicit Decision → Authority boundary.
4. Insert Effect → Verification boundary.
5. Move retry/recovery onto verified state transitions.
6. Introduce provider routing.
7. Apply I2E recursively to workflow/flow-mesh execution.

Backward compatibility MAY be maintained only through adapters. Before phase 1,
reconcile rather than duplicate SE-386 laws/capabilities, SE-393 contracts,
SE-394/396 execution integrity, SE-397 SAM and SE-400 kernel boundaries.

## 15. Acceptance criteria

The spec is implemented only when:

1. Savia has explicit Reasoner, DecisionProvider, AuthorityEngine, Executor and Verifier contracts.
2. Decision cannot directly invoke Executor.
3. Executor accepts only valid authority evidence where authority is required.
4. Confidence cannot alter authority.
5. Existing model/provider integrations operate through adapters.
6. Deterministic and probabilistic DecisionProviders swap without orchestration changes.
7. A human decision/approval path uses the same semantic contracts.
8. Execution completion cannot mark success before verification.
9. Effects are independent from tool calls.
10. Verifier may use a provider different from Executor.
11. Recovery starts from verified state, not conversation continuation.
12. Replanning invalidates authorization when action/effect scope changes.
13. Evidence reconstructs the complete Intent → Effect lifecycle.
14. Nested execution cannot bypass authority.
15. Flow nodes consume verified Effects/Evidence, not only free text.
16. Existing Savia L4 gates remain fail-closed.
17. Provider replacement requires no AEK semantic primitive changes.

## 16. Mandatory negative tests

```text
decision_without_authority               → BLOCK
high_confidence_without_authority        → BLOCK
stale_authorization                      → BLOCK
modified_action_after_authorization      → BLOCK
modified_effect_after_authorization      → BLOCK
execution_success_without_verification   → NOT_SUCCESS
failed_verification                      → FAIL_OR_RECOVER
nested_agent_without_authority           → BLOCK
provider_attempts_authority_elevation    → BLOCK
reasoner_direct_tool_execution           → BLOCK
decision_provider_direct_tool_execution  → BLOCK
unverified_checkpoint_recovery           → BLOCK
```

## 17. Architectural laws

- **LAW-I2E-01:** Intelligence may propose. It may not self-authorize.
- **LAW-I2E-02:** A decision is not a permission.
- **LAW-I2E-03:** Confidence is not authority.
- **LAW-I2E-04:** Execution is not evidence of success.
- **LAW-I2E-05:** Effects, not tools, define semantic execution.
- **LAW-I2E-06:** Only verified state may become recovery state.
- **LAW-I2E-07:** Authority is scoped to an action and expected effect.
- **LAW-I2E-08:** Providers are replaceable; semantics are stable.
- **LAW-I2E-09:** Governance controls the loop, not the model.
- **LAW-I2E-10:** Every material effect is attributable to Intent, Authority and Evidence.

## 18. Example: production deployment

Intent: deploy payments 4.2.1 while preserving SLO. Reasoning observes 4.2.0,
green CI and verified staging. Candidate A deploys; B waits; C requests evidence.
Decision selects A. Authority requires L4 while the runtime has L2, producing
`REQUIRES_APPROVAL`. An authorized human approves. ArgoCD executes. Independent
verification checks sync state, 10/10 healthy pods, error rate and version
endpoint. Only `VERIFIED` produces `STOP_SUCCESS` and an I2E receipt.

Replacing ArgoCD with Kubernetes, Terraform or a human changes only the executor
adapter, not lifecycle or semantics.

## 19. Definition and strategic consequence

**Intent-to-Effect Architecture (I2E)** is a provider-agnostic execution
architecture in which intent becomes verifiable effect through explicitly
separated reasoning, decision, authority, execution, verification and evidence.

Savia acts as governed I2E runtime. AEK defines stable semantic and governance
primitives. Agents, LLMs, prompts, tool calls and vendors are replaceable
mechanisms. The stable enterprise execution unit is a governed, observable and
auditable transformation from Intent to verified Effect, recursively composable
into tasks, workflows, agentic loops, flow meshes, departments and operating
processes.

## 20. Planning gates and stop conditions

This proposal does not approve implementation. Before code:

- reconcile the existing contracts and publish a no-duplication map;
- identify the canonical repositories and ownership boundary for AEK (its source
  repository is not present in this workspace checkout);
- approve which primitives belong to AEK versus Savia runtime;
- define migration slices, test mapping and rollback without weakening L4;
- obtain explicit human approval of the reconciled executable delta.

STOP on unresolved ownership, a second authority/policy truth, provider leakage
into semantic contracts, an incompatible recovery model or any L4 regression.

## 21. Reconciliation map and absorbed delta — 2026-09-23

This section satisfies the pre-code no-duplication step; it does not approve L4
implementation.

| I2E responsibility | Reuse from | New delta | Owner candidate |
|---|---|---|---|
| Laws, principal, capability, policy and authority vocabulary | SE-386 and AEK | Action/effect-scoped authorization validity | AEK |
| Adapter descriptor, execution request, lease, cancellation and observation | SE-393–396 | AuthorizedAction boundary and effect-aware receipt | Savia Runtime |
| Runtime/surface/provider separation | SE-397/398/400 | Decision/verification provider roles without vendor primitives | Savia Runtime + SAM projection |
| Evidence and content-bound review receipts | SE-260/387/396 | Complete I2E evidence chain and terminal transition | Savia Runtime |
| Recovery and retries | SE-387/394/396 | Only verified checkpoints may resume; replan invalidates authority | Savia Runtime governed by AEK policy |
| Flow composition | existing Savia Flow contracts | Verified effects/evidence on edges and scoped child intent | Savia Runtime; AEK semantics |

The first executable delta SHALL also distinguish typed refusal/failure causes:
authority refusal, provider refusal, transport failure, malformed envelope and
inconclusive assessment cannot collapse into one generic error. Assessment
failure is fail-closed and MUST NOT produce a low-risk decision. Review
candidates, when used as evidence, are frozen once, corrected within an
explicit budget and closed by a terminal receipt; this reuses SE-260 rather
than creating a second review lifecycle.

Unresolved gate: the canonical AEK repository and final ownership of
Intent/Effect/Evidence primitives are still not available in this checkout.
Consequently no new I2E runtime implementation begins until the operadora
approves this ownership table against AEK. Existing SE-396 authority work is a
reused prerequisite, not an implicit approval of SE-401.
