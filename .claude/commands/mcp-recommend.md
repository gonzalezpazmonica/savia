---
name: mcp-recommend
description: >
  Recommend MCP servers based on team profile, project stack, and workflow needs.
argument-hint: "[--stack dotnet|python|node] [--role pm|dev|qa]"
allowed-tools: [Read, Glob, Grep]
model_tier: fast
context_cost: low
tier: core
---

# /mcp-recommend — MCP Recommendations

Recommend MCP servers based on your team profile and project stack.

## Usage

- `/mcp-recommend` — Auto-detect stack and suggest MCPs
- `/mcp-recommend --stack dotnet` — Recommendations for .NET projects
- `/mcp-recommend --role pm` — Recommendations for PM workflows

## Behavior

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔌 /mcp-recommend — MCP Suggestions
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

1. Detect project stack from files (language pack detection)
2. Read user profile for role
3. Match against curated MCP catalog
4. Present prioritized recommendations

## Curated MCP Catalog

### Essential (All teams)

| MCP | Purpose | Install |
|---|---|---|
| **Context7** | Up-to-date library docs (prevents hallucinated APIs) | `npx context7-mcp` |
| **DeepWiki** | GitHub repo documentation and analysis | `npx deepwiki-mcp` |

### Development

| MCP | Purpose | Best for |
|---|---|---|
| **Playwright** | Browser automation, UI testing, screenshots | Frontend, E2E |
| **Excalidraw** | Architecture diagrams from prompts | All dev teams |
| **Docker** | Container management | Microservices |
| **PostgreSQL/MySQL** | Direct database queries | Backend |

### PM / Scrum

| MCP | Purpose | Best for |
|---|---|---|
| **Slack** | Team notifications and search | All teams |
| **GitHub** | PR, issues, project boards | GitHub-hosted projects |
| **Linear** | Issue tracking integration | Linear users |
| **Notion** | Documentation sync | Notion users |

### Observability

| MCP | Purpose | Best for |
|---|---|---|
| **Sentry** | Error tracking, bug creation | Production apps |
| **Grafana** | Dashboard queries | Monitored services |

## Stack-Specific Recommendations

| Stack | Primary MCPs |
|---|---|
| .NET | Context7, Docker, Playwright |
| Python | Context7, Docker, PostgreSQL |
| Node/TypeScript | Context7, Playwright, Excalidraw |
| Go/Rust | Context7, Docker |

## Output

Table with: MCP name, relevance score, install command, and rationale.
