---
layer: peripheral
name: team-onboarding
description: Usar cuando se incorpora un nuevo miembro al equipo y se evalúan sus competencias.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: tech-writer
  savia.maturity: stable
  savia.category: pm-operations
  savia.context: fork
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Onboarding de nuevos miembros: documentacion auto-generada, plan personalizado 30/60/90 y agente buddy de 3 capas. Output: guia de onboarding + plan + checkpoints."
  savia.tags: "onboarding, competencies, ramp-up, team"
---

# Skill: Team Onboarding & Expertise Evaluation

## Cuándo usar esta skill

Invocar cuando se incorpora un **nuevo programador** a un proyecto del workspace:
- El miembro es nuevo en el equipo o en el proyecto
- Se necesita acelerar su ramp-up (de 4-8 semanas a 5-10 días)
- Se quiere registrar su perfil de competencias para el algoritmo de asignación

## Qué produce

Tres outputs que cubren el ciclo completo de incorporación:

1. **Nota informativa RGPD** — documento de transparencia para el trabajador (obligatorio antes de recoger datos)
2. **Guía de onboarding personalizada** — contexto, tour del codebase, checklist día a día
3. **Perfil de competencias** — evaluación que alimenta el campo `expertise` en `equipo.md`

## Flujo completo

```
Nuevo miembro se incorpora al proyecto
    ↓
/team-privacy-notice {nombre}     ← PM genera nota informativa RGPD
    ↓                                (trabajador lee, firma, se archiva)
/team-onboarding {nombre}         ← Fases 1-2: contexto + tour del código
    ↓                                (mentor valida cada fase)
  [Fase 3: primera task asistida]  ← Mentor asigna task B/C, pair programming con Claude
    ↓                                (Code Review humano obligatorio)
/team-evaluate {nombre}            ← Fase 4: cuestionario interactivo de competencias
    ↓                                (autoevaluación + calibración Tech Lead)
  [Fase 5: autonomía progresiva]   ← Semanas 1-3 con supervisión decreciente
```

**Fases 3 y 5 no son comandos** — son procesos humanos guiados por el mentor.

## Cuándo NO usar

- El miembro ya lleva >2 semanas productivo en el proyecto (ya está onboarded)
- Cambio de proyecto de un miembro existente (usar solo `/team-evaluate` para actualizar dominio)
- Becarios o personal de soporte que no escriben código (el cuestionario es para programadores)
- Si no se ha entregado la nota informativa RGPD — `/team-evaluate` verificará esto

## Almacenamiento

Los documentos se guardan en el directorio del proyecto:
```
projects/{proyecto}/privacy/
├── {nombre}-nota-informativa-{fecha}.md     ← Nota RGPD firmada

projects/{proyecto}/onboarding/
├── {nombre}-guia.md                         ← Guía personalizada

projects/{proyecto}/evaluaciones/
├── {nombre}-competencias-{fecha}.yaml       ← Respuestas raw del cuestionario
```

El perfil final se integra directamente en `projects/{proyecto}/equipo.md`.

**Privacidad:** Los directorios `privacy/`, `onboarding/` y `evaluaciones/` están en `.gitignore`. Nunca se suben al repositorio público.

## Plantillas

Las plantillas están en `references/`:
- `references/onboarding-checklist.md` — checklist día a día para mentor y nuevo miembro
- `references/questionnaire-template.md` — cuestionario completo (A: .NET, B: transversal, C: dominio)
- `references/expertise-mapping.md` — algoritmo de conversión respuestas → campo `expertise` en equipo.md
- `references/privacy-notice-template.md` — plantilla de nota informativa Art. 13-14 RGPD

## Agente responsable

- **PM/Scrum Master** — orquesta el proceso completo y genera la nota informativa
- **Mentor humano** — valida fases 1-3, aprueba checkpoints
- **business-analyst** — ejecuta la calibración de competencias (Fase 4) vía `/team-evaluate`
- **Tech Lead** — co-firma la evaluación final de competencias

## Métricas de éxito

| Métrica | Objetivo | Cómo se mide |
|---------|----------|--------------|
| Time-to-First-PR | ≤ 3 días | Timestamp del primer PR aprobado |
| Calidad del primer PR | ≤ 3 rondas de review | Comentarios de code review |
| Confianza autoreportada | ≥ 7/10 | Encuesta al día 5 y día 15 |
| Independencia al día 10 | Puede tomar tasks sin spec | Validación del mentor |
| Retención a 90 días | 100% | Seguimiento HR |

## Conformidad legal

Este skill procesa datos personales (competencias laborales). Ver `references/privacy-notice-template.md` para el marco legal completo. Resumen:

- **Base legal:** Interés legítimo del empleador (Art. 6.1.f RGPD), NO consentimiento
- **Minimización:** Solo competencias (1-5), interés (S/N), fecha. Sin métricas de productividad individual
- **Derechos:** Acceso, Rectificación, Supresión, Oposición, Portabilidad (Arts. 15-21 RGPD)
- **Nota informativa obligatoria** antes de recoger cualquier dato
