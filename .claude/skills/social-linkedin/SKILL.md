---
layer: peripheral
name: social-linkedin
description: "Importa el export oficial de LinkedIn y genera digests locales (temas, historia, estilo). Usar cuando haya que analizar la actividad propia en LinkedIn; nunca publica."
---

# LinkedIn Provider Skill (MVP1 — read/import)

## Estado de capabilities (permission discovery, §43)

| Capability | Estado MVP1 | Origen del dato |
|---|---|---|
| read_profile | UNKNOWN | requiere API product aprobado |
| import_portability | REQUIRES_APPROVAL | EEA/CH + producto DMA (probe 2026-09-05) |
| import_manual | SUPPORTED | export ZIP oficial del propio miembro |
| read_posts | UNKNOWN vía API; SUPPORTED vía export | Snapshot API pendiente de producto |
| draft_local | SUPPORTED (fase 2) | local |
| publish_post | NOT_GRANTED | ninguna API product concede publish en MVP1 |
| edit/delete_post | NOT_GRANTED | gate independiente pendiente (L4) |
| analytics | NOT_AVAILABLE | fuera de MVP |

Error ante capability no concedida: `LINKEDIN_PERMISSION_NOT_GRANTED`.

## Uso

```bash
# Importar export oficial (ZIP descargado por la operadora)
python3 scripts/social-linkedin-import.py --zip ~/Downloads/linkedin-export.zip

# Status (capabilities + almacén local)
python3 scripts/social-linkedin-status.py

# Digests locales (themes, savia-history, writing-style)
python3 scripts/social-linkedin-digest.py
```

Almacén: `~/.savia/social/linkedin/{raw/,normalized/,derived/,receipts/,manifest.json}`.
Los tres scripts aceptan `SOCIAL_STORE=<dir>` para redirigirlo (tests, perfiles
aislados); `import` admite además `--store <dir>`, que tiene prioridad.

### Qué lee el import

| Fichero en el ZIP (nombre base, sin distinguir mayúsculas) | artifact_type | Texto | authored |
|---|---|---|---|
| `Shares.csv`, `Shares_<id>.csv` (export completo), `Share.csv` (legado) | post | `ShareCommentary` (+ `ShareMediaDescription`) | SELF_AUTHORED |
| `Articles.csv`, `Articles_<id>.csv` | article | `ArticleTitle` + `ArticleDescription` | SELF_AUTHORED |
| `Comments.csv`, `Comments_<id>.csv` | comment | `Message` (o `Comment`) | MIXED |

- CSV en UTF-8 con o sin BOM; campos con comas, comillas `""`, saltos de
  línea (se normalizan a `\n`) y campos de más de 128 KiB. `Comments.csv`
  usa comillas escapadas con `\"` como la exportación real.
- Filas sin texto (reposts sin comentario) se omiten.
- El ZIP nunca se extrae a disco: los CSV se leen en memoria por nombre
  base, así que entradas con rutas `../` (zip-slip) no escriben nada.
- Contactos (`Connections.csv`), mensajes (`messages.csv`) y el resto del
  export NO se normalizan.

### Exit codes del import

| Código | Significado |
|---|---|
| 0 | import correcto (también con 0 artefactos creados) |
| 1 | ZIP inexistente o no válido (error en stderr; no se escribe nada) |
| 2 | uso incorrecto, o almacén dentro de un repositorio git (rechazado) |

`manifest.json` y `receipts/import-<sha12>.json` son JSON. Un `manifest.json`
corrupto se aparta como `manifest.json.corrupt-<fecha>` con aviso en stderr.

## Garantías MVP1

- Provenance obligatoria por artefacto (provider, acquisition=manual_export,
  acquired_at, source_file, source_hash) — sin tokens jamás.
- Dedupe por hash de (provider_id + texto); provider_id es la URL
  (`ShareLink`/`Link`) o, si falta, el hash del texto. Reimportar el mismo
  export crea 0 artefactos (idempotente). Un post editado (misma URL, texto
  distinto) se importa como artefacto nuevo: el anterior no se sustituye.
  Cada import añade una entrada a `manifest.json.exports` aunque sea repetido.
- PII de terceros: la copia `raw/export-<sha12>.zip` es el export completo
  (contactos, mensajes). El almacén se crea con permisos 0700 y la copia raw
  con 0600; el import se niega (exit 2) si el almacén cae dentro de un
  repositorio git, para que nada de esto acabe en ficheros versionables.
- origin=untrusted: el contenido importado jamás se ejecuta ni promueve a
  memoria confiable sin trust-gate (memory-origin-gate).
- Solo SELF_AUTHORED alimenta writing-style.
- Posts NUNCA se inyectan completos en contexto: progressive disclosure
  (L0 índice → L1 digest → L2 fragmentos → L3 completo bajo demanda).
- Retention metadata por artefacto (manual_user_export: user_owned_source).
- Documentación pin: portability docs verificadas 2026-09-05
  (view li-dma-data-portability-2026-08, ms.date 2026-04-07). Revisar en
  `/social linkedin compliance-check` (próxima fase) o al implementar MVP2.

## Fuera de alcance MVP1

OAuth programático (el producto DMA usa OAuth Token Generator manual, solo
EEA/CH), publish/edit/delete, analytics, scraping (prohibido §40/41 SE-385).
