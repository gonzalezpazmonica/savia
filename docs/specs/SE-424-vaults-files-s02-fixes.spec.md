---
status: IMPLEMENTED
approved_at: 2026-09-30
approval: "Operadora 2026-09-30 en chat (AskUserQuestion): arreglos H1, H2, H3 y H4 aprobados, un PR Draft por arreglo"
priority: P1
developer_type: agent-single
created: 2026-09-30
author: Savia
phase: A
risk: L2
related_specs: [SE-416, SE-419, SE-421, SE-422, SE-423]
origin: revisión S02 de Vaults/Files (docs/evidence/S02-vaults-files-review-20260930.md), hallazgos H1–H4
resource: https://github.com/gonzalezpazmonica/savia/tree/main/projects/savia-vaults/src
---

# SE-424 — SaviaVaults/Files: arreglos de la revisión S02 (escaneo > 2 GiB, A2A, revocación en MCP, modelos del lector de PDF)

## Problema

La revisión S02 (2026-09-30) encontró, con procesos reales, cuatro fallos que la suite no
detectaba. Evidencia completa en `docs/evidence/S02-vaults-files-review-20260930.md`.

| # | Fallo | Consecuencia |
|---|---|---|
| H1 | ClamAV no analiza más de 2 GiB − 1 por fichero y responde «OK» (código 0) | Con `scan: required`, un fichero de 2–10 GiB (SE-421/422) se guarda como limpio sin analizar |
| H2 | A2A sin token sirve cualquier cúpula (N4 incluida), rutas absolutas y `Access-Control-Allow-Origin: *`; `--host` no se valida | Cualquiera en la red, o una web en el navegador, lee las cúpulas |
| H3 | El servidor MCP carga los usuarios una vez | `user revoke`/`delete` no afectan a un proceso MCP abierto |
| H4 | `files setup` no descarga los modelos de docling y el worker va offline | En una máquina limpia todos los PDF quedan `FAILED` |

## Solución

### H1 — Escaneo que no cubre el fichero entero falla cerrado (`src/files/scan.ts`)

- `--alert-exceeds-max=yes` en todas las llamadas a `clamscan` (ruta y stdin). ClamAV
  marca `Heuristics.Limits.Exceeded.*` y termina con código 2.
- Antes de lanzar ClamAV, si el tamaño es ≥ 2 GiB − 1:
  - `scan: required` ⇒ rechazo `SCAN_REQUIRED` con motivo `too-large-to-scan` (sin blob
    ni temporales). En HTTP (tus), la creación con `Upload-Length` por encima da 422 con
    ese motivo, antes de recibir bytes.
  - `scan: optional` ⇒ se guarda con `scan: { status: "skipped", reason: "too-large-to-scan" }`,
    visible en `show`, `list` y en el MCP.
- Un `Heuristics.Limits.Exceeded` inesperado (p. ej. límites internos de archivos
  comprimidos) se trata igual que «no analizado».

### H2 — Guarda de A2A (`src/server/a2a.ts`, `src/cli/main.ts`)

- Fuera de loopback, A2A no arranca sin `SAVIA_VAULTS_TOKEN`, con un mensaje llano.
- Sin token, solo sirve cúpulas N1/N2; las N3/N4 no aparecen ni en `/domes` ni en
  búsquedas ni en lecturas.
- Token comparado en tiempo constante (`timingSafeEqual` sobre SHA-256).
- Sin `Access-Control-Allow-Origin: *`. `SAVIA_A2A_CORS_ORIGINS` (lista explícita) es
  opcional; sin ella no hay cabeceras CORS.
- `/domes` sin `path`.
- El modelo por usuario y el PDP común llegan con SE-423; esto es la guarda mínima.

### H3 — Revocación en caliente en MCP (`src/server/mcp.ts`)

- `authorize` llama a `userStore.reloadIfChanged()` antes de decidir. Si el fichero no
  existe y antes existía, se deniega todo.
- Coste medido: `stat` por llamada, y bcrypt solo al cambiar el fichero o al validar.

### H4 — Modelos del lector de PDF (`src/files/setup.ts`, `src/files/extract.ts`)

- `files setup` descarga `layout` y `tableformer` con
  `python -m docling.cli.tools models download layout tableformer -o <tools>/docling-models`
  (unos 506 MiB), con reintento y verificación. Para verificar, se escribe un manifiesto
  SHA-256 por fichero la primera vez, y `status` lo comprueba.
- El worker recibe `artifacts_path=<tools>/docling-models` (variable
  `SAVIA_FILES_DOCLING_MODELS`) y sigue offline.
- `files status` dice «faltan los modelos del lector de PDF» y `files setup` los completa
  (idempotente: una segunda ejecución descarga 0 bytes).
- Los documentos `FAILED` por este motivo se recuperan con `files reprocess`; `status` lo
  indica.

## Criterios de aceptación

- **AC1 (H1)** Con una firma de prueba `.ndb` y un stream de más de 2 GiB con el marcador en
  el byte 0: `scan: required` ⇒ `SCAN_REQUIRED`/`too-large-to-scan`, sin blob;
  `optional` ⇒ guardado con `skipped`. En tus, 422 al crear. Por debajo de 2 GiB, el
  marcador se detecta (`QUARANTINED`). Con ClamAV gestionado real.
- **AC2 (H2)** `--host 0.0.0.0` sin token ⇒ no arranca (test del proceso, sin escuchar).
  Sin token en loopback, una cúpula N4 no aparece en `/domes`, `/search` ni lectura; N2
  sí. No hay `Access-Control-Allow-Origin` por defecto. `/domes` sin rutas. Token
  incorrecto de la misma longitud ⇒ 401.
- **AC3 (H3)** Cliente MCP real (stdio): permitido → `user revoke` ⇒ denegado en la
  siguiente llamada; `user delete` ⇒ `Invalid or expired token`; sin reiniciar.
- **AC4 (H4)** `files setup` en un HOME y `SAVIA_TOOLS_HOME` vacíos (sin caché de
  HuggingFace) ⇒ `contrato.pdf` `READY` con cita de página. Segunda ejecución: 0 bytes.
  Un modelo manipulado ⇒ `status` lo marca y `setup` lo repara.
- **AC5** Suite completa en verde; `docs/files.md`, `docs/files-http.md` y la skill
  actualizados.

## Entregables (rutas)

- `projects/savia-vaults/src/files/scan.ts`, `projects/savia-vaults/src/files/service.ts`,
  `projects/savia-vaults/src/server/tus.ts`
- `projects/savia-vaults/src/server/a2a.ts`, `projects/savia-vaults/src/cli/main.ts`
- `projects/savia-vaults/src/server/mcp.ts`
- `projects/savia-vaults/src/files/setup.ts`, `projects/savia-vaults/src/files/extract.ts`,
  `projects/savia-vaults/workers/files/extract.py`
- `projects/savia-vaults/tests/unit/files/scan.test.ts`,
  `projects/savia-vaults/tests/integration/files/scan-limits.test.ts`,
  `projects/savia-vaults/tests/integration/server/a2a-guard.test.ts`,
  `projects/savia-vaults/tests/e2e/mcp-revocation.test.ts`,
  `projects/savia-vaults/tests/unit/files/setup.test.ts`,
  `projects/savia-vaults/tests/unit/files/extract.test.ts`, `projects/savia-vaults/tests/unit/files/fake-artifacts.ts`
- `projects/savia-vaults/docs/files.md`, `projects/savia-vaults/docs/files-http.md`

## Esfuerzo

Agente ~8 h (H1 2 h, H2 2 h, H3 1 h, H4 3 h); revisión humana ~1 h por PR.
Un PR Draft por arreglo, en este orden: H1, H2, H3, H4.

## Fuera de alcance

El modelo de identidad (Subject, credenciales, PDP): SE-423. Analizar ficheros de más de
2 GiB por trozos, que no es fiable con firmas que cruzan el corte. OCR.

## OpenCode Implementation Plan

### Bindings touched

Solo `projects/savia-vaults` (TypeScript/Node y worker Python). Nada del workspace.

### Verification protocol

- [ ] H3 con cliente MCP real en Claude Code y OpenCode.
- [ ] H4 en un HOME limpio real.

### Portability classification

- [x] **PURE_NODE** (H4 usa el worker Python ya existente, sin bindings de frontend)

## Resultados

### H1 (2026-09-30)

| AC | Evidencia | Estado |
|---|---|---|
| AC1 | `scan-limits.test.ts`: con `required`, un alta de 3 GiB da `SCAN_REQUIRED`/`too-large-to-scan` sin abrir el stream ni guardar; tus da 422 al crear (3 GiB) y 201 con 1 KiB; sin antivirus, 422. ClamAV gestionado real con firma `.ndb`: marcador detectado en 1 MiB; stream de 2,1 GiB → `too-large-to-scan` (antes del arreglo, `clean`). `scan.test.ts`: tope 2³¹−1, `Heuristics.Limits.Exceeded` nunca es infección y se pide `--alert-exceeds-max=yes` | OK |
| AC5 | Suite completa 726/726, `tsc` y `eslint` limpios; `docs/files.md` y `docs/files-http.md` actualizados | OK |

Desviación: con `scan: optional` (en el código, `auto`) no se crea un campo
`scan.status`; se reutiliza el motivo `too-large-to-scan` en `skipped`, que ya existía
desde SE-421 y es visible en `show`, `list` y en el MCP.

### H2 (2026-09-30)

| AC | Evidencia | Estado |
|---|---|---|
| AC2 | `a2a-guard.test.ts` (4): con host no-loopback (TEST-NET 192.0.2.1) y sin token, no arranca ni el servidor ni la CLI (código 1); sin token en loopback, N4 ausente de `/domes`, `/search`, `/context` y `/share`, y N2 accesible; sin `Access-Control-Allow-Origin`; `Origin` ajeno ⇒ 403 en lectura y en escritura `text/plain`; origen permitido con eco; token de igual longitud distinto ⇒ 401. Sonda real repetida (CLI, loopback, N4): `{"results":[]}` y `{"domes":[]}` | OK |

Desviaciones:

1. **Peticiones con `Origin`** (navegador) se rechazan salvo lista explícita. La spec solo
   pedía quitar `CORS *`; sin esto, una web podía escribir por `POST /share` con
   `text/plain`, que no provoca preflight. Clientes sin navegador (CLI, federación, curl)
   no envían `Origin` y no cambian.
2. **TLS**: A2A no tiene TLS propio y la documentación de federación decía lo contrario;
   se corrige `projects/savia-vaults/docs/FEDERATION.md`. Exigir TLS o proxy fuera de loopback queda para SE-423.

### H3 (2026-09-30)

| AC | Evidencia | Estado |
|---|---|---|
| AC3 | `tests/e2e/mcp-revocation.test.ts`: cliente MCP real por stdio, un solo proceso: permitido → quitar la cúpula ⇒ denegado (`vault_list` y `vault_search`) → volver a concederla ⇒ permitido → regenerar el token ⇒ `Invalid or expired token` → fichero de usuarios retirado ⇒ denegado (no pasa a modo local). Antes del arreglo, el test fallaba en el segundo paso (`PERMITIDO`) | OK |

Coste: `reloadIfChanged` sin cambios, 1,99 µs por llamada (20 000 llamadas).
Añadido: si el servidor arrancó con usuarios y el fichero desaparece, se deniega en vez de
volver al modo local.

### H4 (2026-10-01)

| AC | Evidencia | Estado |
|---|---|---|
| AC4 | Premisa medida: sin red y sin caché, docling falla (`LocalEntryNotFoundError`); con `models download layout tableformer -o DIR` y `artifacts_path=DIR`, el PDF se extrae. `setup.test.ts` (5): instala con manifiesto SHA-256, segunda ejecución 0 bytes, sin modelos `stale` y solo reinstala modelos (uv no se descarga), modelo manipulado ⇒ `stale` y `setup` lo repara, descarga fallida sin restos, desinstalar los borra. Real: `files setup --extractor` sobre el extractor ya instalado descargó 669 MB en 19 s; la segunda ejecución, 2 s sin descarga; `files add contrato.pdf` con HOME vacío ⇒ `READY` (antes `FAILED`); `extract.test.ts` real con HOME sin caché ⇒ `READY` con cita de la página 2 | OK |

Desviaciones:

1. **AC4 sin reinstalar el venv desde cero.** La prueba real con `SAVIA_TOOLS_HOME` vacío
   descargaría además ~1,5 GB del venv; se probó el fallo exacto (HOME sin caché) con
   las herramientas gestionadas existentes y los modelos instalados por el nuevo `setup`.
2. **Tamaño**: 669 MB, no los ~506 MiB estimados: `layout` incluye también la variante
   ONNX del modelo de maquetación.
3. **`status` comprueba tamaño y fecha**; el SHA-256 completo lo comprueba `setup`
   (unos 2 s por ejecución), para que `status` siga siendo instantáneo.

## Enmienda H5 (2026-11-17) — contención de rutas y «sin escritura sin contraseña»

Origen: auditoría de seguridad interna (2026-11-16), reproducida en una instancia aislada.
Decisión de la operadora del 2026-11-17: el servicio local deja de escribir sin credencial
en cualquier nivel, y nada sale de la carpeta de su cúpula. Es la continuación de H2 (la
guarda de A2A ya prohibía servir rutas absolutas); extiende la guarda al almacenamiento,
que es donde se toca disco, para que valga igual por A2A, MCP y CLI.

### Problema

| # | Fallo | Consecuencia |
|---|---|---|
| H5a | `VaultStorage.read/write/delete/diff/log` unían la ruta pedida con la raíz sin comprobar el resultado; `guardRead`/`guardWrite` no tenían llamantes | `../`, rutas absolutas y enlaces que salen leen, escriben y comparan fuera de la cúpula; por MCP, un permiso sobre una N1 alcanza la N4 vecina |
| H5b | `git diff <ruta>` sin `--` | una «ruta» `--output=<fichero>` hace que git escriba donde se le diga |
| H5c | A2A sin credencial escribía en N1/N2 | cualquier proceso local escribe en las cúpulas de la persona |
| H5d | A2A no validaba `Host` | una web con DNS reasignado a 127.0.0.1 lee lo público por el navegador |

### Solución

- `VaultSecurity.contain(ruta)`: única puerta del almacenamiento a disco. Rechaza vacía/NUL,
  absoluta (POSIX, unidad, UNC), cualquier segmento `..` (también tras descodificar `%xx`),
  barra invertida como separador, `.git`/`.savia-vault`/`.trash`/`deniedPaths`, profundidad
  máxima, y cualquier prefijo existente que sea un enlace fuera de la raíz real (o roto).
  `guardRead`/`guardWrite` se construyen sobre ella. El nivel se sigue comprobando en la
  cúpula del almacenamiento, que tras la contención es siempre la de destino.
- git recibe siempre `--` antes de la ruta (`add`, `rm`, `diff`).
- A2A: escritura sin credencial válida ⇒ 401 en todos los niveles; rutas rechazadas ⇒ 400.
  Credenciales: las que ya existían (token personal de SE-423 con rol `writer`, o el secreto
  obsoleto `SAVIA_VAULTS_TOKEN` en loopback). Ningún mecanismo nuevo.
- A2A: `Host` admitido = bucle local, IP literal, `--host` de escucha y
  `SAVIA_A2A_ALLOWED_HOSTS`; el resto ⇒ 403 antes de cualquier ruta (también `/health`).
- `scripts/sldc-context-loop.sh` envía `SLDC_VAULTS_TOKEN` (por stdin de curl).

### Criterios de aceptación

- **AC6 (H5a/b)** Pruebas con directorio temporal: lectura, escritura, comparación,
  historial y borrado con `..`, absolutas, `%2e%2e`, `%2f`, barras invertidas, unidad
  Windows, NUL, enlaces de fichero, de directorio y rotos ⇒ rechazo sin tocar nada fuera;
  `--output=` no crea fichero; prueba que falla si una operación no pasa por `contain`.
  Por MCP (stdio real), con permiso en una N1, ni lectura, ni escritura ni comparación
  alcanzan la N4 vecina.
- **AC7 (H5c)** A2A sin credencial ⇒ 401 en N1, N2 y vault por defecto, sin fichero creado;
  con credencial, escribe; `../` desde la N1 ⇒ 400.
- **AC8 (H5d)** `Host` ajeno ⇒ 403; bucle local, IP literal y nombre configurado ⇒ 200;
  la CLI lee `SAVIA_A2A_ALLOWED_HOSTS`.
- **AC9** Suite completa en verde; mutación: quitar cada comprobación nueva hace fallar
  alguna prueba. README y `docs/USAGE.md` dicen qué se rompe al actualizar y cómo se arregla.

### Fuera de alcance (H5)

Aplicar la lista de extensiones y el tamaño máximo de `guardRead` a la API de notas (hoy
nunca se aplicaron; activarlos cambiaría qué se puede leer). Límite de tamaño del cuerpo de
`POST /share`. Carreras (TOCTOU) entre la comprobación y la escritura por un proceso que
ya puede escribir dentro de la cúpula.
