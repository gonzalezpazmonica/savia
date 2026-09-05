---
layer: peripheral
name: project-update
description: Usar cuando se necesita una actualización integral del proyecto activo desde todas las fuentes.
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, Task]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.argument-hint: "--slug {codename} [--only {refresh|digest}] [--skip {source}] [--skip-auth] [--dry-run]"
  savia.maturity: stable
  savia.category: pm-operations
  savia.context: "Activar cuando el PM pide \"actualizar proyecto\", \"refrescar contexto\", \"digerir información\", \"pon al día\", \"update completo\"."
  savia.context_cost: low
  savia.max_context_tokens: 8000
  savia.output_max_tokens: 3000
  savia.priority: high
---

**Última actualización**: 2026-04-29

# /project-update — Procedimiento formal

Procedimiento determinista, paralelo, reutilizable. Implementación: `scripts/project-update.py`.

## Principios inmutables

1. **F1 es 100% determinista** — subprocesos Python paralelos, NO agentes LLM.
2. **Agentes solo para digerir y consolidar** (F2 meeting-digest, F3 análisis cruzado).
3. **Confidencialidad por capa**:
   - Nombres reales: `~/.azure/`, `~/.savia/`, `projects/{slug}_main/` (gitignored).
   - Codenames: cualquier sitio (incluye repo público).
   - Outputs intermedios: `~/.savia/project-update-tmp/{slug}/` (N4, nunca a git).
4. **Reutilización**: cada source es un script existente; orquestador = despacho + agregación.
5. **Read-only en sistemas externos** (DevOps, Outlook, Teams, SharePoint, OneDrive).
6. **Time-boxing**: cada job tiene timeout. F1 entera < 15 min.

## Configuración (fuera del repo)

```
~/.azure/
  ├── <real-name>-pat                      # PAT Azure DevOps
  └── projects/<real-project-name>.json    # {_codename, org, project, iteration, pat_file}

~/.savia/
  ├── mail-accounts.json                   # por cuenta: tenant, email, drive_id, ...
  ├── project-update-tmp/{slug}/           # outputs intermedios (efímero)
  ├── captured-vtt/{account}/              # VTTs descargados/extraídos
  └── pm-radar/state.json                  # historial runs
```

Si `~/.azure/projects/` tiene 1 fichero, auto-elige. Si varios, busca por `_codename == slug`.

**Path resolution sin leaks**: scripts F2/F3/F4 leen documents root vía `scripts/savia_paths.py`. Order: `$SAVIA_DOCS_ROOT` → `~/.savia/savia-paths.json` → `ConfigError`. Ningún script bajo `scripts/` debe contener nombres de organización ni rutas personales. Test: `tests/scripts/test_project-update-confidentiality.py`.

## Invocación

```bash
python scripts/project-update.py --slug "{codename}"                  # completo
python scripts/project-update.py --slug "{codename}" --only refresh   # F1
python scripts/project-update.py --slug "{codename}" --only digest    # F2 (VTTs ya capturados)
python scripts/project-update.py --slug "{codename}" --skip teams-transcripts
python scripts/project-update.py --slug "{codename}" --dry-run        # plan-only
python scripts/project-update.py --slug "{codename}" --skip-auth      # daemons ya auth
```

## Pipeline

### F0 — Auth gate (graceful, per-source)

`scripts/ensure-daemons-auth.sh` re-auth si caducó. `probe_auth_per_account()` parsea `check-daemon-auth.sh` JSON. Cuentas con `status != running` → `account_skip` solo en jobs **CDP-dependent** (`sp-recordings`, `onedrive`, `teams-transcripts`); **saved-session** (`mail`, `calendar`, `teams-chats`) se intentan igual. NO aborta. Bypass: `--skip-auth` o `--dry-run`.

### F1 — Refresh paralelo (ThreadPoolExecutor, 8 workers)

| Job | Script | Timeout | Cuántos |
|---|---|---|---|
| `devops` | `scripts/project-update-devops.sh` | 240s | 1 (slug) |
| `mail-{account}` | `scripts/inbox-check.py` | 90s | × cuentas |
| `calendar-{account}` | `scripts/calendar_72h.py` | 90s | × cuentas |
| `teams-chats-{account}` | `scripts/teams-check.py` | 90s | × cuentas |
| `sp-recordings-{account}` | `scripts/sp-recordings.py --action list` | 120s | × cuentas |
| `onedrive-{account}` | `scripts/onedrive_recent.py` | 120s | × cuentas |
| `teams-transcripts-{account}` | `scripts/extract-teams-transcripts.py --batch` | 900s | × cuentas |

Outputs a `~/.savia/project-update-tmp/{slug}/` o `~/.savia/captured-vtt/{account}/`. Orquestador captura `rc + elapsed_s + stderr_tail + stdout_preview` por job.

### F2 — Digestión

| Paso | Script | Naturaleza |
|---|---|---|
| Transcript → MD esqueleto | `scripts/meetings_auto_digest.py` | **Determinista básico**. Ingiere `**/*.vtt` + `**/*.transcript.txt` recursivo. Genera digest mínimo: speakers, total_lines, preview, tail. NO invoca agente meeting-digest. |

Salida: `projects/{slug}_main/{slug}-{username}/meetings/YYYYMMDD-{titulo}.md`.

El digest determinista NO sustituye al agente `meeting-digest`. Workflow:
1. F2 genera esqueleto + recordatorio "Source file: X".
2. PM revisa y para reuniones críticas invoca: `Task(meeting-digest, source=<file>)`.
3. Digest enriquecido sobreescribe el esqueleto.

### F3 — Análisis determinista

`scripts/project-update-analyze.py` — pure Python, sin LLM. Lee F1 + F2. Produce radar consolidado:

- `## Sources status` — auth + counts por fuente
- `## DevOps snapshot` — raw md
- `## Calendario 72h` — eventos por día
- `## Reuniones digeridas` — counts action items / decisiones
- `## Action items abiertos (consolidado)` — checkbox items vía regex agrupados

Idempotente. Salida: `projects/{slug}_main/{slug}-{username}/reports/radar/YYYYMMDD-HHMM-radar.md`.

### F4 — Sync determinista (PENDING.md auto-update)

`scripts/project-update-sync.py` — lee radar más reciente, append action items a `PENDING.md` bajo `## Acciones esta semana`. Dedup case-folded — idempotente. Actualiza `**Última actualización**`.

## Confidencialidad por carpeta

| Path | Nivel | Contenido | Origin push |
|---|---|---|---|
| `projects/{slug}_main/{slug}-{username}/` | N3 | reports, briefings, meetings, decisions | NO |
| `projects/{slug}_main/digests/` | N3 | digests email/teams/attachments | NO |
| `projects/{slug}_main/{slug}-pm/` | N3 | members, capacity, sprint-analysis | NO |
| `~/.savia/project-update-tmp/` | N4 | outputs efímeros | nunca |
| `~/.savia/captured-vtt/` | N4 | transcripts originales | nunca |
| `~/.azure/`, `~/.savia/mail-accounts.json` | N4b | PATs, tenant URLs | nunca |
| `scripts/`, `.opencode/skills/` | N1 público | código + procedimientos (codenames OK) | sí |

## Anti-patrones

- Lanzar agentes LLM por source en F1.
- Hardcodear nombres reales en `scripts/` o `.claude/`.
- Usar `sharepoint_transcripts.py` (deprecated). Usar `sp-recordings.py`.
- Pushear a `origin` contenido de `projects/`.
- Confiar en que el Shield desenmascara args de tool-call.

## Roadmap pendiente

1. F4 sync con Gitea machine-local.
2. Wrappers idénticos a `project-update-devops.sh` si firma de algún script cambia.
3. Fix proxy Shield: unmask de tool-args.
