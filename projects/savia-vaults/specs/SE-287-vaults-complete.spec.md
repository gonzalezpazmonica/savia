# SE-287 — SaviaVaults: completar producto (MCP, A2A, backup Nextcloud, gaps)

**Status:** IN_PROGRESS
**Fecha:** 2026-08-01
**Proyecto:** projects/savia-vaults
**Padre:** SE-286 (producto verificable v0.1.0)
**Branch:** agent/se287-vaults-complete
**Estimacion total:** ~32h (6 slices)

---

## Origen

Análisis completo de gaps post-SE-286 (2026-08-01). SE-286 convirtió un esqueleto de 263 líneas (solo federation) en un producto verificable de 16 módulos con 89 tests. Pero los dos servidores que el producto promete en su título —MCP y A2A— no existen. El servidor MCP es un esqueleto de 36 líneas que ni importa el SDK de MCP. El servidor A2A no tiene archivo. Y 27 carencias adicionales cubren firma, backups, export, persistencia, y CLI.

### Lo que funciona (SE-286)

10 módulos operan sobre código real con tests: storage, search, security, ratelimit, registry, cache, a2a-client, circuit-breaker, audit-logger, hash-verify (este último retirado el 2026-11-20, ver AC-4.5). CLI con init/search/stats funcionales.

### Lo que NO funciona

| Gap | Severidad | Detalle |
|---|---|---|
| MCP Server | CRITICAL | 36-line skeleton; MCP SDK no se usa; 0 de 9 tools |
| A2A Server | CRITICAL | Archivo no existe; 0 de 5 endpoints |
| Ed25519 | HIGH | Placeholder sha256 en storage; no crypto real |
| CLI | HIGH | 27 subcomandos prometidos no existen |
| Federation wiring | MEDIUM | CircuitBreaker/AuditLogger/HashVerify huérfanos |
| Search persistence | MEDIUM | Índice se reconstruye cada vez |
| Backup + Nextcloud | HIGH | Zero código; usuario lo pide explícitamente |
| Export | MEDIUM | Skeleton |
| Confidentiality | MEDIUM | Zero filtrado N1-N4 |
| Config loading | MEDIUM | Schema existe, nadie lo lee |

---

## Objetivo

Completar SaviaVaults como producto: servidor MCP real con 9 tools, servidor A2A con 5 endpoints HTTP, firma Ed25519, backups locales + sincronización con Nextcloud, CLI completa, y wiring de todos los módulos de federación. Al terminar, `savia-vaults serve --transport mcp` inicia un servidor MCP funcional que cualquier cliente MCP puede usar.

## Out of scope

- NO interfaz gráfica ni servicio alojado
- NO multi-escritor distribuido
- NO embeddings semánticos
- NO user management (SE-284 S4) — baja prioridad, sin tests
- NO dome/confidentiality CLI tree completo (SE-284 S3/S6) — sin tests que los exijan
- NO skill/agent SE-285 — es artefacto de documentación, no código

---

## Slice 1 — MCP Server: 9 tools con stdio transport

**Problema:** El MCP server es el valor central del producto y no existe. El `@modelcontextprotocol/sdk` está instalado pero nunca se importa.

**Diseño:**
- `src/server/mcp.ts` reescrito como servidor MCP real usando `@modelcontextprotocol/sdk`
- Transporte stdio (entrada/salida estándar) — el que esperan Claude Code, Codex, Cursor
- 9 tools registradas: `vault_read`, `vault_write`, `vault_search`, `vault_list`, `vault_stats`, `vault_index`, `vault_diff`, `vault_log`, `vault_tags`
- Cada tool delega en `VaultStorage`, `SearchEngine`, o `VaultSecurity` según corresponda
- Modo lectura por defecto: `vault_write` requiere flag `--write-mode` en el CLI
- `vault_search` acepta `query`, `maxResults`, `pathPrefix`
- Errores MCP estándar con mensajes accionables

**Acceptance criteria:**

AC-1.1. `savia-vaults serve --transport mcp` inicia servidor MCP funcional.
AC-1.2. Cliente MCP externo (Claude Code, mcp-inspector) descubre las 9 tools.
AC-1.3. `vault_search "microservices"` devuelve resultados correctos via MCP.
AC-1.4. `vault_read "notes/test.md"` devuelve contenido con frontmatter.
AC-1.5. `vault_write` denegado sin flag `--write-mode`.
AC-1.6. `mcp-server.test.ts` ampliado con tests de protocolo real.

**Esfuerzo:** 8h

---

## Slice 2 — A2A Server: HTTP REST con 5 endpoints

**Problema:** El archivo `src/server/a2a.ts` no existe. El cliente de federación (`A2AClient`) asume que `/search` y `/health` existen pero no hay servidor que los sirva.

**Diseño:**
- `src/server/a2a.ts`: servidor HTTP con Node.js `http` nativo (sin dependencia extra)
- Endpoints: `GET /search?q=&maxResults=`, `GET /context/:vault/:path`, `GET /stats`, `GET /health`, `POST /share`
- `GET /health` devuelve `{ status: "ok", uptime, noteCount }`
- `GET /search` delega en SearchEngine, devuelve JSON
- `GET /context/:vault/:path` lee y devuelve documento con frontmatter
- `GET /stats` devuelve estadísticas del vault
- `POST /share` acepta contenido para写入 en el vault (si --write-mode)
- Rate limiter integrado: `RateLimiter` envuelve cada endpoint
- Bind a loopback por defecto; `--host 0.0.0.0` requiere flag explícito con aviso
- Auth via `Authorization: Bearer <token>` si `SAVIA_VAULTS_TOKEN` está configurado

**Acceptance criteria:**

AC-2.1. `curl http://127.0.0.1:8923/health` devuelve 200 con estado.
AC-2.2. `curl "http://127.0.0.1:8923/search?q=architecture"` devuelve resultados JSON.
AC-2.3. `curl http://127.0.0.1:8923/context/default/docs/test.md` devuelve contenido.
AC-2.4. Rate limiter bloquea tras 100 req/min.
AC-2.5. Sin token configurado, endpoints públicos funcionan; con token, requieren Authorization.
AC-2.6. Bind a 0.0.0.0 emite warning.

**Esfuerzo:** 6h

---

## Slice 3 — Backups locales + sincronización con Nextcloud

**Problema:** Zero código de backup. El usuario pide explícitamente backup contra Nextcloud.

**Diseño:**
- `src/backup/index.ts`: módulo de backup con operaciones `create`, `list`, `restore`
- `create`: empaqueta el vault en tar.gz con timestamp en `~/.savia-vaults/backups/`
- `list`: lista backups disponibles con tamaño, fecha, vault
- `restore`: extrae backup a directorio destino, valida integridad
- Nextcloud: si el usuario configura una carpeta sync de Nextcloud (via `SAVIA_BACKUP_NEXTCLOUD_DIR` o `savia-vaults.config.json`), los backups se copian allí automáticamente tras cada `create`
- Alternativa WebDAV: si no hay carpeta local sync pero sí `NEXTCLOUD_URL` + `NEXTCLOUD_USER` + `NEXTCLOUD_PASS`, subir via WebDAV PUT
- `savia-vaults backup create` → crea backup local
- `savia-vaults backup list` → lista backups locales
- `savia-vaults backup restore <id>` → restaura backup
- `savia-vaults backup status` → muestra estado de sync con Nextcloud

**Acceptance criteria:**

AC-3.1. `savia-vaults backup create` produce tar.gz verificable.
AC-3.2. `savia-vaults backup list` muestra backups con fecha y tamaño.
AC-3.3. `savia-vaults backup restore <id>` extrae y verifica.
AC-3.4. Con `SAVIA_BACKUP_NEXTCLOUD_DIR` configurado, backup se copia automáticamente.
AC-3.5. Nextcloud sync funciona con carpeta local (desktop client) y WebDAV.
AC-3.6. Backup corrupto → restore falla con mensaje claro.

**Esfuerzo:** 6h

---

## Slice 4 — Firma Ed25519 real + wiring de federación

**Problema:** La firma es un placeholder sha256. CircuitBreaker, AuditLogger y HashVerify existen pero nadie los llama.

**Diseño:**
- `src/security/` añade `signContent()` y `verifySignature()` usando `node:crypto` con Ed25519
- `VaultStorage.write()` usa `signContent()` en lugar del placeholder
- `FederatedSearchEngine` integra `CircuitBreaker` (reemplaza health tracking manual)
- `FederatedSearchEngine` integra `FederationAuditLogger` (registra cada query federada)
- ~~`FederatedSearchEngine` integra `verifyContentHash()` al recibir resultados remotos~~ (retirado, ver nota bajo los AC)
- Key pair generado en `~/.savia-vaults/keys/` al primer uso
- `savia-vaults verify` verifica firma de todos los documentos del vault

**Acceptance criteria:**

AC-4.1. `write()` produce firma Ed25519 real verificable.
AC-4.2. Documento alterado tras firmar → verificación falla.
AC-4.3. CircuitBreaker se activa tras 5 fallos consecutivos de un dome.
AC-4.4. Auditoría registra cada query federada en JSONL.
AC-4.5. ~~Resultados remotos con hash incorrecto se descartan.~~ RETIRADO (ver nota). La firma Ed25519 (AC-4.1, AC-4.2) cubre solo los documentos locales firmados al escribirlos; la integridad de resultados remotos federados NO está cubierta hoy y requeriría resultados firmados, trabajo nuevo fuera de esta retirada.
AC-4.6. `savia-vaults verify` verifica todos los documentos y reporta.

**Retirada/enmienda 2026-11-20 por decisión de la operadora (pregunta interactiva):** se retira AC-4.5 y se elimina `src/federation/hash-verify.ts` con su test. Era un hash de 32 bits no criptográfico que el cliente local (`a2a-client.ts`) calcula sobre el mismo snippet que después se comprobaría: la verificación salía bien por construcción y no detectaba ninguna manipulación. No protegía nada y nadie lo importaba. `contentHash` sigue existiendo como clave de deduplicación en la búsqueda federada, sin función de integridad.

**Esfuerzo:** 5h

---

## Slice 5 — CLI completa + persistencia de índice + export

**Problema:** Solo 3/6 comandos del CLI funcionan. Índice de búsqueda se reconstruye en cada arranque. Export es un print vacío.

**Diseño:**
- `serve` inicia servidor real MCP o A2A (usando Slice 1 y 2)
- `verify` verifica firmas de todo el vault
- `export` produce directorio con todos los documentos en formato legible sin la herramienta
- `federate add|list|remove|health` — comandos de federación usando FederationRegistry
- `backup create|list|restore|status` — comandos de backup (Slice 3)
- `config show` — muestra configuración actual
- Persistencia de índice: `SearchEngine` guarda/carga índice serializado en `.savia-vault/search-index.json`
- Índice incremental: `buildIndex()` solo reindexa archivos modificados desde último build

**Acceptance criteria:**

AC-5.1. Los 6 comandos originales (init, serve, search, stats, verify, export) funcionan.
AC-5.2. `federate add|list|remove|health` funcionan.
AC-5.3. `backup create|list|restore|status` funcionan.
AC-5.4. Índice persiste en disco y carga en caliente (segundo arranque no reindexa).
AC-5.5. `export` produce directorio legible sin la herramienta.

**Esfuerzo:** 5h

---

## Slice 6 — Documentación, smoke final, PR

**Problema:** Sin documentación del producto completo, los usuarios no saben usarlo.

**Diseño:**
- README actualizado con todos los comandos funcionales
- `docs/USAGE.md` con guía completa de uso
- `docs/BACKUP.md` con guía de backup + Nextcloud
- CHANGELOG actualizado a v0.2.0
- Smoke test completo: init → write → search via MCP → backup → restore → verify
- Todos los tests en verde

**Acceptance criteria:**

AC-6.1. README documenta todos los comandos funcionales.
AC-6.2. `docs/USAGE.md` cubre MCP, A2A, backup, federación.
AC-6.3. CHANGELOG v0.2.0 documenta todos los cambios.
AC-6.4. Smoke test pasa: install → init → serve mcp → search → backup → restore → verify.
AC-6.5. 0 tests fallando.

**Esfuerzo:** 2h

---

## Verification method

1. Servidor MCP funcional con cliente real (mcp-inspector o Claude Code)
2. Servidor A2A funcional con curl
3. Backup + restore ciclo completo
4. Nextcloud sync (local dir o WebDAV)
5. Firma Ed25519 end-to-end
6. CLI con 12+ comandos funcionales

## Orden recomendado

1 (MCP, 8h) → 2 (A2A, 6h) → 3 (Backup+Nextcloud, 6h) → 4 (Ed25519+wiring, 5h) → 5 (CLI+persistencia+export, 5h) → 6 (Docs+smoke, 2h)

Total: 32h.
