# Hooks Coverage Matrix — SE-253 Slice 2

> Auto-generated. Do not edit by hand. Run: `bash scripts/hooks-coverage-matrix.sh`

## Summary

| Total hooks | TS Guards | Git Hook mitigated | CI Job mitigated | NONE |
|---|---|---|---|---|
| 122 | 18 (14.8%) | 4 | 5 | 95 |

## Bloqueantes sin cobertura ni mitigacion

Ninguno — AC-2.2 satisfecho.

## Cobertura real OpenCode

- **TS Guards activos**: 18/122 (14.8%)
- **Hooks sin cobertura TS**: 95 (77.9%)
  - De los cuales son bloqueantes sin ninguna mitigacion: 0
  - Eventos no disponibles en OpenCode (degradacion aceptada): 33

## Full matrix

| event | hook | portado_ts | cobertura | criticidad | mitigacion |
|---|---|---|---|---|---|
| ConfigChange | config-reload.sh | no | NONE | telemetria | evento ConfigChange no disponible en OpenCode — degradacion_documentada |
| CwdChanged | cwd-changed-hook.sh | no | NONE | telemetria | evento CwdChanged no disponible en OpenCode — degradacion_documentada |
| FileChanged | file-changed-staleness.sh | no | NONE | telemetria | evento FileChanged no disponible en OpenCode — degradacion_documentada |
| InstructionsLoaded | instructions-tracker.sh | no | NONE | telemetria | evento InstructionsLoaded no disponible en OpenCode — degradacion_documentada |
| PostCompact | post-compaction.sh | no | NONE | warning | evento PostCompact no disponible en OpenCode — degradacion_documentada |
| PostToolUse | sycophancy-strip.sh | si | TS_GUARD | bloqueante | sycophancyGuard |
| PostToolUse | agent-trace-log.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | bash-output-compress.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | cognitive-debt-check.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | cognitive-debt-telemetry.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | competence-tracker.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | context-drop-after-use.sh | si | TS_GUARD | telemetria | contextDropAfterUse |
| PostToolUse | context-origin-stamp.sh | si | TS_GUARD | telemetria | contextOriginStamp |
| PostToolUse | criterion-simulation-challenge.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | data-sovereignty-audit.sh | si | TS_GUARD | telemetria | dataSovereigntyAudit |
| PostToolUse | decision-trace-capture.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | discovery-order-telemetry.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | dual-estimation-gate.sh | no | CI_JOB | telemetria | CI validate-ci-local.sh |
| PostToolUse | fronesis-gate-reminder.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | judge-auto-router.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | learning-capture-hook.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | live-progress-emitter.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | memory-auto-capture.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | memory-feedback-task.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | output-verbosity-sentinel.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | pbi-history-capture.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | post-report-write.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | post-spec-edit-reindex.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | repeat-tool-guard.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | router-mode-dispatch.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | speculative-skill-preload.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | token-tracker-middleware.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PostToolUse | acm-turn-marker.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUse | ast-quality-gate-hook.sh | no | CI_JOB | warning | CI validate-ci-local.sh |
| PostToolUse | bus-factor-warn.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUse | compress-agent-output.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUse | memory-origin-gate.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUse | post-digestion-kg-extract.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUse | post-edit-lint.sh | no | CI_JOB | warning | CI validate-ci-local.sh |
| PostToolUse | post-write-validate.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUse | propuestas-index-refresh.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUse | speculative-pre-execute.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUse | twin-posttooluse.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PostToolUseFailure | post-tool-failure-log.sh | no | NONE | telemetria | evento PostToolUseFailure no disponible en OpenCode — degradacion_documentada |
| PreCompact | pre-compact-backup.sh | no | NONE | warning | evento PreCompact no disponible en OpenCode — degradacion_documentada |
| PreToolUse | acm-enforcement.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; ACM enforcement no portado — candidato SE-254 |
| PreToolUse | agent-dispatch-validate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; agent dispatch sin gate en OpenCode — candidato SE-254 |
| PreToolUse | agent-git-discipline.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code |
| PreToolUse | agent-hook-premerge.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; pre-merge gate no portado en OpenCode |
| PreToolUse | agent-tool-call-validate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; tool call validation en OpenCode via toolCallHealing TS (parcial) |
| PreToolUse | android-adb-validate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; adb commands no usados en sesiones OpenCode normales |
| PreToolUse | block-branch-switch-dirty.sh | si | TS_GUARD | bloqueante | blockBranchSwitchDirty |
| PreToolUse | block-credential-leak.sh | si | TS_GUARD | bloqueante | blockCredentialLeak |
| PreToolUse | block-force-push.sh | si | TS_GUARD | bloqueante | blockForcePush |
| PreToolUse | block-gitignored-references.sh | si | TS_GUARD | bloqueante | blockGitignoredReferences |
| PreToolUse | block-infra-destructive.sh | si | TS_GUARD | bloqueante | blockInfraDestructive |
| PreToolUse | block-pat-file-write.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; credenciales write bloqueado via blockCredentialLeak TS (parcial) |
| PreToolUse | block-project-whitelist.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; whitelist check no portado en OpenCode |
| PreToolUse | compliance-gate.sh | no | GIT_HOOK | bloqueante | git pre-commit/pre-push |
| PreToolUse | context-greedy-inject.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; greedy inject no portado en OpenCode |
| PreToolUse | context-preflight-check.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; context preflight no ejecuta en OpenCode |
| PreToolUse | context-sanitize-input.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; input sanitize no portado en OpenCode |
| PreToolUse | data-sovereignty-gate.sh | si | TS_GUARD | bloqueante | dataSovereigntyGate |
| PreToolUse | delegation-guard.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; delegation guard no portado en OpenCode |
| PreToolUse | memory-verified-gate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; memory gate no portado en OpenCode |
| PreToolUse | memory-write-sanitize.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; memory write sanitize no portado en OpenCode |
| PreToolUse | mind-virus-write-gate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code |
| PreToolUse | permission-mode-gate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code |
| PreToolUse | pr-summary-gate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; PR summary validado via git pre-push |
| PreToolUse | project-isolation-gate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; isolation gate no portado en OpenCode |
| PreToolUse | prompt-hook-commit.sh | no | GIT_HOOK | bloqueante | git pre-commit/pre-push |
| PreToolUse | prompt-injection-guard.sh | si | TS_GUARD | bloqueante | promptInjectionGuard |
| PreToolUse | protected-job-guard.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; protected job guard no portado en OpenCode |
| PreToolUse | recursion-guard.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; Task nesting bloqueado via agent-dispatch-validate |
| PreToolUse | responsibility-judge.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; judge no portado en OpenCode |
| PreToolUse | spec156-token-budget-projection.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; budget projection no disponible en OpenCode |
| PreToolUse | tdd-gate.sh | si | TS_GUARD | bloqueante | tddGate |
| PreToolUse | tool-call-healing.sh | si | TS_GUARD | bloqueante | toolCallHealing |
| PreToolUse | validate-bash-global.sh | si | TS_GUARD | bloqueante | validateBashGlobal |
| PreToolUse | validate-layer-contract.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; layer contract no portado en OpenCode |
| PreToolUse | vault-frontmatter-gate.sh | no | NONE | bloqueante | degradacion_documentada: solo Claude Code; vault gate no portado en OpenCode |
| PreToolUse | block-commit-to-main.sh | si | TS_GUARD | telemetria | blockCommitToMain |
| PreToolUse | cognitive-debt-hypothesis-first.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PreToolUse | contract-test-guard.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PreToolUse | live-progress-hook.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PreToolUse | output-effort-router.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PreToolUse | savia-budget-guard.sh | no | NONE | telemetria | degradacion_documentada: solo Claude Code |
| PreToolUse | subagent-audience-filter.sh | si | TS_GUARD | telemetria | subagentAudienceFilter |
| PreToolUse | ast-comprehend-hook.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PreToolUse | auto-grill-me.sh | si | TS_GUARD | warning | autoGrillMe |
| PreToolUse | auto-zoom-out.sh | si | TS_GUARD | warning | autoZoomOut |
| PreToolUse | blast-radius-hook.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PreToolUse | model-tier-inject.sh | no | NONE | warning | degradacion_documentada: solo Claude Code |
| PreToolUse | plan-gate.sh | no | CI_JOB | warning | CI validate-ci-local.sh |
| SessionEnd | cache-hygiene-hook.sh | no | NONE | telemetria | evento SessionEnd no disponible en OpenCode — degradacion_documentada |
| SessionEnd | session-end-memory.sh | no | NONE | telemetria | evento SessionEnd no disponible en OpenCode — degradacion_documentada |
| SessionStart | mind-virus-load-gate.sh | no | NONE | bloqueante | evento SessionStart no disponible en OpenCode — degradacion_documentada |
| SessionStart | cache-hygiene-hook.sh | no | NONE | telemetria | evento SessionStart no disponible en OpenCode — degradacion_documentada |
| SessionStart | emergency-mode-readiness.sh | no | NONE | telemetria | evento SessionStart no disponible en OpenCode — degradacion_documentada |
| SessionStart | session-init.sh | no | NONE | telemetria | evento SessionStart no disponible en OpenCode — degradacion_documentada |
| SessionStart | shield-autostart.sh | no | NONE | telemetria | evento SessionStart no disponible en OpenCode — degradacion_documentada |
| SessionStart | check-daemon-auth.sh | no | NONE | warning | evento SessionStart no disponible en OpenCode — degradacion_documentada |
| Stop | agents-md-auto-regenerate.sh | no | NONE | telemetria | evento Stop no disponible en OpenCode — degradacion_documentada |
| Stop | emotional-regulation-monitor.sh | no | NONE | telemetria | evento Stop no disponible en OpenCode — degradacion_documentada |
| Stop | pre-commit-review.sh | no | GIT_HOOK | telemetria | git pre-commit/pre-push |
| Stop | scope-guard.sh | no | CI_JOB | telemetria | CI validate-ci-local.sh |
| Stop | session-end-snapshot.sh | no | NONE | telemetria | evento Stop no disponible en OpenCode — degradacion_documentada |
| Stop | stop-dod-gate.sh | no | NONE | telemetria | evento Stop no disponible en OpenCode — degradacion_documentada |
| Stop | stop-memory-extract.sh | no | NONE | telemetria | evento Stop no disponible en OpenCode — degradacion_documentada |
| Stop | postponement-judge.sh | no | NONE | warning | evento Stop no disponible en OpenCode — degradacion_documentada |
| Stop | stop-quality-gate.sh | no | GIT_HOOK | warning | git pre-commit/pre-push |
| SubagentStart | subagent-lifecycle.sh | no | NONE | telemetria | evento SubagentStart no disponible en OpenCode — degradacion_documentada |
| SubagentStop | subagent-lifecycle.sh | no | NONE | telemetria | evento SubagentStop no disponible en OpenCode — degradacion_documentada |
| TaskCompleted | task-lifecycle.sh | no | NONE | telemetria | evento TaskCompleted no disponible en OpenCode — degradacion_documentada |
| TaskCreated | task-lifecycle.sh | no | NONE | telemetria | evento TaskCreated no disponible en OpenCode — degradacion_documentada |
| UserPromptSubmit | cache-hygiene-hook.sh | no | NONE | telemetria | evento UserPromptSubmit no disponible en OpenCode — degradacion_documentada |
| UserPromptSubmit | memory-prime-hook.sh | no | NONE | telemetria | evento UserPromptSubmit no disponible en OpenCode — degradacion_documentada |
| UserPromptSubmit | re-anchor-redlines.sh | no | NONE | telemetria | evento UserPromptSubmit no disponible en OpenCode — degradacion_documentada |
| UserPromptSubmit | recommendation-tribunal-followup.sh | no | NONE | telemetria | evento UserPromptSubmit no disponible en OpenCode — degradacion_documentada |
| UserPromptSubmit | stress-awareness-nudge.sh | no | NONE | telemetria | evento UserPromptSubmit no disponible en OpenCode — degradacion_documentada |
| UserPromptSubmit | learning-recall-hook.sh | no | NONE | warning | evento UserPromptSubmit no disponible en OpenCode — degradacion_documentada |
| UserPromptSubmit | user-prompt-intercept.sh | no | NONE | warning | evento UserPromptSubmit no disponible en OpenCode — degradacion_documentada |
