---
status: APPROVED
approved_at: 2026-10-27
approved_by: "operadora, AskUserQuestion 2026-10-27"
priority: P2
developer_type: agent-single
created: 2026-09-29
phase: E
risk: L2
related_specs: [SE-380]
origin: output/research/harness-referencias-20260929.md (§2, mobile-next/mobile-mcp)
---

# SE-408 — Automatización móvil por árbol de accesibilidad (mobile-mcp) bajo soberanía

## Problema

`android-autonomous-debugger` maneja Savia Mobile con ADB y capturas de pantalla
(`scripts/lib/adb-wrapper.sh`). Cada paso visual consume tokens de imagen y la
lectura de la UI es ambigua. `mobile-mcp` (Apache-2.0) lee el árbol de
accesibilidad nativo (sin modelo de visión), devuelve elementos estructurados,
cubre Android e iOS y añade logs, crashes y comandos por lotes.

## Riesgos que condicionan la adopción

- Telemetría activada por defecto (PostHog + Scarf). Es la misma razón por la que
  se deprecó lightpanda frente a obscura.
- El README propone `npx @mobilenext/mobile-mcp@latest`: sin versión fijada hay
  riesgo de cadena de suministro.
- Herramientas de nube con efectos externos (`mobile_login_to_cloud_provider`,
  `mobile_allocate_remote_device`, `mobile_release_remote_device`).

## Slices

### S0 — Feasibility probe (sin integrar)

En un entorno aislado con un emulador: versión fijada (`package-lock` +
integridad), `MOBILEMCP_DISABLE_TELEMETRY=1` y verificación de que no hay tráfico
saliente con la red capturada. Se compara con el flujo ADB actual en 3 tareas
(login, navegación y lectura de estado) midiendo tokens, pasos y aciertos.

- AC1: informe GO/NO-GO con los números de las 3 tareas.
- AC2: 0 conexiones salientes con la telemetría desactivada; si hay alguna, NO-GO.

### S1 — Integración con allowlist (solo si S0 da GO)

Servidor MCP registrado con la versión fijada, la variable de telemetría forzada
en su `env` y una denylist de herramientas de nube en el gate de MCP de Savia.
`android-autonomous-debugger` prefiere el árbol de accesibilidad y conserva ADB
como fallback.

- AC3: una llamada a una herramienta de nube se deniega en ambos frontends.
- AC4: `sovereignty-auditor` pasa sin hallazgos nuevos.

## Fuera de alcance

Dispositivos en la nube; iOS real (requiere Xcode, no disponible en el host actual).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Servidor MCP | `.mcp.json` | `opencode.json` `mcp` |
| Denylist de herramientas | hook PreToolUse MCP | `tool.execute.before` |

### Verification protocol

- [ ] Denylist efectiva en ambos runtimes
- [ ] Telemetría desactivada en ambos

### Portability classification

- [x] **DUAL_BINDING**
