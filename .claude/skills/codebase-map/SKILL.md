---
layer: peripheral
name: codebase-map
description: Usar cuando se necesita un mapa de dependencias del workspace (comandos→agentes→reglas→skills).
allowed-tools: [Read, Glob, Grep, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.maturity: beta
  savia.priority: high
  savia.summary: "Mapa de dependencias internas: que comandos invocan que agentes, que reglas cargan, que skills usan. Reduce alucinaciones en routing. Output: grafo de dependencias del workspace. Mapa de dependencias internas de pm-workspace: que comandos invocan que agentes, que reglas cargan, que skills usan. Reduce hallucination en routing de agentes."
  savia.tags: "indexing, routing, dependencies, discovery"
  savia.user-invocable: True
---

# Skill: Codebase Map — Indexacion de Dependencias Internas

> Inspirado en GitNexus: knowledge graph que indexa codebases en symbol maps.
> Aplicado a pm-workspace: indexa comandos, agentes, reglas y skills.

## Cuando usar

- Al inicio de sesion para entender que herramientas hay disponibles
- Cuando el NL-resolver no encuentra el comando correcto
- Para detectar reglas huerfanas o agentes nunca invocados
- Para entender cadenas de dependencia antes de modificar una regla

## Que escanea

### Comandos (.opencode/commands/*.md)
- Referencias `@` a reglas, skills, agentes
- Frontmatter: model, allowed-tools, context_cost
- Skill referenciado: linea "Ejecutar skill: @..."

### Agentes (.opencode/agents/*.md)
- Frontmatter: tools, model, permissionMode
- Descripcion: PROACTIVELY triggers
- Referencias a ficheros de proyecto en el body

### Reglas (docs/rules/domain/*.md)
- Quien las referencia (comandos, agentes, otras reglas)
- Hub score: numero de consumidores

### Skills (.opencode/skills/*/SKILL.md)
- Frontmatter: category, tags, priority
- Dependencias: que reglas o agentes invocan

## Output

Fichero: `output/codebase-map-{YYYYMMDD}.md`

Secciones:
- **Grafo de dependencias**: comando → agente → regla → skill (formato lista)
- **Hubs**: reglas con 5+ consumidores (cross-ref con semantic-hub-index.md)
- **Huerfanos**: reglas/agentes sin ningun consumidor
- **Cadenas criticas**: si una regla cambia, que comandos se afectan
- **Estadisticas**: total comandos, agentes, reglas, skills, densidad de conexiones

## Algoritmo

1. Glob todos los .md de commands/, agents/, rules/domain/, skills/
2. Para cada fichero: extraer referencias @ y menciones de otros componentes
3. Construir grafo dirigido: nodo = componente, arista = referencia
4. Calcular in-degree (hub score) y out-degree (dependencias)
5. Detectar nodos con in-degree 0 (huerfanos)
6. Detectar nodos con in-degree >= 5 (hubs)
7. Generar reporte

## Limitaciones

- Solo detecta referencias explicitas (@path o nombres en texto)
- No detecta invocaciones dinamicas (NL-resolver, skill-auto-activation)
- El grafo es estatico — snapshot del momento de ejecucion
