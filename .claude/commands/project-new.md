---
name: project-new
description: >
  Create a new project interactively — directory structure, CLAUDE.md,
  environments, memory, and CLAUDE.local.md entry. Asks all data step by step.
argument-hint: "<nombre-proyecto>"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# /project-new — Create New Project

Interactive wizard to set up a new project from scratch in pm-workspace.

## Usage

- `/project-new mi-proyecto` — Start wizard with project name
- `/project-new` — Start wizard (asks name interactively)

## Workflow

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🆕 /project-new — New Project Setup
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 1 — Validate name

If `$ARGUMENTS` provided → use as project name. Otherwise ask.
Name must be kebab-case: `^[a-z0-9]+(-[a-z0-9]+)*$`
Verify `projects/{name}/` does NOT already exist.

### Step 2 — Gather project data (interactive, one question at a time)

Ask each field using AskUserQuestion. Show default in brackets.

| # | Question | Field | Default |
|---|----------|-------|---------|
| 1 | Brief description (1 line) | description | — |
| 2 | Tech stack / language | language_pack | auto-detect later |
| 3 | Git provider (github / azure-repos / gitlab / local) | git_provider | github |
| 4 | Repository URL (if remote) | repo_url | — |
| 5 | PM tool (azure-devops / jira / savia-flow / none) | pm_tool | none |
| 6 | If azure-devops: project name in Azure DevOps | azdo_project | — |
| 7 | If azure-devops: team name | azdo_team | — |
| 8 | If azure-devops: iteration path | azdo_iteration | — |
| 9 | Environments (comma-separated) | environments | DEV,PRO |
| 10 | Auto-deploy DEV? (y/n) | auto_deploy_dev | y |

Skip questions 6-8 if pm_tool is not azure-devops.
Skip question 4 if git_provider is local.

### Step 3 — Create directory structure

```
projects/{name}/
├── CLAUDE.md                    ← Generated from answers
├── config.local/                ← git-ignored secrets
│   └── .env.example             ← Template with placeholders
├── diagrams/                    ← Architecture diagrams
│   └── local/                   ← Mermaid diagrams
└── docs/                        ← Project-specific docs
```

### Step 4 — Generate CLAUDE.md (≤ 150 lines)

Use the gathered data to generate `projects/{name}/CLAUDE.md`:

```markdown
# {name} — {description}

## Stack
Language Pack: {language_pack}
Git: {git_provider} | {repo_url}

## PM Tool
{pm_tool config block — Azure DevOps fields if applicable}

## Environments
{table of environments with auto_deploy flag}

## Conventions
(To be filled as the project evolves)

## Notes
Created: {date} via /project-new
```

### Step 5 — Add entry to CLAUDE.local.md

Append to `CLAUDE.local.md` projects table:

```markdown
| {name} | {pm_tool} | `projects/{name}/CLAUDE.md` |
```

If pm_tool is azure-devops, also append to `.claude/rules/pm-config.local.md`:

```
PROJECT_{SLUG}_NAME           = "{azdo_project}"
PROJECT_{SLUG}_TEAM           = "{azdo_team}"
PROJECT_{SLUG}_ITERATION_PATH = "{azdo_iteration}"
PROJECT_{SLUG}_LOCAL_PATH     = "projects/{name}"
```

### Step 6 — Initialize memory

Run: `bash scripts/setup-memory.sh {name}`
Creates 6 template files in `~/.claude/projects/{name}/memory/`.

### Step 7 — Generate .env.example in config.local/

Template with `APP_ENVIRONMENT`, `DATABASE_CONNECTION_STRING`, `LOG_LEVEL` as placeholders.

### Step 8 — Summary banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ /project-new — Project created
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Project .............. {name}
  Path ................. projects/{name}/
  CLAUDE.md ............ projects/{name}/CLAUDE.md
  PM Tool .............. {pm_tool}
  Environments ......... {list}
  Memory ............... initialized

  Next steps:
  → /context-load {name}     — Load project context
  → /project-audit {name}    — Run initial audit
  → /onboard --project {name} — Onboard team members
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ /compact
```

## Restrictions

- NEVER overwrite an existing project directory
- NEVER write real credentials — only placeholders
- NEVER commit CLAUDE.local.md or pm-config.local.md
- All generated CLAUDE.md ≤ 150 lines
