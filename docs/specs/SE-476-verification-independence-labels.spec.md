---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-29
author: Savia
phase: D
risk: L2
related_specs: [SE-444, SE-469, SE-471, SE-474]
origin: revisión de Anthropic Research en Savia Labs (privado), propuesta derivada a spec pública por encargo de la operadora 2026-10-29
timeline:
  - from: "2026-10-29"
    learned: "2026-10-29"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-476 — Independencia de la verificación: acuerdo correlacionado, autorrevisión e informe del propio modelo

## Problema

Savia trata como evidencia tres cosas que no son independientes de lo que verifican:

1. **Acuerdo entre jueces del mismo modelo.** Los tribunales (Truth, Recommendation, Code Review Court) y las
   revisoras `claude -p` resuelven sus jueces por tier (`model_tier`) contra el mismo proveedor: 21 jueces en
   `.claude/agents/*-judge.md`, 15 `mid`, 4 `heavy`, 2 `fast`. Su acuerdo se agrega como si fueran votos
   independientes. No lo son: comparten sesgos y puntos ciegos.
2. **Autorrevisión del worker.** Los workers autónomos repasan su propio diff antes de marcar OK. Es higiene útil,
   pero nada impide leer ese OK como verificación (SE-471 separa declarado y validado en el relevo; esta spec fija el
   mismo criterio en la regla de verificación).
3. **Justificación del modelo.** `decision-trace-protocol.md` exige `rationale` y `confidence`, y el
   `calibration-judge` evalúa su coherencia. Ninguna regla dice que el `rationale` es lo que el modelo dice de sí
   mismo, no la causa medida de la decisión.

## Fuente

- Anthropic, «Multiagent systems»: agentes del mismo modelo convergen y coluden sin canal privado, y en tareas de
  perfil oculto no hacen valer la información decisiva de la minoría; «consensus is not necessarily evidence».
  <https://www.anthropic.com/research/multiagent-systems>
- Anthropic, «How AI agents shape experts' judgment calls»: un consenso aparente puede reflejar las preferencias de un
  solo modelo. <https://www.anthropic.com/research/agents-judgment-calls>
- Anthropic, «Harness design for long-running apps»: los agentes que evalúan su propio trabajo lo elogian con
  confianza; separar al evaluador y afinarlo escéptico es mucho más tratable.
  <https://www.anthropic.com/research/harness-design-long-running-apps>
- Anthropic, «Reasoning models don't always say what they think» e «Introspection»: la cadena de razonamiento no
  siempre refleja la causa y la introspección es poco fiable.
  <https://www.anthropic.com/research/reasoning-models-dont-say-think> ·
  <https://www.anthropic.com/research/introspection>
- Priorización: Savia Labs (privado).

## Propuesta

1. **Campo `independence` en los veredictos agregados.** Los agregadores de los tres tribunales añaden
   `independence: correlated | mixed | independent` y `providers: <n>` calculados desde la configuración resuelta de
   cada juez (proveedor, no modelo). Con todos los jueces del mismo proveedor: `correlated`. El texto del veredicto
   dice «N jueces del mismo proveedor (correlacionados)» y nunca «N/N independientes».
2. **Sin ascenso por unanimidad correlacionada.** Una unanimidad `correlated` no eleva la confianza ni el tier de
   evidencia de un AC en SE-444; cuenta como **una** fuente de verificación.
3. **Autorrevisión = higiene.** Regla en `docs/rules/domain/maker-checker-protocol.md`: la autorrevisión del autor no
   cuenta como verificación en ningún gate. Cada elemento de `acceptance_evidence` (SE-444,
   `scripts/lib/planning-completion.sh`) admite `verifier` y `author`; una función de listado señala los AC cuyo
   verificador es el mismo agente o sesión que produjo el cambio.
4. **`rationale` y `confidence` como autoinforme.** `decision-trace-protocol.md` los documenta como autoinforme del
   modelo. El `calibration-judge` puede usarlos para coherencia interna, pero su informe no puede afirmar «la decisión
   se tomó por X» basándose solo en el `rationale`; debe citar evidencia externa (test, diff, dato) o marcar
   `causa: autoinformada`.
5. **Métrica cuando hay segundo proveedor** (enlaza con SE-474): tasa de hallazgos que solo encuentra el proveedor
   independiente, publicada junto al veredicto; sin ella no se afirma independencia.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bats tests/test-tribunal-independence.bats`: con fixtures de jueces del mismo proveedor, cada agregador emite `independence: correlated` y `providers: 1`; con un juez de proveedor distinto simulado, `mixed`; con configuración ilegible o proveedor desconocido, `correlated` (fallo cerrado, nunca `independent`). |
| AC2 | El texto de veredicto con jueces correlacionados no contiene «independientes» (grep negativo en la salida) y sí «correlacionados». |
| AC3 | `bats tests/test-verifier-not-author.bats`: una evidencia de fixture con `verifier` igual a `author` aparece en el listado de AC autoverificados; con `verifier` distinto no aparece; con `verifier` ausente aparece como «verificador no declarado» (fallo cerrado). |
| AC4 | `decision-trace-protocol.md` y `maker-checker-protocol.md` contienen las frases de autoinforme y de higiene (test de presencia), y la regla de independencia no se re-lista en otros ficheros (una sola fuente). |
| AC5 | Regresión: el veredicto PASS/WARN/VETO de cada agregador es idéntico al de `main` sobre sus fixtures; solo se añaden campos. |

## Riesgos

- **Leer `correlated` como «inválido»**: no lo es; es una fuente, no varias. La regla lo explica.
- **Proveedor mal detectado**: si el nombre del proveedor no se puede resolver, fallo cerrado a `correlated`.
- **Superficie nueva**: dos campos y un validador; la entropía de capacidades no debe subir (se consolida en los
  agregadores existentes).

## Alternativas

- **Añadir jueces del mismo modelo con prompts adversariales**: más votos, misma correlación; no resuelve el problema
  de etiqueta.
- **Exigir siempre segundo proveedor**: contradice la opcionalidad de SE-474 y su criterio de abandono.
- **No hacer nada**: los informes siguen sumando como independientes votos que no lo son.

## Lo que no se hace

- No cambia el número ni la composición de los jueces.
- No exige un segundo proveedor (eso es SE-474, opcional).
- No elimina la autorrevisión de los workers: se mantiene como higiene barata.
- No intenta medir la causa real de una decisión (no hay acceso a activaciones desde el arnés).

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Campos `independence`/`providers` en los tres agregadores + texto; AC1, AC2, AC5. |
| S2 | Regla de autorrevisión y listado de AC autoverificados en `planning-completion.sh`; AC3. |
| S3 | Texto de autoinforme en decision-trace y límite del calibration-judge; AC4. |

## Esfuerzo

S1 S, S2 S, S3 S.

## Decisiones pendientes de la operadora

- **D1**: ¿la unanimidad correlacionada cuenta como una fuente en SE-444? (propuesta: sí).
- **D2**: ¿S2 depende de que SE-444 esté integrada? (propuesta: sí; si no, S2 se limita a la regla).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Agregadores de tribunales (`scripts/recommendation-tribunal/aggregate.sh` y equivalentes) | scripts bash | los mismos scripts |
| Resolución de proveedor por juez | `~/.savia/preferences.yaml` → `tiers.claude-code` | `~/.savia/preferences.yaml` → `tiers.opencode` |
| Reglas (`maker-checker-protocol.md`, `decision-trace-protocol.md`) | ficheros de dominio | los mismos, vía AGENTS.md |

### Verification protocol

- [ ] Funciona en runtime OpenCode: el agregador lee el tier del frontend activo.
- [ ] Tests cubren ambos paths (fixtures de tiers de los dos frontends).
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: agregación y validación en bash/Python sin bindings de frontend; el proveedor sale de la
  configuración local de tiers de cada frontend.
