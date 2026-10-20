# Autoridad del verificador en los criterios de aceptación

> SE-444. Un criterio de aceptación (AC) no se da por verificado solo porque exista un fichero de evidencia que pasa: importa con qué autoridad se verificó.

## Valores

| Valor | Significa |
|---|---|
| `real` | Verificado contra el comportamiento real: proveedor real, TEE/HSM real, ejecución H04 con coste, instalación real. |
| `simulada` | Verificado contra un doble, mock, fixture o simulador del comportamiento. |
| `estatica` | Verificado por inspección: existencia de fichero, grep, lectura de código o de documento. |

Orden de autoridad: `estatica` < `simulada` < `real`.

## Regla de cierre

1. El autor de la spec declara por AC la `autoridad_requerida`; la persona que aprueba la spec lo revisa.
2. Un AC cuyo texto exige comportamiento real no se cierra con `simulada` ni `estatica`.
3. Si la autoridad requerida no está disponible (sin HSM, sin proveedor real, sin presupuesto H04), el AC queda como skip con nombre y motivo, nunca como cumplido.
4. Un doble no establece el comportamiento de un proveedor real.
5. La ausencia de evidencia no cierra.

## Registro

Cada elemento de `acceptance_evidence` en `planning-state.json` admite, junto a `criterion` y `file`:

- `authority`: valor obtenido.
- `authority_required`: valor exigido por la spec.

`planning_unverified_authority_list` (`scripts/lib/planning-completion.sh`) lista los AC con `authority` ausente (`ausente`) o inferior a la requerida (`insuficiente`). `scripts/validate-ci-local.sh` los imprime en «Cobertura no verificada».

## Alcance actual

Solo informe. El predicado de cierre `planning_acceptance_evidence_valid` no cambia de resultado y el código de salida de `validate-ci-local.sh` tampoco. Los cierres anteriores a SE-444 aparecen como `authority` ausente sin reclasificarse. Pasar de informe a bloqueo es una decisión pendiente de la operadora (SE-444 D1).

El campo es autodeclarado: la revisión humana del cierre (SE-396) sigue siendo quien decide.
