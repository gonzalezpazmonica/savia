# ADR-003 — Tecnología de UI del instalador visual (SE-399)

> **Fecha**: 2026-10-24
> **Status**: PROPOSED — requiere aprobación humana (gate "UI technology ADR" de SE-399 §16)
> **Contexto**: SE-399 F0 recomienda una sonda de viabilidad Tauri 2, no una selección final.

## Decisión provisional

Candidato preferente: **Tauri 2 + UI web**. Sin dependencia instalada ni código de UI en F1: esta
ADR fija el criterio y el límite, no el framework. El Provisioning Core
(`scripts/provisioning/`) es independiente de la GUI (AC02): la GUI solo proyecta el plan
declarativo (`schemas/installer/installation-plan.schema.json`) y no contiene lógica canónica.

## Candidatos

| Candidato | Evidencia en el repo | Valoración |
|---|---|---|
| Tauri 2 + web | `docs/savia-models/04-rust-tauri-vue-desktop.md` | Mayor reutilización local, shell pequeño, IPC y capabilities explícitas. Preferente |
| Avalonia | ninguna | Viable (.NET); requiere prototipo |
| Qt | ninguna | Maduro/nativo; coste de licencias y empaquetado |
| Flutter | solo guías de lenguaje | Multiplataforma sin precedente de instalador |
| Electron | familiaridad web | Ecosistema amplio; mayor huella y superficie de ataque |

## Criterios de la sonda (pendiente, no ejecutada en F1)

Empaquetado Windows x64/ARM64 y Linux x64/ARM64; accesibilidad (teclado, lector de pantalla, alto
contraste, texto escalable); firma y actualizador; IPC seguro (sin shell desde la UI); huella;
mantenibilidad.

## Condiciones de aceptación

1. Resultado de la sonda con medidas por criterio.
2. La UI solo invoca el Provisioning Core mediante un contrato tipado; nunca ejecuta procesos.
3. Aprobación explícita de la operadora. Hasta entonces F4 (wizard visual) permanece bloqueada.

## Consecuencias

F1 se cierra con contratos y planner de solo lectura. Elegir otro candidato no invalida los
esquemas ni el core.
