// before-guards.ts — guards de tool.execute.before de savia-foundation, en orden.
//
// SE-510 AC-7: módulo aparte para que la paridad de veredictos con los hooks bash
// (.opencode/plugins/__tests__/guard-corpus-cli.ts) use exactamente la misma lista
// que el plugin, sin añadir exports con nombre a savia-foundation.ts.

import { validateBashGlobal } from "../guards/validate-bash-global.ts";
import { autoRedactSecrets } from "../guards/auto-redact-credentials.ts";
import { blockCredentialLeak } from "../guards/block-credential-leak.ts";
import { blockForcePush } from "../guards/block-force-push.ts";
import { blockBranchSwitchDirty } from "../guards/block-branch-switch-dirty.ts";
import { blockCommitToMain } from "../guards/block-commit-to-main.ts";
import { blockInfraDestructive } from "../guards/block-infra-destructive.ts";
import { toolCallHealing } from "../guards/tool-call-healing.ts";
import { dataSovereigntyGate } from "../guards/data-sovereignty-gate.ts";
import { blockGitignoredReferences } from "../guards/block-gitignored-references.ts";
import { promptInjectionGuard } from "../guards/prompt-injection-guard.ts";
import { tddGate } from "../guards/tdd-gate.ts";
import { configSnapshot } from "../guards/config-snapshot.ts";
import { autoGrillMe } from "../guards/auto-grill-me.ts";
import { autoZoomOut } from "../guards/auto-zoom-out.ts";
import { subagentAudienceFilter } from "../guards/subagent-audience-filter.ts";
import { blockBlindSigning } from "../guards/block-blind-signing.ts";
import { dispatchTrace } from "../guards/dispatch-trace.ts";

export const BEFORE_GUARDS = [
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
