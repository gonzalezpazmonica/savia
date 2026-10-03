---
layer: peripheral
name: design-an-interface
description: "Design-an-interface skill with N=3 parallel alternatives and architectural vocabulary. Use when designing a new module interface, when user mentions 'varias alternativas', 'design this module', or '/design-an-interface'."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.attribution: "Clean-room re-implementation of mattpocock/skills/design-an-interface (MIT, 26.4k*). Prose and process are original."
  savia.maturity: beta
  savia.category: architecture
  savia.context: fork
  savia.context_cost: medium
  savia.priority: high
  savia.se: SE-087
  savia.tags: "architecture, interface-design, parallel-agents, sdd"
---

# Skill: Design an Interface

> **Attribution**: Clean-room re-implementation of `mattpocock/skills/design-an-interface` (MIT). SE-087.

Genera 3 disenos alternativos de interfaz en paralelo y consolida en tabla comparativa con recomendacion justificada.

## Authoritative Paths

> Lee estos paths antes de actuar.

| Para | Lee este path |
|---|---|
| Vocabulario arquitectonico | `docs/rules/domain/architectural-vocabulary.md` |
| Codigo existente del proyecto | `projects/<nombre>/` |
| Specs SDD activas | `docs/propuestas/SPEC-*.md` |
| Reglas de dominio | `docs/rules/domain/` |

## Cuando usar

- Se necesita disenar una interfaz nueva para un modulo y no hay precedente claro.
- Se quiere comparar enfoques antes de comprometerse con uno.
- La spec SDD requiere definicion de interfaz antes de implementar.

## Cuando NO usar

- La interfaz ya existe y solo necesita extension — leer el codigo y ampliar.
- El scope es un metodo privado o una funcion de utilidad (demasiado granular).
- La interfaz tiene un patron establecido en el proyecto — seguir el patron existente.

## Decision Checklist

1. El modulo esta definido con nombre y contexto de uso? Si NO: solicitar antes de continuar.
2. Hay restricciones conocidas (rendimiento, compatibilidad, framework)? Si NO: asumir ninguna y documentarlo.
3. Existe codigo relacionado en el proyecto? Si SI: designar como base para Diseno C.

### Abort Conditions

- Si el nombre del modulo es vago o el contexto insuficiente: pedir aclaracion y abortar.
- Si las restricciones implican un unico diseno posible: no lanzar alternativas, documentar la restriccion.

## Workflow

`Recibir → Lanzar 3 sub-agentes paralelos → Consolidar tabla → Recomendar`

### Sub-agentes en paralelo (mismo mensaje, sin dependencias)

Agent tool (Task en OpenCode) con `subagent_type=architect`; cada prompt incluye el vocabulario de SE-082.

**A — Maxima simplicidad**: minimo metodos, sin estado, facilidad de uso.
**B — Maxima flexibilidad**: extensible, plugin-friendly, facil de mockear.
**C — Pragmatico**: equilibrio A+B, inspirado en codigo existente del proyecto.

### Formato de output de cada sub-agente

```
Interface: <NombreInterfaz>
Methods:
  - <metodo>(<param>: <tipo>): <retorno>
Invariants:
  - <descripcion>
Trade-offs:
  + <ventaja>
  - <desventaja>
```

### Consolidacion

Tabla comparativa con columnas: Criterio | Diseno A | Diseno B | Diseno C.
Criterios minimos: numero de metodos, estado requerido, testabilidad, extension futura, coherencia con codigo existente.

### Recomendacion

Un parrafo usando vocabulario de `docs/rules/domain/architectural-vocabulary.md`:
- **Module**, **Interface**, **Seam**, **Depth**, **Leverage**, **Locality**.
- Justificar por que el diseno elegido maximiza Depth y Locality para el contexto dado.

## Outputs esperados

- Tabla comparativa de los 3 disenos.
- Recomendacion con justificacion en vocabulario arquitectonico.
- Opcionalmente: fichero `docs/propuestas/<modulo>-interface-design.md` si se requiere trazabilidad.
  Sin frontmatter no entra en `INDEX.md`. Con frontmatter, regenera el indice o el gate `--check` de validate-ci-local falla:

```bash
bash scripts/propuestas-index-gen.sh
```

## Memory hooks

Cuando la usuaria elige diseno, guardarlo (`--source` es obligatorio por SE-072; sin el, exit 1 y no se guarda nada):

```bash
bash scripts/memory-store.sh save --type decision --title "interface design: <modulo>" \
  --content "<diseno elegido y por que>" --source user:explicit
```

## Related

- Rule: `docs/rules/domain/architectural-vocabulary.md` (SE-082 — vocabulary obligatorio en outputs)
- SE-074: `scripts/parallel-specs-orchestrator.sh` — disenos grandes (>1h por agente). Solo acepta IDs de spec en `docs/propuestas/` (no hay "design tracks"): escribir cada alternativa como spec y planificar antes de lanzar:
  `bash scripts/parallel-specs-orchestrator.sh --dry-run <SPEC-A> <SPEC-B> <SPEC-C>`
- Skill: `.opencode/skills/spec-driven-development/SKILL.md`
- Agent: `.opencode/agents/architect.md`
- Roadmap: `docs/ROADMAP.md`
