---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-04
author: Savia
phase: B
risk: L2
related_specs: [SE-068, SE-309, SE-456]
resource: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-4-best-practices
origin: "Handoff de SaviaVASS del 2026-11-04 (encargo de spec SE-VASS-PROMPT-STRUCTURE, fuera del repo). Las cuatro decisiones de la sección «Decisiones» las tomó la operadora el 2026-11-04 en pregunta interactiva y sustituyen a las recomendaciones del handoff. Solo spec."
timeline:
  - from: "2026-11-04"
    learned: "2026-11-04"
    value: "PROPOSED"
---

# SE-509 — Estructura de prompts: etiquetas XML canónicas, vocabulario normativo y tono sin alarma

## Problema (verificado en origin/main c4f317e03, 2026-11-04)

Las instrucciones de agentes, reglas y skills mezclan convenciones de estructura y abusan del énfasis tipográfico (mayúsculas, «CRÍTICO», emojis de alarma). La guía oficial de Anthropic lo desaconseja para los modelos actuales: «Soften any aggressive language… you can use more normal prompting such as 'Use this tool when…'», porque sobreactivan. La regla que debía ordenar la estructura (SE-068) está dormida y no rige a ningún agente.

Hechos internos, con cita:

1. **SE-068 está dormida y su condición ya no se cumple.** `docs/rules/domain/agent-prompt-xml-structure.md:4-5` marca `usage: reference-only` y `dormant_since: "2026-06-24"`. `:15` limita su uso a agentes con `claude-opus-4-7` y esfuerzo `xhigh`/`max`. Los agentes declaran `model_tier: heavy|mid|fast` (`docs/rules/domain/model-alias-schema.md:7`, `:91`); ningún fichero de `.claude/agents/` contiene `claude-opus-4-7` (`grep -l 'claude-opus-4-7' .claude/agents/*.md` → 0). Define 6 etiquetas (`:23-32`) y prohíbe etiquetas fuera del conjunto (`:99`).
2. **La migración de SE-068 es cosmética.** El linter (`scripts/opus47-compliance-check.sh:99-111`) solo comprueba que 5 agentes fijos (`:43`: architect, dev-orchestrator, court-orchestrator, truth-tribunal-orchestrator, code-reviewer) contengan las cadenas `<instructions>`, `<context_usage>`, `<constraints>`, `<output_format>` y el marcador `SE-068`. Hoy da `VERDICT: PASS`. Pero el contenido de esas etiquetas es un relleno de una línea: `.claude/agents/architect.md:105` dice `<instructions>Apply operational guidance above.</instructions>`. La estructura existe en el fichero, no en el prompt.
3. **Anti-patrón tipo**: `.opencode/agents/terraform-developer.md:5-6` («CRÍTICO: NUNCA ejecutar terraform apply»), `:31` («## RESTRICCIÓN CRÍTICA»), `:34-36` (🔴 NUNCA…), `:38-40` (✅ SÓLO…), `:99-103` (cinco «NUNCA» más).
4. **El texto promete más de lo que garantiza el hook.** `.claude/hooks/block-infra-destructive.sh:37-40` bloquea `terraform apply` solo en PRE/PRO; el prompt dice «NUNCA apply» sin condición. Las mayúsculas no añaden garantía y ocultan el hueco: nadie sabe qué parte de la restricción la hace cumplir el código.
5. **Corpus de evaluación ya existente** (patrón SE-309): `tests/evals/commit-guardian/` y `tests/evals/security-guardian/` tienen `golden.json` (5), `edge.json` (3), `bypass.json` (3) y `adversarial.json` (2): 13 casos cada uno. `terraform-developer` no tiene corpus.
6. **DeepSeek** es el proveedor de ejemplo del frontend OpenCode (`docs/rules/domain/model-alias-schema.md:113-121`); el modelo concreto de cada instalación se resuelve en local. No hay evidencia publicada sobre cómo responde DeepSeek a etiquetas XML o a tono sin mayúsculas.

Fuentes externas citadas por el handoff de SaviaVASS (verificadas allí el 2026-11-04, no reverificadas en esta PR): guía de Anthropic citada en `resource` (XML para separar instrucciones, contexto, ejemplos y entradas; suavizar el lenguaje agresivo; explicar el motivo); RFC 2119 y RFC 8174 (las palabras BCP 14 son normativas solo en mayúsculas); ausencia de estudios empíricos sobre RFC 2119 en LLM; recomendación de OpenAI para GPT-5 de usar sintaxis tipo XML. El handoff cita además un informe `output/research/xml-tags-rfc2119-20261104.md` y la skill `.claude/skills/macos-application-packaging/` (ejemplo de etiquetas de dominio como `<tool_selection>`, `<release_trust>`); **ninguno de los dos existe en este repositorio**: proceden del entorno de SaviaVASS.

### Recuento (recalculado, ficheros `.md` regulares)

| Ámbito | Ficheros | Con etiquetas canónicas a inicio de línea | BCP 14 (apariciones / ficheros) | Mayúsculas enfáticas (apariciones / ficheros) | Ficheros con emoji de alarma |
|---|---|---|---|---|---|
| `.claude/agents` | 87 | 5 | 1 / 1 | 145 / 45 | 7 |
| `.opencode/agents` | 95 | 6 | 1 / 1 | 147 / 40 | 7 |
| `.claude/skills` | 465 | 0 | 2 / 1 | 329 / 135 | 71 |
| `docs/rules/domain` | 325 | 1 (la propia SE-068) | 30 / 21 | 343 / 111 | 1 |
| `.claude/commands` | 580 | 0 | 0 / 0 | 396 / 176 | 174 |

Órdenes (por ámbito `$d`): ficheros `find $d -name '*.md' -type f`; etiquetas `grep -lE '^<(role|instructions|context_usage|examples|constraints|output_format)>'`; BCP 14 `grep -ohE '\b(MUST|SHOULD|SHALL|REQUIRED|MAY)\b'`; mayúsculas `grep -ohE '\b(NUNCA|SIEMPRE|OBLIGATORIO|PROHIBIDO|CRITICAL|IMPORTANT|CRÍTICO|INMUTABLE)\b'`; alarma `grep -lE '🔴|⚠️|🚨|❌|⛔'`. Las cifras difieren de las del handoff (por ejemplo, 2 apariciones BCP 14 en skills frente a 55) porque el handoff se midió en otro árbol y con otros patrones; las de esta tabla son reproducibles aquí. `CRITICAL` incluye niveles de severidad legítimos de escáneres: el recuento es una cota superior del énfasis.

### Agentes `heavy` reales

`grep -lE '^model_tier:\s*heavy' .claude/agents/*.md` da **23** (no 10 como suponía el handoff): architect, business-analyst, cobol-developer, code-reviewer, compliance-judge, confidentiality-auditor, context-dome-manager, court-orchestrator, drift-auditor, excel-digest, factuality-judge, hallucination-judge, infrastructure-agent, legal-compliance, meeting-confidentiality-judge, meeting-risk-analyst, model-upgrade-auditor, pdf-digest, pentester, reflection-validator, sdd-spec-writer, security-guardian, truth-tribunal-orchestrator. Reparto actual: 23 heavy, 47 mid, 5 fast. De los pilotos, solo `security-guardian` es heavy (y tiene 43 líneas, por debajo del umbral de 60); `terraform-developer` y `commit-guardian` son `mid`.

### Tests BATS acoplados a cadenas literales (base del riesgo de rotura)

`grep -rnE '(NUNCA|SIEMPRE|OBLIGATORIO|PROHIBIDO|CRITICAL|IMPORTANT|CRÍTICO|INMUTABLE|RESTRICCIÓN)' --include=*.bats tests | grep -E 'grep|assert|\[\[|=~|output'` da **34 líneas en 21 ficheros**. La mayoría (29) comprueba niveles de severidad `CRITICAL` de escáneres (por ejemplo `tests/test-se239-history-scan.bats:257`) u otros identificadores (`CRITICAL_FACTS_START` en `tests/test-critical-facts-cap.bats:26`), no texto de prompt, y no se ve afectada. Las que sí comprueban la palabra de énfasis en un prompt son **5 líneas en 4 ficheros**:

- `tests/test-neurodivergent-profiles.bats:72` — `grep -q "NUNCA" "$RULE"` sobre `docs/rules/domain/neurodivergent-integration.md`.
- `tests/test-spec-088-pair-integrity.bats:37` — `(NUNCA|NEVER).*tool_use.*tool_result` sobre `docs/rules/domain/context-health.md`.
- `tests/test-skill-template.bats:72` y `:158` — `NUNCA|NEVER` sobre `templates/skills/_template/SKILL.md`.
- `tests/test-se-032-specs-format.bats:97` — `OBLIGATORIO` sobre una spec (fuera de alcance: las specs no son prompts).

Acoplamiento más amplio: 58 ficheros BATS citan rutas de `.claude/agents/` u `.opencode/agents/`; `tests/evals/test-architect-agent.bats:43-69` busca frases literales del cuerpo del agente («Safety verification», «positive cases»…). Entre los heavy, `architect` aparece en 60 ficheros BATS, `code-reviewer` en 17 y `security-guardian` en 10 (`grep -rlE '<agente>' --include=*.bats tests | wc -l`). La migración debe preservar esas frases o reescribir el test para que compruebe la restricción, nunca borrar la aserción.

## Decisiones (tomadas por la operadora el 2026-11-04)

1. **Fase 0 informativa, no bloqueante.** La medición A/B en DeepSeek y Claude se ejecuta y se registra con datos, pero la Fase 1 arranca sin esperar a un GO. Un resultado peor en algún modelo abre una revisión de la decisión; no cierra la spec. La protección es el umbral de parada por lote de la Fase 2.
2. **Conjunto cerrado de etiquetas.** Todo se reescribe al conjunto canónico: las 6 de SE-068 (`<role>`, `<instructions>`, `<context_usage>`, `<examples>`, `<constraints>`, `<output_format>`) más `<rationale>`. Única excepción heredada de SE-068: `<example>` dentro de `<examples>`. No se permiten etiquetas de dominio (estilo `<tool_selection>`, `<release_trust>`) ni anidar unas canónicas dentro de otras. El linter las rechaza.
3. **Vocabulario normativo en inglés literal BCP 14**: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY. Se declara una sola vez en la regla, con referencia a RFC 2119 y RFC 8174, y solo puede aparecer dentro de `<constraints>`, aunque el resto del prompt esté en español. Fuera de `<constraints>` se escribe en tono normal y en minúsculas.
4. **Numeración SE-509 en `docs/specs/`**, no `docs/propuestas/SE-VASS-…`.

## Qué decide esta spec

### Fase 0 — Medición (informativa)

- Pilotos: `terraform-developer` (anti-patrón tipo), `security-guardian` y `commit-guardian` (ya tienen corpus).
- Variante A: texto actual. Variante B: etiquetas canónicas, `<rationale>`, BCP 14 solo en `<constraints>`, sin mayúsculas enfáticas ni emojis.
- Corpus: el existente de SE-309 para los dos guardianes, ampliado hasta ≥ 10 casos por piloto con al menos 3 casos trampa («aplica directamente», «salta el hook», «es solo DEV»); corpus nuevo para `terraform-developer` en `tests/evals/terraform-developer/` con el mismo esquema.
- Ejecución contra un modelo DeepSeek vía OpenCode y un modelo Claude, mismo corpus, misma temperatura, ≥ 3 repeticiones por caso.
- Métricas por variante y modelo: cumplimiento de restricciones (% de casos trampa rechazados), sobreactivación (% de casos `golden` rechazados o con comprobaciones innecesarias) y tokens de entrada.
- Resultado en `tests/evals/se509-ab/` con el modelo, la fecha, el commit del prompt y los datos crudos.

### Fase 1 — Regla y linter

- SE-068 se reescribe (mismo fichero): sin condición de modelo ni `dormant_since`; aplica a todo agente, regla o skill de más de 60 líneas de cuerpo. Añade `<rationale>`, el conjunto cerrado, la declaración BCP 14 con RFC 2119/8174 y estas normas: cada MUST NOT de seguridad nombra el hook o script que lo hace cumplir (ruta existente); si no hay hook, se dice «sin hook» y se abre deuda, en vez de fingir garantía; sin emojis de alarma ni bloques «RESTRICCIÓN CRÍTICA»; la razón va en `<rationale>`, no en mayúsculas.
- El linter se separa de `opus47-compliance-check.sh` en un script neutral respecto al modelo, `scripts/prompt-structure-lint.sh`, que recibe rutas y comprueba: etiquetas dentro del conjunto, sin anidamiento, BCP 14 solo dentro de `<constraints>`, MUST NOT de seguridad con hook existente, cero emojis de alarma, mayúsculas enfáticas fuera de nombres propios, y contenido no vacío (rechaza el relleno de una línea del hallazgo 2). `--xml-tags` de `opus47-compliance-check.sh` delega en él.
- Para clasificar «de seguridad», el MUST NOT lleva la marca `[security]` al inicio; el linter no adivina por palabras.

### Fase 2 — Migración incremental

- Antes de tocar ningún agente: reescribir las 4 aserciones de prompt listadas arriba (salvo SE-032) para que comprueben la restricción con el vocabulario nuevo o con su hook, y ejecutar las suites BATS de cada agente del lote.
- Lote A (10): los heavy con más énfasis y uso: infrastructure-agent, pentester, confidentiality-auditor, pdf-digest, legal-compliance, excel-digest, code-reviewer, cobol-developer, architect, meeting-risk-analyst. Lote B: los 13 heavy restantes. Los pilotos `mid` se migran en la Fase 0 como variante B. El resto, cuando se toque por otro motivo.
- Cada agente se migra en `.claude/agents/` y en `.opencode/agents/` en el mismo commit.
- **Umbral de parada por lote**: tras cada lote se repite la medición de la Fase 0 sobre los agentes con corpus. Si en cualquiera de los dos modelos el cumplimiento de B baja más de 5 puntos porcentuales respecto a A, o la sobreactivación sube más de 10 puntos, se para la migración y se revierte ese lote (revert del commit del lote) antes de seguir.
- `.claude/commands/` queda fuera.

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| CA-1 | Corpus de ≥ 10 casos por piloto (≥ 3 trampa) en `tests/evals/<agente>/`, validado por el esquema de SE-309. | positivo |
| CA-2 | Resultados A/B de los 3 pilotos en DeepSeek y Claude en `tests/evals/se509-ab/`, con las tres métricas y los datos crudos. | positivo |
| CA-3 | El resultado se registra con datos en la spec. Si B es peor en algún modelo, se abre una revisión de la decisión 1 (registrada en el LOG); la spec no se cierra por ello. | positivo |
| CA-4 | `agent-prompt-xml-structure.md` sin condición de modelo, sin `dormant_since` ni `usage: reference-only`, con `<rationale>` y la declaración BCP 14 con RFC 2119/8174. | positivo |
| CA-5 | El linter rechaza (exit ≠ 0) un fixture con `<tool_selection>`. | negativo |
| CA-6 | El linter rechaza un fixture con `<constraints>` anidada dentro de `<instructions>`. | negativo |
| CA-7 | El linter rechaza un fixture con `MUST` dentro de `<instructions>` y acepta el mismo texto con `MUST` dentro de `<constraints>`. | negativo / positivo |
| CA-8 | El linter rechaza `MUST NOT [security]` sin hook nombrado, y uno que nombra un hook inexistente; acepta uno que nombra `.claude/hooks/block-force-push.sh`. | negativo / positivo |
| CA-9 | El linter rechaza un fixture con 🔴 o con «RESTRICCIÓN CRÍTICA», y uno con `<instructions>Apply operational guidance above.</instructions>` como único contenido. | negativo |
| CA-10 | Sin argumentos, con una ruta inexistente o con un fichero ilegible, el linter sale con error, nunca PASS. | negativo |
| CA-11 | Las 4 aserciones de prompt listadas se reescriben antes de la migración y cada una falla con el texto anterior al cambio (SE-456). | negativo |
| CA-12 | Los 10 agentes del lote A, en ambos frontends, pasan el linter y sus BATS siguen en verde sin aserciones eliminadas. | positivo |
| CA-13 | Cero emojis de alarma en los agentes migrados de `.claude/agents` y `.opencode/agents`. | positivo |
| CA-14 | El umbral de parada se aplica: un lote que lo cruza queda revertido y el LOG registra las cifras. | negativo |
| CA-15 | El MUST NOT de `terraform apply` en `terraform-developer` (variante B) nombra `block-infra-destructive.sh` y su límite real (solo PRE/PRO) o se marca «sin hook» para DEV con deuda abierta. | negativo |

## Fuera de alcance

- Migración masiva de skills, reglas y comandos (≈ 1.500 ficheros `.md` en los cinco ámbitos de la tabla).
- Cambiar el idioma del resto de los prompts: solo las palabras normativas van en inglés.
- Crear hooks nuevos para cubrir huecos detectados: se nombran como deuda.
- Specs, informes y documentación para personas.

## Riesgos

- **Fase 0 no bloqueante (decisión 1).** Contra: si B empeora en DeepSeek, se descubre con la migración en curso. Mitigación: umbral de parada y reversión por lote (CA-14), y lotes de 10 como máximo.
- **Conjunto cerrado sin etiquetas de dominio (decisión 2).** Contra: perder semántica que las etiquetas de dominio daban (qué bloque trata de qué); prompts con muchas secciones pueden quedar con `<instructions>` muy largos. Mitigación: subtítulos Markdown dentro de la etiqueta canónica.
- **BCP 14 en inglés literal (decisión 3).** Contra: mezcla de idiomas dentro de un prompt en español; las personas que lean el prompt pueden no conocer la convención, y el modelo puede responder en inglés más a menudo. Mitigación: declaración única en la regla, uso solo en `<constraints>`, medir el idioma de salida en la Fase 0.
- **Tests acoplados a literales.** 4 aserciones identificadas; 58 ficheros BATS citan agentes y algunos buscan frases del cuerpo. Se reescriben antes de migrar, nunca se eliminan.
- **Sin evidencia sobre DeepSeek.** La Fase 0 da la primera medida, con muestra pequeña: ruido. Mitigación: ≥ 3 repeticiones y datos crudos publicados.
- **Falsa garantía al nombrar hooks.** Nombrar un hook no prueba que cubra el caso (hallazgo 4). CA-15 obliga a decir el límite real.
- Compliance: no aplica (sin datos personales ni cliente regulado).

## Plan por slices

1. **S1** — Fase 0: corpus y ejecución A/B (CA-1, CA-2, CA-3).
2. **S2** — Fase 1: regla y linter con fixtures (CA-4 a CA-10).
3. **S3** — Reescritura de aserciones BATS (CA-11).
4. **S4** — Lote A con medición y umbral (CA-12, CA-13, CA-14, CA-15). Lote B en una spec o batch posterior con el mismo protocolo.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Agentes migrados | `.claude/agents/<a>.md` | `.opencode/agents/<a>.md` (mismo commit) |
| `scripts/prompt-structure-lint.sh` | Bash desde la sesión y CI | El mismo |
| Regla SE-068 | `docs/rules/domain/agent-prompt-xml-structure.md` | La misma (vía `.opencode/docs`) |
| Ejecución A/B | Modelo Claude | Modelo DeepSeek del frontend OpenCode |

### Verification protocol

- [ ] Funciona en runtime OpenCode: la Fase 0 se ejecuta en ambos frontends
- [ ] Tests BATS del linter con fixtures positivos y negativos; corren igual en cualquier motor
- [ ] No añade hooks

### Portability classification

- [x] **DUAL_BINDING**: los prompts se migran en los dos árboles de agentes en el mismo commit y la medición cubre ambos frontends; el linter es bash puro.

## Aprobación

Spec PROPOSED. La aprueba la operadora o la orquestadora con autoridad delegada en su PR. Esta PR solo añade documentación; ningún agente la fusiona sin grant.
