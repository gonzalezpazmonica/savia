---
layer: peripheral
name: context-dome
description: >
  Genera CONTEXT_DOME.md para modulos con Bus Factor bajo. Captura
  conocimiento tacito: proposito, decisiones no obvias, dependencias,
  runbook minimo, knowledge owners y plan de distribucion.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: knowledge-management
  savia.maturity: stable
  savia.context: L2
  savia.maturity: calibrated
  savia.se: SE-252
  savia.summary: Skill de documentacion automatica de conocimiento tacito por modulo. Complemento natural del bus-factor-analysis skill.
  savia.tags: "context-dome, bus-factor, documentation, knowledge-transfer, resilience"
---

# Context Dome

## Descripcion

Una cupula de contexto es un artefacto de documentacion que captura el
conocimiento tacito de un modulo: lo que no esta en el codigo pero
que cualquier dev necesita para trabajar con el.

Se genera automaticamente a partir del historial git y la estructura
del proyecto, y se almacena como `CONTEXT_DOME.md` en el directorio
del modulo.

## Ruta critica

- Script:    `scripts/context-dome-generate.sh`
- Hook scan: `.claude/hooks/bus-factor-warn.sh`
- DOMAIN:    `.claude/skills/context-dome/DOMAIN.md`

## Uso

```bash
# Generar cupulas para modulos con riesgo HIGH o superior
bash scripts/context-dome-generate.sh --project <path> --min-risk HIGH

# Solo un modulo especifico
bash scripts/context-dome-generate.sh --project <path> --module src/payments

# Preview sin escribir
bash scripts/context-dome-generate.sh --project <path> --dry-run
```

## Estructura del CONTEXT_DOME.md generado

```markdown
---
module: <nombre>
bus_factor: <N>
risk_level: CRITICAL|HIGH|MEDIUM|LOW
knowledge_owners: [<dev1>, ...]
generated_at: <ISO8601>
spec: SE-252
runbook_confidence: low|medium|high
---

# Context Dome -- <nombre>
## Proposito
## Decisiones no obvias
## Dependencias criticas
## Runbook minimo
## Knowledge owners actuales
## Plan de distribucion sugerido
## Historial de cambios relevantes
```

## Fuentes de datos

| Seccion | Fuentes |
|---------|---------|
| Proposito | CONTEXT.md, README.md, comentarios cabecera |
| Decisiones | git log --grep (why:, because, NOTE:, HACK:, SE-, SPEC-) |
| Dependencias | imports por extension (.py, .ts, .go, .cs) |
| Runbook | Makefile, package.json scripts, README ## Usage, Dockerfile CMD |
| Owners | JSON del bus-factor-scan |
| Historial | git log --no-merges excluyendo chore/format/typo |

## runbook_confidence

| Nivel | Condicion | Accion |
|-------|-----------|--------|
| low | Sin fuentes detectadas | Documentar manualmente |
| medium | 1 fuente encontrada | Revisar y completar |
| high | 2+ fuentes encontradas | Verificar actualizacion |
