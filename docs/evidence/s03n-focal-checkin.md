# S03n: primer slice de focal-checkin

Este slice corrige `scripts/focal-checkin.sh` y refuerza
`tests/test-se230-s3-checkin.bats`. No cierra el grupo de 8–10 ficheros de S03n.
Las suites de workspace-health, focal-status y focal-dispatch se excluyeron
porque ya aparecen en el grupo S03k, PR #1400.

## Cambios observables

- Crear un intervalo en un nido nuevo produce JSON válido con su identidad.
- Cada campo ausente se añade independientemente: fecha, intervalo o pid.
- Leer, modificar y escribir ocurre dentro del mismo bloqueo.
- Un fallo de bloqueo, lectura, directorio o escritura devuelve error;
  no se anuncia una actualización que no se ha persistido.
- Un nombre que sale del directorio focal, un intervalo no entero positivo,
  una opción desconocida o un argumento sin valor se rechazan.
- Los campos escalares incompatibles con el esquema no se sobreescriben.
- La ventana de una hora incluye su límite inferior y excluye el futuro.

Los umbrales actuales de carga se conservan: OK hasta dos cambios/decisiones,
HIGH de tres a cinco y OVERLOAD desde seis. No se resuelve aquí la diferencia
histórica de umbrales entre focal-checkin y focal-status.

## Pruebas y medida

Las 10 pruebas anteriores pasan antes y después del cambio. La suite final
tiene 26 casos y elimina la espera de un segundo del primer caso: una fecha
antigua conocida hace verificable el cambio de timestamp sin sleep ni skip.

Los nuevos casos se ejecutaron contra el script anterior: fallan 13 de ellos,
incluidos el orden lectura/bloqueo y el estado con escalar inválido. Las otras
dos suites de foco pasan sus 96 casos.

El ensayo de mutación compara las suites anterior y nueva sobre el mismo
script corregido. Así mide la capacidad de las pruebas sin confundirla con
el efecto del arreglo. Ambas baselines pasan. Cada mutante se escribe en una
copia aislada, pasa `bash -n` y se ejecuta mediante BATS; un kill exige un caso
`not ok`, no basta con un fallo de arranque. Se registra el SHA-256 del script
ejecutado. No se cambian ficheros del repositorio para sembrar mutantes.

| Mutante | Suite anterior | Suite nueva |
|---|---|---|
| HIGH con cuatro cambios en vez de tres | Sobrevive | Detectado |
| OVERLOAD con siete cambios en vez de seis | Detectado | Detectado |
| HIGH con cuatro decisiones en vez de tres | Sobrevive | Detectado |
| OVERLOAD con siete decisiones en vez de seis | Detectado | Detectado |
| Excluir el instante de hace una hora | Sobrevive | Detectado |
| Incluir cambios futuros | Sobrevive | Detectado |
| Incluir cambios antiguos | Detectado | Detectado |
| Escribir otro campo en vez de session_pid | Sobrevive | Detectado |
| Omitir la identidad en un estado nuevo | Sobrevive | Detectado |
| Ignorar el fallo del bloque de escritura | Sobrevive | Detectado |
| Ignorar el fallo de mkdir | Sobrevive | Detectado |
| Aceptar cualquier intervalo | Sobrevive | Detectado |
| Aceptar cualquier nombre | Sobrevive | Detectado |
| Ignorar opciones desconocidas | Sobrevive | Detectado |
| **Total** | **3/14** | **14/14** |

Esta cifra describe esos mutantes concretos; no es una medida exhaustiva de
cobertura ni prueba de ausencia de otros errores. El ensayo conserva sus
recetas, hashes y salidas TAP como artefactos locales del relevo.

## Auditor y alcance pendiente

El auditor pasa de 40 a 69 puntos. Sigue por debajo de 80; **no se certifica**
este fichero ni se da por cerrado S03n. No se cambian nombres de pruebas para
puntuar palabras inglesas. El auditor no reconoce `FOCAL_CHECKIN` como target,
no reconoce los límites expresados en español y exige una comprobación textual
de flags para puntuar seguridad. Añadir comprobaciones de presencia sólo para
subir esa nota no demuestra el comportamiento corregido.

Faltan seleccionar y reforzar los demás ficheros del grupo. Este slice no toca
los tests sellados, el auditor, su umbral, el ratchet ni los umbrales de carga.

Comprobaciones reproducibles desde la raíz:

```bash
bats tests/test-se230-s3-checkin.bats
bats tests/test-se230-s1-focal-status.bats tests/test-se230-s2-focal-dispatch.bats
python3 scripts/test-auditor-engine.py tests/test-se230-s3-checkin.bats .
bash scripts/validate-ci-local.sh --quick
```

## Integración posterior con S03n

La medida anterior corresponde al slice local original. La integración con
la PR de ocho suites conserva ambos conjuntos de casos, añade dos estados
con campos null y mantiene el límite público de intervalo de 1 a 9999.
Las pruebas de risk-tier usan ahora un commit base real para la lista de
derivados, según SE-501. Las medidas de mutación anteriores no se atribuyen
a la suite combinada ni se afirma haber repetido ese ensayo.
