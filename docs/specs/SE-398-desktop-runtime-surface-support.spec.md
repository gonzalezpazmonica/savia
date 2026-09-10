---
id: SE-398
status: APPROVED
priority: P0
developer_type: agent-team
created: 2026-09-09
approved: 2026-09-10
approved_by: human-operator
author: agent-team
parent: SE-397
related_specs: [SE-037, SE-391, SE-393, SE-394, SE-396, SE-397]
risk: L2
type: runtime-surface-evolution
working_title: Savia Desktop Runtime & Surface Support
execution_scope: F0_ONLY_PENDING_REVIEW
---

# SE-398 — Savia Desktop Runtime & Surface Support

## 1. Problema, objetivo y contrato

Savia debe poder proyectarse sobre OpenCode, Codex y Claude Code en sus
superficies CLI, TUI o Desktop sin que runtime, surface, modelo, provider,
sandbox nativo ni permiso de interfaz se conviertan en authority Savia.

```text
HUMAN → SAVIA → CANONICAL CONTRACT → RUNTIME ADAPTER → SURFACE
```

La equivalencia exigida es semántica: mismo efecto canónico, decisión de
authority, política, resultado y evidencia. No exige herramientas, hooks ni UI
idénticos.

## 2. Invariantes

- `RUNTIME != SURFACE != MODEL != PROVIDER != SAVIA`.
- `SURFACE != POLICY_OWNER` y `RUNTIME_ADAPTER != POLICY_OWNER`.
- `UI_PERMISSION` y sandbox nativo pueden reducir permisos, nunca ampliarlos.
- `TOOL != EFFECT`; CLI/Desktop tool names no son efectos canónicos.
- `AVAILABLE != VERIFIED != SUPPORTED`.
- `CLI_PASS != DESKTOP_PASS` y una Desktop no prueba otra.
- Todo fallo o estado de seguridad desconocido falla de forma segura.
- `CHILD_AUTHORITY <= PARENT_AUTHORITY`.
- Remote execution necesita evidencia propia; hooks locales no prueban efectos remotos.

## 3. Alcance

Runtimes: `opencode`, `codex`, `claude-code`. Surfaces iniciales:
`opencode-tui`, `opencode-desktop`, `codex-cli`, `codex-desktop`,
`claude-code-cli`, `claude-code-desktop`. Deben distinguirse también
`LOCAL`, `REMOTE`, `CLOUD`, `SANDBOXED_LOCAL` y `SANDBOXED_REMOTE` cuando
existan de verdad.

## 4. Solución: extensión SAM requerida

Entidades mínimas futuras: `Runtime`, `Surface`, `RuntimeCapability`,
`SurfaceCapability`, `Adapter`, `NativePrimitive`, `CanonicalEffect`,
`CompatibilityProjection`, `VerificationState` y `WorkspaceExecutionMode`.

Relaciones candidatas: `EXPOSES_SURFACE`, `RUNS_ON`, `USES_RUNTIME`,
`PROJECTS_TO`, `SUPPORTED_BY`, `NATIVELY_SUPPORTS`, `ADAPTS`, `EMULATES`,
`CANNOT_SUPPORT`, `REQUIRES_PROJECTION`, `VERIFIED_ON`, `DEGRADED_ON` y
`SURFACE_DIFFERS_FROM`. F1 debe añadir solo las imprescindibles.

Los manifests runtime declaran capacidades como `NATIVE`, `ADAPTED`,
`EMULATED`, `UNSUPPORTED` o `UNKNOWN`. Los manifests de surface heredan el
runtime y declaran únicamente deltas de proceso, filesystem, shell, entorno,
plugins, lifecycle, permisos, sandbox, contexto, MCP y aprobación.

## 5. Efectos canónicos

Mapear sin depender de tool names: `READ_WORKSPACE`, `SEARCH_WORKSPACE`,
`WRITE_WORKSPACE`, `EXECUTE_LOCAL`, `ACCESS_SECRET`, `ACCESS_NETWORK`,
`CALL_MCP`, `MODIFY_CONFIG`, `CREATE_PROCESS`, `EXTERNAL_EFFECT`,
`CHANGE_SHARED_STATE` y `REQUEST_HUMAN_DECISION`.

Si una surface no ofrece intercepción fiable antes de un efecto crítico, dicho
efecto queda `UNSUPPORTED_FOR_EFFECT`, `DEGRADED_SAFE` o requiere reroute
humano. Nunca `ALLOW_WITH_WARNING`.

## 6. Contratos a reconciliar

F0 debe inventariar instructions, agents/subagents, skills, commands, hooks o
mecanismos equivalentes, shell, filesystem, permissions, plugins, MCP,
sandbox, sesiones, cancelación, retry, parallelism, context, receipts,
network, configuración y precedence. Debe clasificar scripts como lógica
canónica, transport, validator, hook, maintenance, CI-only, compatibilidad o
utility, sin migración estética ni big bang.

Los contratos runtime-agnostic candidatos son `BeforeEffect`, `AfterEffect`,
`PromptAdmission`, `ContextResolve`, `PermissionDecision`, `SessionStart`,
`SessionEnd`, `Compaction`, `SubagentStart`, `SubagentEnd`, `EvidenceEmit`,
`HumanGate` y `Recovery`. No crear una abstracción si ya existe autoridad
equivalente.

## 7. Entorno, lifecycle y concurrencia

Cada surface debe observar de forma sanitizada PATH, HOME, cwd, shell,
ejecutable, tamaño de environment, git root y discovery de config/plugins/
skills/agents/MCP. Debe verificar launch, repo open, new/resume/parallel
session, cancel, close/reopen, restart y sleep/resume cuando sea viable.

Corpus de concurrencia: dos lectores; lector+escritor; dos escritores al mismo
o distinto fichero; agente+edición humana; tests paralelos; intento paralelo
de efecto externo. Verificar ausencia de stale authority/locks, leaks,
duplicated effects, receipt ambiguity y pérdida de evidencia crítica.

## 8. Seguridad, authority y evidencia

`EFFECTIVE_PERMISSION` es la intersección conceptual de authority Savia,
permisos runtime y sandbox. Cada evidencia debe identificar commit Savia,
revisión SAM/adapter/policy, runtime/surface y versiones, OS, workspace mode y
execution mode. No registrar secretos.

Probar límites de secret file/env/runtime/provider/Savia/MCP credential sin
leer valores. Separar fronteras `SAVIA_CONTROLLED`, `RUNTIME_CONTROLLED`,
`OS_CONTROLLED`, `PROVIDER_CONTROLLED` y `UNKNOWN`.

Human Gate conserva operation/decision identity, scope, risk, requested
authority, actor, timestamp, result y provenance. Un botón nativo no satisface
el contrato sin correlación suficiente.

## 9. Doctor, corpus y estados

Surface Doctor detectará runtime/surface/version, repo, adapter, config,
instructions, skills, agents, hooks críticos, Shield, MCP críticos, sandbox,
workspace mode y ceiling antes del primer efecto afectado. Resultado:
`SUPPORTED`, `DEGRADED_SAFE`, `BLOCKED` o `UNKNOWN`.

Golden Corpus común: boot, instructions, discovery, agents/subagents, skills,
commands, context, read/search/edit/write, safe/blocked exec, tests, MCP,
secret deny, Shield allow/block/down, Human Gate, cancel/retry, ambiguous
effect, parallel agent, restart/recovery y long session. Resultados cerrados:
`PASS`, `FAIL`, `NOT_SUPPORTED`, `NOT_AVAILABLE`, `NOT_AUTHORIZED`,
`NOT_VERIFIED`.

Equivalence levels: E0 unknown, E1 discovered, E2 functional, E3 governed,
E4 resilient y E5 operationally equivalent. Estados de surface: unassessed,
discovered, experimental, functional, degraded-safe, supported, blocked o
unsupported. `SUPPORTED` requiere evidencia vigente, corpus, resiliencia,
longitudinal y graduación humana.

## 10. Rendimiento, drift y bootstrap

Medir startup, prompt admission, governance, tool, receipt, total, procesos,
memoria y context overhead. Los presupuestos se fijarán después del baseline.
Cambios de versión invalidan selectivamente evidencia y ejecutan smoke corpus:
boot, instructions, agents, skills, read, write/exec gate, secret deny, MCP y
receipt. Runtime contract drift nunca se adapta en silencio.

Bootstrap futuro: abrir repo → detectar surface → doctor → projection →
capability discovery. Project-local/versioned/reproducible por defecto; no
modificar configuración global sin consentimiento.

## 11. Fases

- F0: discovery y reconciliación; sin implementación funcional.
- F1: modelo mínimo runtime/surface en SAM.
- F2: mapping de efectos críticos.
- F3: OpenCode Desktop E0→E3 y después E5.
- F4: Claude Code Desktop.
- F5: Codex Desktop sin elevar su ceiling.
- F6: equivalencia cross-surface.
- F7: concurrencia Desktop.
- F8: update, drift y recovery.
- F9: graduación humana.

Orden: integridad SE-396 → baseline SAM SE-397 → F0/F1/F2 → surfaces → corpus
→ resilience/longitudinal → graduación humana.

Estimación inicial: esfuerzo alto y ejecución por fases; F1 es un slice medio
de esquema read-only y validación, sujeto a la revisión de F0.

## 12. Acceptance Criteria

- AC01–AC10: reconciliación sin duplicar SE-396/397; Runtime y Surface
  separados; tres runtimes y seis surfaces; inheritance/deltas; efectos
  canónicos; adapter/surface nunca policy owner.
- AC11–AC30 OpenCode Desktop: detección, plugin y provenance, instructions,
  agents/subagents/skills/hooks, Shield allow/block/down fail-closed,
  read/write/exec/MCP/secrets, cancel/restart/recovery, sin E2BIG/leaks y
  corpus longitudinal.
- AC31–AC44 Claude Code Desktop: runtime identificado, CLAUDE/instructions,
  agents/subagents/skills/commands/hooks, efectos gobernados, MCP/secrets,
  Human Gate, receipts, recovery, parallel safety y longitudinal.
- AC45–AC60 Codex Desktop: runtime, AGENTS, skills, agents/parallel isolation,
  effects, read, write/exec gobernados o bloqueados, secrets, MCP/plugins,
  Human Gate, receipts, ceiling, recovery y longitudinal antes de E5.
- AC61–AC70: corpus en seis surfaces, matriz semántica, cero false allows,
  authority escalation o security regression; diferencias explícitas;
  NOT_SUPPORTED no es PASS; versiones/freshness; graduación humana.

## 13. Stop conditions y Human Gates

Stop si un efecto crítico evita el gate, runtime amplía authority, adapter
falla abierto, remote evade governance, secret boundary falla, child supera
parent, concurrencia duplica efecto, receipt no correlaciona, update invalida
enforcement, Desktop exige desactivar Shield/bypass o duplicar policy.

Requiere decisión humana: declarar `SUPPORTED`, elevar ceiling Codex, nuevos
external effects, cambios authority/trust/confidentiality/policy ownership,
reducir sandbox, aceptar surface sin gate, convertir UI approval en Human Gate,
activar remote no verificado o aceptar regresión de seguridad.

## 14. Instrucción inmediata

Persistir la spec y ejecutar **solo F0**. No implementar adapters Desktop.
F0 debe producir la matriz requerida por runtime/surface, cobertura de efectos,
reuse/gaps/blockers, slice F1 y decisiones humanas. No F1 hasta revisión.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode | Codex |
|---|---|---|---|
| F0 | inventario de settings/hooks | inventario plugin/V2/runtime | inventario AGENTS/skills/sandbox |
| F1+ | proyección del contrato canónico | proyección del contrato canónico | proyección fail-safe según ceiling |

### Verification protocol

- [x] F0 distingue evidencia estática, documental y operacional.
- [ ] Tests futuros cubren cada runtime y surface o usan `NOT_VERIFIED`.
- [ ] Hooks nuevos futuros se registran también en el plugin OpenCode.

### Portability classification

- [x] **DUAL_BINDING** ampliado a tres familias; F0 es documentación y no
  introduce bindings ni authority.
