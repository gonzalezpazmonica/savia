// savia-foundation.ts — SPEC-127 Slice 2b-i (foundation) + Slice 2b-ii (hooks wired)
// Extended by SPEC-OC-01 (Savia Shield OpenCode adaptation)
//
// OpenCode v1.14 plugin for Savia. Registers tool.execute.before and
// tool.execute.after dispatchers that run safety guards in order.
// Each guard is a pure async function imported from its own module.
//
// Provider-agnostic by construction (PV-06): the guards branch on tool
// name and command/file content, never on a hardcoded vendor name. They
// preserve the bash hook semantics 1:1 while taking advantage of TS types.
//
// Guard execution order (tool.execute.before):
//   Cheap → expensive. Throwing aborts the chain.
//   1. validate-bash-global   (regex on bash command, ~0ms)
//   2. auto-redact-credentials    (SPEC-142: mutate args.command, ~0ms)
//   3. block-credential-leak  (regex on bash command, ~0ms)
//   3. block-force-push       (regex on git commands, ~0ms)
//   4. data-sovereignty-gate  (regex + base64 + daemon/fallback, ~0ms-2s)
//   5. block-gitignored-refs  (regex on edit/write content, ~0ms)
//   6. prompt-injection-guard (content scan on context-classified files, ~0ms)
//   7. tdd-gate               (filesystem probe, the most expensive, ~10-50ms)
//
// Guard execution order (tool.execute.after):
//   Non-blocking audit, best-effort.
//   1. data-sovereignty-audit (re-scans written file, ~0-50ms)
//   2. edit-ledger-record     (SE-402, path + sha256 to ~/.savia/edits, ~5ms)
//
// Reference: SPEC-127 Slice 2b-i + 2b-ii
// Reference: SPEC-OC-01 (Savia Shield adaptation)
// Reference: docs/rules/domain/provider-agnostic-env.md

import { toV1After, toV1Before } from "./lib/v2-compat.ts";

import { validateBashGlobal } from "./guards/validate-bash-global.ts";
import { autoRedactSecrets } from "./guards/auto-redact-credentials.ts";
import { blockCredentialLeak } from "./guards/block-credential-leak.ts";
import { blockForcePush } from "./guards/block-force-push.ts";
import { applyModelTiers } from "./lib/model-tiers.ts";
import { blockBranchSwitchDirty } from "./guards/block-branch-switch-dirty.ts";
import { blockCommitToMain } from "./guards/block-commit-to-main.ts";
import { blockInfraDestructive } from "./guards/block-infra-destructive.ts";
import { toolCallHealing } from "./guards/tool-call-healing.ts";
import { dataSovereigntyGate } from "./guards/data-sovereignty-gate.ts";
import { blockGitignoredReferences } from "./guards/block-gitignored-references.ts";
import { promptInjectionGuard } from "./guards/prompt-injection-guard.ts";
import { tddGate } from "./guards/tdd-gate.ts";
import { dataSovereigntyAudit } from "./guards/data-sovereignty-audit.ts";
// SE-405 Slice 2: snapshot of watched config files before edit/write
import { configSnapshot } from "./guards/config-snapshot.ts";
// SE-402: attributed edit ledger (path + hash, never content)
import { editLedgerRecord } from "./guards/edit-ledger-record.ts";
import { autoGrillMe } from "./guards/auto-grill-me.ts";
import { autoZoomOut } from "./guards/auto-zoom-out.ts";
// SE-221: context-engineering guards (port of bash hooks)
import { contextOriginStamp } from "./guards/context-origin-stamp.ts";
import { contextDropAfterUse } from "./guards/context-drop-after-use.ts";
import { subagentAudienceFilter } from "./guards/subagent-audience-filter.ts";
// SPEC-150 Slice 2: sycophancy detection (TS port of sycophancy-strip.sh)
import { sycophancyGuard } from "./guards/sycophancy-guard.ts";
// SE-229: block blind signing of confidentiality signature without prior audit
import { blockBlindSigning } from "./guards/block-blind-signing.ts";
// SE-313 S7c: dispatch tracing — resolves subagent model + emits telemetry
import { dispatchTrace } from "./guards/dispatch-trace.ts";
// SCL-003/SCL-008: inject human-authorized criteria at chat.message
import { learningRecallGuard } from "./guards/learning-recall-guard.ts";
import { runGuardsOnVariants } from "./lib/sandbox.ts";

const BEFORE_GUARDS = [
  // Cheap guards first — fail fast.
  toolCallHealing,
  validateBashGlobal,
  autoRedactSecrets,
  blockCredentialLeak,
  blockForcePush,
  blockBranchSwitchDirty,
  blockCommitToMain,
  blockInfraDestructive,
  dataSovereigntyGate,
  blockGitignoredReferences,
  promptInjectionGuard,
  tddGate,
  // SE-229: confidentiality signature must follow real audit, not CI shortcuts
  blockBlindSigning,
  // SE-091: caveman always-on reminders (non-blocking)
  autoGrillMe,
  autoZoomOut,
  // SE-221 Slice 3: audience filter (PreToolUse `task`, non-blocking audit)
  subagentAudienceFilter,
  // SE-313 S7c: dispatch tracing (PreToolUse `task`, non-blocking telemetry)
  dispatchTrace,
  // SE-405 Slice 2: last, so a blocked edit never snapshots (never throws)
  configSnapshot,
] as const;

const AFTER_GUARDS = [
  dataSovereigntyAudit,
  // SE-402: record successful edit/write in the attributed edit ledger
  editLedgerRecord,
  // SE-221 Slice 1: stamp origin block on long Read outputs
  contextOriginStamp,
  // SE-221 Slice 2: drop/stub/keep decision on long Read/WebFetch/Bash outputs
  contextDropAfterUse,
  // SPEC-150 Slice 2: adulation detection (shadow mode by default, non-blocking)
  sycophancyGuard,
] as const;

// ── Shared runners ───────────────────────────────────────────────────────────

async function runBeforeGuards(input: any, output: any): Promise<void> {
  // Si un plugin de sandbox ya envolvió la orden, los guards ven también la de dentro.
  await runGuardsOnVariants(BEFORE_GUARDS, input, output);
}

async function runAfterGuards(input: any, output: any): Promise<void> {
  for (const guard of AFTER_GUARDS) {
    try {
      await guard(input, output);
    } catch {
      // After-guards are non-blocking — errors are logged internally
      // but must not surface as tool failures
    }
  }
}

// ── V2 adapter (SPEC-OC2-01) ────────────────────────────────────────────────
//
// V2 exige un default export con `id` + `setup(ctx)`. Los hooks se registran
// por dominio (`ctx.tool.hook`, `ctx.session.hook`) y reciben un único evento.
// `lib/v2-compat.ts` traduce el evento al par (input, output) que usan los guards.

async function setupV2(ctx: any): Promise<void> {
  const register = async (domain: "tool" | "session", name: string, cb: (event: any) => Promise<void> | void) => {
    try {
      const target = domain === "session" ? ctx?.session : ctx?.tool;
      if (target && typeof target.hook === "function") await target.hook(name, cb);
    } catch {
      // Un runtime sin ese hook no debe romper el arranque.
    }
  };

  await register("tool", "execute.before", async (event: any) => {
    const { input, output } = toV1Before(event);
    await runBeforeGuards(input, output);
    // Los guards pueden sustituir args (redacción); propaga la copia si la hubo.
    if (event && output.args && event.input !== output.args && typeof event.input === "object") {
      event.input = output.args;
    }
  });

  await register("tool", "execute.after", async (event: any) => {
    const { input, output } = toV1After(event);
    await runAfterGuards(input, output);
  });

  await register("session", "prompt", async (event: any) => {
    try {
      await learningRecallGuard({ tool: "chat.message" } as any, event);
    } catch {
      // Non-blocking: a recall failure must never break message flow
    }
  });

  // Saneamiento: V2 copia claves desconocidas de un agente a request.body
  // (p. ej. `model_tier`). Se eliminan antes de enviar la petición.
  await register("session", "model.request", (event: any) => {
    const body = event?.body;
    if (body && typeof body === "object") {
      for (const key of Object.keys(body)) {
        if (key === "model_tier" || key.startsWith("x_savia_")) delete body[key];
      }
    }
  });
}

// ── V1 adapter (OpenCode 1.18.29+) ─────────────────────────────────────────
//
// Ojo: V1 < 1.18.29 solo acepta export de función. Savia soporta el formulario
// objeto desde 1.18.29; para OpenCode 1 más antiguo existe
// `savia-foundation.v1-legacy.ts` (documentado en el plan de adaptación).

async function serverV1(runtime: any): Promise<Record<string, any>> {
  const directory = runtime?.directory ?? process.cwd();
  return {
    config: (cfg: any) => {
      // Provider-agnostic tiers: model_tier → local tier definition.
      applyModelTiers(cfg, directory);
    },
    "tool.execute.before": runBeforeGuards,
    "chat.message": async (input: any, output: any) => {
      try {
        await learningRecallGuard(input, output);
      } catch {
        // Non-blocking: a recall failure must never break message flow
      }
    },
    "tool.execute.after": runAfterGuards,
  };
}

const SaviaFoundation = {
  id: "savia-foundation",
  setup: setupV2,
  server: serverV1,
};

export default SaviaFoundation;
