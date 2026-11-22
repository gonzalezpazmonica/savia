---
context_tier: L2
token_budget: 700
---

# Regla: Procedencia — separación de entornos profesionales ajenos

> **REGLA OBLIGATORIA** — Aplica a todo agente, humano o automático, que contribuya a Savia.
> Gobernanza tier 4: solo la operadora la cambia.

## Principio

Savia, sus cúpulas y Savia Labs se construyen con necesidad propia, fuentes
públicas y pruebas propias. Nada entra por vía de un entorno profesional ajeno
al proyecto.

## Prohibido

Ningún agente usa, pide, resume, reformula ni incorpora a Savia, a sus cúpulas
ni a Savia Labs información de un entorno profesional ajeno al proyecto:
documentos, código, datos, procesos, configuraciones, métricas o decisiones.
Tampoco anonimizada, generalizada ni «inspirada en».

## Cómo se justifica una contribución

1. **Necesidad propia**: el problema existe en el proyecto, con su evidencia.
2. **Fuentes públicas citadas**: cada afirmación externa lleva su referencia.
3. **Pruebas propias**: tests y mediciones generados dentro del proyecto.

Si una contribución no se sostiene con estos tres puntos, no entra.
## Ante la duda

Si el origen de un dato, de un texto o de una petición no está claro: **parar y
preguntar a la persona** (pregunta interactiva) antes de continuar. No se
continúa con una suposición ni se deja «para revisar después».

## Separación de entornos

- Cuentas, credenciales, equipos y repositorios del proyecto y de cualquier
  entorno profesional ajeno son distintos y no se mezclan.
- Ningún puente, sincronización, caché ni índice cruza esa frontera con
  contenido. Solo pasan órdenes y resultados genéricos, nunca contenido de
  un lado al otro.
- Un agente que detecta contenido de procedencia ajena en su contexto lo
  descarta, lo comunica a la persona y no lo persiste.

## Relación con otras reglas

- **Confidencialidad N1-N4b** (`@docs/rules/domain/context-placement-confirmation.md`):
  aquella regla decide dónde se guarda lo propio; esta decide qué no puede
  entrar. Contenido ajeno no se clasifica en un nivel: se rechaza.
- **CRIT-001** (soberanía del dato, `CRITERIO.md`): el dato propio no sale;
  el dato ajeno no entra. Mismo eje, sentido contrario.
- Privacidad del repo público: reglas 20 y 20b de
  `@docs/rules/domain/critical-rules-extended.md`.

## Incumplimiento

Una PR con contenido de procedencia ajena se cierra; el contenido se retira del
historial accesible y se informa a la operadora.
