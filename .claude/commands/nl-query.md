---
name: nl-query
description: "Consultas en lenguaje natural — habla con Savia sin memorizar comandos"
developer_type: all
agent: task
context_cost: medium
model_tier: mid
tier: core
---

# /nl-query — Natural Language Command Resolution

> Savia entiende lo que preguntas y ejecuta el comando correcto.

---

## Uso

```
/nl-query {pregunta}                    # Interpretar y ejecutar
/nl-query --explain {pregunta}          # Mostrar qué ejecutaría sin hacerlo
/nl-query --learn {frase} → {comando}   # Enseñar mapeo personalizado
/nl-query --history                     # Últimas 10 consultas mapeadas
```

---

## Proceso

**1. Cargar perfil**: leer `active-user.md`, obtener proyecto/sprint/rol activos.

**2. Cargar catálogo**: leer `intent-catalog.md`, buscar patrón más similar a pregunta.

**3. Score confianza**: patrón_base (70-95%) + bonus_contexto (+0-5%) + bonus_historial (+0-3%).

**4. Decisión**:
- **≥80%**: ejecutar directo
- **50-79%**: confirmar antes
- **<50%**: sugerir top 3 opciones

**5. Resolver parámetros**: proyecto, sprint, persona, flags (`--format`, `--filter`).

**6. Ejecutar**: correr comando, mostrar resultado.

**7. Registrar**: guardar mapeo exitoso en memoria persistente (concept: `nl-mapping`).

---

## Subcomandos

| Subcomando | Efecto |
|---|---|
| `/nl-query ¿...?` | Interpretar y ejecutar automáticamente |
| `/nl-query --explain ¿...?` | Mostrar comando sin ejecutar (preview) |
| `/nl-query --learn frase → cmd` | Guardar mapeo personalizado en memoria |
| `/nl-query --history` | Últimas 10 mapeos + fechas |

---

## Ejemplo

```
Usuario: ¿cómo va el sprint?

🔍 Mapeado: /sprint-status
📊 Confianza: 92% | Proyecto: sala-reservas | Sprint: 2026-06
[Ejecutando...]

✅ Sprint 2026-06: 43/48 SP completados (90%)
⏱️  Velocidad: 43 SP (histórico: 41-45)
⚠️  3 items bloqueados > 2 días
💡 Llegaremos a tiempo. Revisar bloqueados.
```

---

## Restricciones

- **NUNCA** ejecutar `--delete|--drop|--destroy|--reset` sin confirmación
- **NUNCA** adivinar si confianza < 50%
- **NUNCA** ignorar permisos de rol
- **NUNCA** mapear a comando inexistente

Ver `nl-command-resolution.md` para lógica detallada.

---

## Índice de Comandos

Catálogo completo: `.opencode/commands/references/intent-catalog.md`

Top 20 mapeados en la sección **Core Mappings** del catálogo.

Actualizar con `/nl-query --learn` o revisar con `/memory-search`.
