---
name: context-interview
description: "Entrevista estructurada de contexto para proyectos y clientes"
model_tier: mid
context_cost: high
allowed_tools: ["Bash", "Read", "Write", "Edit", "Task"]
tier: core
---

# /context-interview — Asistente de análisis de contexto

> Reglas: @docs/rules/domain/context-interview-config.md
> Dependencia: @docs/rules/domain/savia-hub-config.md · @docs/rules/domain/client-profile-config.md

## Subcomandos

### /context-interview start {client} [project]

Inicia una entrevista estructurada de contexto.

**Flujo:**
1. Verificar SaviaHub + cliente existen
2. Si hay proyecto → entrevista de proyecto; si no → entrevista de cliente
3. Detectar sector del cliente (vertical-detection si profile.md tiene sector)
4. Seleccionar fases adaptadas al sector
5. Crear fichero de sesión: `interviews/YYYYMMDD-{slug}.md`
6. Iniciar fase 1 con pregunta al PM
7. Cada respuesta → persistir en fichero + avanzar a siguiente pregunta

**Output inicial:**
```
🎤 Entrevista de contexto iniciada
   Cliente: {client} · Proyecto: {project|—}
   Sector detectado: {sector}
   Fases: 8 · Preguntas estimadas: ~{N}

   Fase 1/8 — Dominio
   🦉 {primera pregunta adaptada al sector}
```

### /context-interview resume {client} [project]

Retoma una entrevista pausada.

**Flujo:**
1. Buscar fichero de sesión más reciente para el cliente/proyecto
2. Leer estado: fase actual, preguntas respondidas, pendientes
3. Continuar desde donde se dejó
4. Mostrar progreso

### /context-interview summary {client} [project]

Genera resumen de la información recopilada.

**Flujo:**
1. Leer fichero(s) de entrevista del cliente/proyecto
2. Consolidar respuestas por fase
3. Generar resumen estructurado
4. Opcionalmente actualizar profile.md, rules.md, metadata.md con los datos
5. Mostrar resumen al PM para validación

**Output:**
```
📋 Resumen de contexto — {client}/{project}
   Fases completadas: {N}/8
   Datos recopilados: {N} campos
   Gaps detectados: {N} datos faltantes

   [Resumen por fase]
```

### /context-interview gaps {client} [project]

Detecta información faltante en el perfil del cliente/proyecto.

**Flujo:**
1. Leer profile.md, contacts.md, rules.md, metadata.md
2. Comparar contra esquema completo esperado por fase
3. Listar campos vacíos o incompletos
4. Sugerir preguntas para cubrir los gaps
5. Opcionalmente iniciar mini-entrevista focalizada

**Output:**
```
🔍 Gaps detectados — {client}/{project}
   Fase 1 (Dominio): ⚠️ 2 campos vacíos
   Fase 2 (Stakeholders): ✅ Completa
   ...
   Total: {N} gaps · Preguntas sugeridas: {N}
```

## 8 Fases de la entrevista

| # | Fase | Foco |
|---|------|------|
| 1 | Dominio | Área de negocio, terminología, conceptos clave |
| 2 | Stakeholders | Personas, roles, responsabilidades, decisores |
| 3 | Stack tecnológico | Lenguajes, frameworks, infra, entornos |
| 4 | Restricciones | Limitaciones técnicas, presupuesto, regulación |
| 5 | Reglas de negocio | Lógica de dominio, validaciones, excepciones |
| 6 | Compliance | Normativa aplicable (sector-adaptativa) |
| 7 | Timeline | Hitos, deadlines, fases del proyecto |
| 8 | Resumen | Validación final con el PM, gaps pendientes |

## Adaptación por sector

La fase 6 (Compliance) se adapta al sector detectado:
- **Fintech/Banking**: PCI-DSS, PSD2, MiFID II
- **Healthcare**: HIPAA, HL7/FHIR
- **Legal**: GDPR, retención documental
- **Education**: COPPA, GDPR Art. 8
- **General**: GDPR/LOPD básico

## Errores

- SaviaHub no existe → sugerir `/savia-hub init`
- Cliente no encontrado → sugerir `/client-create`
- Entrevista no encontrada → sugerir `/context-interview start`
- Fase sin respuestas → marcar como gap, no bloquear avance
