---
name: ai-confidence
description: "Transparencia: Savia muestra confianza, razonamiento, datos y limitaciones de cada recomendación"
developer_type: all
agent: task
context_cost: low
tier: extended
---

# /ai-confidence

> 🦉 Confía menos en lo que Savia te dice. Confía en lo que Savia te EXPLICA.

Mostrar transparentemente el nivel de confianza, cadena de razonamiento, fuentes de datos y limitaciones de cada recomendación.

---

## Niveles de Confianza

- **ALTA** (80-100%) — Datos históricos + múltiples fuentes coherentes
- **MEDIA** (40-79%) — Datos limitados o cierto grado de especulación
- **BAJA** (0-39%) — Especulativa, requiere validación humana

---

## Formato de Salida

Cada recomendación incluye:

```
💡 Recomendación: [texto]
📊 Confianza: [ALTA|MEDIA|BAJA] (NN%)
🧠 Razonamiento: [pasos 1...n]
📋 Datos utilizados: [fuentes citadas]
⚠️ Limitaciones: [qué falta, asupciones, edge cases]
🔄 Alternativas descartadas: [por qué no]
👤 Requiere validación: [SÍ|NO]
```

---

## Flujo

1. **Paso 1** — Leer `active-user.md` (detectar rol)
2. **Paso 2** — Activar modo transparencia para la sesión
3. **Paso 3** — Generar recomendación con estructura completa
4. **Paso 4** — Mostrar nivel de confianza + limitaciones
5. **Paso 5** — Sugerir acciones de validación si confianza < 50%

---

## Restricciones

- **NUNCA** ocultar limitaciones
- **NUNCA** inferir confianza sin datos
- **NUNCA** recomendar acciones con confianza < 30% sin advertencia
- **SIEMPRE** citar fuentes (ficheros, APIs, cálculos)
- **SIEMPRE** reconocer asupciones y edge cases
- Si falta información crítica → confianza baja

---

## Configuración

En `company/policies.md`:

```yaml
confidence:
  show_reasoning: true
  show_data_sources: true
  show_alternatives: true
  min_confidence_for_auto: 80
  require_validation_under: 50
```

---

## Integración

Complementa:
- `/ai-boundary` — límites de autonomía
- `/ai-incident` — histórico de errores similares
- `/ai-safety-config` — niveles de supervisión

Ver `@docs/rules/domain/command-ux-checklist.md` para ejemplos.
