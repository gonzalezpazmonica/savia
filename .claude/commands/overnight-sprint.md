---
name: overnight-sprint
description: Launch autonomous overnight sprint — executes low-risk tasks, creates PRs for human review
tier: core
---

# /overnight-sprint

Lanza un sprint nocturno autónomo que ejecuta tareas de bajo riesgo en bucle y genera PRs Draft. La operadora única puede revisar y mergear sus PRs bajo grant expreso.

## 1. Cargar configuración

1. Leer `@docs/rules/domain/autonomous-safety.md` — reglas de seguridad (OBLIGATORIO)
2. Leer `@docs/rules/domain/pm-config.md` + `pm-config.local.md` — obtener constantes
3. Leer `.opencode/skills/overnight-sprint/SKILL.md` — flujo completo

## 2. Uso

```
/overnight-sprint [--project {nombre}] [--max-tasks {n}] [--dry-run]
```

- `--project`: Proyecto específico (default: proyecto activo)
- `--max-tasks`: Sobreescribir OVERNIGHT_MAX_TASKS
- `--dry-run`: Solo mostrar tareas candidatas sin ejecutar

## 3. Gate de arranque

Verificar en orden estricto:

```
✅ Operadora identificada o reviewer distinto elegible → si no: ❌ "Falta ruta de revisión humana"
✅ Doble opt-in (env o grant + --confirm-autonomous) → si no: ❌ "Modo nocturno desactivado"
✅ Tests del proyecto pasan            → si no: ❌ "Baseline roto. Corrige tests antes de lanzar"
✅ Hay tareas overnight-safe           → si no: ⚠️ "No hay tareas candidatas"
```

## 4. Confirmación humana

Mostrar:

```
🌙 Overnight Sprint — {proyecto}

📋 Tareas candidatas: {n}
👤 Revisión: {reviewer elegible u operadora única}
⏱️ Time-box por tarea: {AGENT_TASK_TIMEOUT_MINUTES} min
🛑 Max fallos consecutivos: {AGENT_MAX_CONSECUTIVE_FAILURES}

Tareas:
  1. [AB-1234] Fix linter warnings in auth module
  2. [AB-1235] Add unit tests for user service
  3. [AB-1236] Refactor DTOs for consistency
  ...

¿Confirmar arranque? (s/n)
```

**SIEMPRE pedir confirmación.** El modo autónomo NO arranca sin aprobación explícita del humano.

## 5. Ejecución

Invocar skill `overnight-sprint` con los parámetros validados.

## 6. Output

Al completar, mostrar:

```
🌙 Overnight Sprint — Completado

✅ PRs creados: {n} (ruta de revisión: {reviewer u operadora única})
⚠️ Descartados: {n}
❌ Crashes: {n}
⏱️ Duración total: {hh:mm}

📄 Resultados: output/overnight-results-{fecha}.tsv
📋 Resumen: output/overnight-summary-{fecha}.md
📝 Audit log: output/agent-runs/overnight-{fecha}-audit.log

⚡ /compact
```
