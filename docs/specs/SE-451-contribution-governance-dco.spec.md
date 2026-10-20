---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: A
risk: L2
related_specs: [SE-442]
origin: output/research/20261020-learnings-inditex.md (L1, L6)
resource: https://github.com/InditexTech/foss
---

# SE-451 — Gobernanza de contribuciones: DCO frente a CLA y metadatos de licencia por fichero

## Problema

El repositorio es público y acepta contribuciones de personas ajenas, pero no deja constancia de qué
certifica quien contribuye:

- `CONTRIBUTING.md` no menciona licencia de las contribuciones, `Signed-off-by`, DCO ni CLA (búsqueda
  de `licen`, `firma` y `sign` en el fichero: sin resultados). No hay workflow que lo compruebe
  (`.github/workflows/`: sin `dco` ni `signoff`).
- `docs/rules/domain/enterprise-licensing-policy.md` dice «CLA not required (MIT does not need it)».
- `LICENSE-ENTERPRISE.md` declara que la capa Enterprise es MIT, **permanente, no revocable y sin
  doble licencia**, y que no existe una edición propietaria. Esto es relevante porque el informe de
  investigación que origina esta spec partía de una premisa errónea: que Savia tiene licencia dual y
  que un CLA permitiría relicenciar. En el repo público esa premisa es falsa y un CLA de relicenciación
  contradiría un compromiso escrito.
- No hay metadatos de licencia por fichero (`REUSE.toml`, `LICENSES/`, `NOTICE`: no existen) para
  quien integre Savia en un entorno con auditoría de licencias.

## Valor y evidencia

- Inditex Tech exige `Signed-off-by` en cada commit más commits firmados, con un workflow reutilizable
  `Check Signed-Off-By` que comenta en el PR y exime a los bots (`foss/CONTRIBUTING.md`,
  `.github/.github/workflows/signoff-check.yml`). Además publica un CLA que le da derecho a decidir la
  licencia del proyecto: ese segundo paso es justo el que **no** encaja con el compromiso de Savia.
- Un DCO (el contribuyente certifica que tiene derecho a enviar el código bajo la licencia del
  proyecto) cuesta una línea por commit, es coherente con MIT (licencia entrante = saliente) y deja un
  rastro auditable. No evita disputas por sí solo ni sustituye asesoramiento legal.
- REUSE/SPDX (metadatos de licencia por fichero) es útil para quien audita licencias, pero no hay
  evidencia de que alguien lo haya pedido; se deja como slice opcional.
- Mi recomendación, no una decisión: DCO sí; CLA de relicenciación no; REUSE solo si hay demanda.

## Alcance

| Slice | Entrega | Condición |
|---|---|---|
| S1 | `CONTRIBUTING.md`: sección «Certificación de origen (DCO)» con el texto del DCO 1.1 y el uso de `git commit -s`. | D1 = DCO |
| S2 | Workflow `.github/workflows/dco-check.yml` con evento `pull_request` (no `pull_request_target`), permisos `contents: read`, que lista los commits del PR por la API y falla si alguno no tiene `Signed-off-by` coincidente con el autor. Resultado en el resumen del job, **sin checkout del código del PR**. Exime a los PRs de ramas `agent/*` abiertos por quien mantiene el repo y a los bots listados. Acciones fijadas por SHA (SE-442). | D1 = DCO, D2 |
| S3 | Si D1 = CLA: no se implementa en esta spec; se abre una spec propia con texto legal revisado por una persona abogada y se reconcilia antes con `LICENSE-ENTERPRISE.md`. | D1 = CLA |
| S4 | Opcional, solo con demanda: `REUSE.toml` global con anotaciones por directorio (evita tocar miles de ficheros), `LICENSES/`, `NOTICE` y un job `reuse lint`. Decide qué hacer con `projects/` y con lo vendorizado. | D3 |

## Fuera de alcance

- Redactar o adaptar un CLA (la plantilla de Inditex es CC-BY-SA-4.0 y no es consejo legal).
- Cambiar la licencia de Savia o su capa Enterprise.
- Exigir commits firmados con GPG (decisión aparte; ya existe firma de confidencialidad de PR, que es otra cosa: `confidentiality-sign.sh`).
- Reescribir el historial para añadir sign-offs.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `grep -c 'Signed-off-by' CONTRIBUTING.md` ≥ 1 y el fichero contiene el texto «Developer Certificate of Origin» (S1). |
| AC2 | `bats tests/test-dco-check.bats`: sobre un repositorio git temporal, un commit con `-s` pasa; sin `-s` falla y nombra el SHA; un commit de bot de la lista pasa; un commit de `agent/*` de mantenedor pasa. El BATS ejecuta la misma lógica que el workflow (script embebido en el YAML y probado extrayéndolo). |
| AC3 | El workflow usa `pull_request`, declara `permissions: contents: read` y no contiene `actions/checkout` ni `pull_request_target` (`grep` de ambos: sin resultados). |
| AC4 | Cumple el test de SE-442 (`uses:` fijados por SHA). |
| AC5 | Si D1 = CLA, esta spec queda sustituida y no se mergea ningún cambio de S1/S2. |
| AC6 | Si se hace S4: `reuse lint` termina en 0 en CI y `projects/` y lo vendorizado figuran como excepciones con motivo. |
| AC7 | `bash scripts/validate-ci-local.sh --quick` verde. |

## Riesgos

- Fricción para quien contribuye por primera vez: el mensaje de error del check debe explicar `git commit -s` y `git commit --amend -s`.
- Un check que falla en el PR de quien mantiene frena el flujo de agentes: de ahí la exención de `agent/*` (D2).
- Un sign-off puesto por un agente con la identidad de una persona certifica algo que esa persona no ha leído: por eso no se automatiza el sign-off en nombre de nadie.
- `pull_request_target` con checkout del código del PR es una superficie de ataque conocida; el diseño la evita por construcción (AC3).
- No es asesoramiento legal.

## Licencia de lo reutilizado

El texto del DCO 1.1 es de la Linux Foundation y se distribuye bajo términos que permiten copiarlo
sin modificar; **verificar el texto y su licencia al implementar S1**. Del workflow de Inditex
(Apache-2.0, compatible con MIT) solo se toma el patrón: la lógica se escribe de nuevo. Su CLA no se
usa. Si se hiciera S4, la herramienta `reuse` se usa como utilidad de CI, sin enlazarla ni
redistribuirla; su licencia no se verificó (marcar «a verificar»).

## Esfuerzo

S1 S, S2 S, S3 M con revisión legal, S4 M.

## Decisiones pendientes de la operadora

- **D1**: DCO (recomendado), CLA o ninguno. Un CLA de relicenciación contradice `LICENSE-ENTERPRISE.md`.
- **D2**: exención del check para ramas `agent/*` del mantenedor y lista de bots.
- **D3**: ¿entra REUSE/SPDX (S4)? Recomendación: no hasta que alguien lo pida.
- **D4**: ¿se aplica a contribuciones ya mergeadas? Recomendación: no, solo hacia adelante.

## Referencias cruzadas

SE-442 (acciones fijadas por SHA; comparte `.github/` y `SECURITY.md`).

## OpenCode Implementation Plan

### Bindings touched

Ninguno: documentación y un workflow de GitHub. No toca hooks, agentes ni skills.

### Verification protocol

- [ ] Sin cambios de comportamiento en Claude Code ni en OpenCode.
- [ ] El test BATS corre en CI con ambos frontends ausentes.

### Portability classification

- [x] **PURE_BASH**
