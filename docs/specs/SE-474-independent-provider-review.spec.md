---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-27
author: Savia
phase: D
risk: L3
related_specs: [SE-433, SE-458, SE-469, SE-343, SE-362, SE-445]
origin: decisión de la operadora 2026-10-27 tras una evaluación independiente que señaló sesgo correlacionado (la misma orquestadora propone, sintetiza y guía aprobaciones, y las revisoras son del mismo proveedor)
timeline:
  - from: "2026-10-27"
    learned: "2026-10-27"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-474 — Proveedor independiente opcional: refutación, tribunal, programación y protocolo reforzado de aprobación

## Problema

Hoy un solo proveedor de modelos cumple todos los papeles de una PR de control: la orquestadora propone y sintetiza,
las revisoras (`correctness`, `security`) dictaminan y los jueces de los tribunales opinan. Un fallo que comparten los
modelos del mismo proveedor (un punto ciego, una lectura complaciente de la spec) atraviesa las tres capas porque
ninguna es independiente de las otras. Una evaluación independiente lo señaló como sesgo correlacionado.

Dato que falta, y por eso esta spec nace PROPOSED: no hay medición de cuántos hallazgos reales de una PR de control
habría encontrado un segundo proveedor que las revisoras actuales no vieron. M0 (abajo) la produce antes de construir
nada más.

## Principios de diseño

- **Agnóstico de proveedor**: la fuente no nombra ningún proveedor ni modelo. El proveedor independiente se declara en
  configuración local (`~/.savia/preferences.yaml`, clave `independent_provider`, con el mismo patrón que
  `action_review.command` y los tiers por frontend). Ejemplo de la clave (valores ilustrativos, viven solo en local):
  `independent_provider.command` con marcador `{role}`, `independent_provider.timeout_s`,
  `independent_provider.required_for` (lista de clases de PR de control) y `independent_provider.order` (orden de
  invocación si hay más de uno).
- **Opcional**: sin proveedor configurado o disponible no se bloquea nada. Los flujos siguen como hoy y el informe lo
  declara: «sin revisión independiente de otro proveedor».
- **Solo dictamina**: el proveedor independiente emite veredicto y opinión; nunca aprueba. Aprobar sigue siendo de la
  operadora (Rule 8).

## Los tres papeles

| Papel | Qué hace | Salida |
|---|---|---|
| Refutación (`refutation`) | Intenta romper un control (hook, gate, grant, permiso) con reproducciones concretas | Informe con primera línea `VERDICT:` y las reproducciones que fallan |
| Juez independiente (`tribunal`) | Voto adicional e independiente en Recommendation y Truth Tribunal | Score y veto en el formato de los jueces actuales |
| Programadora (`author`) | Abre PRs en rama `agent/*` como cualquier otro agente | PR Draft; las reglas de autoría de SE-433 aplican (no puede revisar su propia PR) |

## Detección de disponibilidad

`scripts/independent-provider.sh status` devuelve exactamente uno de estos estados y sale con un código distinto:

| Estado | Condición | Exit |
|---|---|---|
| `absent` | clave `independent_provider` sin declarar o sin orden de invocación | 10 |
| `present` | declarada y una sonda no destructiva (`probe`, tiempo limitado) responde bien | 0 |
| `error` | declarada pero la sonda falla, agota el tiempo, devuelve basura o la configuración es ilegible | 11 |

Fallo cerrado: cualquier entrada inesperada (YAML ilegible, comando inexistente, salida vacía) es `error`, nunca
`present`. `absent` no es un error: es el estado normal de otra instalación.

## Obligatoriedad en PRs de control

Cuando el estado es `present`, el proveedor independiente es **obligatorio** en PRs de control: las que `risk-tier.py`
clasifica tier 4 o las que tocan hooks, grants, gates o permisos (lista cerrada de rutas en la configuración de
`merge-sprint`, no en la preferencia local). Reglas:

- `present` + PR de control: `merge-sprint.sh plan` exige un registro del rol `independent` sobre el SHA actual.
- `error` + obligatorio (declarado en `required_for`): la PR queda **en espera** (`WAIT_INDEPENDENT`), ni aprobada ni
  rechazada, y el plan lo lista. No degrada a «sin revisión independiente».
- `absent`: la PR sigue el flujo actual y el informe incluye la frase de ausencia.
- Un HOLD del rol `independent` bloquea el merge igual que el de `correctness` o `security`: `reviews_ok` ya trata
  cualquier veredicto distinto de APPROVE como bloqueo; solo hay que admitir el rol en la gramática y en el conjunto
  de roles necesarios cuando corresponda.

## Protocolo reforzado de aprobación de specs

Se activa solo si el estado es `present`; sin él, el proceso de aprobación actual no cambia.

1. **Plantilla de propuesta** (`templates/spec-approval-proposal.md`). Cada propuesta lleva: problema medido, alternativa
   «no hacer nada» con su coste, coste de la propuesta, dependencias, riesgo residual, criterio de abandono y una
   **opinión contraria** redactada por el proveedor independiente.
2. **Opciones no recomendadas aplazadas por defecto**: en la pregunta a la operadora, toda opción distinta de la
   recomendada figura como «aplazada» salvo que ella la active.
3. **Cuatro aprobaciones separadas**: investigación, spec, implementación y aceptación de resultado. Aprobar una no
   implica la siguiente.
4. Un validador (`scripts/validate-approval-proposal.sh`) rechaza una propuesta sin alguna de las seis secciones o con
   la opinión contraria vacía cuando el estado es `present`.

## Opinión contraria

Redactada aquí como ejemplo del protocolo (la escribe la propia spec porque en esta redacción no hay proveedor
independiente que la firme; lo declara y la operadora debe pedirla al aprobar):

- **Coste y latencia**: cada PR de control añade una consulta externa de minutos y gasto de cuota. Con SE-458 limitando
  la atención humana, una revisión más puede alargar la cola sin cambiar el resultado en la mayoría de PRs.
- **Falsa sensación de independencia**: dos modelos de proveedores distintos comparten datos de entrenamiento, sesgos
  de complacencia y puntos ciegos con el mismo código. Que coincidan no prueba que estén bien; puede ser la misma
  alucinación dos veces. Un APPROVE de dos proveedores se leería como más fuerte de lo que es.
- **Dependencia nueva**: una cuenta externa que caduca, cambia de condiciones o de modelo sin aviso añade un modo de
  fallo (de ahí `error` y la espera), y el tiempo de mantener la sonda y el parser.
- **Alternativa barata**: más revisoras del mismo proveedor con prompts adversariales distintos, o refutación mecánica
  (mutación, fuzzing de hooks) que no depende de ningún modelo.
- **Lo que haría cambiar de opinión**: M0 mide cuántos hallazgos P0/P1 reales aporta el proveedor independiente sobre
  las PR de control ya revisadas. Si es menos de 1 de cada 10 PRs, se abandona (criterio de abandono).

## Alternativa «no hacer nada»

Las revisoras actuales y los tribunales siguen. Coste de no actuar: el sesgo correlacionado señalado sigue sin medir y
sin mitigar; no se puede afirmar ni negar que exista. Beneficio: cero superficie, cero dependencia, cero latencia.

## Criterio de abandono

Se abandona (la spec pasa a REJECTED o DEFERRED) si M0 mide menos de 1 hallazgo P0/P1 útil por cada 10 PRs de control
revisadas por el proveedor independiente y no vistas por las revisoras, o si la latencia media de `status` +
dictamen supera 15 min por PR en tres lotes seguidos.

## Alcance

| Slice | Entrega |
|---|---|
| M0 | Medición: 20 PRs de control ya fusionadas, revisadas a ciegas por el proveedor independiente con el rol `refutation`; cuántos hallazgos P0/P1 reproducibles aportan que las revisoras no vieron. Informe en el domo de investigación (no en `output/`). Sin código de producto. |
| S1 | `scripts/independent-provider.sh` (`status`, `probe`) y lectura de `independent_provider` en `preferences.yaml`, fallo cerrado. Tests AC1 y AC3. |
| S2 | `merge-sprint.sh`: rol `independent` en `parse_verdict`, `reviews_ok`, `plan` y estado `WAIT_INDEPENDENT`. Tests AC2. |
| S3 | `templates/spec-approval-proposal.md` y `validate-approval-proposal.sh`. Tests AC4. |
| S4 | Papeles `tribunal` y `author`: conexión con los tribunales y con el lanzador de PRs. Solo tras M0 favorable. |

S2 a S4 no empiezan sin que la operadora apruebe la implementación (aprobación separada, según el propio protocolo).

## Fuera de alcance

- Cambiar el número de revisoras actuales.
- Quitar la revisión humana de tier 3 y 4 (SE-362).
- Que el proveedor independiente apruebe nada: solo dictamina.
- Nombrar un proveedor o un modelo concretos en fuente, tests o documentación versionada.
- Enviar al proveedor independiente contenido N3 o superior: aplica el nivel de confidencialidad vigente; sin recibo
  de datos, no sale (ver `confidentiality-scan.sh`).

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bats tests/test-independent-provider.bats`: `status` devuelve `absent` (exit 10) sin clave, `present` (exit 0) con un comando de prueba que responde, y `error` (exit 11) con comando inexistente, con tiempo agotado, con salida vacía y con YAML ilegible. Con `required_for` declarado y estado `error`, el plan de `merge-sprint` marca la PR `WAIT_INDEPENDENT` y nunca la lista como aprobable. |
| AC2 | `bats tests/test-merge-sprint.bats`: `review-register` acepta `role=independent`; un HOLD de ese rol impide `reviews_ok` aunque `correctness` y `security` sean APPROVE; sin `independent` en una PR de control y estado `present`, `reviews_ok` falla. |
| AC3 | Regresión: con `independent_provider` sin declarar, la salida de `merge-sprint.sh plan` y `reviews_ok` es idéntica byte a byte a la de `main` sobre las mismas fixtures, y el informe contiene la frase «sin revisión independiente de otro proveedor». |
| AC4 | `bats tests/test-approval-proposal.bats`: la plantilla contiene las seis secciones; el validador rechaza una propuesta a la que le falta cada una de ellas (una prueba por sección) y rechaza una opinión contraria vacía; sin proveedor `present` no exige la opinión. |
| AC5 | `grep` de nombres de proveedor y de modelo sobre los ficheros nuevos no devuelve nada (test BATS); `capability-entropy.py --check` PASS. |

## Riesgos

- Falsa sensación de independencia (ver «Opinión contraria»). Mitigación: el informe indica el proveedor solo como
  `independent`, y un APPROVE coincidente no sube el tier de confianza.
- Fuga de contenido sensible al proveedor externo. Mitigación: confidencialidad por nivel antes de cada consulta.
- Bloqueo operativo por una cuenta caída en modo obligatorio. Mitigación: la espera es visible en el plan y la
  operadora puede quitar `required_for` en local; `absent` nunca bloquea.
- Dependencia de SE-469, que no consta en `main` a fecha de esta spec: debe confirmarse su alcance antes de S2.

## Esfuerzo

M0 S, S1 S, S2 S, S3 S, S4 M.

## Decisiones pendientes de la operadora

- **D1**: investigación M0 primero (propuesta: sí; si no, no hay evidencia para el resto).
- **D2**: `independent` obligatorio para tier 4 y rutas de control solo con estado `present`, o también exigir su
  presencia (propuesta: solo con `present`; exigir presencia contradice la opcionalidad).
- **D3**: S4 (tribunal y programadora) en esta spec o en otra tras M0 (propuesta: aparte, tras M0).

## Referencias cruzadas

SE-433 (merge-sprint, registro de revisiones), SE-458 (presupuesto de atención humana), SE-469 (por confirmar),
SE-343 y SE-362 (grants y tiers), SE-445 (revisor de acciones: mismo patrón de configuración local y fallo cerrado),
`docs/rules/domain/provider-agnostic-env.md`, `docs/rules/domain/action-review-policy.md`.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/independent-provider.sh` | script bash invocado por `merge-sprint.sh` | el mismo script |
| `scripts/merge-sprint.sh` (rol `independent`) | bash con Python embebido | el mismo script |
| `templates/spec-approval-proposal.md` y validador | fichero y script bash | los mismos |

### Verification protocol

- [ ] Los tests corren sin frontend y con un comando de proveedor simulado (ningún proveedor real en CI).
- [ ] El estado `status` es idéntico desde los dos frontends (misma configuración local, mismo script).
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: lógica en bash y Python embebido sin bindings de frontend; el proveedor es una orden configurable.
