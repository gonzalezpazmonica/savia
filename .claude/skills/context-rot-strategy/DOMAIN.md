# Context Rot Strategy — DOMAIN (Clara Philosophy)

> Por que importa. Cuando aplica. Que evita. Que provoca si se ignora.

## Problema de negocio

Los modelos con ventanas grandes (1M tokens, Opus 4.7) no escalan su atencion linealmente con el tamano del contexto. Hay degradacion de calidad antes del limite fisico — el famoso *context rot*. Un desarrollador que trabaja con sesiones largas sin estrategia de corte experimenta:

- Respuestas que ignoran ficheros recientes porque la atencion se diluyo
- Diagnosticos fallidos acumulados que enturbian el siguiente intento
- Auto-compacts automaticos que disparan en el peor momento (cerca del limite) y pierden justo lo que necesitabas
- Sesiones de 8 horas que producen menos que 4 sesiones de 2 horas con cortes limpios

## Por que ahora (Era 186)

Opus 4.7 introduce la ventana de 1M tokens como default para sesiones IA (tier `heavy`; el modelo concreto se resuelve en la definición local de tiers, `~/.savia/preferences.yaml`). Antes, las sesiones de 200K se cortaban solas por limite fisico. Ahora, el limite fisico esta tan lejos que la calidad se degrada antes de tocarlo.

Sin una estrategia explicita, los usuarios:
1. Siguen trabajando en una sesion porque "aun cabe"
2. Experimentan bajada de calidad silente
3. Cuando auto-compact dispara, el resumen es pobre
4. Culpan al modelo en lugar de al workflow

## Que hace este skill

Formaliza un **modelo mental de 5 opciones** per turno — continue, rewind, /compact con hint, /clear, subagent — y umbrales numericos (60% amarillo, 75% rojo, 90% critico) para elegir la accion correcta antes de que la degradacion ocurra.

No automatiza decisiones (el usuario decide). Sirve como rubrica consultable.

## Que evita

- Auto-compacts disparados en el peor momento (pico de context rot)
- Sesiones zombies que producen menos por token gastado
- Perdida de trabajo por compacts lossy mal dirigidos
- Narrar fallos en contexto cuando rewind deja la sesion mas limpia

## Que provoca si se ignora

**Evidencia real observada**: sesiones de 8h con Opus 4.7 + 1M context donde:
- Primera hora: outputs de alta calidad
- Hora 3-4: el modelo empieza a ignorar ficheros leidos en hora 1-2
- Hora 5-6: auto-compact dispara, resume con sesgo al final de la sesion, pierde decisiones iniciales
- Hora 7-8: productividad efectiva equivale a 2h frescas

Coste de oportunidad: 4h de trabajo perdidas por turno vs cortes proactivos.

## Cuando NO aplicar

- Sesion < 30 min (corte prematuro, overhead sin beneficio)
- Tarea mecanica repetitiva donde el contexto es irrelevante (ej: 30 renames)
- Usuario con flujo establecido que ya hace cortes implicitos

## Relacion con otras skills

| Skill | Que cubre | Relacion |
|---|---|---|
| `context-budget` | Presupuesto per sesion | Complementario — budget plantea el limite, rot-strategy como llegar sin degradar |
| `context-compress` | Compresion semantica manual | Subordinado — compact con hint usa esta logica |
| `context-optimized-dev` | Desarrollo con 40% libre | Complementario — dev optimization es preventivo, rot-strategy es reactivo |
| `context-defer` | Carga diferida | Complementario — defer evita cargar, rot-strategy libera lo cargado |

## Fitness function

Skill exitoso si:
- Las sesiones largas (>2h) mantienen calidad estable de output hasta el final
- Los auto-compacts se disparan menos frecuentemente (< 1 por sesion de 4h)
- El usuario puede articular que accion tomar cuando el counter sube (no adivina)

Skill fallido si:
- Usuarios ignoran la rubrica y siguen teniendo auto-compacts en peor momento
- Compacts manuales no usan hint (lossy indiscriminado)
- Sesiones zombies persisten

## Referencias

- Anthropic Opus 4.7 migration guide: "Context rot is real"
- SPEC-069 propuesta
- Memory feedback_session_journal (session-journal.md como soporte para /clear)
- Settings `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75`
