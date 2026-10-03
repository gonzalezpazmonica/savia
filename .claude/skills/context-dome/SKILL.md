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
  savia.maturity: beta
  savia.context: L2
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
# Generar cupulas para modulos con riesgo HIGH o superior (default HIGH)
bash scripts/context-dome-generate.sh --project <path> --min-risk HIGH

# Solo un modulo especifico (name o path del scan)
bash scripts/context-dome-generate.sh --project <path> --module src/payments

# Preview sin escribir
bash scripts/context-dome-generate.sh --project <path> --dry-run

# Repo publico: owners sin dominio de email
bash scripts/context-dome-generate.sh --project <path> --redact-owners

# Regenerar aunque la cupula se haya editado a mano (pierde la edicion)
bash scripts/context-dome-generate.sh --project <path> --force
```

Requiere un scan previo (`scripts/bus-factor-scan.sh`) en `BF_OUTPUT_DIR`
(default `output/bus-factor/`).

## Exit codes

| Codigo | Caso |
|--------|------|
| 0 | Cupulas generadas, sin cambios, nada que generar, o modulos saltados con `WARN` (directorio ausente, ruta insegura, symlink, edicion manual) |
| 1 | Uso invalido: falta `--project` o su valor, `--min-risk` desconocido, proyecto que no es directorio, sin scan del proyecto, scan con `project` de otro proyecto |
| 2 | Scan JSON ilegible (corrupto o sin lista `modules`) |

## Estructura del CONTEXT_DOME.md generado

```markdown
---
module: "<path del modulo>"
bus_factor: <N>
risk_level: CRITICAL|HIGH|MEDIUM|LOW
knowledge_owners:
  - "<dev1>"
generated_at: <ISO8601>
spec: SE-252
warnings: [...]
runbook_confidence: low|medium|high
dome_hash: <huella del contenido>
---

# Context Dome -- <path>
## Proposito
## Decisiones no obvias
## Dependencias criticas
## Runbook minimo
## Knowledge owners actuales
## Plan de distribucion sugerido
## Historial de cambios relevantes
```

Los valores de texto del frontmatter van entre comillas JSON: un owner o
una ruta con `:`, `#`, `*`, espacios o unicode no rompen el YAML. Sin
owners, `knowledge_owners: []`. La cupula se escribe en `<path>/` del
modulo (campo `path` del scan); rutas absolutas, con `..` o directorios
symlink que salen del proyecto se rechazan.

## Idempotencia

- Regenerar sin cambios en las fuentes no toca el fichero (`UNCHANGED`).
- Si el scan o el historial cambian, se reescribe entera; nunca duplica.
- Los commits que solo tocan `CONTEXT_DOME.md` no cuentan como historial
  ni como decisiones: commitear la cupula no la hace cambiar.
- Huella y edicion en python3 (sin `sha256sum` ni `sed -i` GNU): portable a macOS.
- `dome_hash` detecta ediciones manuales: si la cupula se edito tras
  generarse (o no tiene huella, como las de versiones anteriores), no
  se pisa sin `--force`.

## Confidencialidad

- Aislamiento N4: solo se aceptan `<proyecto>.json` o
  `<proyecto>-<YYYYMMDD>T<HHMMSS>Z.json` (el mas reciente), y su campo
  `project` debe coincidir. Nunca otro proyecto ni prefijos parecidos.
- Decisiones e historial salen de `HEAD`: commits de ramas sin integrar
  no acaban en la cupula.
- Los owners son emails git (dato personal). En repos publicos usar
  `--redact-owners`. Ver `DOMAIN.md` (Consideraciones de PII).

## Fuentes de datos

| Seccion | Fuentes |
|---------|---------|
| Proposito | CONTEXT.md, README.md, comentarios cabecera |
| Decisiones | git log -E --grep en HEAD (why:, because, NOTE:, HACK:, FIXME:, decision:, tradeoff:, SE-, SPEC-) |
| Dependencias | imports por extension (.py, .ts, .go, .cs) |
| Runbook | Makefile, package.json scripts, README ## Usage, Dockerfile CMD |
| Owners | JSON del bus-factor-scan |
| Historial | git log en HEAD --no-merges excluyendo chore/format/typo/style |

## runbook_confidence

| Nivel | Condicion | Accion |
|-------|-----------|--------|
| low | Sin fuentes detectadas | Documentar manualmente |
| medium | 1 fuente encontrada | Revisar y completar |
| high | 2+ fuentes encontradas | Verificar actualizacion |
