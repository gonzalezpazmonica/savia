# Revisión de graduación — lote grad-b (sesión S27)

Commit medido: `9c3284e98`. Fecha: 2026-11-10. Una línea por spec; el detalle (tabla de AC, orden ejecutada y mutaciones) está en cada fichero. Ningún `status` se ha cambiado: graduar lo decide la operadora.

| Spec | Recomendación | Resumen |
|---|---|---|
| [SE-468](SE-468-20261110.md) | RESTO | AC1-AC4, AC6-AC7 cumplidos con mutaciones; AC5 sin la línea de «cobertura no verificada» del gate de evals. |
| [SE-471](SE-471-20261110.md) | GRADUAR | 8 AC cumplidos, 16 tests ok y mutaciones que los rompen. Kill criterion y D1/D2 son seguimiento. |
| [SE-480](SE-480-20261110.md) | GRADUAR | AC-1..AC-8 cumplidos (32 tests ok, 5 mutaciones caen). Instalación de la unidad queda a la operadora. |
| [SE-481](SE-481-20261110.md) | RESTO | AC-1..AC-7, AC-9, AC-10 cumplidos; AC-8 (baseline en `savia-docs` real) no verificable aquí. |
| [SE-485](SE-485-20261110.md) | RESTO | N1-N5 cumplidos; AC-6 (suite completa verde) no: `federation/search.test.ts` usa `/tmp` fijo y falla si el directorio es de otro usuario. |
| [SE-483](SE-483-20261110.md) | GRADUAR | AC-1..AC-6 cumplidos; AC-7 (descripción en GitHub) a la operadora. `test-equality-shield.sh` huérfano con 4 fallos previos. |
| [SE-484](SE-484-20261110.md) | RESTO | 63 tests ok y mutaciones; AC-8 (smoke en OpenCode y Claude Code) no verificable. |
| [SE-487](SE-487-20261110.md) | GRADUAR | AC-1..AC-6 cumplidos (50 tests ok, guardia en CI de PR); `install.ps1` no se ejecutó en Windows. |
| [SE-395](SE-395-20261110.md) | RESTO | R00-R04 y aislamiento V02 cumplidos (AC01-06, 13-14, 17-20); AC07-12, AC15 y AC16 no hechos (pasan a SE-489). |
| [SE-378](SE-378-20261110.md) | RESTO | S1-S3, AC2 y AC3 cumplidos; AC1: la comprobación «IMPLEMENTED sin evidencia» no tiene test que falle y no existe «prioridades contradictorias». |
| [SE-387](SE-387-20261110.md) | NO GRADUAR | Paraguas con B que marca COMPLETE sin validar la cadena, F2-F5 sin cablear (9 WARN DECLARED), deuda en wave 0 y 3 códigos adversariales sin test o sin código. |

## Hallazgos transversales

- `projects/savia-vaults/tests/unit/federation/search.test.ts` usa la ruta fija `/tmp/fake-federation-test`: falla con `EACCES` cuando existe con otro propietario (afecta a SE-485 y SE-395).
- Los tests de `savia-vaults` se ejecutaron copiando `node_modules` del checkout principal; no se instaló nada.
- `scripts/test-equality-shield.sh`: 37/41, fallos anteriores a SE-483/487 y fuera de CI.
