# Memory System — PM-Workspace

> Guide to leveraging the AI coding assistant's (Claude Code / OpenCode) persistent memory system in pm-workspace.

---

## Memory Hierarchy

PM-Workspace uses Claude Code / OpenCode's full memory hierarchy:

| Type | Location | Purpose | Shared |
|---|---|---|---|
| **Project (global)** | `~/claude/CLAUDE.md` | PM role, critical rules, structure | Team (repo) |
| **Modular rules** | `docs/rules/domain/*.md` | On-demand rules by topic | Team (repo) |
| **Language rules** | `docs/rules/languages/*.md` | Conventions with auto-load via `paths:` | Team (repo) |
| **Local project** | `~/claude/CLAUDE.local.md` | Private config: PATs, real projects | You only |
| **Specific project** | `projects/{name}/CLAUDE.md` | Per-project Azure DevOps config | Team (repo) |
| **Auto Memory** | `~/.claude/projects/*/memory/` | Claude's automatic notes per project | You only |
| **User** | `~/.claude/CLAUDE.md` | Global personal preferences | You only |
| **User rules** | `~/.claude/rules/*.md` | Personal modular preferences | You only |

---

## Path-Specific Rules (auto-load by file type)

Language rules include YAML frontmatter `paths:` that triggers automatic loading when Claude works with files of the corresponding language:

```yaml
---
paths:
  - "**/*.cs"
  - "**/*.csproj"
---
# Rule: .NET Conventions
```

**Benefit**: You don't need to manually load language conventions with `@`. They activate automatically when touching a `.cs`, `.py`, `.go`, etc.

### Languages with auto-load

| Language | Extensions |
|---|---|
| C#/.NET | `.cs`, `.csproj`, `.sln`, `.razor` |
| TypeScript | `.ts`, `.mts`, `.cts` |
| Angular | `.component.ts`, `.module.ts`, `.service.ts` |
| React | `.tsx`, `.jsx` |
| Java | `.java`, `pom.xml`, `build.gradle` |
| Python | `.py`, `pyproject.toml`, `requirements.txt` |
| Go | `.go`, `go.mod` |
| Rust | `.rs`, `Cargo.toml` |
| PHP | `.php`, `composer.json` |
| Swift | `.swift`, `Package.swift` |
| Kotlin | `.kt`, `.kts`, `build.gradle.kts` |
| Ruby | `.rb`, `Gemfile` |
| VB.NET | `.vb`, `.vbproj` |
| COBOL | `.cob`, `.cbl`, `.cpy` |
| Flutter | `.dart`, `pubspec.yaml` |
| Terraform | `.tf`, `.tfvars`, `.hcl` |

### Domain rules with auto-load

| Rule | Extensions |
|---|---|
| Infrastructure as Code | `.tf`, `.tfvars`, `.bicep`, `Dockerfile`, `docker-compose*.yml` |
| GitHub Flow | `.github/**`, `.gitignore`, `.gitattributes` |
| Azure Repos | `azure-pipelines*.yml`, `.azuredevops/**` |

---

## Auto Memory

Claude automatically saves notes about each project in `~/.claude/projects/<project>/memory/`. Recommended structure:

```
~/.claude/projects/<project>/memory/
├── MEMORY.md              ← Index (max. 200 lines, loaded at startup)
├── sprint-history.md      ← Velocity, burndown, impediments per sprint
├── architecture.md        ← Architectural decisions for the project
├── debugging.md           ← Resolved problems and their solutions
├── team-patterns.md       ← Team preferences and patterns
└── devops-notes.md        ← Pipeline config, environments, secrets
```

**Only the first 200 lines of MEMORY.md are loaded at startup** (hard cap: 25KB bytes).
Entries should be < 150 chars to avoid wasting context on index lines.
Topic files are read on demand.

### Asking Claude to remember something

```
> Remember that in this project we use pnpm, not npm
> Save to memory that integration tests need local Redis
> Note that the team prefers commits in Spanish
```

### Synchronizing memory with `/memory-sync`

The `/memory-sync` command consolidates insights from the current sprint into auto memory topic files.

---

## Agent Memory — 3 Levels

Agents have separate persistent memory at 3 levels for privacy and portability:

| Level | Path | In git | Content |
|---|---|---|---|
| **Public** | `public-agent-memory/{agent}/` | YES | Generic best practices (DDD, SOLID, security) |
| **Private** | `private-agent-memory/{agent}/` | NO | Personal context, team, organization |
| **Project** | `projects/{p}/agent-memory/{agent}/` | NO | Client data, processing state |

**Load order**: public → private → project. Project takes precedence in conflicts.

**Canonical rule**: `docs/rules/domain/agent-memory-isolation.md`

---

## Imports with `@`

CLAUDE.md supports imports with `@path/to/file` syntax:

```markdown
Config detallada: @docs/rules/domain/pm-config.md
Buenas prácticas: @docs/best-practices-claude-code.md
```

Paths are relative to the file containing the import. Imports are resolved recursively (max. 5 levels).

---

## Symlinks for Shared Rules

If you work on projects outside `~/claude/`, you can share language rules via symlinks:

```bash
# In the external project, create symlink to the language packs
ln -s ~/claude/docs/rules/languages/ /path/to/project/.claude/rules/languages

# Or just a specific language
ln -s ~/claude/docs/rules/languages/python-conventions.md /path/to/project/.claude/rules/python.md
```

---

## `--add-dir` for External Projects

To work on an external project while maintaining access to workspace rules:

```bash
# Load pm-workspace rules while working in another repo
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 claude --add-dir ~/claude
```

---

## User-Level Rules (`~/.claude/rules/`)

Personal preferences that apply across ALL your projects (not just pm-workspace):

```
~/.claude/rules/
├── pm-preferences.md     ← PM communication style
├── report-format.md      ← Preferred report format
└── git-workflow.md       ← Personal Git preferences
```

These rules have lower priority than project-level rules.

---

## Memory Store Enhancements (v1.9.0)

### Concepts Dimension

Entries now support a `--concepts` parameter (CSV) stored as JSON array. This enables 2D taxonomy: type (decision, bug, pattern...) + concepts (testing, ci, architecture...). Search and stats both leverage concepts for better categorization.

### Progressive Disclosure (3 layers)

`/memory-recall` offers three levels to minimize token consumption: `index` (titles + types only), `timeline` (last N with summaries), `detail` (full content of a specific entry by topic_key).

### Token Economics

Every saved entry includes `tokens_est` (content length / 4). `/memory-stats` shows total tokens in store, breakdown by type and concept, and recommends pruning when thresholds are exceeded.

### Auto-Capture

The `memory-auto-capture.sh` PostToolUse hook automatically captures patterns from Edit/Write operations on key files (scripts, rules, commands). Rate-limited to 1 capture per 5 minutes.

### NL→Command Resolution

`/nl-query` uses `intent-catalog.md` (60+ patterns, bilingual) to map natural language to commands. Confidence scoring: base (70-95%) + context bonus (+0-5%) + history bonus (+0-3%). Thresholds: ≥80% auto-execute, 50-79% confirm, <50% suggest top 3.

### Trust-Gated Memory (SE-352)

Every entry carries an `origin` class governing its trust during consolidation:

- `owner` — written by the operator (or via `--source user:explicit`)
- `agent` — written by an agent over locally verified facts (`tool:*`, `file:*`, `verified:*`)
- `untrusted` — network source, unverified subagent, or entry without `src:` (fail-safe)
- `system` — generated by infra hooks/scripts (no decision semantics)

Rules:
- **Fail-safe**: an entry without `--origin` or a trusted source is classified `untrusted`. NEVER `owner` by default.
- **Turn taint**: after a network tool (webfetch, curl, git fetch...), subsequent entries in the turn degrade to `untrusted` (hook `memory-origin-gate.sh`).
- **Consolidation**: `memory-store.sh consolidate` excludes `untrusted`/`system` from promotion (`--dry-run` to preview). Excluding is not deleting: excluded entries, and legacy ones without an `origin` field, move to `output/.memory-store-quarantine.jsonl` and stay recoverable. A recalled entry never promotes its own trust level.
- **Search filter**: `memory-store.sh search "..." --min-origin owner|agent|untrusted`.
- **Audit**: `memory-store.sh audit-origins` reports the origin distribution.

Persistence: the `origin` field is stored in the JSONL and in the `MEMORY.md` index as `· src:{origin}`.

---

## Best Practices

1. **Concise MEMORY.md** — max 200 lines AND 25KB. Each entry < 150 chars. Move details to topic files
2. **Focused topic files** — one topic per file (debugging, architecture, etc.)
3. **Review periodically** — update memory when changing sprints
4. **Don't duplicate** — if something is already in the project's CLAUDE.md, don't repeat it in auto memory
5. **`paths:` only where applicable** — don't add frontmatter to generic domain rules
6. **Concepts tags** — use `--concepts` when saving to facilitate domain-based searches
7. **Consolidate sessions** — run `/memory-consolidate` at the end of long sessions
