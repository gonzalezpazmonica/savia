---
context_tier: L3
token_budget: 1077
usage: reference-only
dormant_since: "2026-06-24"
review_note: "Quarterly review 2026-Q2"
---

# Agent Permission Levels — 5-Tier Access Control

> Complementa agent-policies.yaml con niveles granulares por agente.

## 5 Niveles

| Nivel | Nombre | Tools | Puede escribir | Puede ejecutar | Ejemplo |
|-------|--------|-------|----------------|----------------|---------|
| L0 | Observer | Read, Glob, Grep | No | No | reflection-validator, coherence-validator |
| L1 | Analyst | Read, Glob, Grep, Bash(readonly) | No | Solo queries | architect, business-analyst |
| L2 | Writer | Read, Write, Edit, Glob, Grep | Si (proyecto) | No | tech-writer, sdd-spec-writer |
| L3 | Developer | Read, Write, Edit, Bash, Glob, Grep | Si (proyecto) | Si (build, test) | dotnet-developer |
| L4 | Operator | Read, Write, Edit, Bash, Glob, Grep, Task | Si (todo) | Si (todo) | commit-guardian |

## Restricciones por nivel

### L0 — Observer
- Solo lectura de ficheros y busqueda
- No puede modificar nada ni ejecutar comandos bash

### L1 — Analyst
- Lectura + bash readonly (git log, git diff, wc)
- Bash bloqueado para escritura

### L2 — Writer
- Puede crear y editar ficheros
- No puede ejecutar bash (excepto readonly)

### L3 — Developer
- Acceso completo a Read, Write, Edit, Bash
- Bash permitido: build, test, format, lint
- Bash bloqueado: git push, git merge, deploy, rm -rf
- Scope limitado a paths del proyecto activo

### L4 — Operator
- Acceso completo incluido Task (invocar subagentes)
- Sigue sujeto a autonomous-safety.md (nunca merge/deploy)

## Asignacion por agente

| Agente | Nivel | Justificacion |
|--------|-------|---------------|
| reflection-validator | L0 | Solo valida |
| coherence-validator | L0 | Solo verifica |
| architect | L1 | Analiza, no implementa |
| business-analyst | L1 | Analiza reglas |
| diagram-architect | L1 | Analiza diagramas |
| security-auditor | L1 | Audita |
| code-reviewer | L1 | Revisa |
| drift-auditor | L1 | Audita drift |
| azure-devops-operator | L1 | Queries Azure DevOps |
| visual-qa-agent | L1 | Analiza screenshots |
| meeting-risk-analyst | L1 | Analiza riesgos |
| meeting-confidentiality-judge | L1 | Juzga confidencialidad |
| confidentiality-auditor | L1 | Audita |
| model-upgrade-auditor | L1 | Audita |
| tech-writer | L2 | Escribe docs |
| sdd-spec-writer | L2 | Escribe specs |
| meeting-digest | L2 | Escribe digests |
| visual-digest | L2 | Escribe digests |
| pdf-digest | L2 | Escribe digests |
| word-digest | L2 | Escribe digests |
| excel-digest | L2 | Escribe digests |
| pptx-digest | L2 | Escribe digests |
| memory-agent | L2 | Escribe memoria |
| dotnet-developer | L3 | Implementa codigo |
| typescript-developer | L3 | Implementa codigo |
| frontend-developer | L3 | Implementa codigo |
| java-developer | L3 | Implementa codigo |
| python-developer | L3 | Implementa codigo |
| go-developer | L3 | Implementa codigo |
| rust-developer | L3 | Implementa codigo |
| php-developer | L3 | Implementa codigo |
| ruby-developer | L3 | Implementa codigo |
| mobile-developer | L3 | Implementa codigo |
| cobol-developer | L3 | Asiste con legacy |
| terraform-developer | L3 | IaC (nunca apply) |
| test-engineer | L3 | Escribe y ejecuta tests |
| security-defender | L3 | Propone patches |
| security-attacker | L3 | Ejecuta scans |
| pentester | L3 | Testing dinamico |
| web-e2e-tester | L3 | Tests E2E |
| feasibility-probe | L3 | Prototipa |
| commit-guardian | L4 | Orquesta pre-commit |
| dev-orchestrator | L4 | Orquesta dev sessions |
| test-runner | L4 | Orquesta test pipeline |
| frontend-test-runner | L4 | Orquesta tests frontend |
| infrastructure-agent | L4 | Orquesta infra |
| security-guardian | L4 | Orquesta security |

## Frontmatter del agente

Anadir campo `permission_level:` al frontmatter:

```yaml
---
name: dotnet-developer
permission_level: L3
tools: [Read, Write, Edit, Bash, Glob, Grep]
---
```

## Validacion

Script `scripts/validate-agent-permissions.sh` verifica las tools del agente contra su nivel declarado (el nivel es un máximo):

- Tool **por encima** del nivel (exceso) = ERROR, exit 1, con agente y tool.
- Tool del nivel no declarada = WARNING (tener menos es válido).
- Excesos pendientes de decisión: línea base `docs/agent-permissions-excess-baseline.txt` (pares `agente tool`). Solo decrece: una entrada que ya no es exceso falla como *stale*; el test `tests/test-validate-agent-permissions-excess.bats` fija el máximo. Resolver un caso = subir el nivel o quitar la tool, y borrar la línea.

## Integracion con agent-policies.yaml

El nivel define el maximo. agent-policies.yaml puede restringir mas. autonomous-safety.md siempre prevalece.

## Precedencia

1. autonomous-safety.md (inmutable)
2. permission_level del agente (maximo)
3. agent-policies.yaml del proyecto (restriccion)
4. Runtime overrides (solo con confirmacion humana)

## Enforcement por sesión (SE-354)

Los niveles declarados se refuerzan en **código** (policy as code), no por
promesa al modelo, mediante el hook `permission-mode-gate.sh` (PreToolUse):

- `SAVIA_PERMISSION_MODE=read-only` → deniega estructuralmente (exit 2) las
  tools de mutación: `Write`, `Edit`, `MultiEdit`, y comandos Bash de mutación
  (`git push/commit/merge/reset --hard`, `rm`, `mv`, `cp`, installers).
- Whitelist read-safe dentro de Bash: `git status/log/diff/show/fetch`,
  `ls/cat/grep/rg/find/wc/head/tail`.
- `SAVIA_PERMISSION_MODE=full` (default) → sin cambios de comportamiento.

Equivale a una sesión L0/L1 forzada por hook. Los agentes L2+ pueden optar a
ejecutar su trabajo en modo read-only (auditorías, consultas) sin riesgo de
mutación accidental.

Ref: SE-354 (spec `docs/specs/SE-354-readonly-permission-mode.spec.md`),
inspirado en OpenClaw permission modes.
