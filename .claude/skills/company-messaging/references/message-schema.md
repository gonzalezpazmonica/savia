# Message Schema — YAML Frontmatter Spec

## Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique ID: `YYYYMMDD-HHMMSS-PID` |
| `from` | string | Yes | Sender @handle |
| `to` | string | Yes | Recipient @handle or `"all"` |
| `date` | string | Yes | ISO 8601 UTC: `2026-03-03T10:00:00Z` |
| `subject` | string | Yes | Message subject line |
| `priority` | string | No | `normal` (default) or `high` |
| `thread` | string | No | ID of first message in thread |
| `reply_to` | string | No | ID of message being replied to |
| `encrypted` | boolean | No | `true` if body is encrypted |
| `type` | string | No | `announcement` for company-wide |

## Examples

### Direct Message

```markdown
---
id: "20260303-100000-12345"
from: "monica"
to: "carlos"
date: "2026-03-03T10:00:00Z"
subject: "Sprint review agenda"
priority: "normal"
thread: ""
reply_to: ""
encrypted: false
---

Hi Carlos, can you prepare the demo for the sprint review?
Focus on the new API endpoints.
```

### Reply (threaded)

```markdown
---
id: "20260303-103000-12346"
from: "carlos"
to: "monica"
date: "2026-03-03T10:30:00Z"
subject: "Re: Sprint review agenda"
priority: "normal"
thread: "20260303-100000-12345"
reply_to: "20260303-100000-12345"
encrypted: false
---

Sure, I'll have the demo ready by Thursday.
```

### Announcement

```markdown
---
id: "20260303-090000-12340"
from: "admin"
to: "all"
date: "2026-03-03T09:00:00Z"
subject: "Office closed March 10"
priority: "high"
type: "announcement"
encrypted: false
---

The office will be closed on March 10 for maintenance.
Work from home that day.
```

### Encrypted Message

```markdown
---
id: "20260303-110000-12347"
from: "monica"
to: "carlos"
date: "2026-03-03T11:00:00Z"
subject: "Credentials for staging"
priority: "high"
thread: ""
reply_to: ""
encrypted: true
---

base64key:::base64body
```

Body format when `encrypted: true`:
`base64(RSA_encrypted_AES_key):::base64(AES_encrypted_body)`

## File Naming

Messages are stored as `{id}.md`:
- Pending: `exchange:pending/{id}.md`
- Personal: `user/{handle}:inbox/unread/{id}.md` (rama `user/{handle}`)
- Announcements: `company/inbox/{id}.md`

## Validation Rules

- `id` must be unique within the repo
- `from` must match a valid @handle in `directory.md`
- `to` must be a valid @handle or `"all"`
- `date` must be valid ISO 8601
- `encrypted: true` → body must contain `:::` separator
