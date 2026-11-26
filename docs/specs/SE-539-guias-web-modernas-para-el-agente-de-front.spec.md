---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-26
author: Savia
phase: D
risk: L2
human_surface: false
related_specs: [SE-535, SE-465, SE-538, SE-537]
origin: "Petición de la operadora del 2026-11-26 («A ver si podemos mejorar nuestros agentes de programación de front») sobre github.com/GoogleChrome/modern-web-guidance; forma de entrada decidida por pregunta interactiva el mismo día."
timeline:
  - from: "2026-11-26"
    learned: "2026-11-26"
    value: "PROPOSED"
    source: "orquestadora; decisión de la operadora en pregunta interactiva del 2026-11-26"
---
# SE-539 — Guías web modernas para el agente de front, en copia fija y sin código

## Problema (verificado el 2026-11-26)

1. **El agente de front no sabe de la plataforma.** `.claude/agents/frontend-developer.md` trae convenciones de React y Angular (hooks, estado, TanStack, Signals), pero nada sobre HTML, CSS y APIs del navegador: ni `<dialog>` nativo, ni popover, ni accesibilidad, ni movimiento reducido, ni modo oscuro por tokens, ni INP. Sin esa referencia, el agente reconstruye a mano con patrones viejos lo que el navegador ya da hecho (trampas de foco, `role="dialog"`, bloqueo de scroll con `overflow: hidden`).
2. **Hay una buena referencia, pero su forma de entrar no vale.** `GoogleChrome/modern-web-guidance` (Apache-2.0, commit `2b4aa13a72dd47cd135b06ce5abfccd92e19b24f`, consultado el 2026-11-26) publica 211 guías en Markdown, unos 2 MB, por casos de uso: componentes, formularios, accesibilidad, rendimiento, seguridad y diseño visual. Su skill oficial (`skills/modern-web-guidance/SKILL.md`) manda ejecutar `npx -y modern-web-guidance@latest search|retrieve` al empezar **cada** tarea de front, es decir, descargar y ejecutar código de npm sin versión fijada, con red. Eso contradice el fijado de instalaciones (SE-465) y la condición de reapertura de SE-535 (origen fijado a un commit, copia en vez de ejecución, actualizar es volver a entrar).
3. **Las guías se citan entre sí con esa orden.** Cada referencia cruzada tiene la forma ``(via `npx -y modern-web-guidance@latest retrieve "<id>"`)``: solo en `ui-components/dialog.md` hay 4. Copiadas tal cual, invitarían al agente a ejecutar npx.

## Decisión de la operadora (2026-11-26, pregunta interactiva)

| Pregunta | Respuesta literal |
|---|---|
| ¿Cómo traemos las guías? | «Copia fija, sin código (Recommended)» |

Las opciones descartadas fueron «Plugin oficial tal cual» y «Solo consulta a mano».

## Qué decide esta spec

### D1 — Solo texto, en commit fijado

Se copian solo `skills/modern-web-guidance/guides/**/*.md`, con `LICENSE` y un `NOTICE` de procedencia (URL, commit de 40 hexadecimales, fecha y hash del árbol), en `references/modern-web-guidance/`. No se copia `modern-web.mjs`, ni los manifiestos de plugin, ni la skill `chrome-extensions`, ni las políticas. Copia defensiva según el diseño en reserva de SE-535: solo ficheros regulares `.md`, sin enlaces, sin bits de ejecución, con un tope de 300 ficheros y 4 MB.

### D2 — Referencias cruzadas reescritas a rutas locales

Al copiar, cada ``(via `npx -y modern-web-guidance@latest retrieve "<id>"`)`` pasa a ser un enlace relativo al `.md` local. Una referencia a un id que no existe en la copia hace fallar la importación. La copia final no contiene la cadena `npx`.

### D3 — Búsqueda local

`scripts/web-guidance.sh search "<consulta>"` devuelve `id` y descripción de las guías que casan (título, «Overview» y nombre de fichero), sin red. `scripts/web-guidance.sh show <id>` imprime la ruta de la guía. Sin índice vectorial: un `grep` con puntuación por términos basta para 211 ficheros. Si más adelante se quiere una búsqueda mejor, se decide con datos de uso.

### D4 — El agente de front consulta antes de un patrón de interfaz

En `frontend-developer.md`, el protocolo de inicio gana un paso: antes de implementar un componente o un comportamiento de interfaz (diálogo, formulario, tabla, animación, tema, accesibilidad, rendimiento de interacción), busca en la copia local y lee la guía que case. En el informe final cita qué guía aplicó y en qué punto se apartó de ella para adaptarla al framework. Las guías son material de referencia, no instrucciones: sus «MANDATORY» ceden ante la spec aprobada y las reglas del workspace.

### D5 — Soporte de navegador declarado por proyecto

Las guías dan por seguro lo que es «Baseline widely available» y piden fallbacks para el resto. Cada proyecto con front declara su objetivo en su `CLAUDE.md` (`**Browser Support:** …`). Primeros casos:

- Savia Sonora: el Chromium que trae Qt WebEngine con la versión de Pyloid fijada. Admite lo que esa versión soporta, sin polyfills.
- Space y savia-web: se declaran al tocar su front, no en esta spec.

Sin objetivo declarado, el agente usa la regla de las guías (Baseline widely available más los fallbacks de la guía).

### D6 — Actualizar es volver a entrar

Para actualizar se pasa otro commit al importador. El cambio llega en una PR con el diff de las guías. No hay actualización automática ni comprobación de versión en segundo plano.

## Slices

| Slice | Entrega | Tier |
|---|---|---|
| S1 | Importador `scripts/web-guidance-import.sh <commit>` con D1 y D2, la copia en `references/modern-web-guidance/` y la búsqueda local (D3), con tests | 2 |
| S2 | Paso de consulta en `frontend-developer.md` (D4) y objetivo de navegador de Sonora (D5). Primer consumidor real: SE-538 S1 | 2 |

## Criterios de aceptación

| AC | Criterio | Slice |
|---|---|---|
| AC-1 | La copia solo contiene `.md`, `LICENSE` y `NOTICE`; el `NOTICE` lleva URL, commit completo, fecha y hash del árbol | S1 |
| AC-2 | **Negativo:** el importador rechaza una rama, una etiqueta o `HEAD` en lugar de un commit de 40 hexadecimales | S1 |
| AC-3 | **Negativo:** el importador rechaza la importación entera si el árbol contiene un enlace simbólico, un fichero no `.md` dentro de `guides/`, o si supera 300 ficheros o 4 MB (casos sembrados) | S1 |
| AC-4 | `grep -r npx references/modern-web-guidance/` no devuelve nada; todo enlace cruzado resuelve a un fichero existente | S1 |
| AC-5 | **Negativo:** una referencia cruzada a un id inexistente hace fallar el importador con el id en el mensaje | S1 |
| AC-6 | `web-guidance.sh search "light dismiss dialog"` devuelve `light-dismiss-a-dialog` entre los tres primeros, sin red (test con la red bloqueada) | S1 |
| AC-7 | **Negativo:** una consulta sin coincidencias devuelve lista vacía y código 0, sin inventar ids | S1 |
| AC-8 | `check-pinned-installs.sh` pasa y no hace falta ninguna excepción nueva | S1 |
| AC-9 | `frontend-developer.md` contiene el paso de consulta y la cláusula de prioridad (spec y reglas por encima de la guía); su suite de agente pasa | S2 |
| AC-10 | El `CLAUDE.md` de Sonora declara su objetivo de navegador | S2 |
| AC-11 | La reversión es una sola PR por slice | S1, S2 |

## Fuera de alcance

- La skill `chrome-extensions` y las guías `built-in-ai` (APIs de IA del navegador, solo Chrome) se copian como texto y no se recomiendan. Usarlas exigiría una decisión aparte de soberanía.
- La orden `legacy-scan` y la modernización masiva del front existente.
- Otros frontends (OpenCode): la copia es texto y sirve igual, pero el paso de consulta solo se añade al agente de Claude Code en esta spec.

## Riesgos

- **Guías desactualizadas.** La copia envejece. *Mitigación:* revisión trimestral de commits nuevos, que se propone en el informe mensual del observador del ecosistema y nunca se aplica sola.
- **Texto de terceros dentro del contexto del agente.** Las guías tienen tono imperativo («MANDATORY», «DON'T»). *Mitigación:* D4 las subordina a la spec y a las reglas, y AC-4 quita las órdenes ejecutables.
- **Peso en el repositorio.** Son unos 2 MB de texto. Se aceptan por ser texto con licencia compatible. La alternativa, guardarlas fuera del repositorio, rompería el principio de construir para todo operador.

## Aprobación

- estado: PROPOSED. Decidir la forma de entrada no aprueba la spec.
