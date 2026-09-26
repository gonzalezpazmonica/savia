---
name: onboard
description: >
  Guided onboarding for new team members — auto-explore project, generate
  component map, create personalized plan by role.
argument-hint: "--role {dev|pm|qa} [--project name]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Task]
model_tier: mid
context_cost: medium
tier: core
---

# /onboard — New Team Member Onboarding

Guided workflow for new team members. Auto-explores project, generates
component map, and creates personalized onboarding checklist by role.

## Usage

- `/onboard --role dev` — Developer onboarding
- `/onboard --role pm` — Project Manager onboarding
- `/onboard --role qa` — QA Engineer onboarding
- `/onboard --role dev --project {name}` — Project-specific onboarding

## Workflow

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎓 /onboard — Team Member Onboarding
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 1 — Auto-Explore Project

1. Detect language pack from project files
2. Scan architecture: directories, key files, config
3. Identify tech stack, frameworks, patterns
4. Generate component map (modules, services, dependencies)

### Step 2 — Role-Specific Checklist

**Developer:**
- [ ] Clone repo and run build
- [ ] Understand architecture (layers, patterns)
- [ ] Set up local dev environment
- [ ] Read CLAUDE.md and key domain rules
- [ ] Run test suite, understand coverage
- [ ] Complete first small task (guided)

**PM / Scrum Master:**
- [ ] Review active sprint and backlog
- [ ] Understand team composition and capacity
- [ ] Review recent retrospective actions
- [ ] Familiarize with reporting commands
- [ ] Set up Azure DevOps access

**QA Engineer:**
- [ ] Review test infrastructure
- [ ] Understand test categories and coverage
- [ ] Review quality gates and hooks
- [ ] Set up test environment
- [ ] Review recent bug patterns

### Step 3 — Personalized Plan

1. Generate time-boxed plan (Day 1, Week 1, Month 1)
2. Assign buddy/mentor suggestion
3. List key contacts and channels
4. Create onboarding tracker file

## Output

Saves to `output/onboarding/{name}-{role}-{date}.md`

## Integration

- Uses team-onboarding skill for checklist generation
- Integrates with `/profile-setup` for new user profile
- References `@docs/rules/domain/role-workflows.md` for role context
