---
name: user-profile
description: Gestiona perfiles de miembros del equipo — ver, crear o editar.
argument-hint: "@handle [--edit] [--section skills|vacations|locality]"
model_tier: mid
context_cost: low
tier: core
---

# /user-profile — Perfil de miembro del equipo

**Argumentos:** $ARGUMENTS

> Gestiona datos de miembros: habilidades, debilidades, vacaciones, localidad.
> Estos datos alimentan la asignación de tareas y el cálculo de capacidad.

## 0. Preparación

1. Leer `.claude/profiles/savia.md` — adoptar voz de Savia
2. Parsear `$ARGUMENTS`:
   - `@handle` — obligatorio (sin @ → error)
   - `--edit` — modo edición (sin flag = modo lectura)
   - `--section {s}` — editar solo una sección específica
3. Ruta del perfil: `teams/members/{handle}.md` (sin @)

## 1. Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🦉 /user-profile — Perfil de @{handle}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. Si el perfil NO existe → Crear

Savia inicia conversación para crear el perfil:

> "No tengo perfil de @{handle}. Vamos a crearlo."

Preguntar en orden (una pregunta a la vez, AskUserQuestion):

1. **Nombre completo**
2. **Email**
3. **Rol** — developer, qa, tech-lead, architect, pm, designer
4. **Supervisor** — @handle de su responsable
5. **Localidad** — país, región y ciudad (para festivos)
6. **Skills** — "¿En qué destaca?" (lista, separada por comas)
7. **Dislikes** — "¿Tareas que no le gustan o le cuestan?" (lista)
8. **Vacaciones** — periodos preferidos, periodos a evitar, notas

Guardar en `teams/members/{handle}.md` usando formato de `teams/members/template.md`.

## 3. Si el perfil EXISTE y NO --edit → Mostrar

Leer `teams/members/{handle}.md` y presentar:

```
🧑 @{handle} — {name} ({role})
📧 {email} | 👤 Supervisor: {supervisor}
📍 {city}, {region}, {country}

💪 Skills: {skills como lista}
👎 Prefiere evitar: {dislikes como lista}

🏖️ Vacaciones:
   Prefiere: {preferred_periods}
   Evita: {avoid_periods}
   Notas: {notes}
   Planificadas: {planned_vacations o "ninguna"}

🏢 Equipos: {teams o "sin asignar"}
```

## 4. Si --edit → Editar

Si `--section` especificado → editar solo esa sección.
Si no → preguntar qué editar:

| Sección | Campos |
|---|---|
| `identity` | name, email, role, supervisor |
| `locality` | country, region, city |
| `skills` | skills[], dislikes[] |
| `vacations` | preferred_periods, avoid_periods, notes, planned |

Mostrar valores actuales, preguntar cambios, guardar.

## 5. Banner final

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🦉 Perfil de @{handle} — {acción: creado|mostrado|actualizado}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✏️ /user-profile @{handle} --edit
⚡ /compact
```

## Integración

| Comando | Uso del perfil |
|---|---|
| `/sprint-plan` | Consulta locality → festivos → capacidad real |
| `/pbi-assign` | Consulta skills/dislikes → match de tareas |
| `/capacity-forecast` | Consulta planned_vacations → disponibilidad |
| `/team-orchestrator assign` | Actualiza campo teams[] del perfil |
| `/workload-balance` | Consulta skills para redistribución |

## Restricciones

- Datos personales (RGPD) → fichero git-ignorado
- NUNCA mostrar email completo en informes públicos
- NUNCA commitear perfiles reales al repositorio
