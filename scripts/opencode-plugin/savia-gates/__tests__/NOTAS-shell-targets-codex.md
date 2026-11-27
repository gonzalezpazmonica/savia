# Tests cruzados de ReDoS — alerta #116

Fecha: 2026-11-27. Base verificada: `HEAD == origin/main`,
commit `ef702d97bd029f88ba86d194e2fa7f90e03b1bfa`. Runner: Bun 1.4.2.
Solo se añaden este documento y `shell-targets-codex.test.ts`.
No se modifica producto, ni specs, ni estado de planificación. Sin commits ni PR.

## Reproducción

Desde la raíz del repo:

```bash
bun test scripts/opencode-plugin/savia-gates/__tests__/shell-targets-codex.test.ts
```

Resultado actual: **67 pass, 5 fail, 72 tests**, 81 aserciones, 8,13 s.
Los fallos son intencionales: dejan evidencia antes de la corrección independiente.

## Qué falla hoy

| Caso | Resultado en main | Contrato exigido |
|---|---|---|
| `reaches`: 30 estrellas consecutivas + `b`, nombre `a` × 5000 | Hijo terminado al superar 2000 ms | Resolver en <100 ms |
| `reaches`: `a*` × 30 + `b`, nombre `a` × 5000 | Hijo terminado al superar 2000 ms | Resolver en <100 ms |
| `reaches` con `-iname`: `a*` × 30 + `b`, nombre `A` × 5000 | Hijo terminado al superar 2000 ms | Resolver en <100 ms |
| `globHits`: destino `rm a*a*…b`, nombre `a` × 5000 | Hijo terminado al superar 2000 ms | Resolver en <100 ms |
| `find . -name "$PATTERN" -delete`, patrón desconocido | Devuelve `null` | Devolver `"."`: ante la duda, alcanza |

Los cuatro primeros reproducen #116 en sus dos consumidores. La quinta es un
hallazgo adicional del contrato de cierre seguro: `findTargets` conserva el texto
de la variable como patrón literal; no demuestra ReDoS y una corrección limitada
a `globRegex` puede dejarla pendiente. Se mantiene visible, sin modificar producto.

## Cobertura y decisiones

- Expectativas normales fijadas contra main, con casos que alcanzan y que no:
  `*`, `**`, `?`, `/`, patrones vacíos, literales, clases, negación, rangos,
  caracteres de regex escapados, mayúsculas, puntos iniciales, Unicode y saltos de línea.
- `**` conserva el comportamiento actual: cada estrella permanece dentro de un
  componente; no se introduce semántica recursiva de globstar.
- Se comprueban rutas frente a basenames de `find`, filtros `-name`/`-iname`,
  rutas normalizadas, comodines citados, ausencia de gates y órdenes de solo lectura.
- Cierre seguro: filtro no interpretable, patrón dinámico, sintaxis inválida y
  límite real del inventario (5000 entradas descartan; 5001 fuerzan «alcanza»).
- Coincidencia positiva adversarial: `a*` × 30 sí alcanza el nombre de 5000
  caracteres dentro del presupuesto. En una ejecución de comprobación, la llamada
  al guard midió 3,158 ms; la duración completa del test incluye arrancar Bun.
- En los casos adversariales sin coincidencia se admite `null` si un matcher
  exacto resuelve el patrón, o el destino si una guarda conservadora decide bloquear.
  No se impone un algoritmo ni un umbral de complejidad no especificado.

Los nombres de 5000 caracteres se suministran por `protectedRel`, que alimenta
`gateNames`, sin crear basenames imposibles por `NAME_MAX`. No hay mocks ni
exportaciones de funciones privadas. Las órdenes shell se analizan como texto;
no se ejecuta `find` ni `rm`.

La medida con `performance.now()` rodea solo `protectedTarget`: excluye el arranque
del hijo y la preparación del fixture. El watchdog externo de 2000 ms contiene el
bloqueo síncrono; **no sustituye** la aserción estricta `<100 ms`. Un timeout, un
error del hijo o una respuesta inválida hacen fallar el test.

## Verificación de los tests

- Las 5 pruebas rojas fallan contra el producto de main sin tocarlo.
- En una copia temporal se invirtieron las aserciones de las 67 pruebas verdes:
  **0 pass, 67 fail**, las otras 5 excluidas. Todas pueden fallar.
- Otra copia temporal cambió solo el presupuesto `<100` por `<0`: la coincidencia
  adversarial positiva falló en la aserción temporal, con 3,158 ms medidos.
- Suite existente `tests/dual-cli/test_shell_targets.py`: **17 tests, OK**,
  incluida la equivalencia del corpus entre Python y OpenCode.
- Bun existente (`sandbox.test.ts`, `dome-guard.test.ts`): **16 pass, 0 fail**.
- Arranque `validate-ci-local.sh --quick`: 15 comprobaciones aprobadas, 0 fallos,
  2 advertencias preexistentes (coherencia y documentación indexada atrasada).

No se ejecuta `--clean-state` ni se actualiza el handoff privado: esas operaciones
inspeccionan otros worktrees o acceden a estado fuera del alcance permitido para
esta worker. No se generan derivados ni se publica nada por el encargo de solo tests.

Siguiente paso: entregar ambos ficheros a la orquestadora para ejecutar la suite
contra la corrección independiente; decidir explícitamente el hallazgo dinámico
si se mantiene fuera del arreglo de #116.
