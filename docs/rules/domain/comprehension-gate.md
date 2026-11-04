# Puerta de comprensión — escenas confirmadas antes de la spec, prototipo antes del código

> SE-505. Gate: `scripts/comprehension-gate.py` (comprobación 11 de `bash scripts/roadmap.sh validate`).

Las revisoras comprueban código contra spec; nadie comprueba spec contra intención. Esta puerta cierra ese hueco en toda spec que toque una interfaz o una experiencia humana. Delegar criterio no es permiso para interpretar.

## Qué exige

1. **Frontmatter `human_surface: true | false`** en toda spec en ámbito. Si es `false` y la spec cita rutas de superficie (`apps/`, `ui/`, `projects/*/src/web`, `.tsx`, `.vue`, `.html`…), añade `human_surface_exempt: <motivo>`.
2. **Sección `## Lo que he entendido`** con `### Escenas` (de 3 a 5 escenas concretas: «Son las 8:30, abres el móvil y…»), `### Palabras de la persona` (cita literal «…» con fecha), `### Qué SÍ será`, `### Qué NO será` y `### Confirmación` (`fecha:` y `respuesta: «…»` con el texto literal de la respuesta a la pregunta interactiva que validó las escenas).
3. **`## Slice S0 — Prototipo navegable`** con `prototipo:` y `### Confirmación del prototipo`. S1 o posteriores no se ponen en curso (IMPLEMENTING, IMPLEMENTED o `current_slice: S1+`) sin esa confirmación.

## Cómo se obtiene la confirmación

- Las escenas se enseñan a la persona por pregunta interactiva **antes** de pedir la aprobación de la spec. Se copia su respuesta literal; no se resume ni se interpreta.
- El prototipo se le da para que lo use en su dispositivo. Su respuesta tras usarlo es la confirmación de S0.
- Una respuesta del tipo «no es esto» no es confirmación: se reescriben las escenas y se vuelve a preguntar.
- Inventar o parafrasear una confirmación viola Radical Honesty (Rule #24). La revisión humana de la PR comprueba su origen.

## Ámbito

Specs SE-504 o posteriores, o aprobadas desde 2026-11-04, en estado APPROVED, IMPLEMENTING o IMPLEMENTED. Lo aprobado antes no se reabre. Fail-closed: fichero o vista ilegible, frontmatter sin cerrar o iniciativa en ámbito de la vista sin spec localizable cuentan como FAIL. EXEMPT y DECLARED-FALSE (`human_surface: false`) se imprimen siempre, también en CI, para que la revisora vea cada autoexención.

Plantilla: `.claude/skills/spec-driven-development/references/spec-template.md`.
