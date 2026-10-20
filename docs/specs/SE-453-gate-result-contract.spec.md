---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: A
risk: L3
related_specs: [SE-444, SE-449, SE-239, SE-244]
origin: output/research/20261020-learnings-zero-breach.md (A1, A2)
resource: https://github.com/interplains/zero-breach
---

# SE-453 — Contrato de resultado de los gates: limpio, hallazgos y desconocido

## Problema

Un gate de seguridad que no pudo ejecutarse y se lee como «sin hallazgos» es un falso verde. La regla
`docs/rules/domain/checker-fail-closed.md` lo prohíbe, pero es una regla de texto: no fija un
vocabulario de salida común, así que cada script decide por su cuenta qué significa cada código.
Medido sobre `main` (2c54b4f63):

- **Tres vocabularios incompatibles.** `scripts/dependency-scan.sh`: 1 = hallazgos, 2 = error
  (Trivy ausente, escaneo o SBOM fallido). `scripts/git-history-secret-scan.sh`: 1 = hallazgos
  críticos **o gitleaks ausente**, 2 = solo MEDIUM/LOW, 4 = escaneo fallido. `scripts/ast-quality-gate.sh`:
  1 = fallo, 2 = error de entorno, 3 = UNVERIFIED con `meta.coverage`. El mismo número 2 significa
  «error», «hallazgos menores» y «entorno» según el script. Un llamador genérico no puede decidir.
- **Herramienta ausente confundida con hallazgos.** gitleaks ausente sale 1, el mismo código que
  secretos críticos: bloquea, pero por una causa que el informe no distingue.
- **Guards `blocking: true` que salen 0 sin `jq`.** `.claude/hooks/block-credential-leak.sh` y
  `.claude/hooks/block-force-push.sh` hacen `exit 0` si `command -v jq` falla, con un aviso solo en
  stderr. Reproducido el 2026-10-20 en el primero: con un token de GitHub sintético en el comando,
  el hook sale 2 con `jq` y **0 con un `PATH` sin `jq`**. El segundo tiene el mismo código (lectura,
  no reproducido). `docs/rules/domain/hooks-blocking-guards.md` exige salir
  «solo con 0 o 2 … sin `jq` en el PATH»: se cumple la letra, no el propósito (el guard queda
  desactivado sin que nada lo señale). `install.sh` trata `jq` como opcional. En cambio,
  `.claude/hooks/block-infra-destructive.sh` ya degrada a un parseo con `grep`: es el patrón correcto.
- 12 hooks que comprueban `jq` salen 0 sin él; la mayoría no son de seguridad (índices, marcadores),
  y su fallo abierto es aceptable si queda registrado como no medido.

`ast-quality-gate.sh` ya implementa el patrón (capa que no corre = `missing|failed|unsupported`, baja
`meta.coverage`, resultado UNVERIFIED): es el modelo interno. Falta extenderlo y hacerlo obligatorio.

## Valor y evidencia

- El escáner externo zero-breach (Apache-2.0) lo resuelve en el tipo de resultado: `CLEAN`, `HITS`,
  `UNKNOWN`, `PARTIAL`; un módulo con algo que no pudo ejecutar pasa a `PARTIAL` automáticamente, un
  tope de recursos (ficheros, bytes, profundidad, tiempo) se registra como hueco y no como limpio, y
  un test lo fijó tras una revisión que halló una carpeta podada marcada como limpia (lectura sin
  ejecutar). Su contrato lo resume: «un elemento omitido no es un elemento limpio».
- Evidencia propia: los tres vocabularios y el fallo abierto de dos guards, medidos arriba. No hay
  incidente conocido; el valor es cerrar una clase de falso verde, no corregir un daño.

## Alcance

| Slice | Entrega |
|---|---|
| S0 | **Auditoría**: tabla de todos los escáneres (`scripts/*scan*`, `*audit*`, `*gate*` de seguridad) y hooks `blocking: true` con tres columnas: vocabulario de códigos, qué hace si falta una dependencia, qué hace si supera un tope o timeout. Entrega `docs/evidence/SE-453-S0-gate-result-audit.md`. Define el alcance real de S1 a S3. |
| S1 | Contrato `docs/rules/domain/gate-result-contract.md`, **extensión** de `checker-fail-closed.md` (se enlaza, no se duplica): tres estados `clean`, `findings`, `unknown`; campo JSON `result` y lista `gaps[]` (cada hueco con `check`, `reason`: `missing_tool`, `limit`, `timeout`, `unreadable`); tabla de correspondencia de los códigos **existentes** de cada script al estado canónico, sin renumerarlos. Los scripts nuevos siguen el contrato desde el origen. |
| S2 | Guards `blocking: true` sin `jq`: degradan a un parseo con `grep` como `block-infra-destructive.sh`, y si tampoco pueden evaluar, salen 2. Nunca 0 sin haber evaluado. Los hooks no marcados que salen 0 sin `jq` añaden una línea al registro de no medido (`output/unmeasured-gates.jsonl`). |
| S3 | Topes que producen `unknown`: cada escáner con tope de recursos, timeout o límite de tamaño identificado en S0 registra el desborde como hueco y no como `clean`. Primer lote: los de S0 con exposición real; el resto, por demanda. |
| S4 | **Sonda de gradación de evidencia** (sin cambio de producto). En `data-sovereignty-gate.sh` una lista de «parece código» rebaja un hallazgo a aviso; el default para una entidad no reconocida ya es bloqueo. Se mide si esa lista puede ocultar un dato real (por ejemplo una entidad que empieza por una palabra de código). Si hay un caso, se abre un delta; si no, se cierra como no aplicable. |

## Fuera de alcance

- Renumerar los códigos de salida existentes: rompe llamadores (hooks, CI, skills). Se documenta la
  correspondencia.
- Convertir `unknown` en bloqueante de CI desde el primer día: decisión D3.
- Estado epistémico de los informes de tribunal (SE-449) y autoridad del verificador en el cierre
  (SE-444): son capas distintas; esta spec solo trata el resultado de los escáneres y guards.
- Reemplazar gitleaks, Trivy o Semgrep.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `docs/evidence/SE-453-S0-gate-result-audit.md` lista cada escáner y guard `blocking` auditado con las tres columnas, y `grep -c '^| ' docs/evidence/SE-453-S0-gate-result-audit.md` es ≥ 10. |
| AC2 | `docs/rules/domain/gate-result-contract.md` define los tres estados, `result`, `gaps[]` y la tabla de correspondencia; enlaza a `checker-fail-closed.md` sin copiar sus reglas (`grep -c 'Reglas duras'` en el nuevo fichero es 0). |
| AC3 | Test BATS `tests/test-gate-result-contract.bats`, caso 1: con `PATH` sin `gitleaks`, `git-history-secret-scan.sh` informa `result: unknown` con un hueco `missing_tool` y no sale con el mismo código que un hallazgo crítico. |
| AC4 | Mismo test, caso 2: con un fixture que supera el tope de un escáner de S3, el resultado es `unknown` con hueco `limit`, nunca `clean`. |
| AC5 | Test BATS: con `PATH` sin `jq` y un token de GitHub sintético en el comando (construido en el test, no escrito en el fichero), `block-credential-leak.sh` y `block-force-push.sh` (con `git push --force`) salen 2 y no 0. |
| AC6 | Mismo test, caso con `jq` presente: sin cambios de comportamiento (token → 2; comando inocuo `ls -la` → 0). |
| AC7 | Con `PATH` sin `jq`, un hook no marcado de S2 sale 0 y añade una línea JSON válida a `output/unmeasured-gates.jsonl` con `hook` y `reason: missing_tool`. |
| AC8 | Si S4 encuentra un caso, publica `docs/evidence/SE-453-S4-evidence-grading.md` con el fixture; si no, el mismo fichero declara «no aplicable» con la medición. |
| AC9 | `bash scripts/hooks-integrity-check.sh --blocking` y `bats tests/test-hooks-blocking-audit.bats` siguen en verde. |
| AC10 | `capability-entropy.py --check` PASS y `validate-ci-local.sh --quick` verde. |

## Riesgos

- Puede volver rojo CI que hoy pasa en falso. Es el objetivo: el contador baseline de `unknown`
  se congela y solo puede bajar; el primer ciclo es de aviso (D3).
- S2 sin `jq`: el parseo con `grep` es menos robusto que `jq`. Mitigación: ante duda sale 2, y
  `block-infra-destructive.sh` ya lo hace así sin incidencias conocidas.
- Si el contrato se sobreespecifica, los scripts nuevos lo ignorarán. Se mantiene en una página y un
  campo (`result`) más una lista (`gaps`).
- Una máquina sin `jq` y con guards en exit 2 quedaría sin poder ejecutar Bash. Por eso el primer
  recurso es degradar, no bloquear, y el instalador avisa de que `jq` es requisito de los guards.

## Licencia de lo reutilizado

zero-breach es Apache-2.0, compatible con MIT. Se toma el patrón de diseño; no se copia código. Sus
reglas YARA (DRL 1.1, CC BY-SA 4.0) no se incorporan ni se mezclan con el código de Savia.

## Esfuerzo

S0 S, S1 S, S2 S, S3 M, S4 S.

## Decisiones pendientes de la operadora

- **D1**: mantener los códigos de salida existentes con tabla de correspondencia (propuesta) o
  renumerarlos.
- **D2**: guards `blocking` sin `jq`: degradar a `grep` y si no, salir 2 (propuesta), solo salir 2, o
  mantener el aviso.
- **D3**: `unknown` bloquea CI desde el primer día o tras un ciclo de aviso con contador baseline
  (propuesta: un ciclo).

## Referencias cruzadas

`docs/rules/domain/checker-fail-closed.md` (regla de texto que esta spec hace ejecutable),
`docs/rules/domain/hooks-blocking-guards.md` (requisito de salida 0/2), SE-444 (cobertura no
verificada en el cierre), SE-449 (estado epistémico en informes), SE-239 (escaneo de historial),
SE-244 (escaneo de dependencias).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Guards `blocking` (S2) | hooks bash registrados en `.claude/settings.json` | función equivalente del plugin `savia-gates` |
| Escáneres (S1, S3) | scripts bash | mismos scripts |
| Contrato y evidencia | documentos | mismos documentos |

### Verification protocol

- [ ] S2 probado en OpenCode además de Claude Code: mismas entradas en el guard bash y en su equivalente TypeScript, mismo código de salida.
- [ ] Tests de ambas rutas (con `jq` y sin `jq`).
- [ ] Si el equivalente TypeScript de un guard no depende de `jq`, el caso sin `jq` se marca no aplicable con motivo.

### Portability classification

- [x] **DUAL_BINDING**: S2 en ambos desde la primera slice; S1, S3 y S4 son PURE_BASH.
