---
layer: peripheral
name: agent-file-map
description: Usar cuando se trabaja con ficheros externos al workspace que los agentes deben localizar.
allowed-tools: [Bash, Read, Glob, Grep, Write, Edit]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: pm-operations
  savia.maturity: stable
  savia.context: project
  savia.maturity: experimental
  savia.priority: high
  savia.summary: "Genera INDEX.afm por proyecto con rutas reales a ficheros externos (drives corporativos, OneDrive/SharePoint, NAS). Evita que los agentes pierdan tiempo y tokens buscando el mismo Excel o PDF en cada sesión. Complementa .acm (código) y .hcm (narrativa). Nivel de confidencialidad por proyecto."
  savia.tags: "afm, agent-maps, external-files, context, file-index"
  savia.user-invocable: True
---

# Agent File Map — Índice de Ficheros Externos

Genera ficheros `.afm` (Agent File Map) que indexan ficheros que los agentes consultan pero que NO están dentro del workspace git (Excels de capacity, PDFs de contratos, dashboards PowerBI exportados, videos de reuniones, diagramas Miro/Draw.io, SharePoint).

## Problema que resuelve

Sin .afm, cada sesión de agente repite el mismo patrón: "¿dónde está el Sprint26.xlsx?" → `find / -iname "*sprint26*"` → 30 segundos perdidos y varios tokens gastados. Si el fichero tiene un path con espacios y caracteres especiales (muy común en OneDrive/SharePoint), añadimos más errores.

Con .afm, el path canónico está pre-indexado, y el agente accede con coste cero.

## Cuándo usar

- **Onboarding de proyecto**: crear `INDEX.afm` al inicializar el proyecto
- **Tras primera consulta repetida**: cuando un fichero externo se usa 2+ veces, añadirlo al .afm
- **Cambio de path**: si el usuario reorganiza OneDrive/SharePoint, actualizar antes que los digests que lo referencian
- **Auditoría**: `/afm:check` verifica que todos los paths indexados existen

## Comandos slash propuestos

| Comando | Descripción |
|---------|-------------|
| `/afm:init` | Crea la estructura `.agent-maps/files/INDEX.afm` en el proyecto activo |
| `/afm:add <path> [--category X]` | Añade un fichero al .afm, verificando que existe |
| `/afm:check` | Valida que todos los paths del .afm existan en disco |
| `/afm:resolve <alias>` | Devuelve el path real de un alias (ej: `Sprint26.xlsx`) |
| `/afm:stats` | Muestra total ficheros, por categoría y antigüedad de last_sync |

## Formato .afm

YAML frontmatter + secciones markdown por categoría:

```yaml
---
name: {proyecto}-files.afm
description: "Usar cuando se trabaja con ficheros externos al workspace que los agentes deben localizar."
version: 1.0
last_sync: YYYY-MM-DD
confidentiality: {N1|N2|N3|N4|N4b}
---

# Agent File Map — {Proyecto}

## Convenciones de path
- `$VAR` = ruta base (resolve con env vars o paths conocidos)

## {Categoría: Sprint tracking, Contratos, Diagramas, etc.}
| Fichero | Propósito | Path |
|---|---|---|
| ... | ... | ... |
```

## Reglas de diseño

1. **Paths verificables**: todos deben existir en disco al momento de añadirlos
2. **Alias estables**: el nombre del fichero es la clave; si se renombra, actualizar aquí antes que digests
3. **Propósito explícito**: "qué información contiene" + "cuándo usarlo"
4. **Metadata de estructura** si aplica: ej. Excel con N hojas y columnas clave
5. **Cross-reference a digests**: si el fichero se digirió a markdown local, apuntar ahí
6. **Confidencialidad heredada**: el .afm hereda el nivel más alto de sus ficheros referenciados
7. **No duplicar contenido**: el .afm apunta, no replica

## Estructura recomendada en proyecto

```
projects/{proyecto}/
├── .agent-maps/
│   ├── INDEX.acm           ← código (existente)
│   ├── files/
│   │   ├── INDEX.afm       ← este skill
│   │   └── {categoria}.afm ← opcional, si el proyecto tiene muchas categorías
│   └── {layer}/*.acm
└── .human-maps/            ← narrativa humana (existente)
```

## Categorías estándar sugeridas

- **Sprint tracking**: Excel de planning, capacity, roadmap
- **Dashboards**: Exports PowerBI, Grafana, Tableau
- **Documentos legales**: Contratos, NDAs, Order Forms
- **Diagramas**: Links a Miro, Draw.io, Figma
- **Reuniones**: Transcripciones fuente (SharePoint), grabaciones
- **Repositorios externos**: Clones locales de repos cliente
- **Compliance**: Reports ISO, auditorías externas

## Integración con otros componentes

- **agent-code-map**: .afm y .acm conviven en `.agent-maps/`. El .acm mapea código, el .afm mapea ficheros externos
- **human-code-map**: los .hcm pueden referenciar .afm para "ver el Excel de capacidad en X" sin incrustar el path
- **digest-traceability**: si un fichero del .afm se digiere, el digest-log apunta a la entrada .afm
- **session-init**: al iniciar sesión en un proyecto, cargar el INDEX.afm del proyecto activo para que los agentes conozcan ficheros externos sin buscar

## Anti-patterns

- **NUNCA** incrustar contenido del fichero en el .afm (usar digests para eso)
- **NUNCA** añadir paths que no existan (verificar antes)
- **NUNCA** exponer paths N3/N4 en .afm de nivel N1
- **NUNCA** añadir credenciales o tokens (aunque sean paths a ficheros de credenciales)

## Madurez

Este skill arranca como **experimental**. Promoción a `beta` cuando:
- 3+ proyectos lo adopten
- Tengamos métrica de "tiempo ahorrado en búsquedas" por sesión
- Los comandos slash `/afm:*` estén implementados

Propuesta original: proyecto example-project, 2026-04-16 (detección de fricción repetida buscando Sprint26.xlsx).
