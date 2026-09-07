---
lang: es
---
# AGENTS.md

> Auto-generated from `.opencode/agents/*.md`. **Do not edit by hand.**
> Source of truth: `docs/rules/domain/agents-md-source-of-truth.md` (SE-078).

## Savia startup — all frontends

Before working, read `CLAUDE.md` and its critical context files explicitly:
`docs/critical-facts.md`, `.claude/profiles/savia.md`,
`docs/rules/domain/radical-honesty.md`, `docs/rules/domain/autonomous-safety.md`,
`docs/rules/domain/caveman-default.md`, and
`docs/rules/domain/knowledge-discovery-priority.md`.
Read `.claude/profiles/active-user.md` and the active profile's preferences
when present; keep private profile and memory data out of tracked output.
Do not assume that another frontend expands Claude-style `@imports`.
Before working in a project, read its `projects/<name>/CLAUDE.md`.

Skills share one source: `.claude/skills/`. OpenCode exposes it through
`.opencode/skills`; Codex through `.agents/skills`. Use `SKILLS.md` and
`docs/RESOLVER.md` to find the relevant instructions, then read the skill.
This registry describes roles; its model identifiers and permissions are
OpenCode metadata, not automatically configured Codex subagents.

For concurrent sessions in the same directory, read
`docs/rules/domain/parallel-session-protocol.md`. The working tree, branch
and Git index are shared: coordinate file ownership, serialize Git mutations,
and never switch branches, stage another session's edits or discard changes.
Use separate worktrees when tasks need independent branches.
Hooks and MCP configuration are frontend-specific: do not assume Codex runs
`.claude/settings.json` hooks or `.opencode/plugins`. Run the applicable
validation scripts explicitly and report any unverified gate.
## Savia autonomy contract

For the `autonomous-l2` profile, proceed without an extra human gate for
repository reads, local analysis, workspace edits, tests, builds, linters,
deterministic repository scripts, reversible fixes, worktrees and verification
inside the approved scope. The number of commands does not create authority.

Require human authority for external effects, publication, push, merge, deploy,
secrets, scope expansion, unresolved product or architecture choices, irreversible
effects and risk above L2. Unknown operations fail safe. Execution may be
delegated; decision authority remains human. Never raise this profile or disable
the sandbox to finish a task.

## How to use

This file is the cross-frontend mirror of Savia's agent registry. Claude Code
reads `.opencode/agents/*.md` directly; OpenCode v1.14, Codex, Cursor and other
modern frontends pick up this `AGENTS.md` as freeform context. The source of
truth is `.opencode/agents/*.md`; this index is regenerated automatically by
the Stop hook `agents-md-auto-regenerate.sh` whenever an agent file changes.

## Agents

| Name | Model | Permission | Tools | Description |
|---|---|---|---|---|
| architect | opencode-go/glm-5.3 | L1 | — | Diseño de arquitectura .NET y decisiones técnicas de alto nivel. Usar PROACTIVELY cuando: se diseña una nueva feature... |
| architecture-judge | opencode-go/deepseek-v4-flash | L1 | — | Code Review Court judge — boundaries, coupling, layer violations, patterns |
| archive-digest | opencode-go/deepseek-v4-flash | L2 | — | Digestión de formatos de archivo y contenido comprimido via markitdown (SE-172). Soporta ZIP (itera contenidos), EPub... |
| authority-claim-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — detects credential claims ("soy investigador"). NUNCA veto. (SPEC-193) |
| azure-devops-operator | opencode-go/deepseek-v4-flash | L1 | — | Operaciones rápidas en Azure DevOps: consultas WIQL, actualización de work items, gestión de sprint, capacidades del ... |
| business-analyst | opencode-go/glm-5.3 | L1 | — | Análisis de reglas de negocio, descomposición de PBIs, criterios de aceptación y evaluación de competencias del equip... |
| calibration-judge | opencode-go/deepseek-v4-flash | L1 | — | Truth Tribunal judge — confidence statements match evidence strength |
| cobol-developer | opencode-go/glm-5.3 | L3 | — | Asistencia en código COBOL/mainframe. IMPORTANTE: La mayoría de tareas COBOL deben realizarlas humanos expertos en le... |
| code-reviewer | opencode-go/glm-5.3 | L1 | — | Revisión de código .NET como quality gate antes de merge. Usar PROACTIVELY cuando: se completa una implementación y n... |
| code-twin-agent | opencode-go/deepseek-v4-flash | L1 | — | Agente especializado en consultar el Application Code Twin de un proyecto. Usa code-twin-load.sh, code-twin-sync-chec... |
| cognitive-judge | opencode-go/deepseek-v4-flash | L1 | — | Code Review Court judge — debuggability at 3AM, naming, complexity, logs |
| coherence-court-orchestrator | opencode-go/glm-5.3 | L4 | — | Convenes the Coherence Court, consolidates .coherence.crc, applies human gate |
| coherence-factual-judge | opencode-go/deepseek-v4-flash | L1 | — | Coherence Court judge — stage output contradicts facts fixed in earlier stages |
| coherence-judge | opencode-go/deepseek-v4-flash | L1 | — | Truth Tribunal judge — internal consistency (sums, dates, entities) |
| coherence-objectives-judge | opencode-go/deepseek-v4-flash | L1 | — | Coherence Court judge — stage output contradicts declared objectives of the flow |
| coherence-premise-drift-judge | opencode-go/deepseek-v4-flash | L1 | — | Coherence Court judge — silent premise drift between stages of a flow |
| coherence-scope-judge | opencode-go/deepseek-v4-flash | L1 | — | Coherence Court judge — stage output violates scope/constraints fixed earlier |
| coherence-validator | opencode-go/deepseek-v4-flash | L0 | — | Verifies that generated outputs (specs, reports, code) actually match the stated objective. Use PROACTIVELY post-SDD,... |
| commit-guardian | opencode-go/deepseek-v4-flash | L4 | — | Guardian de commits: verifica que todos los cambios staged cumplen las reglas del workspace ANTES de hacer el commit.... |
| completeness-judge | opencode-go/deepseek-v4-flash | L1 | — | Truth Tribunal judge — report covers what its title/abstract promises |
| compliance-judge | opencode-go/glm-5.3 | L1 | — | Truth Tribunal judge — PII, N1-N4b levels, format rules, confidentiality |
| concession-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — detects position changes without new evidence (SPEC-192) |
| confidentiality-auditor | opencode-go/glm-5.3 | L1 | — | Audita cumplimiento de confidencialidad en PRs de pm-workspace (repo publico). Descubre dinamicamente datos sensibles... |
| configurator | opencode-go/deepseek-v4-flash | L1 | — | Centralizes workspace dispatch decisions: selects skills, agents, rules, and memory queries for each user intent. Emi... |
| context-dome-manager | opencode-go/glm-5.3 | L2 | — | Arquitecto de conocimiento — disena, audita y evoluciona cupulas de contexto (SaviaVaults). Decide estructura, federa... |
| correctness-judge | opencode-go/deepseek-v4-flash | L1 | — | Code Review Court judge — logic, tests, edge cases, error paths |
| court-orchestrator | opencode-go/glm-5.3 | L4 | — | Convenes the Code Review Court, manages fix cycles, produces .review.crc |
| criterion-simulation-judge | opencode-go/glm-5.3 | L1 | — | Criterion Simulation Layer judge — SPEC-194. Executes 4 meta-questions (frame challenge, historical priors, operator ... |
| dev-orchestrator | opencode-go/deepseek-v4-flash | L4 | — | Analiza specs y crea planes de implementación con slices, dependencias y presupuestos de contexto |
| diagram-architect | opencode-go/deepseek-v4-flash | L1 | — | Architecture diagram specialist. Analyzes code and infrastructure to generate Mermaid diagrams, validates business ru... |
| dotnet-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código C#/.NET siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implementa una feature en... |
| drift-auditor | opencode-go/glm-5.3 | L1 | — | Auditoría de convergencia repo: detecta drift entre docs, config y código. Usar PROACTIVELY tras cambios grandes o al... |
| excel-digest | opencode-go/glm-5.3 | L2 | — | Digestion de hojas de calculo Excel (XLSX/XLS/CSV) — pipeline de 4 fases. Extrae estructura, formulas, patrones de da... |
| expertise-asymmetry-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — when draft falls in a domain the active user marks as `audit_level: blind`, force a r... |
| factuality-judge | opencode-go/glm-5.3 | L1 | — | Truth Tribunal judge — factual accuracy of claims against verifiable sources |
| feasibility-probe | opencode-go/deepseek-v4-flash | L3 | — | Validates spec feasibility by attempting a time-boxed prototype. Produces viability report with score, blocking secti... |
| fiction-framing-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — detects persona-shift plus content-equivalent framing over sensitive domain (SPEC-193) |
| fix-assigner | opencode-go/deepseek-v4-flash | L2 | — | Creates fix tasks from Court findings, assigns to dev agents, triggers re-review |
| frontend-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código frontend (Angular y React) siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implem... |
| frontend-test-runner | opencode-go/deepseek-v4-flash | L4 | — | Post-commit frontend test execution — unit, component, e2e, coverage |
| go-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código Go siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implementa una feature en Go (... |
| hallucination-fast-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — verifies that entities cited in a draft (files, functions, flags, libs, paths, comman... |
| hallucination-judge | opencode-go/glm-5.3 | L1 | — | Truth Tribunal judge — detects invented facts via SelfCheck-style consistency |
| infrastructure-agent | opencode-go/glm-5.3 | L4 | — | Agente de gestión de infraestructura cloud. Recibe solicitudes del architect, detecta infraestructura existente, crea... |
| java-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código Java/Spring Boot siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implementa una f... |
| legal-compliance | opencode-go/glm-5.3 | L2 | — | Auditoría de compliance legal contra legislación española consolidada (legalize-es). Usar PROACTIVELY cuando: se crea... |
| meeting-confidentiality-judge | opencode-go/glm-5.3 | L1 | — | Juez de confidencialidad post-extraccion de reuniones. Valida que datos marcados como confidenciales NO se filtren a ... |
| meeting-digest | opencode-go/deepseek-v4-flash | L2 | — | Digestion de transcripciones de reuniones (VTT, DOCX, TXT). Extrae datos estructurados de personas, contexto de negoc... |
| meeting-risk-analyst | opencode-go/glm-5.3 | L1 | — | Analisis de riesgos post-digestion de reuniones. Cruza decisiones, compromisos y dinamicas extraidas de una transcrip... |
| memory-agent | opencode-go/deepseek-v4-flash | L2 | — | Gestiona la memoria persistente de pm-workspace via lenguaje natural. |
| memory-conflict-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — detects when a draft recommendation contradicts the active user's auto-memory (feedba... |
| mobile-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código mobile (Swift/iOS + Kotlin/Android + Flutter) siguiendo specs SDD aprobadas. Usar PROACTIVEL... |
| model-upgrade-auditor | opencode-go/glm-5.3 | L1 | — | Audits agents, skills, and prompts for workarounds that newer models may no longer need. Proposes simplifications wit... |
| pdf-digest | opencode-go/glm-5.3 | L2 | — | Digestion de documentos PDF con extraccion de texto e imagenes — pipeline de 4 fases. Documentos tecnicos, propuestas... |
| pentester | opencode-go/glm-5.3 | L3 | — | Hacker ético de máximo nivel con pipeline autónomo de 5 fases inspirado en Shannon. Ejecuta pentests dinámicos contra... |
| php-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código PHP/Laravel siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implementa una featur... |
| pptx-digest | opencode-go/deepseek-v4-flash | L2 | — | Digestion de presentaciones PowerPoint (PPTX) — pipeline de 4 fases. Extrae texto, notas del presentador, imagenes, d... |
| pr-agent-judge | opencode-go/deepseek-v4-flash | L1 | — | External 5th judge of the Code Review Court — wraps qodo-ai/pr-agent OSS (SPEC-124). Opt-in via COURT_INCLUDE_PR_AGEN... |
| python-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código Python (FastAPI/Django) siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implement... |
| recommendation-tribunal-orchestrator | opencode-go/deepseek-v4-flash | L2 | — | Recommendation Tribunal orchestrator — 4 fast judges in parallel, aggregates scores, applies vetos, mutates output wi... |
| reconciler | opencode-go/deepseek-v4-flash | L1 | — | Classifies contradictions into 3 buckets: evolution, auto-resolve, conflict-doc. Invoked by drift-auditor. |
| reflection-validator | opencode-go/glm-5.3 | L0 | — | Meta-cognitive validation of responses and decisions (System 2). Use PROACTIVELY when: evaluating a response to a com... |
| repetition-truth-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — detects user claims repeated and assumed true without verification (SPEC-192) |
| ruby-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código Ruby on Rails siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implementa una feat... |
| rule-violation-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — detects when a draft recommendation violates canonical rules (CLAUDE.md, autonomous-s... |
| rust-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código Rust (Axum, Tokio) siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implementa una... |
| sdd-spec-writer | opencode-go/glm-5.3 | L2 | — | Generación y validación de Specs SDD (Spec-Driven Development) como contratos ejecutables. Usar PROACTIVELY cuando: s... |
| security-attacker | opencode-go/deepseek-v4-flash | L3 | — | Agente Red Team que simula ataques contra el código y la configuración del proyecto. Busca vulnerabilidades, misconfi... |
| security-auditor | opencode-go/deepseek-v4-flash | L1 | — | Agente auditor independiente que evalúa la calidad del análisis Red/Blue Team, verifica que las correcciones son adec... |
| security-defender | opencode-go/deepseek-v4-flash | L3 | — | Agente Blue Team que propone correcciones para las vulnerabilidades encontradas por el attacker. Genera patches, conf... |
| security-guardian | opencode-go/glm-5.3 | L4 | — | Especialista en seguridad, confidencialidad y ciberseguridad. Audita los cambios staged ANTES de cualquier commit par... |
| security-judge | opencode-go/deepseek-v4-flash | L1 | — | Code Review Court judge — OWASP, PII, injection, auth, credentials |
| social-networks | opencode-go/deepseek-v4-flash | L2 | — | Coordinador agnóstico de redes sociales (SE-385). Selecciona proveedor, comprueba credenciales y permisos (capability... |
| source-traceability-judge | opencode-go/deepseek-v4-flash | L1 | — | Truth Tribunal judge — every claim must have a verifiable @ref citation |
| spec-judge | opencode-go/deepseek-v4-flash | L1 | — | Code Review Court judge — implementation vs approved spec, acceptance criteria |
| structural-framing-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — detects output with manual/protocol form over CBRN or sensitive domain |
| sycophancy-judge | opencode-go/deepseek-v4-flash | L1 | — | Recommendation Tribunal judge — detects empty social validation in conversational drafts (SPEC-192) |
| tabular-analyst | opencode-go/deepseek-v4-flash | L2 | — | Analisis estadistico de datos tabulares. Usar PROACTIVELY cuando: se reciben datos en CSV, Excel, tablas markdown, o ... |
| tech-writer | opencode-go/deepseek-v4-flash | L2 | — | Documentación técnica: README, CHANGELOG, comentarios XML en C#, docs de proyecto. Usar PROACTIVELY cuando: se actual... |
| terraform-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código Terraform (IaC) siguiendo specs SDD aprobadas. CRÍTICO: NUNCA ejecutar terraform apply autom... |
| test-architect | opencode-go/deepseek-v4-flash | L3 | — | Designs and generates the highest quality tests across all 16 language packs and 14 test types. Use PROACTIVELY when:... |
| test-engineer | opencode-go/deepseek-v4-flash | L3 | — | Creación y ejecución de tests en proyectos .NET. Usar PROACTIVELY cuando: se escriben tests unitarios o de integració... |
| test-runner | opencode-go/deepseek-v4-flash | L4 | — | Ejecución de tests y verificación de cobertura post-commit. Ejecuta suite completa de tests, valida que todos pasan, ... |
| truth-tribunal-orchestrator | opencode-go/glm-5.3 | L2 | — | Truth Tribunal orchestrator — convenes 7 judges, aggregates scores, applies vetos, drives iteration |
| typescript-developer | opencode-go/deepseek-v4-flash | L3 | — | Implementación de código TypeScript/Node.js siguiendo specs SDD aprobadas. Usar PROACTIVELY cuando: se implementa una... |
| visual-digest | opencode-go/deepseek-v4-flash | L2 | — | Digestión de imágenes con OCR contextual — 5 pasadas. Fotos de pizarras, notas manuscritas, diagramas en papel, captu... |
| visual-qa-agent | opencode-go/deepseek-v4-flash | L1 | — | Visual QA: screenshot analysis, wireframe comparison, regression detection. Usar PROACTIVELY cuando se detectan cambi... |
| web-e2e-tester | opencode-go/deepseek-v4-flash | L3 | — | Autonomous E2E testing of web apps against live instances. Use PROACTIVELY when: deploying savia-web, after UI change... |
| word-digest | opencode-go/deepseek-v4-flash | L2 | — | Digestion de documentos Word (DOCX) con extraccion de texto, tablas e imagenes — pipeline de 4 fases. Actas, propuest... |