---
layer: peripheral
name: context-interview-conductor
description: Usar cuando se necesita recopilar contexto estructurado de un usuario mediante entrevista guiada.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: communication
  savia.maturity: stable
  savia.context_cost: high
  savia.dependencies: "savia-hub-sync, client-profile-manager"
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Conduce entrevistas estructuradas de contexto para proyectos nuevos. Genera preguntas adaptativas, captura respuestas y produce documento de contexto completo para el equipo."
  savia.tags: "interview, context, structured, discovery"
---

# Skill: Context Interview Conductor

> Regla: @docs/rules/domain/context-interview-config.md
> Hub: @docs/rules/domain/savia-hub-config.md

## Prerequisitos

- SaviaHub inicializado
- Cliente existe en `clients/{slug}/`
- Si proyecto → `clients/{slug}/projects/{project}/` existe

## Flujo: Iniciar entrevista

1. Verificar SaviaHub + cliente (+ proyecto si aplica)
2. Leer `profile.md` → extraer sector (si existe)
3. Si sector vacío → preguntar sector al PM en fase 1
4. Crear `interviews/` dir si no existe: `mkdir -p interviews/`
5. Generar nombre de sesión: `YYYYMMDD-{project|general}.md`
6. Escribir frontmatter: client, project, started, status=in-progress, phase=1
7. Adaptar preguntas de fase 6 según sector detectado
8. Lanzar fase 1 con primera pregunta

## Flujo: Conducir fase

Para cada fase (1-7):
1. Mostrar banner: `Fase {N}/8 — {nombre}`
2. Formular pregunta (UNA a la vez)
3. Esperar respuesta del PM
4. Persistir respuesta bajo la sección de la fase en el fichero de sesión
5. Actualizar fichero destino (profile.md, contacts.md, rules.md, metadata.md)
6. Si hay más preguntas en la fase → siguiente pregunta
7. Si fase completa → avanzar `current_phase` en frontmatter

Reglas de conducción:
- **Una pregunta a la vez** — no bombardear
- **Sin bloqueo** — si PM no sabe → marcar gap, avanzar
- **Ejemplos** — ofrecer cuando la pregunta es abstracta
- **Inconsistencias** — detectar y preguntar amablemente
- **Persistencia inmediata** — guardar cada respuesta al instante

## Flujo: Fase 8 (Resumen)

1. Leer todas las respuestas de fases 1-7
2. Generar resumen consolidado por sección:
   - Dominio: {resumen}
   - Stakeholders: {N} personas identificadas
   - Stack: {lenguajes}, {infra}
   - Restricciones: {N} documentadas
   - Reglas: {N} definidas
   - Compliance: {normativas}
   - Timeline: {N} hitos
3. Detectar gaps: campos vacíos vs esquema esperado
4. Presentar resumen + gaps al PM
5. Si PM valida → status=completed
6. Commit: `[savia-hub] interview: complete {client}/{project}`
7. Si remote + no flight-mode → push

## Flujo: Resume

1. Buscar `interviews/*.md` del cliente/proyecto → ordenar por fecha desc
2. Leer la más reciente con status=in-progress o paused
3. Extraer current_phase y última pregunta respondida
4. Mostrar progreso: `Fase {N}/8 · {M} respuestas · {G} gaps`
5. Continuar con siguiente pregunta pendiente

## Flujo: Summary

1. Leer todos los ficheros de entrevista del cliente/proyecto
2. Consolidar respuestas por fase (priorizar más recientes)
3. Generar resumen en formato legible
4. Opción: actualizar profile.md, rules.md, metadata.md con datos nuevos
5. Requiere confirmación del PM antes de sobrescribir

## Flujo: Gaps

1. Leer profile.md, contacts.md, rules.md, metadata.md
2. Comparar contra esquema mínimo por fase:
   - Fase 1: area_negocio, producto, usuarios_finales
   - Fase 2: ≥1 contacto con rol
   - Fase 3: ≥1 lenguaje, infra
   - Fase 4: ≥1 restricción
   - Fase 5: ≥1 regla
   - Fase 6: normativa identificada
   - Fase 7: ≥1 hito con fecha
   - Fase 8: resumen validado
3. Listar gaps con sugerencia de pregunta para cada uno
4. Opción: iniciar mini-entrevista focalizada en los gaps

## Preguntas adaptativas por sector

### Fintech/Banking (fase 6)
- ¿Procesáis datos de tarjetas? (PCI-DSS)
- ¿Operáis servicios de pago? (PSD2)
- ¿Gestión de inversiones? (MiFID II)

### Healthcare (fase 6)
- ¿Datos de pacientes? (HIPAA/RGPD sanitario)
- ¿Interoperabilidad con otros sistemas? (HL7/FHIR)

### General (fase 6)
- ¿Datos personales de ciudadanos EU? (GDPR/LOPD)
- ¿Transferencias internacionales de datos?

## Errores

| Error | Acción |
|-------|--------|
| SaviaHub no existe | Sugerir `/savia-hub init` |
| Cliente no existe | Sugerir `/client-create` |
| Entrevista no encontrada | Sugerir `/context-interview start` |
| Fase sin respuestas | Marcar gap, permitir avance |

## Seguridad

- NUNCA incluir credentials en sesiones de entrevista
- Datos con `<private>` → respetar, no incluir en resúmenes públicos
- Confirmar con PM antes de push al remote
