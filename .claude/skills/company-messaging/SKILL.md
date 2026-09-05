---
layer: peripheral
name: company-messaging
description: Usar cuando se envían mensajes internos cifrados entre miembros de la organización vía Company Savia.
allowed-tools: [Read, Bash, Glob, Grep]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: communication
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.maturity: 
  savia.priority: medium
  savia.summary: "Mensajeria interna Company Savia con cifrado E2E basado en ramas git. Soporta mensajes directos, broadcasts y threading. Datos en company repo compartido. Nivel N2 (empresa)."
  savia.tags: "messaging, company, encryption, privacy"
  savia.user-invocable: False
---

# Company Messaging — Skill (Branch-Based v3)

## Overview

Company Savia enables async messaging between users across a company using
orphan Git branches. Messages are plain markdown files with YAML frontmatter,
stored in personal inboxes and a pub/sub exchange branch.

## Branch Architecture

```
main (orphan)
  ├── company/identity.md, org-chart.md
  ├── pubkeys/user/{handle}.pem
  └── .savia-index/users.idx

user/{handle} (orphan)
  ├── inbox/unread/        ← Personal messages (unread)
  ├── inbox/read/          ← Personal messages (archive)
  └── outbox/              ← Sent message archive

exchange (orphan)
  └── pub/sub/pending/
      ├── {msg_id}.md      ← Pending delivery (temp)
      └── .index           ← Routing table by recipient

team/{name} (orphan)
  └── (shared team resources)
```

## Message Lifecycle

1. **Compose**: Create message with YAML frontmatter
2. **Encrypt** (optional): RSA-4096 + AES-256-CBC via `savia-crypto.sh`
3. **Deliver**: Write to `exchange:pub/sub/pending/{msg_id}.md`
4. **Sync**: `git add + commit + push` to exchange branch
5. **Pull**: Recipient syncs and fetches from `exchange:pub/sub/pending/`
6. **Move**: Transfer to `user/{handle}/inbox/unread/`
7. **Read**: User moves to `user/{handle}/inbox/read/`
8. **Archive**: Old messages can be purged per retention policy

## Fetch-Messages Workflow

```bash
git show exchange:pub/sub/pending/{msg_id}.md | decrypt | move to user/{handle}/inbox/unread/
```

No need to checkout exchange branch — just `git show`.

## @Handle Resolution

Handles are resolved from `main:company/directory.md` (admin-only):

```markdown
| Handle | Name | Role | Status |
|--------|------|------|--------|
| @admin | Admin Name | Admin | active |
```

Pubkeys stored at `main:pubkeys/user/{handle}.pem`.

## Encryption Protocol

**Hybrid RSA-4096 + AES-256-CBC** (openssl only, zero deps):

1. **Keygen**: `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096`
2. **Encrypt**: Random AES-256 key → encrypt body → encrypt AES key with recipient RSA pubkey
3. **Store**: Base64-encoded `encrypted_key:::encrypted_body` in frontmatter
4. **Decrypt**: RSA-decrypt AES key (private.pem: chmod 600) → AES-decrypt body

Public keys auto-published to `main:pubkeys/user/{handle}.pem` by admin script.

## Privacy Rules

Before any `git push`:

1. **Layer 1**: `validate_privacy()` — PATs, tokens, IPs, connection strings
2. **Layer 2**: Scan YAML frontmatter and body for secrets
3. **Layer 3**: Verify subject line has no sensitive data (see messaging-subject-safety.md)

Script: `scripts/privacy-check-company.sh`

## Message Types

| Type | Location | Persist | Encrypted |
|---|---|---|---|
| Direct message | exchange:pending → user/{handle}/inbox/unread/ | 7 days | Optional |
| Reply | user/{handle}/inbox/ | Until archived | Optional |
| Broadcast | exchange:pending (deliver to each user/{handle}) | 7 days | Optional |
| Announcement | main:company/announcements/ | Permanent | Never |

## Threading

Messages form threads via YAML frontmatter:
- `thread`: ID of first message
- `reply_to`: ID of message being replied to

Replies auto-inherit thread from parent.

## Read Tracking

- **Personal messages**: moved from `unread/` to `read/` on user branch
- **Announcements**: tracked in `$HOME/.pm-workspace/company-inbox-read.log`

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/savia-branch.sh` | Abstraction layer for branch operations |
| `scripts/savia-messaging.sh` | Message CRUD (create, fetch, deliver, archive) |
| `scripts/savia-crypto.sh` | E2E encryption (RSA+AES) |
| `scripts/privacy-check-company.sh` | Privacy validation pre-push |

## Worktree Pattern

Writes use temporary worktrees to avoid checkout pollution:

```bash
git worktree add .claude/worktrees/{temp} user/{handle}
# Write/edit files
git add && git commit && git push
git worktree remove .claude/worktrees/{temp}
```

## Session-Init Integration

Unread count from `user/{handle}/inbox/unread/` (local, no network):

```
📬 3 unread messages · 1 pending broadcast
```
