---
status: APPROVED
approved_at: 2026-11-03
approved_by: "operadora, pregunta interactiva 2026-11-03 (Puerta de comprensión obligatoria); aprobada por la operadora por pregunta interactiva; se formaliza al fusionar (SE-488)"
priority: P0
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L4
human_surface: false
human_surface_exempt: "Gate de CI y documentación sin interfaz propia; las rutas de superficie humana se citan solo como patrones de detección."
related_specs: [SE-444, SE-476, SE-488, SE-490, SE-500, SE-503, SE-504]
origin: "Decisión de la operadora del 2026-11-03 por pregunta interactiva, opción «Puerta de comprensión obligatoria», tras la revisión de SE-490. Una sola PR con spec e implementación."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "APPROVED"
---
# SE-505 — Puerta de comprensión: escenas confirmadas antes de la spec, prototipo antes del código

## Problema

Durante tres semanas se especificó, construyó, revisó y fusionó el gemelo operativo (SE-490) con toda la CI en verde, y el producto no era lo que la operadora pidió. Ella quería un agente activo que vive y trabaja con la persona; se construyó un lector de datos con consultas por botones.

Tres huecos lo permitieron:

1. **Nadie contrastó la spec con la intención.** Las revisoras comparan código contra spec; ninguna compara spec contra lo que la persona dijo. Si la spec malinterpreta, todo lo demás hereda el error con firma de calidad.
2. **La delegación de criterio se leyó como permiso para interpretar.** La spec se aprobó sin que la persona viera, en sus palabras, qué iba a recibir.
3. **Nadie usó el producto antes de entregarlo.** El primer contacto real de la persona con la interfaz fue el producto terminado.

## Objetivo

Que ninguna spec que toque una interfaz o una experiencia humana llegue a APPROVED sin que la persona haya confirmado, por escrito y con fecha, escenas concretas de uso; y que ningún código de producto (S1 y posteriores) empiece sin que haya visto y confirmado un prototipo navegable (S0). La CI lo comprueba y falla cerrada.

## Diseño

### 1. Sección «Lo que he entendido» (obligatoria con superficie humana)

```markdown
## Lo que he entendido

### Escenas
1. Son las 8:30, abres el móvil y …   (de 3 a 5 escenas concretas)

### Palabras de la persona
> «texto literal de lo que pidió» — AAAA-MM-DD

### Qué SÍ será
- …

### Qué NO será
- …

### Confirmación
- fecha: AAAA-MM-DD
- respuesta: «texto literal de la respuesta a la pregunta interactiva que validó las escenas»
```

### 2. Slice S0 — Prototipo navegable

```markdown
## Slice S0 — Prototipo navegable
- prototipo: qué se enseña y dónde (ruta, enlace o captura navegable)

### Confirmación del prototipo
- fecha: AAAA-MM-DD
- respuesta: «texto literal de la persona tras usar el prototipo»
```

La confirmación de S0 puede estar vacía mientras la spec está APPROVED y el prototipo se construye. Es obligatoria en cuanto S1 o posterior se pone en curso.

### 3. Cuándo una spec tiene superficie humana

- Frontmatter `human_surface: true | false`. En ámbito es **obligatorio**: sin el campo, FAIL. La detección por rutas no basta (el caso origen, SE-490, citaba rutas web como `/continuidad` y carpetas `src/` que ningún patrón razonable distingue de un servicio).
- Detección por rutas citadas entre comillas invertidas: `apps/`, `ui/`, `projects/<p>/src/web`, `projects/<p>/{web,ui,app,android,ios,mobile,frontend}/`, proyectos cuyo nombre contiene `web`, `mobile` o `space`, y ficheros `.tsx`, `.jsx`, `.vue`, `.svelte`, `.html`, `.css`.
- `human_surface: false` con rutas detectadas exige `human_surface_exempt: <motivo>`. El gate lo imprime como EXEMPT para que la revisora lo vea, también en CI (`--quiet` no lo oculta). `human_surface: false` sin rutas detectadas sale como DECLARED-FALSE por la misma razón.

### 4. Gate

`scripts/comprehension-gate.py`, invocado como comprobación 11 de `bash scripts/roadmap.sh validate` (que ya corre en `validate-ci-local.sh` y en CI). Recorre `docs/specs/**/SE-*.md`, `docs/propuestas/SE-*.md` y la `evidence` de cada iniciativa de la vista de planificación. Una iniciativa en ámbito de la vista sin spec localizable es FAIL: el gate no se esquiva con un nombre de fichero que no case. La `evidence` solo cuenta como spec si la iniciativa no tiene ya una en esos globs y es un `.md` con `status:` en el frontmatter; si apunta a la spec de otra iniciativa, FAIL. Las fechas de confirmación deben existir en el calendario y no ser posteriores a hoy.

- **Ámbito**: estado APPROVED, IMPLEMENTING o IMPLEMENTED (en el frontmatter o en la vista de planificación) y, además, número SE-504 o superior, o `approved_at` desde 2026-11-04.
- **FAIL** si: falta `human_surface`; superficie humana sin la sección completa (escenas fuera de 3–5, sin cita literal con fecha, listas SÍ/NO vacías); confirmación sin fecha o con respuesta vacía o de relleno (`{…}`, `pendiente`, `TBD`); falta el slice S0 o su `prototipo:`; S1 en curso sin confirmación de S0.
- **S1 en curso** = estado IMPLEMENTING o IMPLEMENTED, o `current_slice: S1` (o mayor) en el frontmatter.
- **Fail-closed**: fichero ilegible, vista de planificación ilegible o cualquier error del validador → FAIL.

### Decisiones

- **SE-490 queda fuera del ámbito.** Se aprobó y construyó antes de esta regla; reabrirla rompería `main` sin cambiar nada del producto. Su corrección pasa por SE-504, que sí cae en el ámbito (número ≥ 504).
- **Formato literal y no un juez LLM.** La puerta comprueba que la confirmación existe y es de la persona, no que las escenas sean buenas: eso lo decide ella al leerlas. Un juez automático reintroduciría la interpretación que esta spec quiere quitar.

## Criterios de aceptación

| AC | Verificación | autoridad_requerida | autoridad_obtenida |
|---|---|---|---|
| AC-1 | Spec APPROVED con `human_surface: true` sin «Lo que he entendido» → FAIL | estatica | `tests/test-se505-comprehension-gate.bats` |
| AC-2 | Sección presente con confirmación vacía o de relleno → FAIL | estatica | ídem |
| AC-3 | Escenas fuera de 3–5, sin cita con fecha o listas SÍ/NO vacías → FAIL; 3 y 5 escenas → PASS | estatica | ídem |
| AC-4 | Rutas de superficie detectadas sin `human_surface`, o con `false` sin motivo → FAIL; con motivo → EXEMPT | estatica | ídem |
| AC-5 | Falta S0 o su `prototipo:` → FAIL; APPROVED con S0 sin confirmar → PASS; IMPLEMENTING (frontmatter o vista) o `current_slice: S1` sin confirmar S0 → FAIL | estatica | ídem |
| AC-6 | Fuera de ámbito (número < 504 y aprobada antes de 2026-11-04, o PROPOSED) → no se evalúa | estatica | ídem |
| AC-7 | `roadmap.sh validate` falla cuando el gate falla y pasa en el repo actual | estatica | ídem + ejecución en la PR |
| AC-8 | Fichero o vista ilegible → FAIL | estatica | ídem |
| AC-9 | Regla en `docs/rules/domain/comprehension-gate.md` enlazada desde el índice, línea en el lazy reference de `CLAUDE.md` (≤ 150 líneas) y plantilla de spec actualizada | estatica | revisión del diff |

## Fuera de alcance

- Juzgar la calidad de las escenas o del prototipo.
- Verificar que la cita de la persona es auténtica: el gate exige que esté y la revisión humana de la PR (tier 4) comprueba de dónde sale.
- Reabrir SE-490 u otras specs aprobadas antes de 2026-11-04.
- Herramienta para construir prototipos.

## Riesgos

- **Rellenar por cumplir**: una cita inventada pasa el gate. Mitigación: la regla exige la respuesta literal de la pregunta interactiva y la revisión humana es obligatoria; inventarla es una violación de Radical Honesty, no un atajo de formato.
- **Falsos positivos por rutas**: una spec de backend que cita un `.html` de informes. Mitigación: `human_surface: false` + motivo, visible como EXEMPT.

## OpenCode Implementation Plan

### Bindings touched
- `scripts/comprehension-gate.py` (nuevo), `scripts/roadmap.sh` (comprobación 11). Sin hooks ni settings.

### Verification protocol
- `bats tests/test-se505-comprehension-gate.bats` y `bats tests/test-roadmap-validate.bats`; `bash scripts/roadmap.sh validate --diff origin/main`.

### Portability classification
- Portable: Python 3 estándar y bash; idéntico en Claude Code y OpenCode.

## Aprobación

Aprobada por la operadora por pregunta interactiva el 2026-11-03 (opción «Puerta de comprensión obligatoria»); se formaliza al fusionar (SE-488).
