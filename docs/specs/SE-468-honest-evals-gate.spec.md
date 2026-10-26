---
status: PROPOSED
priority: P0
developer_type: agent-single
created: 2026-10-26
author: Savia
phase: A
risk: L2
related_specs: [SE-456, SE-453, SE-204, SE-381, SE-444, SE-469]
origin: síntesis de una tesis sobre evaluación y aseguramiento de agentes; diseño en el repo de investigación privado
---

# SE-468 — El gate de evals debe poder fallar

## Problema

El workflow `Evals CI Gate` (`.github/workflows/evals-ci.yaml`) se ejecuta en cada PR que toca `.claude/` u `.opencode/`
(skills, agentes, hooks) y publica una tabla de delta pareado contra un baseline. Su nota no depende de ningún fichero de
skill, agente ni hook:

- `scripts/evals-runner.sh` solo lee `tests/evals/datasets` y `tests/evals/baselines`.
- Modo mock, el único que usa la CI (`evals-ci.yaml:84` y `:173`, siempre `--mock`):
  `score = min(0.95, 0.70 + len(input)/1000)`, es decir, la longitud del texto del caso (`evals-runner.sh:112-115`).
- Modo vivo: `score = 0.80` constante, con el comentario «placeholder: real LLM call would go here»
  (`evals-runner.sh:116-118`).
- Un dataset sin baseline devuelve `threshold_pass: true`.

Medido el 2026-10-26 sobre `e7224df97`: en un directorio temporal con solo el runner, `evals-paired-delta.py`, los
datasets y los baselines, **sin ninguna skill, agente ni hook**, el gate da el mismo resultado que en el repo
(`pbi-decomposition` delta +0,0056 PASS; `privacy-shield` PASS sin baseline). Es un test que no puede fallar (SE-456) en
el sitio donde la PR busca la señal «la skill no ha empeorado».

## Valor y evidencia

- Quita una garantía falsa que hoy acompaña a cada PR de skills, agentes y hooks. Es el riesgo central que señalan las
  guías de evaluación de agentes (Anthropic, *Demystifying evals for AI agents*, ene-2026; NIST CAISI, *Cheating AI agent
  evaluations*, dic-2025): superar un eval no demuestra que la ejecución sea correcta. Aquí es peor: el eval aprueba sin
  mirar.
- No añade superficie: corrige un componente que existe. Desbloquea SE-381 (DEFERRED), que reutiliza `tests/evals/` y
  hoy heredaría el runner vacuo.

## Alcance (slice S)

| Slice | Entrega |
|---|---|
| S1 | **Resultado honesto.** Mientras el runner no ejecute el artefacto evaluado, cada dataset emite `result: unknown` con un hueco `gaps[].reason: not_executed` (contrato de SE-453; el motivo nuevo es la decisión D1). El paso de umbral distingue `clean`, `findings` y `unknown`, y `unknown` no se presenta como verde en el comentario de la PR. Un dataset sin baseline también da `unknown` (`reason: no_baseline`). |
| S2 | **Sin placeholder.** Se elimina `score = 0.80`: el modo vivo sin juez ni ejecutor configurado sale con código ≠0 y un mensaje que nombra la variable que falta (fallo cerrado, `checker-fail-closed.md`). |
| S3 | **Prueba de sabotaje** (criterio de SE-456 para que un gate cuente como evidencia): fixture con el artefacto evaluado vacío o saboteado. El gate solo puede declarar un dataset como evaluado si esa fixture produce `findings`. |

## Fuera de alcance

- Conectar el modo vivo con un ejecutor real: SE-381 o SE-469.
- Crear datasets nuevos o tocar los golden sets de los tribunales (SE-469).
- Cambiar umbrales del delta pareado.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | BATS que falla antes del cambio: con el artefacto del dataset `pbi-decomposition` sustituido por uno vacío, el gate **no** devuelve PASS; devuelve `unknown` o `findings`. |
| AC2 | BATS negativo: `evals-runner.sh` sin `--mock` y sin juez configurado sale con código ≠0 y el mensaje nombra la variable que falta. Hoy sale con 0 y nota 0,80. |
| AC3 | BATS: un dataset sin baseline produce `result: unknown` con `reason: no_baseline`, nunca `threshold_pass: true`. |
| AC4 | El JSON que consume el paso `github-script` contiene el resultado por dataset y el comentario de la PR muestra «no evaluado» para los `unknown` (test sobre el JSON, no sobre la UI). |
| AC5 | Si el detector de vacuidad de SE-456 cubre workflows, clasifica el gate antiguo como vacuo y el nuevo como no vacuo; si no los cubre, se registra como cobertura no verificada (SE-444), sin afirmarlo. |
| AC6 | Los tests existentes del runner (`tests/` que referencian `evals-runner.sh`) en verde, y `capability-entropy.py --check` PASS. |

## Riesgos

- Las PRs de skills dejan de ver un verde. Alguien puede leerlo como «la CI empeoró»; el comentario lo explica. Es la
  corrección buscada, no un efecto secundario.
- Que `unknown` acabe ignorado igual que el PASS falso. Mitigación: SE-453 D3 decide cuándo `unknown` bloquea; este slice
  solo lo hace visible.

## Esfuerzo

S: un script, un workflow y 3–4 tests.

## Decisiones pendientes de la operadora

- **D1**: añadir `not_executed` y `no_baseline` a los motivos de hueco de SE-453 (propuesta: sí, en este slice).
- **D2**: mientras no exista ejecución real, mantener el workflow (informando `unknown`) o retirarlo de las PRs
  (propuesta: mantenerlo; retirar ocultaría que no hay evaluación).

## Referencias cruzadas

SE-456 (vacuidad, APPROVED), SE-453 (contrato de resultado de gate), SE-204 (runner), SE-381 (matriz de evals por
riesgo, DEFERRED), SE-444 (autoridad del verificador), SE-469 (tribunales medidos).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/evals-runner.sh`, `scripts/evals-paired-delta.py` | scripts invocados por CI | los mismos |
| `.github/workflows/evals-ci.yaml` | CI, independiente del frontend | la misma |

### Verification protocol

- [ ] Los tests corren sin frontend.
- [ ] Sin hooks nuevos.
- [ ] El mismo JSON de resultado desde los dos frontends (mismo script).

### Portability classification

- [x] **PURE_BASH**: scripts y workflow de CI; ningún binding de frontend.
