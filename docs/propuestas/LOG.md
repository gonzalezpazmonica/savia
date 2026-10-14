<!-- @generated/managed by scripts/spec-lifecycle.sh — append-only -->
<!-- Most recent entries at the top. Format: ## YYYY-MM-DD SPEC-ID STATUS -->
# Specs Lifecycle Log

> Conceptual history of specs in docs/propuestas/. Append-only.
> Each entry: date, spec ID, status transition, optional rationale.
> Ref: SE-222 S1 OKF Adoptable Patterns (log.md convention).

## 2026-10-07 SE-434 APPROVED

Delta FS-6b (D-MED-9): el motor corre con las máscaras N2 y el bash del agente va por intermediario sin anidar; aprobado con condición APTO de rev-fs6b REV5

## 2026-10-06 SE-436 APPROVED

operadora, AskUserQuestion 2026-10-06: aprobada con las recomendaciones de Savia (D30-1..6, D23-14)

## 2026-10-06 SE-436 PROPOSED

Propuesta tras la validación e2e del gallinero (huecos G-01, G-02, G-03, G-06, G-07)

## 2026-10-06 SE-431 APPROVED

operadora, AskUserQuestion 2026-10-06

## 2026-10-05 SE-435 APPROVED

Aprobada por la operadora (AskUserQuestion 2026-10-05: «Apruebo, empieza por D1»)

## 2026-10-05 SE-435 PROPOSED

Propuesta tras D-MED-7 (AskUserQuestion 2026-10-05)

## 2026-10-05 SE-432 APPROVED

Aprobada por la operadora (AskUserQuestion 2026-10-05)

## 2026-10-05 SE-430 APPROVED

Aprobada por la operadora (AskUserQuestion 2026-10-05)

## 2026-10-05 SE-429 APPROVED

Aprobada por la operadora (AskUserQuestion 2026-10-05)

## 2026-10-05 SE-434 APPROVED

Aprobada por la operadora (AskUserQuestion 2026-10-05: «Apruebo, pero S1 y S2 a la vez»); decisiones D-MED-1..6

## 2026-10-04 SE-433 APPROVED

Aprobada por la operadora (AskUserQuestion 2026-10-04: «Apruebo SE-433»). D1 cambia después a autorización por respuesta en la sesión orquestadora.

## 2026-10-04 SE-433 PROPOSED

merge-sprint: merges en serie de una lista congelada de PRs firmada antes por la operadora; ejecutor determinista; las salidas de agentes solo restan.

## 2026-10-03 SE-428 IMPLEMENTING

La operadora sube el WIP a 4 con un hueco temporal solo para Savia Space (addendum ADR-002); Space es frontend de Savia sin ampliar autoridad.

## 2026-10-03 SE-432 PROPOSED

Savia Space: escritorio infinito y experiencia; superficie principal del sustituto (SE-428), apariencia gestionada por la persona.

## 2026-10-02 SE-431 PROPOSED

Savia Soul: bucle continuo configurable y bajo demanda dentro de Space; A2A con otros bots y mensajería con la operadora.

## 2026-10-02 SE-430 PROPOSED

Savia Space Mobile: app Android nueva, cliente de Space por red local o VPN, aprobación con biometría.

## 2026-10-02 SE-429 PROPOSED

Savia Space interoperable: API JWT/OpenAPI, MCP y A2A; recibos firmados; compatible con AEK, AEOS y TEE.

## 2026-10-02 SE-428 PROPOSED

Savia Space como sustituto de OpenCode, con OpenCode como motor (mandato original y decisiones de la operadora).

## 2026-10-02 SE-426 IMPLEMENTING

Aprobada por la operadora y en el hueco libre del WIP (3/3). Paso 1: código y tests sin tocar la CI.

## 2026-10-02 SE-426 APPROVED

Aprobada por la operadora; el secreto de CI lo crea Savia tras el paso 1.

## 2026-10-02 SE-426 PROPOSED

Firma de confidencialidad con secreto de CI y HMAC siempre verificado (decisión de la operadora
del 27/09). RCA del handback hmac-signature-ci-20260927: falso positivo del gate de soberanía,
corregido por #1162. Pendiente de aprobación.

## 2026-10-01 SE-405 IMPLEMENTED

Coste por subagente, snapshots de config y timeline de memoria (#1169). AC1–AC9 verificados el
2026-10-01 (29 BATS). Graduada por la operadora; no ocupaba WIP.

## 2026-10-01 SE-402 IMPLEMENTED

Registro de ediciones atribuidas (#1168). AC1–AC7 verificados el 2026-10-01 (15 BATS, hook p95
20 ms). Graduada por la operadora; no ocupaba WIP.

## 2026-10-01 SE-424 IMPLEMENTED

Arreglos de la revisión S02 de Vaults/Files: H1 #1204, H2 #1205, H3 #1206, H4 #1213. Graduada
por la operadora; no ocupaba WIP.

## 2026-10-01 SE-425 IMPLEMENTED

Lockfiles de npm versionados (scripts/, savia-vaults), `npm ci` en CI, auditoría sobre los locks y
job de CI de la suite de savia-vaults (#1220). Graduada por la operadora; sale del WIP.

## 2026-10-01 SE-425 IMPLEMENTING

Lockfiles y CI de savia-vaults entran en el WIP en el hueco de SE-423, por decisión de la operadora.

## 2026-10-01 SE-423 IMPLEMENTED

Identidad mínima completa: PR 1 #1216 (credenciales con caducidad, migración) y PR 2 #1218 (A2A
por usuario, cortes de stream, svt1 ligado, listas por subjectId, `user rename`). Desviaciones en
la spec (CLI sin tokens, receipts sin identidad). Graduada por la operadora; sale del WIP.

## 2026-10-01 SE-425 APPROVED

Lockfiles de npm versionados (scripts/, savia-vaults), `npm ci` en CI y job de CI para la suite
de savia-vaults (D1). savia-web y savia-monitor cuando se toquen (D2). Espera hueco WIP.

## 2026-10-01 SE-425 PROPOSED

Lockfiles de npm versionados (scripts/, savia-vaults) y CI de savia-vaults: hueco real del
auditor externo de SE-407 S4. Pendiente de decisión de la operadora (D1/D2).

## 2026-10-01 SE-423 IMPLEMENTING

Identidad mínima entra en el WIP en el hueco de SE-407, por decisión de la operadora.
Dos PR: credenciales con caducidad y migración; PDP común, streams y A2A.

## 2026-10-01 SE-407 IMPLEMENTED

Predicado de estado consistente completo: S1 #1208, S2 #1209, S3 #1210, S4 #1214 (auditor
externo fijado). Graduada por decisión de la operadora; sale del WIP.

## 2026-10-01 SE-416 IMPLEMENTED

Instalador sin consola graduado tras SE-424 H4 (#1213): los modelos del lector de PDF se
instalan con manifiesto SHA-256; PDF READY con HOME limpio. Decisión de la operadora.

## 2026-10-01 SE-412 IMPLEMENTED

Graduada con AC3 no cumplido (CLI ~500 ms frente a < 400 ms, límite de MiniSearch) y aceptado
por la operadora; para agentes, MCP (7–32 ms) o vault_rag.

## 2026-10-01 SE-422 IMPLEMENTED

Graduada por decisión de la operadora tras integrar SE-424 H1 (#1204), que cerraba su único
bloqueo (ficheros de más de 2 GiB sin analizar). PR #1202; evidencia S02 y resultados H1.

## 2026-10-01 SE-421 IMPLEMENTED

Graduada por decisión de la operadora tras integrar SE-424 H1 (#1204), que cerraba su único
bloqueo (ficheros de más de 2 GiB sin analizar). PR #1201; evidencia S02 y resultados H1.

## 2026-09-30 SE-424 APPROVED

Arreglos de la revisión S02: escaneo que no cubre > 2 GiB falla cerrado (H1), guarda de A2A
(H2), revocación en caliente en MCP (H3) y modelos del lector de PDF en files setup (H4).
Aprobados por la operadora, un PR Draft por arreglo. Bloquea graduar SE-416, SE-421 y SE-422.

## 2026-09-30 SE-423 APPROVED

Identidad mínima de SaviaVaults: Subject, credenciales con caducidad y revocación individual,
PDP común en MCP/A2A/HTTP/CLI y corte de streams. Aprobada por la operadora: tokens migrados
caducan a los 365 días; SAVIA_VAULTS_TOKEN obsoleto con aviso una versión.

## 2026-09-30 SE-420 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1200; suite 721/721 sobre c9b42de5.

## 2026-09-30 SE-419 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1199; suite 721/721 sobre c9b42de5.

## 2026-09-30 SE-418 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1198; suite 721/721 sobre c9b42de5.

## 2026-09-30 SE-417 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1197; suite 721/721 sobre c9b42de5.

## 2026-09-30 SE-415 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1195; suite 721/721 sobre c9b42de5.

## 2026-09-30 SE-414 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1194; suite 721/721 sobre c9b42de5. AC9 parcial declarado.

## 2026-09-30 SE-413 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1193; suite 721/721 sobre c9b42de5.

## 2026-09-30 SE-411 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1190; suite 721/721 sobre c9b42de5.

## 2026-09-30 SE-410 IMPLEMENTED

Graduada tras la revisión S02 (docs/evidence/S02-vaults-files-review-20260930.md) por decisión de la operadora («9 limpias ahora»).
PR #1188; suite 721/721 sobre c9b42de5.

## 2026-09-30 SE-422 APPROVED

Savia Files: API HTTP (serve --transport http) con subida reanudable tus 1.0 propia,
descarga por rangos, usuarios por persona y autorizaciones acotadas para delegar subidas
y descargas desde el chat. Aprobada por la operadora junto a SE-421.

## 2026-09-30 SE-421 APPROVED

Savia Files: almacén en streaming (hasta 10 GiB, rangos, cifrado frame a frame, antivirus
por stdin, tope de extracción). Primera mitad de D09 tratada como producto open source;
la API HTTP con tus 1.0 es SE-422. Aprobadas ambas por la operadora, PR por spec.

## 2026-09-30 SE-420 APPROVED

SaviaVaults: una nota con confidentiality mayor que su cúpula deja de servirse por
MCP y A2A (antes solo RAG la omitía), y vault_write la rechaza. Aprobada por la operadora:
oculta para todos, admin incluido, como hace RAG.

## 2026-09-30 ROADMAP REPRIORITIZED

Recopilación y orden de próximas sesiones solicitados por la operadora. Se
conservan ADR-002, fases A–F y WIP SE-407/376/396 (3 + 1 Labs). Cola canónica
S01–S09 en `planning-state.json → route.session_plan`: estado consistente,
seguridad y revisión de entregas, deuda certificada, graduación operacional,
frontera TEE/AEK, conformidad, kernel mínimo, adopción y pilotos.
Necesidad/urgencia/valor/desbloqueos/esfuerzo son cualitativos; sin ROI inventado.
Integraciones SE-402–405 y SE-410–419 verificadas en main se registran como
`delivery`, sin inventar `completion` ni transiciones a IMPLEMENTED. H04 ya
implementado en #1183, sin ejecución real. Los pendientes privados de Labs
permanecen en la cúpula. Inventario: `docs/roadmap-inventory-20260930.md`.

## 2026-09-30 SE-419 APPROVED

Savia Files: permisos por documento (listas readers/writers que restringen y nivel del
documento con la tabla de roles), aplicados también a cada hit de vault_rag con la
política actual. Aprobada por la operadora; la política la cambia un writer con acceso.

## 2026-09-30 SE-418 APPROVED

Savia Files: ledger git privado por cúpula (sin remoto) como autoridad, journal
node:sqlite con outbox e idempotencia, y receipts Ed25519 con clave propia.
Aprobada por la operadora, con D02 (ACL por documento) en una spec aparte.

## 2026-09-30 SE-417 APPROVED

Savia Files: cifrado en reposo (N3/N4 siempre, N1/N2 opcional), borrado
criptográfico, rotación y migración sin re-embeber, e índice RAG cifrado. Copia de
seguridad con las claves por otro canal y recuperación con frase. Aprobada por la
operadora con la clave en fichero aparte y la subida de claves configurable.

## 2026-09-30 SE-416 APPROVED

Instalador de las dependencias de Savia Files sin consola ni administrador, para que
Savia pueda instalarlas por un PM o analista: lector de documentos y ClamAV oficial
desempaquetado. Aprobada por la operadora con antivirus por lote y solo Linux.

## 2026-09-30 SE-415 APPROVED

Savia Files: fidelidad de extracción y cobertura honesta (PDF escaneados, JSON
grandes, notas PPTX, contexto de celdas XLSX, Windows-1252, worker por lotes).
Aprobada por la operadora junto a SE-414.

## 2026-09-30 SE-414 APPROVED

Savia Files: robustez y seguridad del MVP, a partir de la evaluación local
(bomba de descompresión, workers sin límite, nombres invisibles, home por symlink,
extracción no ligada, lock sin espera, manifiesto único). Aprobada por la operadora
junto a SE-415 («PR por spec»); se estabiliza el MVP antes de crecer.

## 2026-09-30 SE-413 APPROVED

Savia Files (MVP): originales inmutables por cúpula, extracción con localizador
(página, diapositiva, elemento, celda, fila, clave), fuente de Savia RAG con cita
y borrado real. Aprobada por la operadora como MVP recortado; el resto de la línea
se abrirá como delta-specs por slice.

## 2026-09-29 SE-412 APPROVED

Higiene y arranque en frío de `vault_search` (solo markdown, tags reales, caché
persistente, JSON compacto) y corrección del fallo intermitente del fan-out.
Aprobada por la operadora en chat.

## 2026-09-29 SE-411 APPROVED

Aprobada por la operadora para implementar.

## 2026-09-29 SE-411 PROPOSED

Eficiencia de Savia RAG: cinco defectos medidos (fusión entre cúpulas dependiente
del orden, caché de índices menor que las cúpulas habilitadas, descarga del modelo,
respuesta inflada y arranque en frío de la CLI). Pendiente de aprobación.

## 2026-09-29 SE-410 APPROVED

Savia RAG: búsqueda híbrida paralela en SaviaVaults (MCP + CLI) y política dinámica
de embeddings. Aprobada por la operadora; se implementa en una PR sin ocupar WIP.

## 2026-09-29 SE-407 APPROVED IMPLEMENTING

Entra en el WIP sustituyendo a SE-378 (decisión de la operadora, repriorización por valor).

## 2026-09-29 SE-378 IMPLEMENTING DEFERRED

Sale del WIP a favor de SE-407. Lo mergeado permanece; retoma en la Fase A.

## 2026-09-29 SE-409 PROPOSED

Bucle experiencia → skill con curación y retirada (referencia: hermes-agent;
análisis no verificado, S0 lee la fuente). Fase D, P3.

## 2026-09-29 SE-408 PROPOSED

Automatización móvil por árbol de accesibilidad (mobile-mcp) con telemetría
desactivada verificada, versión fijada y herramientas de nube denegadas. Fase E, P2.

## 2026-09-29 SE-407 APPROVED

Predicado único de estado consistente (frescura de artefactos generados en
validate-ci-local.sh) y cierre de sesión limpio. Fase A, P0. Aprobada por la
operadora; sustituirá a SE-378 en el WIP.

## 2026-09-27 SE-406 PROPOSED

Savia Relay: canal activo con la operadora por WhatsApp. Propuesta para revisión
(decisiones D1-D8 abiertas); nada se implementa hasta su aprobación.

## 2026-09-27 SE-405 APPROVED

Coste por subagente en el ledger de runs, snapshots de configuración y timeline
de memoria (P5-P7 de output/research/harness-mejoras-20260927.md).

## 2026-09-27 SE-404 APPROVED

G13 v2 (specs en docs/specs, formatos de AC, globs, Fix-trace) y una corrección
por revisión en el Court (P3-P4). Riesgo L3: revisión explícita del PR.

## 2026-09-27 SE-403 APPROVED

Trazas crudas, frontera y hash de selección para el runner de SE-384 (P1).

## 2026-09-27 SE-402 APPROVED

Registro de ediciones atribuidas y gate advisory G19 (P2). Aprobación de la
operadora: "Redacta todas las specs que necesites y adelante con todas las
propuestas en sprint nocturno".

## 2026-09-27 SE-376 IMPLEMENTING

Reapertura de deuda (decisión de la operadora). El wave 1 de #1097 declaró
"deuda 133→48, objetivo cumplido" creando 121 tests de presencia (score 23 en el
auditor, fallidos desde su creación por un patrón anclado) y marcando 130 skills
`stable` sin evidencia; el wave 2 (#1100) añadió 5 más del mismo tipo que
afirmaban un estado no alcanzado. Calibrated exige ahora test certificado (>=80).
Deuda real 128/137 (125/134 antes de las 3 skills GRC de #1142); presupuesto vuelve a wave 0 (baseline 133). Se retiran los
126 tests de presencia.

## 2026-09-26 SE-375 IMPLEMENTED

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: PR #1083 (S1); S2 rule/hook kinds y vistas derivadas pendientes

## 2026-09-26 SE-376 IMPLEMENTING

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: PRs #1097 y #1100: waves 1-2 redujeron deuda 133→48; objetivo final 0 o excepciones aprobadas permanece pendiente. Fase ADR-002: A.

## 2026-09-26 SE-377 DEFERRED

ADR-002: aplazada a fase C; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-378 IMPLEMENTING

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: PR #1085: planning-state canónico, CLI roadmap y vista generada mergeados; reconciliación factual continua pendiente. Fase ADR-002: A.

## 2026-09-26 SE-379 IMPLEMENTED

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: PR #1082

## 2026-09-26 SE-380 DEFERRED

ADR-002: aplazada a fase D; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-381 DEFERRED

ADR-002: aplazada a fase C; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-383 DEFERRED

ADR-002: aplazada a fase C; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-384 DEFERRED

ADR-002: aplazada a fase C; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-385 DEFERRED

ADR-002: aplazada a aparcado (tras Gate D); lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-386 DEFERRED

ADR-002: aplazada a fase B; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-387 DEFERRED

ADR-002: aplazada a fase C; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-388 DEFERRED

ADR-002: aplazada a fase D; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-389 DEFERRED

ADR-002: aplazada a aparcado (tras Gate D); lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-390 DEFERRED

ADR-002: aplazada a fase E; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-391 DEFERRED

ADR-002: aplazada a fase D; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-392 APPROVED

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: Spec persistida; equivalencia funcional y E2E aún no demostradas. Fase ADR-002: D.

## 2026-09-26 SE-393 DEFERRED

ADR-002: aplazada a fase B; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-394 DEFERRED

ADR-002: aplazada a fase B; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-395 APPROVED

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: PR #1122: aislamiento de grafo por dome. PR #1131: V02 de cache por principal/policy/contenido, provenance y límites mergeada con 349 tests SaviaVaults. Experimento adaptativo permanece pendiente. Fase ADR-002: E.

## 2026-09-26 SE-396 IMPLEMENTING

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: PRs #1112/#1113/#1122/#1129/#1130/#1131/#1132/#1133/#1135 mergeadas. H02/H10/A01b/A01c: autoridad previa al executor, composición aislada y sustitución operacional Codex/OpenCode. Auditoría AC local: docs/evidence/SE-396-closure-review-20260924.md; 127 tests dual-cli, 18 de planificación y gate canónico previo 6/6. Doctor nativo permanece DEGRADED_SAFE; recibo A01c requiere revisión de procedencia. Fase ADR-002: B.

## 2026-09-26 SE-397 DEFERRED

ADR-002: aplazada a fase D; lo mergeado permanece. Transición aplicada en PR #1140 sin registro en LOG.md; se registra ahora (SE-378).

## 2026-09-26 SE-398 APPROVED

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: docs/specs/SE-398-f0-desktop-runtime-discovery.md. Fase ADR-002: E.

## 2026-09-26 SE-399 APPROVED

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: docs/specs/SE-399-f0-installer-discovery.md. Fase ADR-002: E.

## 2026-09-26 SE-400 APPROVED

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: docs/specs/SE-400-f0-model-agnostic-ablation-inventory.md. Fase ADR-002: D.

## 2026-09-26 SE-401 PROPOSED

Backfill SE-378: estado vigente en planning-state; la transición original no se registró en LOG.md. Evidencia: docs/specs/SE-401-intent-to-effect-execution-architecture.spec.md. Fase ADR-002: B.

## 2026-09-19 SE-397 F5A IMPLEMENTED_PENDING_HUMAN_REVIEW

Fast exit implementado con oracle 13/13, p50 local `49 -> 6` ms y p95
`50 -> 7` ms. Entradas ambiguas, relevantes y coincidencias históricas
embebidas conservan la ruta completa. 26 BATS, 38 unit y 9 SAM BATS verdes;
sin cambios de reglas, settings, authority ni SLO. Merge pendiente de revisión.

## 2026-09-19 SE-397 F5A APPROVED

Aprobada explícitamente la revisión `0024781c`. Autoriza caracterización,
benchmark local y fast exit solo bajo paridad completa y umbrales GO/NO_GO; no
autoriza merge, publicación, cambios de authority ni el resto de F5.

## 2026-09-19 SE-397 F5A PROPOSED

Propuesto fast exit por relevancia para `validate-bash-global.sh`, condicionado
a paridad completa del corpus y mejora p50 mínima del 30%. La evidencia local
sitúa gobernanza en 52 de 54 ms de SAFE_BASH. Sin cambio de reglas, settings,
authority ni SLO; el resto de F5 y F6–F10 permanece pendiente.

## 2026-09-19 SE-397 F4 MERGED

Operational Trace integrado en `main` mediante PR #1127. SAM/SCM frescos,
observaciones report-only y sin elevación de authority.

## 2026-09-19 SE-397 F4 IMPLEMENTED_PENDING_HUMAN_REVIEW

Implementado Operational Trace local y report-only: eventos cerrados,
proyección determinista, gaps explícitos, correlación opcional de receipts y
baseline READ/SAFE_BASH controlado. 17 unit + 26 BATS verdes; SAM/SCM frescos.
Sin SLO, export, enforcement, instrumentación nativa ni elevación de authority.
F5–F10 permanecen pendientes.

## 2026-09-16 SE-397 F4 PROPOSED

Propuesto Operational Trace local y report-only: observaciones separadas del
SAM, paths formados solo por nodos existentes, gaps explícitos y baseline
end-to-end controlado para reconciliar SE-037. Sin instrumentación nativa de
frontends, SLO, optimización, export, enforcement ni elevación de authority.

## 2026-09-16 SE-397 F3 IMPLEMENTED_PENDING_HUMAN_REVIEW

Implementada la verificación arquitectónica report-only: drift declarado vs
descubierto con bindings explícitos, claim/evidence con gaps visibles e impacto
de grafo acotado. Se corrigió además la provenance inestable tras squash/rebase.
21 unit + 7 BATS verdes; sin inferencia semántica, enforcement ni elevación de
authority. F4–F10 permanecen pendientes.

## 2026-09-14 SE-397 F2 IMPLEMENTED_PENDING_HUMAN_REVIEW

Implementado el Runtime & Authority Model declarado y report-only: seis flujos,
efectos, riesgos, autoridad de ejecución delegada, gates humanos y estados de
fallo bajo schema SAM v2. 17 unit + 6 BATS verdes; sin enforcement, decisiones,
receipts ni observación runtime. F3–F10 permanecen pendientes.

## 2026-09-13 SE-397 F1 IMPLEMENTED_PENDING_HUMAN_REVIEW

Implementado el SAM mínimo read-only: contrato y schema cerrados, declaraciones
por referencia, proyección determinista sobre el capability registry y vistas
foundation/capabilities/structural report-only. 11 unit + 5 BATS verdes. No
modela runtime ni gradúa evidencia/authority; F2–F10 permanecen pendientes.

## 2026-09-10 SE-400 PROPOSED→APPROVED; F0 READY_FOR_HUMAN_REVIEW

La operadora ordena añadir SE-400 al roadmap e implementarla. Su instrucción
inmediata limita el trabajo a un inventario model-agnostic F0: sin delete,
move, deprecation, pack migration ni F1. Las clasificaciones son provisionales
y no autorizan retirada física.

## 2026-09-10 SE-398/SE-399 PROPOSED→APPROVED; F0 READY_FOR_HUMAN_REVIEW

La operadora ordena persistir e implementar ambas specs. Su instrucción
inmediata limita la ejecución a F0: se completaron la reconciliación de
runtimes/surfaces Desktop y el inventario del instalador. SAM continúa sin F1,
ninguna Desktop se declara SUPPORTED y no se implementó engine, GUI ni adapter.

## 2026-09-09 SE-397 F0 APPROVED_WITH_CONCERNS
La operadora aprueba F0 y el trabajo pendiente. F1–F10 quedan autorizadas con
sus gates de fase; `.scm/` será la proyección inicial, SQLite seguirá siendo
cache y drift/impact permanecen report-only. Sin elevación de authority.

## 2026-09-08 SE-397 PROPOSED→APPROVED
Savia Architectural Self-Knowledge & Operational Excellence. Aprobación humana
explícita; ejecución inmediata limitada a F0 (reconciliación report-only).
F1–F10 conservan gate humano tras revisar el informe F0.

## 2026-09-01 SE-365 APPROVED→IMPLEMENTED
Company as Code (renumerado de SE-265, que colisionaba con court-model-tiers):
estándar de entidades organizacionales como código. org-registrar.py valida
(frontmatter común, vocabulario de relaciones cerrado, consistencia referencial,
origin/source SE-352), indexa el grafo company/projects/resources, propone con
escritura mediada. Skill org-registrar + grafo piloto (5 entidades). 6 pytest + 5 bats.

## 2026-08-31 SE-359 APPROVED→IMPLEMENTED
REVIEW.md policy (origen Anthropic playbook Stage 5): passes canónicos, vocab
cerrado Important|Nit, cap 5 nits, exclusiones; review-policy-parse.py. 7 pytest + 7 bats.

## 2026-08-31 SE-364 APPROVED→IMPLEMENTED
Bucle de evidencia (origen Anthropic playbook): evidence-capture.py captura
intervenciones/rechazos de ledgers locales → corpus de evals discriminantes
(filtro N3/N3b/N4b), evidence-capture.sh integra con runner SPEC-151.
5 pytest + 4 bats verdes.

## 2026-08-31 SE-363 APPROVED→IMPLEMENTED
Registros-no-archivos (origen Anthropic playbook): governance-sync.py extrae CRIT
de CRITERIO.md a registro JSONL consultable (estado/aprobación), governance-query.sh.
Markdown = vista, registro = dato. 5 pytest + 5 bats verdes.

## 2026-08-31 SE-362 APPROVED→IMPLEMENTED
Risk Tiering (origen Anthropic playbook gobernanza ejecutable + modelo Amplitude):
risk-tier.py clasifica cambios T1-T4, push-pr --merge consulta el tier (T3/T4
bloqueado sin review humana aun con grant), doc risk-tiering.md. 7 pytest + 5 bats.

## 2026-08-31 SE-361 APPROVED→IMPLEMENTED
Presupuesto de tiempo de CI (origen Anthropic playbook): ci-duration-agg.py mide
duración por job (p50/p95), detecta over-budget 5min; ci-duration.sh.
Alimenta etapa ci de SE-360. 5 pytest + 4 bats verdes.

## 2026-08-31 SE-360 APPROVED→IMPLEMENTED
Costo por cambio aceptado (origen Anthropic playbook): acceptance-cost-agg.py
descompone time-to-acceptance por etapa desde ledgers locales (SE-349/355),
p50/p95 + bottleneck; acceptance-cost.sh. 6 pytest + 3 bats verdes.

## 2026-08-31 SE-358 APPROVED→IMPLEMENTED
plan.md verificado (origen Anthropic playbook Stage 3/5): plan-validate.py +
plan-diff-check.sh (sync plan↔diff, warn/block). 11 bats verdes.

## 2026-08-31 SE-357 APPROVED→IMPLEMENTED
Control Bands autónomas (origen Anthropic AI-Native SDLC Playbook Stage 6):
detección determinista sin LLM + tiers σ (1σ log, 2σ diagnose, 3σ propose),
control-bands.yaml, historial local, intent/ como re-entrada al pipeline.
12 bats verdes.

## 2026-08-31 SE-356 APPROVED→IMPLEMENTED
Skills Two-Layers (origen OpenClaw VISION): layer core/peripheral en 132 SKILL.md
(peripheral por defecto), skills-registry/INDEX.json + REVIEW.md (criterios de
promoción), skill-layer-check.sh. 8 bats verdes.

## 2026-08-31 SE-355 APPROVED→IMPLEMENTED
Audit Ledger metadata-only + decision receipts (origen OpenClaw 2.0):
audit-receipts.sh con vocabulario cerrado, enforced solo si gate gobernó,
ledger local data/audit sin prompts/PII, retention 30d batch, non-claims doc.
12 bats verdes.

## 2026-08-31 SE-352 APPROVED→IMPLEMENTED
Trust-Gated Memory (origen OpenClaw 2.0): origin class owner/agent/untrusted/system
en memory-store, taint de turno vía hook memory-origin-gate.sh, consolidación que
excluye untrusted/system, filtro search --min-origin, audit-origins. 15 bats verdes.

## 2026-08-31 SE-220 IMPLEMENTED
Speculative Tool Execution — S0 feasibility (PROCEED, acceptance_rate=1.00) + Slices 1-4.
Implementado en PR #874 (2026-06-26): predictor heurístico (`speculative-tool-predictor.py`),
orquestador (`speculative-tool-execution.py`), cache con flock+TTL 30s (`speculative-cache-manager.py`),
telemetría JSONL + dashboard (`speculative-telemetry-report.sh`), hooks pre-execute (S2) y
skill-preload (S3) registrados. 39 pytest + 35 bats verdes.

## 2026-06-24 SPEC-182 IMPLEMENTED
Bi-temporal timeline frontmatter on specs and decisions
SPEC-182 implementado: spec-timeline-append.py + spec-timeline-query.py + lifecycle --no-timeline + 10 back-fills + 21 tests

## 2026-06-23 SE-222 PROPOSED (S0 IMPLEMENTED)
OKF Adoptable Patterns — resource: URI + log.md + index.md.
S0 (resource: URI validator + 5 specs back-filled) implementado en PR #850.

## 2026-06-23 SE-220 PROPOSED
Speculative Tool Execution — draft+verify pattern (S0 feasibility BLOQUEANTE).

## 2026-06-23 LOG.md created (SE-222 S1)
Bootstrap entry — fichero creado a partir de este punto.
Nuevas transiciones se añaden al top.
