# SE-530 S1 — Prerregistro de H9 y de las clases de evidencia

> Este fichero se commitea **antes** de ejecutar la primera medición (SE-530 D6).
> Lo que se vea después va a «Desviaciones» al final; el resto no se reescribe.

## Hipótesis H9

En una ventana de 14 días, al menos el 10 % de las marcas `ESTADO: OK` de la línea de producción no tienen evidencia independiente registrada.

- **Marca OK**: un fichero de marca de fin cuya línea `ESTADO:` declara `OK` y cuya fecha de modificación cae dentro de la ventana.
- **Sin evidencia independiente**: el estado derivado de la marca (D1) es `declarado`. Un trabajo `verificado` o `refutado` tiene evidencia independiente registrada; un trabajo con solo evidencia no independiente, de un SHA anterior o sin aprobar, no la tiene.
- **Cifra**: `sin_evidencia / n_ok`, con aritmética entera. El umbral se compara como `sin_evidencia * 100 >= n_ok * 10`, sin redondeo.

## Refutación

- H9 se **refuta** si la cifra es inferior al 10 % con `n_ok >= 200`.
- H9 se **confirma** si la cifra es igual o superior al 10 % con `n_ok >= 200` (20 de 200 = 10,0 % confirma; 19 de 200 = 9,5 % refuta).
- Con `n_ok < 200` el resultado es **no concluyente**; se amplía la ventana sin cambiar el umbral ni la definición.
- El umbral del 10 % no se rebaja para que la hipótesis salga (causa raíz, SE-456).

## Definiciones congeladas

Una comprobación es independiente si cumple las tres: (1) el verificador no es el ejecutor (identidad distinta, comparada con el campo `ejecutor` del registro); (2) el verificador no es la orquestadora que despachó el trabajo, salvo que la clase sea mecánica (`ci_base`, `postcondicion`); (3) lo comprobado no lo escribió el ejecutor.

- **Orquestadora que despachó**: cualquier identidad de la lista de orquestadoras que usa `scripts/merge-sprint.sh` (`MERGE_SPRINT_ORCHESTRATOR`, por defecto `savia-orchestrator savia-orquestadora`). `hecho-verificado.py` acepta la misma lista por `--orchestrator` o `HECHO_VERIFICADO_ORCH`.
- **Prueba de la base**: una prueba que existía en `origin/main` antes del trabajo y sigue en verde sobre el SHA vigente. El recolector de evidencia anota `pruebas_base` (cuántas de esas pruebas pasaron) y `pruebas_propias` (cuántas añadió el ejecutor en su diff).
- **`revision`**: veredicto de una revisora con `reviewer` distinto de `author` y de la orquestadora, sobre el SHA vigente. `APPROVE` = superada, `HOLD` = fallida.
- **`persona`**: confirmación registrada de la persona sobre este trabajo y SHA. El verificador no puede ser el ejecutor ni la orquestadora.
- **`ci_base`**: CI sobre el SHA exacto con `pruebas_base >= 1`. Cuenta como independiente.
- **`ci_propio`**: CI cuyo `pruebas_base` es 0 o falta. **No** cuenta como independiente: el trabajo sigue `declarado` y se informa aparte.
- **`postcondicion`**: comprobación mecánica definida antes del trabajo por alguien distinto del ejecutor.
- **`autodeclaracion`**: la marca de fin, un fichero que creó el ejecutor, su resumen. **No** cuenta. Es la clase de toda marca OK por construcción, así que se informa como `n_ok`.
- **SHA vigente**: el último registro `head` del trabajo en el fichero de evidencia. Sin SHA vigente, ninguna comprobación cuenta (fail-closed). Una comprobación de otro SHA no cuenta (D4).
- **Comprobación propuesta por el ejecutor** (D3): no cuenta salvo que traiga `aprobada_por` de una identidad que no sea el ejecutor ni la orquestadora, con `aprobada_hash` igual a `contenido_hash`.
- **Campos de estado escritos por el ejecutor** (`estado`, `verificado`): se descartan y se anotan como anomalía.

## Alcance de la medición y sesgo conocido

- La evidencia que se recolecta para esta primera medición es la que existe ya como registro: el registro de revisiones del merge-sprint (clase `revision`) y el SHA de cabeza de cada PR. No hay recolector histórico de `persona`, `ci_base` ni `postcondicion`: esas clases se miden con las mismas definiciones, pero con cero registros donde nadie los guardó.
- Consecuencia declarada de antemano: la cifra de `sin_evidencia` está **sesgada al alza** por la evidencia no recolectada. El informe lo dice junto a la cifra y no la corrige.
- Un trabajo sin PR, o cuya PR no aparece en el registro, no tiene evidencia y cuenta como `declarado`.

## Qué cambia según el resultado

- Si H9 se confirma, la regla de S2 se mantiene y se vigila el ruido.
- Si H9 se refuta, la regla de S2 se mantiene igual (decisión de la operadora de aplicarla desde ya); lo que se replantea es S3 y el tamaño del aviso, no el umbral.
- Si es no concluyente, se amplía la ventana.

## Desviaciones

Escritas después de la primera medición; las definiciones y el umbral de arriba no cambian.

1. **Ejecución de prueba sin evidencia.** Antes de la medición definitiva se ejecutó `measure` sin ficheros de evidencia para ver el n (244 OK en la ventana). No se leyó ninguna cifra de H9 de esa ejecución, que da 100 % `declarado` por construcción.
2. **Opción `--repo`.** Los números de PR de otros repositorios (labs, space) colisionan con los de este. Se añadió `--repo` para que solo las PR del repositorio reciban evidencia y se midió con ella. No cambia ninguna definición de clase ni el umbral; evita falsos `verificado` por coincidencia de número.
3. **Marca de ventana.** La ventana usa la fecha de modificación de la marca de fin, que es lo que hay; una marca reescrita cambia de fecha.
