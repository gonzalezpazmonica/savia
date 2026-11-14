# Changelog — SaviaVaults

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — 2026-11-14 · Clave de firma de autorizaciones estable (SE-528 S3)

### Security
- La clave de firma de las autorizaciones `svt1` solo se crea si no existe. Cualquier otro fallo
  de lectura (permisos, fichero ocupado) o una clave de longitud inválida ya no la regenera en
  silencio: se registra con `SECURITY` y el código del sistema, la clave no cambia, firmar y
  verificar fallan cerrados y la API HTTP responde `503 KEY_UNAVAILABLE`. Regenerarla es una
  decisión explícita de la persona.

## [Unreleased] — 2026-10-07 · Registro local de cúpulas fusionado con el base (SE-436 D30-2)

### Added
- Además de `savia-vaults.domes.json`, el registro lee `savia-vaults.domes.local.json` (junto a él,
  ignorado por git): ahí escribe Savia Space las cúpulas que crea. Los dos se fusionan; con el
  mismo nombre gana el local. Funciona con solo el fichero local.

### Changed
- `save()` devuelve cada cúpula al fichero de donde salió: lo creado por Space no se mezcla con el base.

## [Unreleased] — 2026-10-01 · Identidad mínima: A2A por usuario, transferencias y renombrado (SE-423 PR 2)

### Added
- A2A con usuarios: cada petición lleva un token personal y pasa por el mismo control que
  MCP y HTTP (permiso por cúpula, alcance del token, revocación en la siguiente petición);
  `/domes` y `/search` solo muestran lo que el usuario puede leer.
- Descargas y `PATCH` HTTP en curso se revalidan cada 8 MiB o 30 s y se cortan si el token
  se revoca, caduca o pierde el permiso.
- `user rename <usuario> <nombre>`: conserva `subjectId`, tokens, permisos y acceso por
  documento; el nombre anterior queda como alias y no se reutiliza.

### Changed
- Las listas `readers`/`writers` fijadas por MCP o HTTP se guardan por `subjectId` y se
  muestran por nombre; las antiguas por nombre se siguen respetando.
- Los enlaces de subida y descarga `svt1.…` quedan ligados al token que los emitió.
- `SAVIA_VAULTS_TOKEN` en A2A queda obsoleto: solo en loopback y con aviso. Fuera de
  loopback, A2A exige usuarios.
- La validación de tokens personales usa una caché de 60 s (bcrypt solo en la primera
  llamada), revalidada contra revocación y caducidad en cada uso.

### Fixed
- A2A que arrancó con usuarios ya no pasa a modo público si desaparece el fichero de
  usuarios: responde 401.

## [Unreleased] — 2026-10-01 · Identidad mínima: credenciales con caducidad (SE-423 PR 1)

### Added
- Cada usuario tiene un `subjectId` estable y varias credenciales `sv_…` con caducidad
  obligatoria (90 días por defecto, máximo `SAVIA_VAULTS_PAT_MAX_DAYS`, 365), alcance
  opcional (`--domes`, `--max-role`, que solo restringen) y revocación individual:
  `user tokens`, `user token-create`, `user token-revoke`; `user list` avisa de lo que caduca.
- MCP y HTTP aplican caducidad, revocación y alcance en la siguiente petición; la caché de
  tokens HTTP nunca dura más que la credencial.

### Changed
- `savia-vaults.users.json` pasa al formato v2, escrito de forma atómica en `0600`. El
  formato v1 se migra al cargar: los tokens siguen valiendo y caducan a los 365 días; copia
  `savia-vaults.users.json.v1.bak`.
- `user token --regenerate` revoca todas las credenciales del usuario.

## [Unreleased] — 2026-10-01 · Savia Files: modelos del lector de PDF en files setup (SE-424 H4)

### Fixed
- `files setup` no instalaba los modelos de Docling y el worker va sin red: en una
  máquina sin caché de HuggingFace todos los PDF quedaban `FAILED`. Ahora:
  - `setup` descarga `layout` y `tableformer` (~670 MB) en `tools/docling-models`,
    con manifiesto SHA-256 por fichero; idempotente y repara lo manipulado;
  - `status` distingue «se leen Word/PowerPoint/Excel pero no los PDF» (`stale`);
  - el worker recibe `SAVIA_FILES_DOCLING_MODELS` (`artifacts_path`);
  - desinstalar el extractor borra también los modelos.
- Documentación: el tamaño real del lector es ~2,2 GB; los modelos no se bajaban
  «en la primera extracción», como decía.

## [Unreleased] — 2026-09-30 · MCP: revocación en caliente (SE-424 H3)

### Security
- Un proceso MCP ya abierto no veía `user revoke`, `user delete` ni un token regenerado
  hasta reiniciarse. Ahora recarga el fichero de usuarios si cambió (un `stat` por
  llamada, ~2 µs) y aplica el cambio en la siguiente llamada.
- Si el fichero de usuarios desaparece, un servidor que arrancó con usuarios deniega
  el acceso en vez de pasar al modo local (todo permitido).
## [Unreleased] — 2026-09-30 · A2A: guarda mínima (SE-424 H2)

### Security
- Sin `SAVIA_VAULTS_TOKEN`, A2A servía cualquier cúpula (N4 incluida) con sus rutas
  absolutas y `Access-Control-Allow-Origin: *`, y aceptaba escrituras de cualquier web
  (`text/plain` no pide preflight). Ahora:
  - sin token no arranca fuera de loopback y solo sirve cúpulas N1/N2;
  - peticiones con `Origin` rechazadas (403) salvo `SAVIA_A2A_CORS_ORIGINS`;
  - token comparado en tiempo constante; `/domes` sin rutas.
- `docs/FEDERATION.md` anunciaba `serve --transport a2a --tls`, que no existe: A2A no tiene
  TLS propio (proxy delante). Exigir TLS y usuarios por cúpula queda para SE-423.
## [Unreleased] — 2026-09-30 · Savia Files: escaneo que no cubre el fichero entero falla cerrado (SE-424 H1)

### Fixed
- ClamAV analiza como mucho 2 GiB − 1 por fichero y respondía «OK» sin leer el resto:
  con `scan: required`, un fichero de 2–10 GiB se guardaba como limpio. Ahora:
  - `CLAMSCAN_MAX_BYTES` = 2 GiB − 1 (antes 4 000 MB);
  - con `required`, el alta y la creación tus se rechazan antes de aceptar bytes
    (`SCAN_REQUIRED`, `too-large-to-scan`; 422 por HTTP), también sin antivirus;
  - `--alert-exceeds-max=yes`, y `Heuristics.Limits.Exceeded` cuenta como no
    analizado, nunca como infección.
- Probado con el ClamAV gestionado real y una firma propia: detectada por debajo del
  tope; un stream de 2,1 GiB ya no sale «limpio».

## [Unreleased] — 2026-09-30 · Savia Files: API HTTP con tus 1.0 (SE-422)

### Added
- `serve --transport http` (`src/server/http.ts`):
  - rutas `/v1/files/{cúpula}/uploads|documents|operations`;
  - usuarios y tokens personales (con caché de bcrypt), permisos de cúpula y de
    documento (SE-419);
  - exige usuarios, y TLS o `--behind-proxy` fuera de loopback;
  - rate limit por usuario y timeouts de cabeceras e inactividad.
- tus 1.0 propio (`src/server/tus.ts`): creation, creation-with-upload,
  termination, expiration y checksum sha256. Conformidad probada con
  `tus-js-client` (devDependency), con reinicio del servidor a mitad.
- Subidas reanudables (`src/files/uploads.ts`):
  - estado en el journal (esquema v2: `uploads`, `used_tokens`);
  - SVFU1 y metadatos sellados en cúpulas cifradas;
  - dueño guardado como hash;
  - límite de subidas activas; caducidad y `files gc`.
- Descargas con `Range` (206/416), `ETag`/`If-None-Match`/`If-Range`,
  `Content-Disposition` seguro, `nosniff` y CSP `sandbox`.
- Autorizaciones acotadas (`src/server/grants.ts`, HMAC con clave propia):
  subida de un solo uso (1 h) y descarga de un documento (15 min).
  `vault_files action:"upload"` y `action:"link"`.
- `AccessController.authorizeUser` y `UserStore.reloadIfChanged`: revocar un
  usuario invalida sus accesos sin reiniciar.

## [Unreleased] — 2026-09-30 · Savia Files: almacén en streaming (SE-421)

### Added
- `FileStore.addStream` / `openRead` (entera verificada al final, o por rango).
  - En claras: blob por SHA-256 con deduplicación.
  - En cifradas: SVF1 frame a frame (`StreamEncryptor`/`StreamDecryptor`, mismo
    formato que SE-417).
  - Memoria acotada: ~160 MiB medidos con 2 GiB.
- Formato de subida parcial cifrada SVFU1 (`sealUploadChunk`/`openUploadChunks`),
  reanudable, para SE-422.
- `scanStream`: clamscan por stdin (cifrados grandes, sin copia en claro).
  `--max-filesize/--max-scansize` a 4 000 MB en todos los análisis.
- `inspectZipFile`: guardia de ZIP que lee solo la cola y el directorio central.
- CLI: `files add` en streaming y `files get --range`, a un `.part` renombrado al
  verificar.
- `files.maxBytes` por cúpula y `SAVIA_FILES_MAX_EXTRACT_BYTES`
  (`too-large-to-extract`).

### Changed
- `SAVIA_FILES_MAX_BYTES` por defecto 1 GiB (antes 100 MiB), tope de 10 GiB.
- `readBytes` rechaza lo que supera `maxTransferBytes` (usar `openRead`).
- `gc` respeta los temporales y envolturas de un alta en curso.

## [Unreleased] — 2026-09-30 · Notas fuera de nivel (SE-420)

### Fixed
- Una nota con `confidentiality` mayor que su cúpula ya no se sirve por MCP ni A2A:
  - `vault_read`, `vault_diff` y `vault_log` dan `Note not found`;
  - no aparece en list, search, tags, graph, query, introspect, wikilinks ni
    backlinks.
- `vault_write` rechaza crearla o pisarla (`POLICY_DENIED`).
- `vault_stats.outOfLevel` da el recuento.
- La regla (`exceedsDomeLevel`) vive en `src/storage/note-level.ts` y la comparte
  el indexador de RAG.

### Changed
- `VaultConfig.confidentiality` (opcional): lo rellenan las instancias de cúpula y
  A2A; sin él (CLI local), nada cambia.
- La caché de búsqueda sube de versión e incluye el nivel de la cúpula en la
  huella.

## [Unreleased] — 2026-09-30 · Savia Files: permisos por documento (SE-419)

### Added
- Listas `readers`/`writers` por documento, que solo restringen (null hereda, `[]`
  solo admin), y el nivel del documento aplicado con la tabla de roles de las
  cúpulas.
  - Se aplican en `list`, `get`, `text`, `download`, `put` (`replaces` y nivel de
    creación), `delete`, `reprocess` y en cada hit de fichero de `vault_rag`, con
    la política actual.
  - Sin permiso de lectura, `NOT_FOUND`; sin permiso de escritura, `POLICY_DENIED`.
- `vault_files action:"policy"` y `files policy`: operación del ledger con receipt,
  `policyVersion` y `CONFLICT` si cambia antes; las listas nunca van al ledger.
- `vault_rag` declara `filtered` por cúpula y descarta hits de documentos ya
  borrados.

### Changed
- `authorize` del servidor MCP devuelve el principal `{username, role}`; `FilesService`
  y `RagService` lo usan (sin él, modo local: todo permitido).

## [Unreleased] — 2026-09-30 · Savia Files: ledger git privado, journal y receipts (SE-418)

### Added
- Ledger por cúpula (`<FilesHome>/<cúpula>/ledger`): repo git local sin remoto ni
  hooks, aislado de la configuración global.
  - Es la autoridad: un commit por operación con manifiestos compactos (ids, hashes,
    estados) e intent; tombstones al borrar.
  - En cúpulas cifradas solo guarda el hash del cifrado.
  - Un payload tocado a mano da `INTEGRITY`.
- Journal `node:sqlite` (WAL): operaciones pendientes con lease y proceso dueño,
  outbox al menos una vez (`extract`, `rag-sync`) y receipts. Se reconstruye
  desde el ledger si se pierde.
- Idempotencia (`idempotencyKey`) en `put`, `delete` y `reprocess`;
  `IDEMPOTENCY_CONFLICT` si la clave se reutiliza con otra petición.
- Recuperación automática:
  - `COMMIT_PENDING` si git falla, nunca `READY`;
  - el reconciliador completa o cancela las operaciones cortadas.
- Receipts Ed25519 con clave de firma propia y registro de claves públicas
  (`files keys rotate-signing`), incluidos en la copia sellada de claves.
- `vault_files`: `operation`, `log`, `verify` y `recover`. CLI: `files verify
  [--deep]`, `files log`, `files recover`.

### Changed
- `engines.node` pasa a `>=22.13.0`.
- `delete` y `reprocess` devuelven también `operationId` y `receipt`.
- Los tests usan un almacén de claves temporal (`tests/setup-isolation.ts`).

## [Unreleased] — 2026-09-30 · Savia Files: cifrado en reposo (SE-417)

### Added
- Cifrado en reposo con libsodium, obligatorio en N3/N4 y opcional en N1/N2
  (`files.encryption`):
  - originales en `crypto_secretstream` por frames;
  - texto extraído y manifiestos sellados con XChaCha20-Poly1305 y AAD canónico;
  - índice RAG (chunks, vectores, BM25) sellado.
- Claves: KEK por cúpula en `~/.savia-vaults/keys/files` (0600, fuera de git) y una
  DEK por revisión envuelta. Borrado criptográfico al borrar.
- `files encrypt` (migración reanudable, sin re-embeber) y `files keys rotate`
  (re-envuelve y re-sella, sin re-embeber). `KEY_MISSING` si falta la clave; nunca
  se crea una en silencio.
- Recuperación:
  - `files keys export` genera un fichero de recuperación con frase (Argon2id);
  - `files keys backup` genera la copia nocturna de claves sellada para la clave
    pública de recuperación;
  - `files keys import` restaura.
- MCP `vault_files`: `encrypt` y `keys` (`rotate|export`, admin). `status` avisa
  de cúpulas cifradas sin recuperación.
- `scripts/vaults-backup-cron.sh` incluye el almacén de ficheros y las claves por
  otro canal. Las claves solo se suben si `SAVIA_BACKUP_UPLOAD_KEYS=true`.
- Copias temporales en claro para el lector y el antivirus en `/dev/shm`, siempre
  liberadas.

### Dependencies
- `libsodium-wrappers-sumo` 0.8.4 (WASM, sin compilación nativa).

## [Unreleased] — 2026-09-30 · Savia Files: instalador sin consola (SE-416)

### Added
- `savia-vaults files setup|status` y `vault_files` `setup`/`status`: instalan el
  lector de documentos (Python gestionado + Docling con lock con hashes) y el
  antivirus ClamAV oficial en `~/.savia-vaults/tools`, sin administrador. Versiones
  y SHA-256 fijados, instalación atómica e idempotente, mensajes en lenguaje llano.
  Por MCP corre en segundo plano y exige rol admin si hay usuarios.
- Firmas de ClamAV al día sin intervención: actualización en segundo plano a las
  24 h; `required` rechaza con firmas de más de 7 días.
- Análisis antivirus por lote: una llamada para todos los ficheros de un `put`.
- Solo Linux x86_64 (probado); otras plataformas lo dicen en `status`.

## [Unreleased] — 2026-09-30 · Savia Files: fidelidad de extracción y cobertura honesta (SE-415)

### Fixed
- Un documento del que no se extrae ninguna unidad ya no queda `READY`:
  `ARCHIVE_ONLY` con el motivo (`page-without-text` en PDF escaneados, `empty`).
- JSON grandes declaran lo omitido (`max-units`, `max-depth`) y los muy anidados
  ya no desbordan la pila.
- CSV y TXT en Windows-1252 se extraen (antes `ARCHIVE_ONLY`).

### Added
- Notas del presentador de PPTX, citadas por diapositiva.
- Celdas XLSX con el nombre de su columna y la etiqueta de su fila.
- Worker por lotes: `files add` de varios ficheros usa un solo proceso (6 PDF:
  73,8 s → 37,1 s). `FilesService.putMany`.

## [Unreleased] — 2026-09-30 · Savia Files: robustez y seguridad (SE-414)

### Security
- Guardia de descompresión para DOCX, PPTX y XLSX: un fichero de 1 MB que se
  descomprime a 414 MB se rechaza en 3 ms en vez de ocupar el worker 180 s con 1,2 GB.
- Un worker Python a la vez por proceso (`SAVIA_FILES_WORKERS`): 4 subidas
  simultáneas pasan de 4,5 GB a 1,15 GB de RAM.
- Nombres con caracteres Unicode de formato (bidi, zero-width, BOM) o separadores
  de línea rechazados.
- `SAVIA_FILES_HOME` y `SAVIA_RAG_HOME` resuelven symlinks antes de comprobar
  que no están dentro de un repo git.
- La extracción queda ligada a su revisión por digest: una edición en disco
  devuelve `INTEGRITY` y no llega a Savia RAG.

### Changed
- Un manifiesto por documento (`docs/<id>.json`) con migración automática del
  MVP: guardar + extraer un TXT con 3000 documentos en la cúpula baja de 49,6 a
  2,2 ms/doc. Un manifiesto corrupto ya no inutiliza la cúpula.
- `vault_files list` devuelve `{documents, corrupt}`.
- Las escrituras esperan el lock hasta `SAVIA_FILES_LOCK_WAIT_MS` (def. 10 s).

## [Unreleased] — 2026-09-30 · Savia Files MVP (SE-413)

### Added
- Savia Files: guarda originales en la cúpula (`$SAVIA_FILES_HOME`, fuera de git),
  con blobs de solo lectura direccionados por SHA-256, revisiones (`replaces`),
  borrado real y `gc` de huérfanos.
- Extracción con localizador: TXT/MD por líneas, CSV por fila y JSON por clave en
  TS; PDF por página, PPTX por diapositiva, DOCX por elemento (Docling sin OCR) y
  XLSX por celda con valor y fórmula (openpyxl) en un worker Python aislado.
  Cobertura declarada; `ARCHIVE_ONLY` si no hay extracción.
- Escaneo opcional con ClamAV (`files.scan: auto|required|off`); infectado ⇒
  `QUARANTINED` sin bytes.
- Savia RAG indexa los ficheros como fuentes `files/<id>`; los hits llevan
  `source` (documento, revisión, localizador), también en la respuesta `lean`.
- MCP `vault_files` y CLI `savia-vaults files add|list|show|text|get|rm|reprocess|gc`.
- Bloque `files` por cúpula en `savia-vaults.domes.json` (desactivado por defecto).
- Documentación: `docs/files.md`.

## [Unreleased] — 2026-09-29 · Higiene de vault_search (SE-412)

### Fixed
- `vault_search` indexa solo markdown (o `allowedExtensions` de la cúpula) y
  excluye `node_modules` y directorios ocultos; `#648` ya no cuenta como tag.
- Fan-out RAG: una cúpula que vence el timeout ya no carga su índice después
  (`AbortSignal` por tarea); era la causa de un test intermitente.

### Changed
- CLI `search`: caché persistente del índice (`SAVIA_SEARCH_CACHE`, 0600, fuera de
  git), índice sin texto completo (snippet leído del fichero) y módulo propio:
  1,37 s → ~0,5 s en savia-docs.
- MCP: JSON compacto en `vault_search`, `vault_list` y `vault_tags`.

## [Unreleased] — 2026-09-29 · Eficiencia de Savia RAG (SE-411)

### Fixed
- Fusión entre cúpulas invariante al orden: coseno global con contrato compartido,
  desempate determinista si no (`fusion` en la respuesta).
- Caché de índices dimensionada a las cúpulas habilitadas y a `SAVIA_RAG_MEMORY_MB`.
- `rag gc` con gracia 0 no borraba ficheros recién escritos (reloj).

### Changed
- `vault_rag`: JSON compacto, perfil `fields: lean|full`, `maxChars` (def. 6000)
  acota la respuesta entera.
- Embeddings con `keep_alive` (`SAVIA_RAG_KEEP_ALIVE`, def. `30m`).
- Consultas: digest vía `/api/tags` con caché, sin embedding de sondeo; índice BM25
  persistido por generación; embedding solapado con la carga de BM25.
- CLI: `savia-vaults rag …` carga solo su módulo (arranque 240 → 100 ms).

## [Unreleased] — 2026-09-29 · Savia RAG (SE-410)

### Added
- **Savia RAG** (`src/rag/`): chunking markdown por encabezados con cabecera
  contextual, embeddings locales vía Ollama, almacén flat exacto por generación
  (escritura atómica, 0600, fuera de git), BM25 sobre chunks con stopwords es/en,
  fusión RRF, filtro de frescura (`status`, `valid_until`, `superseded_by`, decaimiento).
- Fan-out paralelo cúpulas × consultas con semáforo, timeout por cúpula y
  resultados parciales; fusión entre cúpulas por rango.
- Política dinámica de embeddings: contrato inmutable por generación (modelo +
  digest + chunker), re-embedding incremental por hash, disparadores en lectura,
  escritura (debounce) y cron, generación sombra ante deriva de digest, gate de
  promoción por eval con línea base registrada, rollback y gc.
- Confidencialidad: ACL por cúpula en el fan-out, N4 fuera de `"*"`, notas con
  nivel superior a su cúpula no se embeben (CRIT-001).
- MCP: `vault_rag`, `vault_rag_status`, `vault_rag_sync`. CLI: `rag search|sync|status|eval|promote|rollback|gc`.
- Banco de eval prerregistrado `eval/rag-savia-docs.json` (36 consultas).
- 84 tests nuevos (433 total en verde).

## [Unreleased] — 2026-08-14 · Mejoras RAG/grafo (SE-327..331)

### Added
- **PPR ranking** (`src/knowledge/ppr.ts`, SE-327): Personalized PageRank determinista
  (power method, sin deps/LLM). `traverse` ordena por PPR (semilla = startId),
  `vaults graph --action ppr` expone ranking.
- **Dual-mode query** (`src/knowledge/communities.ts`, SE-328): detección de
  comunidades (componentes conexos) + resumen global (tipos/relaciones dominantes,
  hubs top-PPR). `vaults query --mode global|hybrid`.
- **Entity resolution** (`src/knowledge/entity-resolution.ts`, SE-329):
  canonicalización de IDs (NFKD, acentos, case, separadores) + sinónimos; resuelve
  aliases en query y reporta colisiones.
- **Context enrichment** (`src/search/enrichment.ts`, SE-330): fusión BM25+grafo —
  `score = bm25 * (1 + α·graphScore)`; `vaults search --enrich`, best-effort.
- **Retrieval eval** (`src/search/eval.ts`, SE-331): precision@k / recall@k
  (RAGAS-like, determinista); `vaults eval-search --modes bm25,enriched`.
- `seed-example-context.sh`: puebla un vault local desde las specs del proyecto.
- 56 tests nuevos (338 total en verde).

## [Unreleased] — 2026-08-06 · Knowledge Governance (SE-309)

### Added
- **Decision records** (`src/knowledge/decision.ts`): nodo de conocimiento de primera clase — categoria, escenario, razonamiento, resultado, confianza, decisor y estado de ciclo de vida (proposed/accepted/rejected) con ProvenanceRef. `createDecisionRecord()` + `validateDecision()`.
- **Decision state log** (`src/knowledge/decision-state.ts`): `promote()`/`getActiveState()`, historial DecisionStateLog con StateChange y razon de cambio.
- **Conflict detection** (`src/knowledge/conflicts.ts`): `detectConflicts()` para hechos contradictorios (misma entidad+propiedad con valores distintos), severidad info/warning/critical, estado open/resolved y `resolveConflict()` sin overwrite silencioso.
- 4 suites de tests nuevas (decision, decision-state, conflicts, index)

## [0.3.0] — 2026-08-01 · Capa de conocimiento (SE-288)

### Added
- **Entity schema** (schema/entities/): 7 tipos base (person, organization, project, decision, document, event, system) con validacion de frontmatter
- **SchemaRegistry** (src/schema/): carga YAML, valida required/vocabulary/pattern, alias resolubles
- **KnowledgeGraph** (src/knowledge/graph.ts): relaciones tipadas direccionales, derivacion de wikilinks, recorrido acotado
- **Introspector** (src/knowledge/introspector.ts): tipos, cobertura, propiedades por vault y entidad
- **QueryEngine** (src/knowledge/query.ts): notacion punteada determinista, doble salida markdown+filas, busqueda difusa
- **ProvenanceEngine** (src/knowledge/provenance.ts): assertions con fuente, autoridad, bitemporalidad, conflictos
- **QualityEngine** (src/knowledge/quality.ts): 8 indicadores de salud, informe formateado
- **Compliance** (src/compliance/): transparencia Art. 50 EU AI Act, inventario de salidas, marcado Ed25519
- 13 MCP tools, 8 A2A endpoints, 10 comandos CLI
- 125 tests (89 original + 36 knowledge layer)


## [0.2.0] — 2026-08-01 · Servidores reales, backups, firma (SE-287)

### Added

- **MCP Server real** (`src/server/mcp.ts`): 9 tools con stdio transport usando `@modelcontextprotocol/sdk`. Cada tool delega en storage/search/security.
- **A2A Server** (`src/server/a2a.ts`): HTTP REST con 5 endpoints (/health, /search, /context, /stats, /share). Rate limiter integrado por cliente. Auth via Bearer token. Loopback por defecto con warning si se expone.
- **Backup system** (`src/backup/index.ts`): creación/lista/restauración de backups tar.gz. Sincronización con Nextcloud via carpeta local (desktop client) o WebDAV directo.
- **Ed25519 signing** (`src/security/index.ts`): firmas criptográficas reales con generación automática de keypair. `signContent()` y `verifySignature()` usando `node:crypto`.
- **Federate CLI**: `federate add|list|remove|health` usando FederationRegistry.
- **Backup CLI**: `backup create|list|restore|status` usando BackupManager.
- **Export funcional**: produce directorio con documentos legibles sin la herramienta.
- **Verify**: verifica integridad de firmas de todos los documentos.
- **Documentación**: `docs/USAGE.md` (guía completa), `docs/BACKUP.md` (guía Nextcloud).

### Changed

- **Storage**: `write()` usa firma Ed25519 real en lugar del placeholder sha256.
- **CLI**: `serve` inicia servidores reales MCP/A2A. `export` y `verify` funcionales.
- **CLI**: añadidos 10+ comandos nuevos (backup, federate, export real, verify real).

## [0.1.0] — 2026-08-01 · Producto verificable (SE-286)

### Added

- **Core types** (`src/types.ts`): VaultConfig, Note, Receipt, SearchResult, Frontmatter, CommitEntry
- **Storage engine** (`src/storage/index.ts`): git-backed CRUD con frontmatter YAML y hashing SHA256
- **Search engine** (`src/search/index.ts`): BM25 full-text search via minisearch
- **Security sandbox** (`src/security/index.ts`): 6-layer path validation
- **Rate limiter** (`src/server/ratelimit.ts`): token bucket per-client
- **MCP server skeleton** (`src/server/mcp.ts`): inicialización de vault
- **CLI** (`src/cli/index.ts`): 6 comandos (init, serve, search, stats, verify, export)
- **Threat model** (`docs/threat-model.md`)
- **Federation modules**: registry, cache, a2a-client, search merge, circuit-breaker, audit-logger, hash-verify

### Tests

- 89 tests en 14 ficheros, todos en verde sobre código real
