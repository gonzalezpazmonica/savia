---
version_bump: minor
section: Added
---

### Added

- SE-512 S1: merge-sprint.sh policy-plan, policy-request y policy-verify. La operadora aprueba el permiso nocturno fusionando una PR de aprobación (SE-488); policy-verify comprueba el recibo, el digest y la ventana efectiva sin fusionar nada. Sin run --policy (S2).
- SE-512 S1, tras revisión: una sola petición por política, policy-plan exige que el clon sea del repo declarado y trae la rama antes de congelar código, y los filtros de rama siguen la semántica de GitHub.

- SE-512 S1, correcciones de la revisión de Codex y de las páginas (#1597): los patrones de ficheros de la política admiten solo `A-Za-z0-9._/*-` (antes `<!--` ocultaba alcance en el resumen de la PR de aprobación), los globs salen entre acentos graves y los checks se escapan; reviewers como logins sin distinguir mayúsculas; solo cuentan los workflows de primer nivel; `policy-request` reserva la petición con O_EXCL antes de abrir la PR, valida la configuración de aprobación antes de registrar y publica solo el artefacto (`commit --only`); `plan` rechaza `repos` no iterable.
