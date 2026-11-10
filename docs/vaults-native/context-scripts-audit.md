# Audit: 33 context scripts — SE-290 S5 classification

Date: 2026-08-01

## SUBSTITUTED (7): replaced by SaviaVaults tools
context-dome-generate, context-aging, context-snapshot, context-meter,
context-budget-check, context-origin-tag, context-receipts-validate

## KEPT (18): orchestration/policy logic SaviaVaults doesn't cover
context-task-classifier, context-task-classify, context-compaction-policy,
context-rotation, context-drop-after-use, context-drop-metrics,
context-auto-prime, context-prefetch, context-reasoning,
context-preflight-check, context-frozen-check, context-erosion-detect,
context-engineering-report, context-greedy-budget, context-jit-lint,
context-restate-anchor, context-capability-check, context-condenser

## ARCHIVED (8): obsolete or redundant
context-audience-graph, context-calibration-measure,
context-capability-metadata, context-distortion-measure, context-tracker

## Metrics
- Before: ~5,794 lines (33 scripts)
- After substitution wrappers: ~4,600 lines
- Reduction: ~1,200 lines

> Actualización 2026-11-10 (SE-511 S1, PR #1509): `context-task-classifier` se retira. Implementaba el mismo contrato SE-029-C que `context-task-classify` con otra heurística y no tenía consumidores; queda `context-task-classify`.
