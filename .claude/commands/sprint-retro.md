---
name: sprint-retro
description: Genera la plantilla de retrospectiva con datos del sprint para facilitar la ceremonia.
model_tier: mid
context_cost: medium
tier: core
---

# /sprint-retro

Genera la plantilla de retrospectiva con datos del sprint para facilitar la ceremonia.

## 1. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Sprint & Daily** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/workflow.md`
   - `profiles/users/{slug}/projects.md`
   - `profiles/users/{slug}/tone.md`
3. Adaptar output según `tone.alert_style` y `workflow.daily_time`
4. Si no hay perfil → continuar con comportamiento por defecto

## 2. Uso
```
/sprint-retro [proyecto] [--sprint "Sprint 2026-XX"]
```

## 3. Pasos de Ejecución

1. Obtener datos del sprint cerrado (mismos que /sprint-review si ya se ejecutó)
2. Recuperar action items de la retro anterior desde `projects/<proyecto>/sprints/<sprint-anterior>/retro-actions.md`
3. Verificar cuáles action items se han cumplido (revisar estado en Azure DevOps si generaron tasks)
4. Calcular métricas de tendencia (velocity, cycle time, bug rate) vs sprint anterior
5. Generar plantilla con datos pre-cargados
6. Guardar en `projects/<proyecto>/sprints/<sprint>/retro-template.md`

## 4. Formato de Salida

```
## Retrospectiva — [Sprint Name] — [Fecha]
**Facilitador:** [PM/Scrum Master] | **Participantes:** [equipo]

---

### ✅ Action Items Sprint Anterior
| # | Acción | Responsable | Estado |
|---|--------|-------------|--------|
| 1 | [acción] | [persona] | ✅ Hecho / ❌ Pendiente / ⏳ En progreso |

---

### 📊 Datos del Sprint (para contexto)
- Velocity: X SP (anterior: Y SP) → 📈/📉 X%
- Items completados: X/Y
- Bugs encontrados: X
- Cycle Time medio: X días
- Interrupciones reportadas: X (ver daily notes)

---

### 🟢 ¿Qué fue bien? (Start Doing / Keep Doing)
[espacio para respuestas del equipo]
-
-

### 🔴 ¿Qué mejorar? (Stop Doing / Improve)
[espacio para respuestas del equipo]
-
-

### 💡 Ideas / Experimentos
-
-

---

### 📌 Action Items de Esta Retro
| # | Acción | Responsable | Fecha límite | Task AzDO |
|---|--------|-------------|--------------|-----------|
| 1 | | | | AB#XXXX |

---
*Guardado en: projects/<proyecto>/sprints/<sprint>/retro-actions.md*
```
