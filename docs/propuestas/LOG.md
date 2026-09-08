<!-- @generated/managed by scripts/spec-lifecycle.sh — append-only -->
<!-- Most recent entries at the top. Format: ## YYYY-MM-DD SPEC-ID STATUS -->
# Specs Lifecycle Log

> Conceptual history of specs in docs/propuestas/. Append-only.
> Each entry: date, spec ID, status transition, optional rationale.
> Ref: SE-222 S1 OKF Adoptable Patterns (log.md convention).

## 2026-09-09 SE-397 F0 APPROVED_WITH_CONCERNS
La operadora aprueba F0 y el trabajo pendiente. F1–F10 quedan autorizadas con
sus gates de fase; `.scm/` será la proyección inicial, SQLite seguirá siendo
cache y drift/impact permanecen report-only. Sin elevación de authority.

## 2026-09-08 SE-397 PROPOSED→APPROVED
Savia Architectural Self-Knowledge & Operational Excellence. Aprobación humana
explícita; ejecución inmediata limitada a F0 (reconciliación report-only).
F1–F10 conservan gate humano tras revisar el informe F0.

## 2026-09-01 SE-365 APPROVED→IMPLEMENTED
Company as Code (renumerado de SE-265, que colisionaba con court-model-tiers):
estándar de entidades organizacionales como código. org-registrar.py valida
(frontmatter común, vocabulario de relaciones cerrado, consistencia referencial,
origin/source SE-352), indexa el grafo company/projects/resources, propone con
escritura mediada. Skill org-registrar + grafo piloto (5 entidades). 6 pytest + 5 bats.

## 2026-08-31 SE-359 APPROVED→IMPLEMENTED
REVIEW.md policy (origen Anthropic playbook Stage 5): passes canónicos, vocab
cerrado Important|Nit, cap 5 nits, exclusiones; review-policy-parse.py. 7 pytest + 7 bats.

## 2026-08-31 SE-364 APPROVED→IMPLEMENTED
Bucle de evidencia (origen Anthropic playbook): evidence-capture.py captura
intervenciones/rechazos de ledgers locales → corpus de evals discriminantes
(filtro N3/N3b/N4b), evidence-capture.sh integra con runner SPEC-151.
5 pytest + 4 bats verdes.

## 2026-08-31 SE-363 APPROVED→IMPLEMENTED
Registros-no-archivos (origen Anthropic playbook): governance-sync.py extrae CRIT
de CRITERIO.md a registro JSONL consultable (estado/aprobación), governance-query.sh.
Markdown = vista, registro = dato. 5 pytest + 5 bats verdes.

## 2026-08-31 SE-362 APPROVED→IMPLEMENTED
Risk Tiering (origen Anthropic playbook gobernanza ejecutable + modelo Amplitude):
risk-tier.py clasifica cambios T1-T4, push-pr --merge consulta el tier (T3/T4
bloqueado sin review humana aun con grant), doc risk-tiering.md. 7 pytest + 5 bats.

## 2026-08-31 SE-361 APPROVED→IMPLEMENTED
Presupuesto de tiempo de CI (origen Anthropic playbook): ci-duration-agg.py mide
duración por job (p50/p95), detecta over-budget 5min; ci-duration.sh.
Alimenta etapa ci de SE-360. 5 pytest + 4 bats verdes.

## 2026-08-31 SE-360 APPROVED→IMPLEMENTED
Costo por cambio aceptado (origen Anthropic playbook): acceptance-cost-agg.py
descompone time-to-acceptance por etapa desde ledgers locales (SE-349/355),
p50/p95 + bottleneck; acceptance-cost.sh. 6 pytest + 3 bats verdes.

## 2026-08-31 SE-358 APPROVED→IMPLEMENTED
plan.md verificado (origen Anthropic playbook Stage 3/5): plan-validate.py +
plan-diff-check.sh (sync plan↔diff, warn/block). 11 bats verdes.

## 2026-08-31 SE-357 APPROVED→IMPLEMENTED
Control Bands autónomas (origen Anthropic AI-Native SDLC Playbook Stage 6):
detección determinista sin LLM + tiers σ (1σ log, 2σ diagnose, 3σ propose),
control-bands.yaml, historial local, intent/ como re-entrada al pipeline.
12 bats verdes.

## 2026-08-31 SE-356 APPROVED→IMPLEMENTED
Skills Two-Layers (origen OpenClaw VISION): layer core/peripheral en 132 SKILL.md
(peripheral por defecto), skills-registry/INDEX.json + REVIEW.md (criterios de
promoción), skill-layer-check.sh. 8 bats verdes.

## 2026-08-31 SE-355 APPROVED→IMPLEMENTED
Audit Ledger metadata-only + decision receipts (origen OpenClaw 2.0):
audit-receipts.sh con vocabulario cerrado, enforced solo si gate gobernó,
ledger local data/audit sin prompts/PII, retention 30d batch, non-claims doc.
12 bats verdes.

## 2026-08-31 SE-352 APPROVED→IMPLEMENTED
Trust-Gated Memory (origen OpenClaw 2.0): origin class owner/agent/untrusted/system
en memory-store, taint de turno vía hook memory-origin-gate.sh, consolidación que
excluye untrusted/system, filtro search --min-origin, audit-origins. 15 bats verdes.

## 2026-08-31 SE-220 IMPLEMENTED
Speculative Tool Execution — S0 feasibility (PROCEED, acceptance_rate=1.00) + Slices 1-4.
Implementado en PR #874 (2026-06-26): predictor heurístico (`speculative-tool-predictor.py`),
orquestador (`speculative-tool-execution.py`), cache con flock+TTL 30s (`speculative-cache-manager.py`),
telemetría JSONL + dashboard (`speculative-telemetry-report.sh`), hooks pre-execute (S2) y
skill-preload (S3) registrados. 39 pytest + 35 bats verdes.

## 2026-06-24 SPEC-182 IMPLEMENTED
Bi-temporal timeline frontmatter on specs and decisions
SPEC-182 implementado: spec-timeline-append.py + spec-timeline-query.py + lifecycle --no-timeline + 10 back-fills + 21 tests

## 2026-06-23 SE-222 PROPOSED (S0 IMPLEMENTED)
OKF Adoptable Patterns — resource: URI + log.md + index.md.
S0 (resource: URI validator + 5 specs back-filled) implementado en PR #850.

## 2026-06-23 SE-220 PROPOSED
Speculative Tool Execution — draft+verify pattern (S0 feasibility BLOQUEANTE).

## 2026-06-23 LOG.md created (SE-222 S1)
Bootstrap entry — fichero creado a partir de este punto.
Nuevas transiciones se añaden al top.
