# Spec: Adopt Understand-Anything — Codebase Knowledge Graphs for Savia

> **RETIRADA (2026-11-22).** La operadora retiró esta integración por SE-535 S2: el instalador clonaba un repositorio externo sin versión fijada y enlazaba sus skills sin leerlas, y no constaba ningún uso. Se eliminaron los dos guiones, las siete órdenes, la skill y sus dos suites. El texto se conserva como historia; el código se recupera del historial de git. Reintroducirla exige pasar por la puerta de entrada descrita en SE-535.

**Task ID:**        SPEC-SE-088-UA-ADOPT
**PBI padre:**      Era 192 — Knowledge Graph Adoption
**Sprint:**         2026-05
**Fecha creacion:** 2026-05-02
**Creado por:**     Savia (investigacion Understand-Anything)

**Developer Type:** agent-single
**Asignado a:**     claude-agent
**Estimacion agent:** ~90 min
**Estado:**         Retirada (2026-11-22, SE-535 S2)
**Prioridad:**      ALTA
**Modelo:**         claude-sonnet-4-6
**Max turns:**      25

---

## 1. Contexto y Objetivo

[Understand-Anything](https://github.com/Lum1104/Understand-Anything) es un plugin
OpenCode-compatible (TypeScript, pnpm, MIT license) que analiza codebases via pipeline
multi-agente y genera un `knowledge-graph.json` con:

- Grafo estructural (archivos, funciones, clases, dependencias)
- Grafo de dominio (procesos de negocio, flujos, steps)
- Grafo de conocimiento (wikis Karpathy-pattern — entidades, claims, relaciones)
- Dashboard interactivo (React, force-directed layout, busqueda semantica, tours guiados)
- Analisis de impacto de diffs
- Actualizacion incremental (post-commit hook)

Compatibilidad nativa con OpenCode (`.opencode/INSTALL.md` ya existe en el repo).
Language packs: TypeScript/JavaScript, Python, Go, Rust, Java, C#, Ruby, PHP, Kotlin,
Swift, C/C++, Scala, Elixir — 13 lenguajes.

**Objetivo:** Integrar Understand-Anything en Savia pm-workspace como skill de
analisis de codebase, conectandolo con el SCM existente y el sistema de memoria.
Esto permite que Savia genere grafos de conocimiento de CUALQUIER proyecto (no solo
el suyo propio), acelere onboarding de nuevos proyectos, y proporcione diffs de
impacto como gate de CI.

---

## 2. Requisitos Funcionales

- **REQ-01** Instalar Understand-Anything via el metodo OpenCode (`git clone` +
  symlinks en `~/.agents/skills/`). No requiere npm global.
- **REQ-02** Crear `scripts/ua-bridge.sh` — wrapper que invoca `/understand` y
  expone el `knowledge-graph.json` al SCM y sistema de memoria de Savia.
- **REQ-03** Anadir comandos Savia wrapper: `/ua-analyze`, `/ua-domain`,
  `/ua-diff`, `/ua-chat`, `/ua-dashboard`.
- **REQ-04** Integrar `knowledge-graph.json` con `memory-agent`: los nodos y edges
  del grafo se alimentan como entidades en el sistema de memoria episodica.
- **REQ-05** Mapeo bidireccional SCM ↔ UA: los intents del SCM se correlacionan
  con nodos del knowledge graph para busqueda semantica cruzada.
- **REQ-06** Gate opcional de CI (G16): `/ua-diff` en PRs para estimar impacto
  superficial del cambio (archivos, funciones, dependencias afectadas).
- **REQ-07** Compatible con `project-onboarding` skill existente: tours guiados
  de UA se integran con el flujo de onboarding de Savia.

---

## 3. Comandos Savia a crear

| Comando | Mapeo UA | Funcion |
|---------|----------|---------|
| `/ua-analyze [path]` | `/understand` | Analizar codebase y generar knowledge-graph.json |
| `/ua-domain [path]` | `/understand-domain` | Extraer dominios de negocio |
| `/ua-diff` | `/understand-diff` | Impacto de cambios no commiteados |
| `/ua-chat {query}` | `/understand-chat` | Preguntas sobre el grafo |
| `/ua-dashboard` | `/understand-dashboard` | Lanzar dashboard interactivo |
| `/ua-onboard` | `/understand-onboard` | Generar guia de onboarding |

---

## 4. Integracion con sistemas existentes

### 4.1 SCM ↔ UA bridge

```
SCM intents ──→ fuzzy match ──→ UA graph nodes ──→ enriched search
UA graph nodes ──→ extract concepts ──→ SCM index expansion
```

### 4.2 Memory feed

`knowledge-graph.json` → `memory-agent` extrae:
- `DOMAIN_ENTITY` edges para nodos de negocio
- `DEPENDS_ON` edges para dependencias tecnicas
- `IMPLEMENTS` edges para funciones/clases → specs/requisitos

### 4.3 CI Gate G16

```bash
# En pr-plan: G16 (WARN, no-blocking)
ua_diff_count=$(bash scripts/ua-bridge.sh diff --count)
[[ $ua_diff_count -gt 50 ]] && echo "WARN: diff impact >50 nodes affected"
```

---

## 5. Arquitectura de instalacion

```
~/.opencode/understand-anything/        # git clone del repo
~/.agents/skills/understand → ...       # symlinks a skills/
~/.understand-anything-plugin → ...      # symlink universal (para dashboard)
```

Savia commands en `.opencode/commands/` como wrappers:
```bash
# /ua-analyze
bash ~/.opencode/understand-anything/scripts/ua-bridge.sh analyze "$@"
```

---

## 6. Criterios de Aceptacion

- **AC-01** `/ua-analyze .` sobre pm-workspace genera `knowledge-graph.json` con
  nodos para cada comando, skill, agente y script del SCM.
- **AC-02** `/ua-dashboard` lanza dashboard interactivo accesible en navegador.
- **AC-03** `/ua-chat "que comandos gestionan sprints?"` retorna resultados
  relevantes del knowledge graph (cross-check con SCM intents).
- **AC-04** `memory-agent` recibe edge `DOMAIN_TERM` para conceptos extraidos del
  knowledge graph.
- **AC-05** SCM regenerado tras `/ua-analyze` incluye entradas UA-bridge como
  recursos rastreables.
- **AC-06** Instalacion completada con un solo comando (`/ua-install`).

---

## 7. Ficheros a Crear/Modificar

| Fichero | Accion |
|---------|--------|
| `scripts/ua-bridge.sh` | CREAR — wrapper principal |
| `scripts/ua-install.sh` | CREAR — instalacion automatizada |
| `.opencode/commands/ua-analyze.md` | CREAR |
| `.opencode/commands/ua-domain.md` | CREAR |
| `.opencode/commands/ua-diff.md` | CREAR |
| `.opencode/commands/ua-chat.md` | CREAR |
| `.opencode/commands/ua-dashboard.md` | CREAR |
| `.opencode/commands/ua-onboard.md` | CREAR |
| `.opencode/commands/ua-install.md` | CREAR |
| `scripts/pr-plan-gates.sh` | MODIFICAR: anadir G16 gate (WARN) |
| `scripts/ci-extended-checks.sh` | MODIFICAR: anadir UA check |

---

## 8. Dependencias y Riesgos

- **Riesgo**: Understand-Anything requiere Node.js + pnpm → verificar disponibles en el host.
- **Riesgo**: El grafo de pm-workspace (~1100 recursos) + CHANGELOG (9200 lineas) puede
  generar un `knowledge-graph.json` grande (>10MB) → usar LFS como recomienda UA.
- **Mitigacion**: Instalacion condicional — si Node/pnpm no disponibles, `/ua-install`
  informa y los comandos UA se deshabilitan (graceful degradation).
- **Depende de**: SPEC-OPC-CROSS-AUDIT (Era 191) para garantizar que los nuevos comandos
  se sincronizan `.opencode/commands/` ↔ `.opencode/commands/`.

---

## 9. Escalabilidad futura (fuera de este spec)

- Pipeline multi-proyecto: `/ua-analyze` en lote sobre `projects/*/`
- Integracion con `visual-digest` agent para OCR de diagramas → nodos del grafo
- Publicacion del knowledge graph como artefacto de release
- Auto-clasificacion de nodos por N1-N4b (confidencialidad)
