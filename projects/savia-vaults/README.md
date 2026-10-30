# SaviaVaults — Context Dome Server (MCP + A2A)

> **Status (2026-08-01): v0.2.0 — servidores reales.** 9-tool MCP server funcional, A2A HTTP REST server, backups con Nextcloud, firma Ed25519. 89 tests en verde.

[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)
[![Node.js](https://img.shields.io/badge/Node.js-22%2B-green.svg)](https://nodejs.org)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.7%2B-blue.svg)](https://www.typescriptlang.org)
[![Status](https://img.shields.io/badge/status-in--progress-yellow.svg)](.)

SaviaVaults da a agentes de IA acceso a cupulas de contexto locales: repositorios versionados, buscables y firmados de conocimiento, expuestos via protocolos estandar (MCP + A2A) con cero dependencia de nube.

---

## Que funciona hoy (2026-08-01)

Servidores MCP y A2A reales, backups locales y Nextcloud, firma Ed25519, CLI completa.

| Modulo | Estado |
|---|---|
| MCP Server (9 tools, stdio) | Funcional |
| A2A Server (5 endpoints HTTP) | Funcional |
| Storage (git-backed CRUD) | Funcional |
| Search (BM25, minisearch) | Funcional |
| **Savia RAG** (híbrido BM25 + embeddings, fan-out paralelo, SE-410) | Funcional |
| Security (6-layer sandbox) | Funcional |
| Backups (tar.gz + Nextcloud) | Funcional |
| Federation (8 modulos) | Funcional |
| CLI (12+ comandos) | Funcional |
| Ed25519 signing | Funcional |

## Savia RAG (SE-410)

Recuperación híbrida sobre una o varias cúpulas en paralelo, por MCP y CLI.
Chunks markdown por encabezados, embeddings locales vía Ollama, BM25 sobre chunks,
fusión RRF y política de frescura explícita. Sin dependencias npm nuevas.

```bash
# Activar por cúpula en savia-vaults.domes.json:
#   "rag": { "enabled": true, "model": "qwen3-embedding:0.6b", "evalSet": "rag/eval.json" }
ollama pull qwen3-embedding:0.6b
savia-vaults rag sync --all                           # incremental por hash
savia-vaults rag search "cómo evito merges sin permiso" "política de backups" --domes all
savia-vaults rag status --check                       # SLO: exit 2 si el índice va por detrás
savia-vaults rag eval --dome savia-docs               # recall@5/@10, MRR, p50/p95
savia-vaults rag promote|rollback|gc ...
```

MCP: `vault_rag` (hasta 8 consultas × N cúpulas en una llamada; respuesta `lean`
compacta de ≤ `maxChars`, def. 6000), `vault_rag_status`, `vault_rag_sync`.
Variables: `SAVIA_RAG_HOME`, `SAVIA_RAG_MODEL`, `SAVIA_OLLAMA_URL`,
`SAVIA_RAG_KEEP_ALIVE` (def. `30m`), `SAVIA_RAG_MEMORY_MB` (def. 512).
`vault_search` indexa solo markdown; la CLI cachea su índice en
`SAVIA_SEARCH_CACHE` (def. `~/.savia-vaults/search-cache/`). Cada cúpula se autoriza por separado; las denegadas aparecen
como `denied`; `"*"` nunca incluye N4; las notas con confidencialidad superior a
su cúpula no se embeben.

| Banco (savia-docs, 36 consultas es) | recall@10 | MRR |
|---|---|---|
| `vault_search` (BM25 por documento) | 0,347 | 0,251 |
| `rag` bm25 por chunk | 0,639 | 0,479 |
| `rag` dense (qwen3-embedding:0.6b) | 0,736 | 0,563 |
| **`rag` hybrid (qwen3-embedding:0.6b)** | **0,806** | **0,566** |

Política de embeddings (contrato por generación, re-embedding por hash,
disparadores, deriva de modelo, gate de promoción, SLO):
[`docs/rules/domain/rag-embedding-policy.md`](../../docs/rules/domain/rag-embedding-policy.md).
El índice vive fuera del vault en `$SAVIA_RAG_HOME` (def. `~/.savia-vaults/rag/`).

RAG autónomo (SE-480): el MCP y A2A releen el registro de cúpulas al cambiar, y `serve --transport a2a --rag-autosync <min>` sincroniza el índice solo. Detalle e instalación de la unidad systemd: [`docs/rag.md`](docs/rag.md).

## Savia Files (SE-413)

Ficheros originales (PDF, DOCX, PPTX, XLSX, TXT, MD, CSV, JSON) en la cúpula,
inmutables y verificados por SHA-256, con el texto extraído por página,
diapositiva, elemento o celda y consultable en `vault_rag` con cita.
Desactivado por defecto: `"files": { "enabled": true, "scan": "auto" }` en la cúpula.

```bash
savia-vaults files add contrato.pdf presupuesto.xlsx --dome proyectos
savia-vaults files text f_3c… --dome proyectos          # [p. 2] Cláusula 7…
savia-vaults rag search "penalización por retraso" --domes proyectos
savia-vaults files rm f_3c… --dome proyectos            # borrado real
```

MCP: `vault_files` (`put|list|get|text|download|delete|reprocess|status|setup`).
Dependencias (lector de documentos y antivirus ClamAV) sin consola ni administrador:
`savia-vaults files setup`, o Savia desde el chat; solo Linux x86_64 por ahora. PDF/DOCX/PPTX
usan Docling sin OCR y XLSX usa openpyxl, en un worker Python aislado
(`workers/files/`). Si falta el worker, esos formatos quedan `ARCHIVE_ONLY`. El
escaneo con ClamAV es opcional. El almacén vive fuera de git en `$SAVIA_FILES_HOME`
(def. `~/.savia-vaults/files/`). Guía completa: [`docs/files.md`](docs/files.md).

## Alcance de Gobernanza

SaviaVaults es un **servidor de contexto**, no un agente soberano. No implementa la constitucion ni el criterio de Savia. Expone cupulas de contexto via protocolos estandar para que cualquier agente (Savia o externo) pueda consumirlas sin adoptar la plataforma.

El servidor respeta niveles de confidencialidad (N1-N4) en el frontmatter de los documentos y filtra por nivel maximo declarado al arrancar. Para verificacion de gobierno completo, la herramienta produce recibos verificables por terceros sin dependencia del ecosistema Savia.

Lee el [modelo de amenaza](docs/threat-model.md) para entender que se protege y que NO. Las garantias de seguridad se detallan en `docs/threat-model.md`.

## Quick Start

```bash
npm install -g savia-vaults
savia-vaults init my-knowledge
savia-vaults serve --transport mcp --path vaults/my-knowledge
savia-vaults search "architecture" --path vaults/my-knowledge
savia-vaults backup create --path vaults/my-knowledge
```

### Registro local de cúpulas

`savia-vaults.domes.json` es local y está en `.gitignore`: guarda rutas de tu
máquina y nombres de tus cúpulas, así que nunca se versiona. Créalo copiando el
ejemplo y ajusta rutas y nombres:

```bash
cp savia-vaults.domes.example.json savia-vaults.domes.json
bash seed-example-context.sh            # opcional: puebla vaults/example-context
savia-vaults dome create mi-cupula      # añade cúpulas al registro local
savia-vaults serve --transport mcp --domes savia-vaults.domes.json
```

Las rutas relativas se resuelven contra el directorio del propio registro.

Junto al registro base se lee un **registro local** (`savia-vaults.domes.local.json`, también ignorado por
git), que es donde escribe Savia Space al crear cúpulas (SE-436 D30-2). Se fusionan; con el mismo nombre
gana el local, y `dome create` y `setDefault` devuelven cada cúpula al fichero de donde salió. Sirve con solo
el local, sin fichero base.
`dome create` escribe en ese registro local, indica la ruta y se niega si el
fichero está versionado en git.

## Development

```bash
git clone https://github.com/gonzalezpazmonica/savia-vaults.git
cd savia-vaults
npm install
npm run build              # compila solo lo que existe (federation + config)
npm test                   # 7 tests unitarios pasan; 7 importan modulos en construccion
npm run test:coverage
```

## License

MIT. See [LICENSE](LICENSE).

---

*Parte del ecosistema Savia — [pm-workspace](https://github.com/gonzalezpazmonica/pm-workspace)*
