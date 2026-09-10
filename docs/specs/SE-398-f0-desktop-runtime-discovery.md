---
id: SE-398-F0
parent: SE-398
status: READY_FOR_HUMAN_REVIEW
created: 2026-09-10
evidence_type: static-and-official-documentation-reconciliation
head: 8cf6c4bf3e3c38f6902df7ad55472674d860f016
---

# SE-398 F0 — Desktop Runtime Discovery

## Estado

F0 completado. No se ha implementado SAM F1 ni adapters Desktop. La evidencia
combina repo en `8cf6c4bf`, probes locales no destructivos y documentación
oficial consultada el 2026-09-10. `AVAILABLE` o documentación de vendor no se
trata como evidencia operacional Savia.

| Campo | Valor |
|---|---|
| HEAD | `8cf6c4bf3e3c38f6902df7ad55472674d860f016` |
| Spec ID | `SE-398`, libre antes de persistir |
| Spec path | `docs/specs/SE-398-desktop-runtime-surface-support.spec.md` |
| SAM state | F0 de SE-397 aprobado; SAM F1 todavía no existe |
| Veredicto | `GO_WITH_CONCERNS` para F1 read-only; cero surfaces graduadas |

## Runtime family: OpenCode

| Área | Evidencia / clasificación |
|---|---|
| Existing adapter | `scripts/opencode-plugin/savia-gates/`, `.opencode/plugins/savia-foundation.ts`, `scripts/opencode-install.sh`, config `.opencode/` |
| Existing support | TUI con plugin y bindings parciales; `EXISTING_BUT_INCOMPLETE` |
| Desktop architecture | Vendor: Desktop levanta sidecar/server local o conecta a server externo; server/client compartido |
| Shared primitives | agents, skills, permissions, shell/edit/read, plugins, MCP, sessions y server API están documentados a nivel runtime |
| Desktop deltas | sidecar lifecycle, server picker/URL, WebView, PATH/env/cwd, OS sandbox/permissions, cache/app state y restart |
| Agents | 89 projections bajo `.opencode/agents`; discovery runtime existente; Desktop no verificado |
| Skills | `.opencode/skills -> ../.claude/skills`; vendor soporta discovery lazy; Desktop no ejecutado |
| Instructions | AGENTS.md generado; carga Desktop no probada |
| Hooks | plugin TS con manifest/permission/shell bridge; equivalencia de todos los hooks crítica aún no existe |
| Permissions | runtime rules existen; no sustituyen authority Savia |
| Shell/filesystem/sandbox | runtime disponible; surface/env/envelope no medidos |
| MCP | runtime documentado y config existente; Desktop Savia `NOT_VERIFIED` |
| Sessions/parallelism | server/session primitives documentadas; cancel/restart/concurrency Savia `UNKNOWN` |
| Known gaps | reconciliar los dos mecanismos plugin, surface detector, manifest/deltas, provenance, doctor, canaries y receipts surface-aware |
| Critical unknowns | fail-closed real de Shield/plugin ante sidecar/restart, remote server trust, secret boundary y lifecycle |
| Recommended projection | reutilizar adapter OpenCode; añadir solo `OpenCodeDesktopProjection` de deltas |

La documentación oficial confirma que la TUI es cliente de un server, Desktop
usa un sidecar/server local y puede conectar a un server WSL. También advierte
que exponer WSL en `0.0.0.0` requiere autenticación. Fuentes:
[Server](https://dev.opencode.ai/docs/server/),
[Desktop troubleshooting](https://dev.opencode.ai/docs/troubleshooting/),
[Windows/WSL](https://opencode.ai/docs/de/windows-wsl/),
[skills](https://opencode.ai/docs/skills) y
[MCP](https://opencode.ai/v2/docs/mcp-servers).

## Runtime family: Claude Code

| Área | Evidencia / clasificación |
|---|---|
| Existing adapter | `.claude/settings.json`, hooks Bash, agents/skills/commands y scripts |
| Existing support | CLI es frontend histórico; executable Claude ausente en entorno F0 |
| Desktop architecture | Vendor ofrece Claude Code dentro de Desktop y distingue local, cloud y remote-control |
| Shared primitives | documentación afirma Claude Code sessions y plugins/MCP; equivalencia con CLI no demostrada |
| Desktop deltas | GUI process, folder grants, local/cloud mode, built-in browser/computer use, app lifecycle/update |
| Agents/subagents/skills/commands | assets del repo abundantes; discovery/invocation Desktop `NOT_VERIFIED` |
| Instructions | CLAUDE.md y nested rules son canonical projection histórica; Desktop no probado |
| Hooks | SessionStart, UserPromptSubmit, PreToolUse y PostToolUse configurados para CLI; Desktop coverage `UNKNOWN` |
| Permissions/shell/filesystem/sandbox | dependen de local/cloud mode; no inferir desde CLI |
| MCP | Desktop extensions/local MCP y remote connectors existen; Savia MCP parity no probada |
| Sessions/parallelism | local, cloud, teleport/remote control documentados; correlation/authority inheritance no probadas |
| Known gaps | detector de mode, manifest surface, hook canaries, provenance y remote-effect governance |
| Critical unknowns | si todos los critical hooks interceptan local Desktop; cloud/remote puede evitar hooks locales |
| Recommended projection | Claude runtime adapter compartido solo tras probar contrato; separar local/cloud projections |

Fuentes oficiales: [Claude Code power-user tips](https://support.claude.com/en/articles/14554000-claude-code-power-user-tips),
[Claude Code web](https://support.claude.com/en/articles/12618689-claude-code-on-the-web),
[Desktop deep links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link)
y [desktop/local connectors](https://support.claude.com/en/articles/11725091-when-to-use-desktop-and-web-connectors).

## Runtime family: Codex

| Área | Evidencia / clasificación |
|---|---|
| Existing adapter | AGENTS.md, `.agents/skills`, SE-388/391, `scripts/dual-cli/`, canaries y doctor |
| Current ceiling | `DEGRADED_SAFE`, máximo verificado L2; L3/L4 blocked-or-human-reroute |
| Local probe | `codex-cli 0.153.4`; no se ejecutó Desktop corpus |
| Desktop architecture | documentación oficial actual presenta Desktop como superficie local con projects/threads, worktrees, skills y sandbox; config/historial compartidos |
| Desktop deltas | app lifecycle, integrated worktrees, UI approval, automations, local/cloud handoff y OS-specific sandbox |
| Agents/skills/instructions | AGENTS y skill symlink existen; Desktop invocation/nested refresh `NOT_VERIFIED` |
| Hooks/equivalent | no hay equivalencia probada de PreToolUse para efectos críticos; gap de SE-388 permanece |
| Permissions/shell/filesystem/sandbox | sistema local impone workspace-write/network boundaries; no eleva Savia ceiling |
| MCP/plugins | capacidad de producto documentada; Savia correlation/enforcement `NOT_VERIFIED` |
| Sessions/parallelism | threads/worktrees paralelos disponibles; parent-child authority y receipt correlation desconocidos |
| Availability | fuentes oficiales abiertas confirman macOS/Windows; Linux Desktop queda `NOT_VERIFIED` en F0 |
| Known gaps | runtime/surface manifest, native-effect projection, doctor surface-aware y operational receipts |
| Critical unknowns | pre-effect enforcement, external effects, remote/cloud governance, child authority y update drift |
| Recommended projection | reutilizar SE-388/391 y dual-cli; ceiling Desktop <= ceiling runtime |

Fuentes oficiales OpenAI:
[Codex developer documentation](https://developers.openai.com/codex/) y
[ChatGPT desktop app documentation](https://learn.chatgpt.com/docs/app). La documentación
oficial accesible no demuestra equivalencia operacional Savia; por ello el
estado permanece `UNASSESSED/NOT_VERIFIED`.

## Canonical effect coverage

| Efecto | Claude CLI | OpenCode TUI | Codex CLI | Desktop conclusion |
|---|---|---|---|---|
| READ_WORKSPACE | implemented | implemented | L0-L2 verified | las tres Desktop `NOT_VERIFIED` |
| WRITE_WORKSPACE | PreToolUse path | plugin path parcial | governed/rerouted hasta L2 | no surface PASS |
| EXECUTE_LOCAL | Bash hooks | shell bridge | sandbox/approval | no semantic parity demostrada |
| ACCESS_SECRET | Shield/hooks | Shield/plugin | native boundary + Savia rules | critical Desktop unknown |
| CALL_MCP | configured | runtime capable | evaluated/partial | Savia correlation pendiente |
| EXTERNAL_EFFECT | human policy | adapter/policy | blocked/reroute | ninguna Desktop autorizada |
| SHARED_STATE | parallel protocol | partial | worktrees disponibles | concurrency corpus pendiente |
| HUMAN_DECISION | canonical human gates | permission projection | approval UI | receipt correlation pendiente |

## Reuse

- Existing mechanisms: laws/human-control, risk tiers, operator grants,
  `dual-cli`, OpenCode plugin y Claude hooks.
- Existing canaries: `codex-day1-canaries.sh`,
  `codex-autonomy-canaries.sh`, `opencode-monthly-canary.sh`,
  agent-degradation and harness/chaos suites.
- Existing doctor: `workspace-doctor.sh` + `dual-cli/autonomy_doctor.py`.
- Existing generators: AGENTS and skill symlinks; `.scm` capability map.
- Existing evidence: receipts/audits/observations are reusable by reference.
- Existing SAM entities: none machine-readable yet; only SE-397 F0 design.

## Do not duplicate

Policy/laws, authority grants, agents/skills, `.scm`, dual-cli contracts,
OpenCode plugin, Claude hooks, receipts, doctor/canaries, planning or evidence
stores. Surface manifests must be deltas, not copies of runtime manifests.

## Gaps and blockers

**New gaps:** minimal SAM runtime/surface schema, manifest schema/validator,
canonical effect projection, evidence freshness and semantic matrix generator.

**Surface-specific:** sidecar/GUI env, lifecycle, updates, local/cloud/remote,
native approval and app sandbox. **Runtime-specific:** missing pre-effect
equivalent in Codex, OpenCode V1/V2 drift and Claude Desktop hook semantics.

**Security blockers:** Shield/plugin unavailable behavior on each Desktop,
secret visibility, remote effects, server authentication and update drift.
**Authority blockers:** native UI approvals lack canonical decision receipts;
Codex remains capped L2; child-agent inheritance is unverified.

## F1 minimum slice

Create a read-only schema/projection under `.scm/` for Runtime, Surface,
NativePrimitive, CanonicalEffect, Projection and VerificationState; three
runtime manifests plus six delta-only surface manifests; deterministic
validator/tests for inheritance, unknown states, provenance and no policy
ownership. No runtime execution, enforcement or support claim.

Estimated complexity: medium, two or three independent slices after human
review and after reconciling the exact SE-397 F1 schema.

## Human decisions required

1. Approve this F0 and the proposed F1 slice.
2. Decide whether SE-397 F1 and SE-398 F1 are one shared schema change.
3. Decide how to name current OpenAI Desktop surface given the official
   product documentation transition; do not mint a false compatibility claim.
4. Retain Codex L2 ceiling and all Desktop states below SUPPORTED until
   operational canaries and graduation.

## Verdict

`GO_WITH_CONCERNS` for a read-only F1 integrated with SE-397. OpenCode Desktop
has the clearest runtime/surface split. Claude local/cloud and Codex
pre-effect/authority paths contain critical unknowns. No Desktop is SUPPORTED.
