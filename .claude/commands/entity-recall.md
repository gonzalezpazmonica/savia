---
name: entity-recall
description: >
  Consulta Entity Memory — busca información almacenada sobre entidades
  específicas (stakeholders, componentes, decisiones) a través de sesiones.
model_tier: mid
context_cost: low
tier: core
---

# /entity-recall

Consulta la memoria de entidades para recuperar información cross-session.

**Argumentos:** $ARGUMENTS

> Uso: `/entity-recall {entidad}` o `/entity-recall --list`

## Parámetros

- `{entidad}` — Nombre de la entidad a buscar (persona, componente, decisión)
- `--list` — Listar todas las entidades registradas (índice)
- `--type {tipo}` — Filtrar: stakeholder, component, decision, dependency
- `--project {p}` — Filtrar por proyecto
- `--save {entidad}` — Registrar nueva entidad o actualizar existente

## Ejemplos

**✅ Correcto:**
```
/entity-recall auth-service --project alpha
→ auth-service (component): Servicio de autenticación JWT
  Decisiones vinculadas: ADR-003 (migrar a OAuth2)
  Última mención: 2026-03-01 | Contexto: sprint-plan
```

**❌ Incorrecto:**
```
/entity-recall auth-service
→ "No tengo información sobre eso" (sin buscar en memory-store)
Por qué falla: Debe buscar en entity store antes de responder
```

## 1. Banner de inicio

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 /entity-recall — Memoria de Entidades
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. Flujo de consulta

1. Buscar en memory-store con `--type entity` y query = nombre de entidad
2. Si hay resultados → mostrar ficha de entidad con historial
3. Si no hay resultados → buscar en memory-store general por coincidencia
4. Si aún nada → informar y sugerir `/entity-recall --save {nombre}`

## 3. Flujo de guardado (--save)

1. Pedir interactivamente: nombre, tipo, descripción, proyecto
2. Guardar con `memory-store.sh save --type entity --concepts {tipo}`
3. Si la entidad ya existe → actualizar (upsert por topic_key)

## 4. Flujo de listado (--list)

Ejecutar `memory-store.sh search "" --type entity` y formatear:

```
## Entidades Registradas — {N} total

### Stakeholders (3)
- alice (PM) — Proyecto alpha, última mención 2026-03-01
- bob (Tech Lead) — Proyecto beta

### Components (5)
- auth-service — alpha — JWT authentication
- api-gateway — alpha — Kong-based routing

### Decisions (2)
- ADR-003 — Migrar a OAuth2 (alpha)
```

## 5. Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ /entity-recall — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Integración

- `memory-store.sh` — usa tipo `entity` y campo `concepts` para subtipo
- `/project-audit` → puede auto-registrar entidades descubiertas
- `/spec-generate` → puede vincular entidades en specs
- `memory-auto-capture.sh` → captura entidades mencionadas en ediciones

## Restricciones

- Datos genéricos en repos (regla PII-Free #20)
- Entity names deben ser descriptivos funcionales, no nombres reales
