---
layer: peripheral
name: onboarding-dev
description: Usar cuando se incorpora un desarrollador nuevo al proyecto y necesita buddy IA.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: tech-writer
  savia.maturity: stable
  savia.category: sdd-framework
  savia.context: fork
  savia.maturity: experimental
  savia.priority: medium
  savia.summary: "Onboarding tecnico con Buddy IA: auto-genera documentacion del proyecto, plan personalizado 30/60/90 y agente buddy de 3 capas. Input: nombre + rol. Output: guia + plan + buddy activo."
  savia.tags: "onboarding, buddy-ia, documentation, ramp-up"
---

# Skill: Onboarding Dev — Buddy IA

> **Seguridad**: `@docs/rules/domain/autonomous-safety.md` — el buddy IA NO toma decisiones, solo orienta.
> **Basado en**: Guía de Onboarding con IA de Manfred (v3.0) — modelo de agente en 3 capas.
> **Complementa**: `team-onboarding` (RGPD, evaluación) — esta skill se enfoca en onboarding técnico.

## Cuándo usar esta skill

- Se incorpora un nuevo desarrollador al proyecto
- Se quiere acelerar el ramp-up de 4-8 semanas a 5-10 días
- Se necesita generar documentación del proyecto automáticamente
- Se busca reducir la dependencia del buddy humano para preguntas repetitivas

## Qué produce

### Fase 1: Auto-análisis (10-12 documentos)
```
projects/{proyecto}/onboarding/
├── 01-arquitectura-alto-nivel.md       ← Diagrama + explicación de servicios y flujos
├── 02-mapa-equipos-ownership.md        ← Quién lleva cada área/sistema
├── 03-glosario-interno.md              ← Vocabulario, siglas, nombres de proyectos
├── 04-herramientas-accesos.md          ← Checklist de configuraciones y accesos
├── 05-setup-local.md                   ← Guía paso a paso + troubleshooting típico
├── 06-flujos-pr-estandares.md          ← Convenciones de commit, PR, review, CI/CD
├── 07-como-se-despliega.md             ← Entornos, releases, rollback, permisos
├── 08-decisiones-tecnicas-clave.md     ← Por qué se eligió X, qué trade-offs se aceptaron
├── 09-historico-incidencias.md         ← Incidencias importantes y postmortems resumidos
├── 10-faq-onboarding.md               ← Preguntas más repetidas y sus respuestas
├── 11-calidad-procesos.md              ← Linting, formato, patrones, anti-patrones, DoD
└── 12-expectativas-rampup.md           ← Qué se espera a los 7 días, 30 días, 90 días
```

### Fase 2: Plan personalizado
```
projects/{proyecto}/onboarding/
├── {nombre}-plan-30-60-90.md           ← Objetivos medibles por periodo
├── {nombre}-checklist-accesos.md       ← Checklist personalizada de accesos y configuraciones
└── {nombre}-primer-pr.md              ← Guía para el primer PR (paso a paso)
```

### Fase 3: Buddy IA activo
El agente queda disponible como buddy interactivo para responder preguntas del nuevo miembro usando la documentación generada como base de conocimiento.

## Prerequisitos

```
1. Proyecto configurado en projects/{nombre}/CLAUDE.md    → si no: ❌ ABORT
2. Acceso al repositorio del proyecto                       → si no: ❌ ABORT
3. equipo.md actualizado con miembros actuales              → si no: ⚠️ continuar con limitaciones
```

## Flujo completo

```
PM ejecuta /onboarding-dev {nombre} --rol {rol} --seniority {jr|mid|sr} --proyecto {nombre}
    ↓
Validar prerequisitos
    ↓
═══ FASE 1: AUTO-ANÁLISIS DEL PROYECTO ═══
    ↓
Analizar repositorio:
  - Leer CLAUDE.md del proyecto
  - Escanear estructura de directorios
  - Identificar tecnologías (package.json, .csproj, requirements.txt, etc.)
  - Leer README, CONTRIBUTING, ARCHITECTURE si existen
  - Analizar git log (últimos 3 meses) para entender actividad reciente
  - Identificar decisiones técnicas en ADRs si existen
    ↓
Generar los 10-12 documentos en projects/{proyecto}/onboarding/
    ↓
Mostrar resumen de documentos generados → PM valida
    ↓
═══ FASE 2: PLAN PERSONALIZADO ═══
    ↓
Adaptar según rol y seniority:
  - Junior: más detalle, más checkpoints, tareas más pequeñas, más pair programming
  - Mid: balance entre autonomía y guía, primer PR en día 2-3
  - Senior: high-level overview, primer PR en día 1-2, foco en decisiones técnicas
    ↓
Generar:
  - Plan 30/60/90 con objetivos medibles
  - Checklist de accesos personalizada (GitHub, Jira, SonarCloud, VPN, Figma, etc.)
  - Guía de primer PR paso a paso
    ↓
═══ FASE 3: BUDDY IA ACTIVO ═══
    ↓
Configurar agente buddy con:
  - Base de conocimiento: documentos generados en Fase 1
  - System prompt con guardarraíles de Manfred (ver abajo)
  - Disponible vía /onboarding-ask {pregunta}
```

## Buddy IA — Comportamiento (Manfred v3.0)

El agente buddy responde con explicaciones breves y accionables, cita fuentes internas (archivo + sección), señala nivel de confianza (alto/medio/bajo), y deriva a personas cuando el tema es sensible (seguridad, compliance). No inventa políticas ni detalles técnicos.

**3 capas**: Orientación (quién/dónde) → Ejecución (setup/PR/deploy) → Contexto (decisiones técnicas pasadas y trade-offs).

**Guardarraíles anti-patrón**: No usar IA para decidir sin entender. Validar decisiones de arquitectura con el equipo. Si no puedes explicar el código, no lo subas. Preguntar primero a la IA, luego al equipo.

## Métricas de ramp-up

| Métrica | Junior | Mid | Senior |
|---------|--------|-----|--------|
| Tiempo hasta primer PR | ≤ 5 días | ≤ 3 días | ≤ 2 días |
| Primer PR aprobado sin cambios | ≤ 10 días | ≤ 5 días | ≤ 3 días |
| Primera contribución significativa | ≤ 30 días | ≤ 15 días | ≤ 7 días |
| Independencia (tasks sin spec) | ≤ 30 días | ≤ 15 días | ≤ 7 días |
| Confianza autoreportada (≥7/10) | Día 15 | Día 10 | Día 5 |

## Cuándo NO usar

- El miembro ya lleva >2 semanas productivo (usar `/team-evaluate` para actualizar perfil)
- Para perfiles no técnicos (usar `team-onboarding` genérico)
- Si no existe CLAUDE.md del proyecto (crear primero con `/project-new`)

## Almacenamiento

Documentación generada en `projects/{proyecto}/onboarding/` — directorio en `.gitignore` por defecto (puede contener info sensible del proyecto).

Plan personalizado en `projects/{proyecto}/onboarding/{nombre}-*.md` — igualmente git-ignorado.
