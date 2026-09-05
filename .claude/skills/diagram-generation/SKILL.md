---
layer: peripheral
name: diagram-generation
description: Usar cuando se necesita generar diagramas de arquitectura o flujo desde código o infraestructura.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: diagram-architect
  savia.maturity: stable
  savia.category: devops
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Genera diagramas de arquitectura y flujo desde codigo. Soporta Draw.io, Miro y Mermaid local. Output: diagrama exportado + metadata en projects/{p}/diagrams/."
  savia.tags: "diagrams, architecture, mermaid, draw-io"
---

# Skill: Diagram Generation — Arquitectura y Flujo

## Propósito

Generar diagramas de arquitectura, flujo de datos y secuencia a partir de la infraestructura y código fuente de un proyecto. Exportar a Draw.io, Miro o formato local (Mermaid).

## Triggers

- Comando `/diagram-generate` — Genera diagrama completo
- Petición directa: "genera el diagrama de arquitectura del proyecto X"

## Contexto Requerido

1. `CLAUDE.md` (raíz) — Contexto global
2. `projects/{proyecto}/CLAUDE.md` — Stack, arquitectura, repos
3. `projects/{proyecto}/infrastructure/` — Terraform, Docker, K8s si existen
4. `docs/rules/domain/diagram-config.md` — Constantes y configuración

---

## Fase 1: Detección de Componentes

Analizar el proyecto para identificar componentes arquitectónicos:

### Fuentes de detección (prioridad)

1. **Infraestructura como código** — `*.tf`, `docker-compose.yml`, `k8s/`, `helm/`
2. **Código fuente** — `*.csproj`, `package.json`, `pom.xml`, `go.mod`, etc.
3. **Documentación existente** — `CLAUDE.md` del proyecto, `architecture.md`
4. **Azure DevOps** — Repos, pipelines, service connections

Para tipo orgchart: la fuente de datos es `teams/{dept}/` (dept.md + team.md de cada equipo),
NO infraestructura de proyecto. Opcionalmente enriquecer con `teams/members/{handle}.md`.

### Entidades a detectar

> Detalle: @references/diagram-entities.md

| Entidad | Detección | Icono |
|---|---|---|
| Microservicio / API | `*.csproj` + Dockerfile | `[Nombre]` |
| Base de datos | ConnectionString, DbContext | `[(DB)]` |
| Cola / Bus | ServiceBus, RabbitMQ config | `{{Cola}}` |
| API Gateway | Ocelot, YARP, Kong | `[[Gateway]]` |
| Frontend / SPA | angular.json, next.config | `(Frontend)` |
| CDN / Cache | Redis, CloudFront | `{Cache}` |

---

## Fase 2: Generación de Modelo Mermaid

Construir la representación en Mermaid según el tipo de diagrama:

> Detalle: @references/mermaid-templates.md

### Tipos soportados

- **Architecture** — C4-style con capas (Frontend, Backend, Data)
- **Flow** — Data flow entre componentes
- **Sequence** — Secuencia temporal de interacciones
- **Orgchart** — Jerarquía organizativa desde datos de `teams/`

---

## Fase 3: Exportar a Herramienta MCP

### 3.1 Draw.io
1. Convertir Mermaid → XML Draw.io
2. Crear o actualizar diagrama
3. Si proyecto tiene `DRAWIO_FOLDER` → usar esa carpeta

### 3.2 Miro
1. Verificar token OAuth válido
2. Crear frame en board del proyecto
3. Convertir entidades a shapes de Miro

### 3.3 Local (sin MCP)
1. Guardar fichero `.mermaid` en `projects/{p}/diagrams/local/`
2. Mostrar preview en respuesta

---

## Fase 4: Guardar Metadata

Crear `projects/{p}/diagrams/{tool}/{tipo}.meta.json`:

```json
{
  "tool": "draw-io",
  "type": "architecture",
  "name": "System Architecture — {proyecto}",
  "url": "https://...",
  "remote_id": "...",
  "local_mermaid": "diagrams/local/architecture.mermaid",
  "created": "2026-02-26T...",
  "elements": { "services": 4, "databases": 2, "queues": 1 }
}
```

---

## Fase 5: Presentar Resultado

```
✅ Diagrama generado: {tipo} — {proyecto}
🔗 URL: {link}
📊 Elementos: {N} servicios, {N} DBs, {N} colas
📁 Metadata: projects/{p}/diagrams/{tool}/{tipo}.meta.json
```

---

## Referencias

- `references/mermaid-templates.md` — Plantillas por tipo
- `references/diagram-entities.md` — Detección de componentes
- `references/draw-io-shapes.md` — Mapeo entidades → shapes
- `references/orgchart-shapes.md` — Shapes de organigrama
- `references/orgchart-mermaid-template.md` — Plantilla Mermaid para orgchart
