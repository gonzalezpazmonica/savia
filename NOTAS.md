# Gate de soberanía: destinos Labs y cúpulas

Entrega TDD cruzada: solo tests y documentación; sin cambios en producción.
Base comprobada: `origin/main` en `c468f0ae57dcbfe55c0497e3afe311e4aa46d910`.
El gate, el decisor y su política coinciden con esa base.

## Resultado contra main

```bash
bats --print-output-on-failure --formatter tap tests/test-data-sovereignty-labs-dest.bats
```

Resultado: **12 pasan, 2 fallan**; salida del runner: **1**.
Los dos fallos son intencionados y quedan sin `skip`, `TODO` ni aserciones anuladas:

1. `CONFIDENTIAL de alta confianza se permite y audita en cúpula SaviaLabs`:
   `/x/vaults/SaviaLabs/labs/research/a.md` devuelve 2; se exige 0 y auditoría.
2. `CONFIDENTIAL de alta confianza se permite y audita en labs de un worktree`:
   `/x/labs-wt-foo/labs/research/a.md` devuelve 2; se exige 0 y auditoría.

Ambos imprimen `BLOQUEADO [fallback]: classifier_confidential_high_confidence`.
La implementación futura debe permitir estas escrituras y dejar un registro
con fichero, timestamp y decisión `ALLOW` o `WARN`, sin registros de bloqueo.
Una excepción que salga antes de clasificar o sin auditar no satisface los tests.

Los otros doce casos ya pasan:

- El mismo contenido confidencial se bloquea en `docs/a.md` (N1) y `foo.md`
  (n4 no protegido), conservando motivo y auditoría del bloqueo.
- `docs/../../vaults/a.md` llega al clasificador como `/x/vaults/a.md`.
  Este caso usa una clasificación pública para aislar la normalización existente
  del permiso pendiente para contenido confidencial; no valida todavía ese
  permiso sobre una ruta con traversal.
- `docs/labs-notes.md` y un prefijo `labs-wt-foo` sin segmento `labs/` bloquean.
- `labs/../docs/a.md` se normaliza a docs y bloquea.
- Token GitHub, marcador de clave privada y cadena de conexión bloquean en
  ambos destinos protegidos, antes del clasificador y con auditoría.

## Aislamiento y comprobación de las aserciones

Cada test usa `BATS_TEST_TMPDIR`. La entrada es JSON por stdin, con
`tool_name: Write`. `CLAUDE_PROJECT_DIR` apunta a un proyecto temporal que
contiene un doble ejecutable de `scripts/sovereignty-classify.sh`; este devuelve
`confidential/0.99` y ninguna coincidencia determinista. No se requiere añadir
una variable nueva al gate ni cambiar producción. El decisor y su YAML se
copian sin modificar desde el repositorio. Se verifica que el doble recibe
exactamente el contenido y la ruta normalizada.

Un doble de `curl` por PATH fuerza el fallback sin red ni daemon. Los casos de
credenciales usan un clasificador público: las regex deben prevalecer incluso
si la clasificación permitiría escribir. Todas las credenciales son sintéticas.
No se ejercitan aquí la ruta del daemon ni herramientas MCP de vault.

Se invirtieron las aserciones de salida en una copia no versionada de la suite:
los doce casos verdes pasaron a fallar. Los dos casos pendientes ya fallan
contra main; al invertir su salida siguen fallando por la auditoría exigida.
No se modificó código de producción para esta comprobación.

## Validaciones adicionales

- Suites existentes `test-data-sovereignty-gate.bats`,
  `test-data-sovereignty.bats` y `test-data-sovereignty-extended.bats`:
  84 pasan, 5 omitidos existentes, 0 fallos.
- Auditor determinista: 82 puntos, `certified: true`, sin vacuidad ni debilidad.
- `validate-ci-local.sh --quick`: 15 correctas, 0 fallos, 2 avisos previos.
- Generación del mapa de capacidades: correcta; derivados no versionados.
- `capability-entropy.py --check`: no verificable por permisos al abrir el
  cerrojo `savia-derived.lock` del worktree (`Read-only file system`), código 2.

La suite nueva debe permanecer roja hasta que otra implementación resuelva
la capa 2; no se han rebajado umbrales ni relajado controles de credenciales.

## Cierre parcial por permisos

`git add` tampoco pudo crear `index.lock` (`Read-only file system`). No hay
commit, push ni PR. No se intentó otra vía para escribir los metadatos Git.
Quedan pendientes SAM/FRESH, entropía, escaneo/firma de confidencialidad,
preflight y cierre de validación local. No se modificó el traspaso privado ni
el registro global de sesiones, fuera del alcance autorizado del worker.
La siguiente acción es restablecer los permisos del worktree y retomar el
cierre, conservando explícitamente los dos fallos TDD esperados.
