---
name: debt-track
description: >
  Registro y seguimiento manual de deuda técnica por proyecto.
  Ratio de deuda, tendencia por sprint, integración con SonarQube.
  NOTA: Para análisis automatizado, ver /debt-analyze, /debt-prioritize, /debt-budget
model_tier: mid
context_cost: medium
tier: core
---

# Debt Track

**Argumentos:** $ARGUMENTS

> Uso: `/debt-track --project {p}` o `/debt-track --project {p} --add`

## 1. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Architecture & Debt** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/projects.md`
   - `profiles/users/{slug}/preferences.md`
3. Adaptar profundidad del análisis según `preferences.detail_level`
4. Si no hay perfil → continuar con comportamiento por defecto

## 2. Banner de inicio

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 /debt-track — Registro de deuda técnica
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Ejemplos

**✅ Correcto:**
```
/debt-track --project alpha --add
→ Pide: descripción, severidad, esfuerzo estimado, componente afectado
→ Registra en projects/alpha/debt-register.md con ID incremental
```

**❌ Incorrecto:**
```
/debt-track --project alpha --add
→ Registrar deuda sin pedir severidad ni componente
Por qué falla: Items sin clasificar impiden priorización posterior
```

## 3. Parámetros

- `--project {nombre}` — Proyecto (obligatorio)
- `--add` — Registrar nuevo item de deuda técnica
- `--resolve {id}` — Marcar item como resuelto
- `--sprint-report` — Informe de deuda del sprint actual
- `--sonarqube {url}` — Importar métricas desde SonarQube
- `--severity {critical|high|medium|low}` — Filtrar por severidad

Si falta `--project`:
```
❌ Falta parámetro obligatorio: --project {nombre}
   Proyectos disponibles: [listar de projects/*/CLAUDE.md]
   Uso: /debt-track --project nombre
```

## 4. Verificar prerequisitos

```
Verificando requisitos para "{proyecto}"...
  ✅ Proyecto: projects/{proyecto}/CLAUDE.md
  ✅ Registro: projects/{proyecto}/debt-register.md (12 items)
```

Si no existe `debt-register.md`:
```
  ⚠️ No existe registro de deuda. Se creará uno nuevo.
```

## 4. Ejecución

### Modo vista (por defecto)

```
📋 Paso 1/3 — Leyendo registro de deuda...
📋 Paso 2/3 — Calculando métricas y tendencia...
📋 Paso 3/3 — Generando dashboard...
```

1. Leer `projects/{proyecto}/debt-register.md`
2. Calcular: items abiertos por severidad, debt ratio, tendencia 5 sprints, edad media
3. Si `--sonarqube` → importar code smells, bugs, vulnerabilities
4. Presentar dashboard (ver formato abajo)

### Modo `--add`
1. Solicitar interactivamente: descripción, severidad, componente, estimación
2. Añadir al registro con ID auto-incrementable
3. Sugerir sprint para resolución según capacity

### Modo `--sprint-report`
1. Generar informe de evolución
2. Guardar en `output/debt/YYYYMMDD-debt-{proyecto}.md`

## 5. Formato de salida

```
## Deuda Técnica — {proyecto} — Sprint {n}

Debt Ratio: 18% (objetivo < 20%) 🟢
Items abiertos: 12 | Resueltos este sprint: 3 | Nuevos: 2
Tendencia: 📉 mejorando (-2 vs sprint anterior)

| ID | Severidad | Descripción | Edad | Asignado |
|---|---|---|---|---|
| DT-01 | critical | SQL injection en AuthController | 3 sprints | — |
| DT-02 | high | Sin tests en módulo de pagos | 2 sprints | Ana |

Recomendación: Incluir DT-01 en el próximo sprint
```

## 6. Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ /debt-track — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Debt ratio: X% | {N} abiertos | Tendencia: 📈/📉/→
```

## Integración con Debt Intelligence

**Automated Analysis (para análisis técnico profundo):**
- `/debt-analyze` — Detecta hotspots de complejidad, acoplamiento, code smells
- `/debt-prioritize` — Prioriza items por impacto de negocio y frecuencia
- `/debt-budget` — Propone % del sprint basado en tendencias de velocity

**Manual Tracking (para gestión de items específicos):**
- `/debt-track` — Registro manual de deuda, versión más ligera
- Útil para equipos pequeños o proyectos con deuda muy manual/heredada

**Uso recomendado**: `/debt-analyze` para descubrimiento, `/debt-track` para seguimiento.

## Integración

`/kpi-dashboard` (debt ratio), `/sprint-plan` (sugiere deuda), `/project-audit` (evalúa salud)

## Restricciones

- Registro en markdown, no en Azure DevOps (salvo `--create-pbi`). SonarQube opcional.
