---
spec_id: SE-396-A01
title: CLI-managed adapter substitution for Savia Bridge
status: APPROVED
implementation_state: A01B_IMPLEMENTED_PENDING_HUMAN_REVIEW
parent: SE-396
approval: "Inherited from SE-396 approval recorded in planning-state.json"
date: 2026-09-22
---

# SE-396 A01 — CLI-managed adapter substitution

## Objective

Remove the Claude executable from the stable bridge path. Savia Bridge selects an
explicit CLI-managed adapter, while each adapter owns discovery, arguments,
native session identity and event translation. Unavailable or unobserved adapters
remain `NOT_VERIFIED`; a fixture never certifies operational substitution.

## Verified discovery

| Candidate | Local version | Observation | Classification |
|---|---:|---|---|
| Codex | 0.155.1 | Ephemeral read-only probe emitted `thread.started`, `turn.started`, `item.completed(agent_message)` and `turn.completed(usage)` | Start stream `VERIFIED`; operational receipt not persisted in repo |
| Codex resume | 0.155.1 | Resume of the ephemeral `thread_id` failed with `no rollout found` | Ephemeral resume `UNSUPPORTED`; persistent mode required |
| OpenCode | 1.18.32 | `run --help` exposes `--format json`, `--session`, `--pure`, `--dir`; bounded probe produced no observable stream/result | Contract declared; execution `NOT_VERIFIED` |
| Claude | unavailable | Existing bridge adapter calls `claude -p --output-format stream-json` directly | Legacy compatibility; current environment `NOT_VERIFIED` |

No prompt, response, session identifier, credential or private path from these
probes is stored in tracked output.

## Stable bridge contract

The bridge consumes only this logical interface:

```text
CliManagedAdapter.describe() -> AdapterDescriptor
CliManagedAdapter.preflight() -> AVAILABLE | NOT_VERIFIED | UNAVAILABLE
CliManagedAdapter.start(BridgeRequest) -> NativeProcess
CliManagedAdapter.resume(BridgeRequest, NativeSessionRef) -> NativeProcess
CliManagedAdapter.translate(json_line) -> TranslationBatch
CliManagedAdapter.cancel(NativeProcess) -> CancelReceipt
```

`TranslationBatch` contains normalized events plus an optional adapter-scoped
native session reference. `BridgeRequest` contains message, optional system prompt, bridge session ID,
working directory, authority ceiling and request ID. It contains no provider-
specific flags. `NativeSessionRef` is adapter-scoped; bridge session IDs are never
assumed to equal Codex thread IDs, OpenCode session IDs or Claude session IDs.

Normalized `BridgeEvent.type` is one of `text`, `tool_use`,
`permission_request`, `error`, `done`. Provider-native events may be retained only
as opaque diagnostics. Hidden reasoning is ignored and never used as evidence.

## Selection and fail-closed rules

1. Selection is explicit through `--cli-adapter`; default `claude` preserves
   compatibility until a separate human-reviewed migration changes it.
2. Server startup validates only the selected adapter. Selecting Codex or
   OpenCode must not call `find_claude_cli`.
3. Unknown adapter, missing binary, malformed JSON, missing native session ID,
   unsupported resume or process failure returns `NOT_VERIFIED`/error and never a
   successful `done` event.
4. Adapters may not add unsafe approval flags. Codex uses a declared sandbox;
   OpenCode never adds `--auto`; Claude retains its existing permission relay.
5. Provider/model identity remains unknown unless the native stream exposes it;
   executable name or configured alias is not evidence of provider identity.
6. Cancellation acknowledges only process termination request, not absence of an
   external effect. Retry follows existing ambiguous-effect safeguards.

## Vertical slices

### A01a — Contract and parsers

Add one adapter module and contract tests using captured synthetic JSON lines.
Codex parsing is based on the verified event names above. OpenCode parsing remains
`NOT_VERIFIED` until an observed stream is available; its parser must reject
unknown shapes rather than guess.

### A01b — Bridge injection

Add `--cli-adapter`, inject the selected adapter into non-interactive chat, and
remove unconditional Claude discovery at startup. Interactive permission relay
stays Claude-only and fails explicitly for adapters that do not implement it.

### A01c — Operational certification

Run the same non-sensitive L2 start/stream/cancel/resume scenario through two
installed adapters. Persist metadata-only receipts with adapter/version/outcome;
no prompts, responses, credentials or native session IDs. Two independent
`VERIFIED` results are required before closing A01/H09.

## Acceptance criteria

- **AC-01:** Selecting Codex with Claude absent reaches Codex discovery and never
  calls the Claude finder.
- **AC-02:** Codex JSONL maps agent messages to `text`, usage completion to
  `done`, and preserves its native thread reference outside the bridge ID.
- **AC-03:** Ephemeral Codex resume is rejected before execution as unsupported.
- **AC-04:** Selecting OpenCode never adds `--auto`; without an observed stream
  its operational status remains `NOT_VERIFIED`.
- **AC-05:** Malformed/unknown native events emit an error and cannot synthesize
  success.
- **AC-06:** Default selection remains Claude-compatible; explicit alternative
  selection does not require the Claude binary at startup.
- **AC-07:** Tests do not call providers. Operational certification is a separate
  approval-bearing action and requires two real adapter receipts.
- **AC-08:** A01 remains open until start, stream, cancel and persistent resume
  are verified on two real adapters.

## Test plan

- unit tests for descriptor, discovery, argv safety and JSONL translation;
- negative tests for unknown adapter/event, missing binary/session reference,
  ephemeral resume, unsafe flags and non-zero process exit;
- bridge test proving explicit Codex selection does not invoke Claude discovery;
- operational probe command reviewed separately for each adapter;
- existing `tests/dual-cli` and Savia Bridge suites remain green.

## OpenCode Implementation Plan

- **Tier:** 2 for A01a/A01b; operational A01c requires external-effect approval.
- **Developer type:** agent-single, WIP=1.
- **Bindings:** `scripts/bridge_cli_adapters.py`, `scripts/savia-bridge.py`, one
  focused test module plus generated capability views.
- **Rollback:** remove adapter selection and module; default legacy Claude path is
  preserved until A01c and human review.
- **Stop:** any need to weaken sandbox/approval flags, infer provider identity,
  or claim a second operational adapter without a real receipt.

## Non-goals

- Direct provider APIs or another model gateway.
- Provider/model routing (A02).
- Domain-pack composition (A03/H10).
- Automatic change of the default adapter.
- Claiming complete SE-396 or I2E implementation.

## A01a implementation record — 2026-09-22

Implemented the inert adapter boundary, safe command builders and Codex event
translation. OpenCode event translation deliberately returns `NOT_VERIFIED`.
Eleven focused tests pass without invoking a provider. The broader dual-cli suite
could not bind Unix sockets under the current sandbox; those environment failures
do not certify or invalidate A01a. A01b/A01c and A01/H09 closure remain open.

## A01b implementation record — 2026-09-22

A01a entered `main` through PR #1133. A01b adds explicit `--cli-adapter`
selection while retaining Claude as the compatibility default. Startup preflights
only the selected adapter; Codex can therefore start without Claude discovery.
Non-interactive chat uses the normalized adapter stream and keeps the Codex
thread reference separate from the bridge session ID.

Unknown events, missing completion, unavailable adapters and non-zero exits do
not emit `done`. OpenCode selection remains `NOT_VERIFIED`, and interactive
permission relay is rejected outside Claude. Twenty focused tests pass without
provider calls. A01c and operational closure of A01/H09 remain open.
