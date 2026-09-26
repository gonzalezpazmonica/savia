---
name: my-focus
description: Modo focus — identifica el item más prioritario y carga todo su contexto
developer_type: all
agent: none
context_cost: medium
model_tier: fast
complexity_tier: mode1
tier: core
---

# /my-focus

> 🦉 Savia elimina el ruido y te enfoca en lo que más importa ahora mismo.

---

## Cargar perfil de usuario

Grupo: **SDD & Agentes** — cargar:

- `identity.md` — nombre, rol
- `workflow.md` — reviews_agent_code, specs_per_sprint
- `projects.md` — sdd_enabled en proyecto target

---

## Subcomandos

- `/my-focus` — item más prioritario con contexto completo
- `/my-focus --next` — segundo item en cola de prioridad
- `/my-focus --list` — top 3 items ordenados por prioridad

---

## Flujo

### Paso 1 — Identificar item prioritario

Ordenar items asignados al usuario por:

1. **Bloqueante** (bloquea a otros) → prioridad máxima
2. **Severidad** (Critical > High > Medium > Low)
3. **Días en progreso** (más días → más urgente)
4. **Dependencias resueltas** (item listo para avanzar)

### Paso 2 — Cargar contexto del item

Para el item seleccionado:

1. Spec SDD asociada (si existe)
2. Tests existentes relacionados
3. Ficheros de código involucrados
4. Agent-notes relevantes
5. PR abierto (si existe)
6. Comentarios o decisiones del PBI

### Paso 3 — Mostrar focus view

```
🦉 Focus Mode — {título del item}

🎯 #{id} — {tipo} — {prioridad}
   Estado: {estado} — {días en progreso} días
   Sprint: {sprint-name}

📄 Contexto cargado:
   Spec: {spec-file} (status: {approved|draft|none})
   Tests: {N} existentes, {N} pendientes
   Código: {lista de ficheros relevantes}
   Agent-notes: {N} notas relacionadas

📌 Siguiente acción sugerida:
   {sugerencia basada en estado actual}

💡 Tip:
   {consejo contextual: ejecutar tests, crear spec, pedir review...}
```

### Sugerencias contextuales

| Estado | Sugerencia |
|---|---|
| New, sin spec | "Genera la spec con `/spec-generate`" |
| New, con spec | "Implementa con `/spec-implement`" |
| Active, sin tests | "Crea tests primero (TDD)" |
| Active, con tests | "Continúa implementación" |
| In Review | "Revisa feedback del PR" |
| Blocked | "Resuelve bloqueante: {descripción}" |

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: my_focus
item_id: 1234
title: "Implementar login OAuth"
priority: high
days_in_progress: 2
spec: projects/app/specs/s14/PBI-1234.spec.md
tests: 3
files: 5
suggested_action: "Continue implementation"
```

---

## Restricciones

- **NUNCA** cambiar el estado del item automáticamente
- **NUNCA** ejecutar comandos sin confirmación
- Solo sugerir — el developer decide qué hacer
