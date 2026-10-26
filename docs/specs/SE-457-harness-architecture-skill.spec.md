---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L1
related_specs: [SE-208, SE-209, SE-445, SE-454]
origin: investigación sobre arquitectura de harness, metaharness y orquestación (2026-10-23)
resource: https://www.anthropic.com/engineering/building-effective-agents
---

# SE-457 — Skill `harness-architecture`: decidir y diseñar la arquitectura de un harness

## Problema

Las skills de ejecución existen (`overnight-sprint`, `code-improvement-loop`, `automation-scheduler`,
`dag-scheduling`), pero ninguna ayuda a decidir **cuánta estructura** necesita un trabajo de agentes
(agente único, orquestadora, metaharness) ni a diseñar bucles, flujos largos y sprints con sus
condiciones de parada. Medido sobre `main` (139268c03):

- `ls .claude/skills | grep -i harness` no devuelve nada: no hay skill de arquitectura de harness.
- Los fallos operativos de Savia con agentes (subagente colgado más de 6 h esperando un permiso,
  pregunta bloqueante que paró 7 entregas durante 4 h, vigilante por recuento que perdió entregas,
  disco al 100 % con agentes en paralelo, 33 PR acumulados en un día) están repartidos entre memorias
  y notas privadas. Ninguna regla pública los reúne con su remedio.
- El tope de agentes simultáneos se trata a veces como límite técnico. Es política de cuenta y de
  máquina; el SDK de agentes trae su propio valor por defecto (20 subagentes simultáneos) y es
  configurable.

## Valor y evidencia

La investigación abrió unas 35 fuentes públicas (lista con URL y fecha en
`.claude/skills/harness-architecture/references/fuentes.md`). Hallazgos que la skill recoge:

- Convergencia en empezar simple y añadir estructura solo tras un fallo observado (Anthropic, OpenAI,
  Cognition). Anthropic y Cognition se concilian separando lectura paralela de escritura acoplada.
- Controles deterministas antes que prosa y guías más sensores (Böckeler, 2026-04-02: sin cifras ni
  experimentos propios).
- Guardarraíles en capas, riesgo por herramienta y escalado a persona por umbral de fallos o acción de
  alto riesgo (OpenAI); una excepción de guardarraíl se trata como resultado desconocido, no como
  aceptación (documentación del Agents SDK).
- Del SDK de agentes de Claude: subagente con conversación nueva y solo su último mensaje vuelve al
  padre; un hook que permite no salta las reglas de denegación; la compactación puede perder
  instrucciones tempranas; el presupuesto puede excederse en una respuesta.
- **Evidencia cuantitativa débil**: casi todo es medición interna de Anthropic de una sola ejecución.
  Cifras de segunda mano verificadas contra su fuente primaria: de seis cifras de Marmelab, dos se
  confirman (con matices), una no es verificable, una no se pudo abrir y dos **no coinciden con su
  fuente** (la bajada del 8 % por un segundo revisor no aparece en la tabla de ablación del artículo
  citado; el efecto de los ficheros de contexto sobre el éxito es pequeño y no significativo). La skill
  no usa las dos discrepantes.
- **Metaharness**: no hay evidencia independiente de que mejore resultados. La skill lo describe como
  experimental (línea de investigación L39 abierta) y exige medir el sobrecoste.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | `SKILL.md` ≤150 líneas (SE-208; objetivo ~100), orientada a decisiones: Decision Checklist de nueve preguntas, condiciones de aborto, tres reglas no negociables y etiquetas de evidencia (medida, medida interna, experiencia propia, opinión, documentación). |
| S2 | `references/`: checklist de diseño, catálogo de patrones, flujos largos/bucles/sprints, metaharness (marcado experimental), anti-patrones con coste observado, plantillas y `fuentes.md` (públicas, URL y fecha, con la verificación de cifras). |
| S3 | Tope de agentes simultáneos como **parámetro de política** (cuenta y máquina) registrado en el plan de sprint con quién lo fijó; el diseño funciona con cualquier valor. |
| S4 | `evals/evals.json` en el formato del estándar Agent Skills: 20 consultas de disparo (10 deben activar, 10 casi-fallos) y 3 evals de salida con aserciones. |
| S5 | `DOMAIN.md` y registro en el catálogo; sin enlaces a ficheros privados. |

## Fuera de alcance

- Implementar harnesses, ejecutar sprints o bucles, programar tareas, gestionar el sprint de proyecto.
- Recomendar metaharness como práctica general antes de cerrar L39.
- Ejecutar las evals de disparo por modelo: la spec entrega las consultas; la medición es una tarea aparte.
- Cambiar `autonomous-safety.md` o el límite de agentes de la cuenta.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bash scripts/skill-catalog-auditor.sh --skill harness-architecture` sin FAIL; `wc -l .claude/skills/harness-architecture/SKILL.md` ≤150 (objetivo ~100). |
| AC2 | `references/fuentes.md` existe, cada fuente con URL y fecha (o `n/d`), y la tabla de verificación de cifras de segunda mano. |
| AC3 | `grep -rniE "labs|/home/|savia-labs" .claude/skills/harness-architecture` no devuelve rutas privadas ni personales. |
| AC4 | `references/metaharness.md` empieza marcando el estado experimental (L39) y `SKILL.md` lo repite en el punto 5 del Decision Checklist. |
| AC5 | `SKILL.md` contiene la regla del tope de agentes como parámetro de política y `plantillas.md` (plan de sprint) pide anotar quién lo fijó. |
| AC6 | `python3 -c "import json;d=json.load(open('.claude/skills/harness-architecture/evals/evals.json'));assert len(d['trigger_evals'])==20 and sum(e['should_trigger'] for e in d['trigger_evals'])==10 and len(d['evals'])==3"` pasa; cada eval de salida tiene `prompt`, `expected_output` y `assertions`. |
| AC7 | Caso negativo de AC6: un `evals.json` con 9 consultas positivas hace fallar la comprobación (el chequeo lo detecta). |
| AC8 | `python3 scripts/sam.py check` FRESH, `capability-entropy.py --check` PASS y `confidentiality-scan.sh --pr` sin bloqueo. |

## Riesgos

- Solape con skills existentes: la sección «Cuándo NO usar» encamina a `overnight-sprint`,
  `code-improvement-loop`, `automation-scheduler`, `dag-scheduling` y `sprint-management`; las 10
  consultas casi-fallo lo prueban cuando se midan.
- Skill que no dispara: en el catálogo hay pocas skills usadas y ninguna con evals; sin la medición de
  S4 el disparo es hipótesis. Mitigación: ejecutar las 20 consultas con varias repeticiones tras el merge.
- Poda: si L39 se cierra en negativo, se retira `references/metaharness.md` y el punto 5 del checklist.
- Cifras externas que cambian: las fuentes llevan fecha y las no verificadas están marcadas.

## Esfuerzo

S1-S5: M (una sesión). Medición de disparo: S, aparte.

## Decisiones pendientes de la operadora

- **D1**: si la skill nace con `maturity: draft` (propuesta) o se espera a medir el disparo.
- **D2**: si el tope de agentes simultáneos de la cuenta se documenta en una regla propia además de la skill.

## Referencias cruzadas

SE-208 (tamaño de SKILL.md), SE-209 (descripción), SE-445 (enforcement de modos autónomos),
SE-454 (formato de spec), `docs/rules/domain/autonomous-safety.md`, `docs/rules/domain/remedy-ladder.md`.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Skill `harness-architecture` | `.claude/skills/harness-architecture/SKILL.md` | el mismo directorio, vía el registro de skills (`.opencode/skills` apunta a `.claude/skills`) |
| Evals | `evals/evals.json` del estándar Agent Skills | el mismo fichero |

### Verification protocol

- [ ] La skill es Markdown y JSON: no depende del frontend; se lee igual en OpenCode.
- [ ] Las referencias a `claude -p` y al SDK se presentan como ejemplos; el diseño no exige Claude Code.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: no hay lógica ejecutable, solo Markdown y JSON independientes del frontend; el único binding es el registro de skills, cubierto por el enlace `.opencode/skills`.
