---
context_tier: L3
token_budget: 1227
---

# PR Natural-Language Summary — Rule

> Cada PR debe abrir con un párrafo en lenguaje no técnico que cualquier persona pueda leer y entender qué cambia, por qué importa, y qué se gana.

## Por qué

Cuando los PRs son autónomos y mergean a ritmo, el repo crece más rápido de lo que cualquier humano puede revisar línea a línea. Sin un resumen plano y honesto al inicio, lo que se acumula deja de ser legible: títulos crípticos (`SE-072 Slice 1 MVP`), lenguaje técnico (`PreToolUse hook`, `JSONL`, `feature-flag`), y diffs de cientos de líneas que solo el agente entiende.

El resultado, a 3 meses vista, es un repo que crece pero pierde transparencia. Quien revisa pierde la capacidad de ejercer control real. Los PRs se aprueban "porque CI pasa", no porque alguien entendió qué hacían.

El párrafo natural restaura el contrato: **el agente tiene que poder explicarse en plano antes de que el código pase**.

## Regla

Cada PR debe contener al inicio del body una sección titulada exactamente:

```markdown
## Qué hace este PR (en lenguaje no técnico)

<párrafo de 100-400 palabras que cumpla los 4 puntos>
```

Los 4 puntos obligatorios:

1. **Qué cambia para el usuario**, en términos del usuario. No "implementé X", sino "ahora cuando hagas Y, ocurre Z".
2. **Por qué importa**. Un escenario concreto donde el cambio se siente, o un coste de no haberlo hecho.
3. **Qué se pierde / qué riesgos quedan abiertos** (si algo). Honestidad sobre limitaciones.
4. **Cómo activar / desactivar / desinstalar**, si el cambio es opt-in o reversible.

## Lenguaje prohibido

Salvo el título técnico (debajo de "## Summary"), el párrafo NO usa:

- IDs de spec sin glosa (`SE-072 Slice 1 MVP` → `el axioma "memoria verificada"`)
- Jerga del proyecto (`PreToolUse hook`, `JSONL`, `feature flag`, `frontmatter`)
- Acrónimos sin expandir (`AC-03`, `CI`, `MCP`)
- Referencias a baselines, ratchets, gates, agentes, tiers, sectors
- Métricas internas (`score 94`, `33 tests`, `60/60 hooks`)
- Versiones de software o dependencies

Lo que NO está prohibido es ser preciso sobre el comportamiento — solo no se traduce a la jerga.

## Enforcement

El gate `G_SUMMARY` en `scripts/pr-plan.sh` valida:

1. Existencia de `.pr-summary.md` en el repo root antes del push
2. Longitud mínima (300 caracteres, ~50 palabras)
3. Existencia del título canónico `## Qué hace este PR (en lenguaje no técnico)`

Si falla, pr-plan se detiene con mensaje pidiendo que se cree el fichero.

`scripts/push-pr.sh` lee `.pr-summary.md` y lo prepend al PR body antes de la sección Summary auto-generada.

El hook `.opencode/hooks/pr-summary-gate.sh` (PreToolUse sobre `gh pr create`) repite las comprobaciones locales (existencia, título, menos de 24 h) y añade una revisión LLM vía `ANTHROPIC_BASE_URL`. La red está acotada: conexión ≤ 3 s y respuesta ≤ `PR_SUMMARY_LLM_TIMEOUT` segundos (90 por defecto, entero 1-90). Si el proxy rechaza la conexión, no contesta a tiempo o devuelve algo no parseable, el hook avisa (`ADVERTENCIA … gate omitido`) y deja pasar: la revisión LLM es fail-open; las comprobaciones locales bloquean siempre.

`.pr-summary.md` está gitignored — vive solo en local. Lo escribe el agente (o el humano) antes de cada PR. Se sobrescribe entre PRs.

## Excepciones

Solo se acepta saltar este gate cuando el PR es:

- **`chore: sign confidentiality audit`** — commit auto, sin contenido funcional. El gate se satisface con un párrafo placeholder ("Solo firma de auditoría, sin cambios funcionales.")
- **PR de revert puro** sin lógica nueva — el original ya tenía su párrafo, este puede referenciarlo.
- **Hotfix de pipa rota** que bloquea el repo — emergency exception, debe documentarse en el body por qué se salta.

NO es excepción válida: "PR pequeño", "cambio trivial", "evidente del título". Si es trivial, escribir el párrafo es trivial.

## Ejemplos

### Bueno

> Hago que mi memoria sea más fiable. Antes podía guardar cualquier idea como si fuera un hecho — incluyendo suposiciones o planes que no llegué a ejecutar. A partir de este cambio, cada vez que escribo algo en mi memoria tengo que decir de dónde viene: ¿lo leí en un fichero?, ¿me lo dijo una herramienta?, ¿lo pediste tú? Si no puedo justificarlo, el sistema me bloquea con un mensaje. La idea viene de un proyecto open source y se llama "sin ejecución, sin memoria". Reduce el riesgo de que tomes decisiones basadas en algo que yo solo supuse.

### Malo

> Implements SE-072 Slice 1: adds --source flag to memory-store.sh save command, registers PreToolUse hook memory-verified-gate.sh in settings.json, validates 4 source formats and rejects 5 blacklisted, includes 33 BATS tests certified at score 94.

(Es una descripción técnica precisa — pero solo legible para quien ya conoce el proyecto. No cumple el contrato del párrafo.)

## Política de evolución

Slice 1: gate hard-fail + auto-inject del fichero al body. Sin LLM-validation.

Posibles fases futuras:
- F2: scoring de "pegas técnicas" — detectar IDs/acrónimos no permitidos
- F3: longitud máxima (evitar prosa excesiva)
- F4: idioma del párrafo según perfil activo (`preferences.md` del usuario activo)

## Referencias

- `scripts/pr-plan-gates.sh` — gate `g_summary`
- `scripts/push-pr.sh` — lee `.pr-summary.md` y lo prepend
- `.gitignore` — `.pr-summary.md` excluido
- `feedback_pr_natural_language` — memoria persistente
