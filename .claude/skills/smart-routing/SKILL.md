---
layer: peripheral
name: smart-routing
description: Usar cuando se necesita descubrir o enrutar a un comando específico entre los 400+ disponibles.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: sdd-framework
  savia.maturity: stable
  savia.context_cost: medium
  savia.maturity: stable
  savia.memory: project
  savia.model: sonnet
  savia.priority: high
  savia.summary: Enrutamiento inteligente de comandos para 400+ herramientas. Capability groups + keyword matching + top-20 algorithm. Reduce tokens cargando solo el grupo relevante.
  savia.tags: "routing, discovery, commands, intent"
---

# Smart Routing for 400+ Commands

Intelligent command discovery and routing for large tool catalogs. Maps user intent to relevant command categories, loads only necessary tools, maintains usage frequency for Top-20 prioritization.

## Core Components

### Intent Classification

Parse user request to identify primary and secondary intents:

```
User: "¿Cómo está el sprint?"
  → Primary: sprint status tracking
  → Category: PM Operations
  → Tools: [sprint-status, board-flow, daily-routine]
```

Implemented in Step 1 (input analysis):
- Extract keywords (sprint, status, dashboard, report, security, etc.)
- Map to category probabilities
- Select top 1-2 categories

### Frequency Tracking

Maintain `data/tool-usage.jsonl` with:
```json
{ "command": "sprint-status", "count": 47, "last_used": "2026-03-06T15:30:00Z", "category": "pm" }
```

Update after each command execution.

### Top-20 Algorithm

Always available commands (never unloaded):
1. Most-used 10 commands (cross-category)
2. 10 most-used from active category

Loaded only when explicitly searched or category active:
- Remaining 90% of catalog
- Loaded via `/tool-search` or `/tool-catalog`

## Routing Logic (5 Steps)

### Step 1: Intent Analysis (input)
- Extract keywords from user request
- Assign category probabilities (PM, Dev, Infra, Reporting, Compliance, Discovery, Admin)
- Identify secondary categories if applicable

### Step 2: Category Selection
- Primary category: highest probability
- Secondary: if probability >30%, include its top tools
- Load 20-30 tools from selected categories

### Step 3: Usage Frequency Weighting
- Boost: most-used commands in category (+priority in suggestions)
- Order results by: relevance + frequency

### Step 4: Suggestion Generation
- Top 3 candidate commands for primary category
- 1-2 commands from secondary category
- Brief description + confidence score (%)

### Step 5: User Confirmation
- Show suggestions with confidence
- User selects or enters new search
- Execute selected command or refine search

## Data Structure

```yaml
categories:
  pm: [pbi-*, sprint-*, capacity-*, project-*]
  dev: [spec-*, dev-*, arch-*, code-*]
  infra: [infra-*, pipeline-*, deploy-*, env-*]
  reporting: [report-*, audit-*, track-*, metric-*]
  communication: [scheduled-*, notify-*, chat-*]
  compliance: [security-*, compliance-*, aepd-*, equality-*]
  discovery: [discovery-*, jtbd-*, prd-*, rules-*]
  admin: [plugin-*, agent-*, profile-*, config-*]

usage_tracking: data/tool-usage.jsonl
command_metadata: .opencode/commands/*.md
skill_metadata: .opencode/skills/*/SKILL.md
agent_metadata: .opencode/agents/*.md
```

## Integration Points

- `/tool-search` — Explicit search activation
- `/tool-catalog` — Browse categories
- NL command resolution — Implicit routing
- Session init — Pre-load Top-20

