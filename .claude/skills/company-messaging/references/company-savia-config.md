# Regla: Configuración Company Savia — Arquitectura Git v3
# ── Repositorio compartido, mensajería async, cifrado E2E (branch-based) ─────

> Esta regla se carga bajo demanda con los comandos `company-repo`, `savia-*`, `savia-branch-*`.

```
# ── Company Repository (Git Branch-Based) ────────────────────────────────────
COMPANY_REPO_ENABLED        = true                                # Feature flag
COMPANY_REPO_CONFIG_FILE    = "$HOME/.pm-workspace/company-repo"  # Config local
COMPANY_REPO_LOCAL_PATH     = "$HOME/.pm-workspace/company-savia" # Clon local
COMPANY_REPO_AUTO_SYNC      = false                               # Auto-sync al inicio

# ── Branch Architecture (v3) ─────────────────────────────────────────────────
COMPANY_MAIN_BRANCH         = "main"                              # Admin-only, pubkeys, .savia-index/
COMPANY_USER_BRANCH_PREFIX  = "user/"                             # user/{handle} branches
COMPANY_TEAM_BRANCH_PREFIX  = "team/"                             # team/{name} branches
COMPANY_EXCHANGE_BRANCH     = "exchange"                          # pub/sub messaging, pending
COMPANY_BRANCH_CONFIG       = "orphan"                            # Branches are orphan (no parent)

# ── User Identity ────────────────────────────────────────────────────────────
COMPANY_USER_HANDLE         = ""                                  # @handle del usuario
COMPANY_USER_ROLE           = "Member"                            # Admin | Member

# ── Encryption ───────────────────────────────────────────────────────────────
COMPANY_ENCRYPTION_ENABLED  = true                                # Permitir cifrado E2E
COMPANY_KEYS_DIR            = "$HOME/.pm-workspace/savia-keys"    # Keypair RSA-4096
COMPANY_KEY_ALGORITHM       = "RSA-4096"                          # Algoritmo de clave
COMPANY_CIPHER              = "AES-256-CBC"                       # Cifrado simétrico
COMPANY_PBKDF2_ITER         = 10000                               # Iteraciones PBKDF2

# ── Privacy ──────────────────────────────────────────────────────────────────
COMPANY_PRIVACY_CHECK       = true                                # Check antes de push
COMPANY_PRIVACY_LEVEL       = "strict"                            # strict | moderate
COMPANY_PRIVACY_SCRIPT      = "scripts/privacy-check-company.sh"

# ── Inbox ────────────────────────────────────────────────────────────────────
COMPANY_INBOX_CHECK_ON_INIT = true                                # Mostrar en session-init
COMPANY_INBOX_READ_LOG      = "$HOME/.pm-workspace/company-inbox-read.log"
COMPANY_INBOX_MAX_UNREAD    = 100                                 # Límite de no leídos

# ── Messaging ────────────────────────────────────────────────────────────────
COMPANY_MSG_ID_FORMAT       = "YYYYMMDD-HHMMSS-PID"
COMPANY_MSG_DATE_FORMAT     = "ISO 8601 UTC"
COMPANY_ANNOUNCE_PERSIST    = true                                # Anuncios nunca se borran
COMPANY_BROADCAST_CONFIRM   = true                                # Confirmar antes de broadcast
```

## Branch Architecture

```
main (orphan)
  ├── company/identity.md
  ├── company/org-chart.md
  ├── directory.md        ← Directorio (tabla | @handle | ... |)
  ├── pubkeys/
  │   └── {handle}.pem
  ├── .savia-index/
  │   ├── users.idx
  │   ├── teams.idx
  │   └── exchange.idx
  └── CODEOWNERS          ← Protección: main branch SOLO admin

user/{handle} (orphan)
  ├── profile.md          ← Perfil público
  ├── documents/          ← Documentos personales
  ├── inbox/
  │   ├── unread/         ← Mensajes sin leer
  │   └── read/           ← Mensajes leídos (archivo)
  ├── outbox/             ← Mensajes enviados (archive)
  ├── flow/assigned/      ← Flow tasks asignadas
  └── timesheet/          ← Timesheet personal

team/{name} (orphan)
  ├── projects/           ← PBIs y features del equipo
  ├── backlog/            ← Backlog compartido
  ├── sprints/            ← Definiciones de sprint
  └── specs/              ← SDD specs del equipo

exchange (orphan)
  └── pending/
      └── {msg_id}.md     ← Mensajes pendientes de entrega (sin purga)
```

## Cross-Branch Reads & Writes

**Lectura:** `git show {branch}:path/to/file.md` (sin checkout)
**Escritura:** `savia-branch.sh write|move`: worktree temporal desacoplado sobre `origin/{rama}`, commit y push con reintento ante rechazo no fast-forward; un push fallido devuelve error

Alternativa: Script `savia-branch.sh` (abstracción layer)

## Scripts

| Script | Función |
|--------|---------|
| `scripts/savia-branch.sh` | Abstracción layer para branch operations |
| `scripts/company-repo.sh` | Ciclo de vida: create, connect, sync |
| `scripts/savia-messaging.sh` | CRUD de mensajes (usa exchange branch) |
| `scripts/savia-crypto.sh` | Cifrado RSA+AES (openssl) |
| `scripts/privacy-check-company.sh` | Validación de privacidad (`--stdin` en send/announce) |

## Comandos

| Comando | Función |
|---------|---------|
| `/company-repo` | Crear, conectar, estado, sincronizar |
| `/savia-send` | Enviar mensaje → exchange:pending/ |
| `/savia-inbox` | Ver user/{handle}/inbox/ |
| `/savia-reply` | Responder con threading |
| `/savia-announce` | Anuncio en main (solo admin) |
| `/savia-directory` | Directorio de usuarios (main:directory.md) |
| `/savia-broadcast` | Mensaje a todos (via exchange) |
