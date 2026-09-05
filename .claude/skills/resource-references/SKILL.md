---
layer: peripheral
name: resource-references
description: Usar cuando se necesitan referencias a recursos y plantillas del workspace.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: devops
  savia.maturity: stable
  savia.maturity: beta
  savia.priority: low
  savia.summary: "Resolucion lazy de referencias @ (azure:workitem, project, spec, team, rules, memory). Cache por sesion. Max 5 simultaneas. Permite referenciar recursos externos en prompts."
  savia.tags: "resources, references, resolution, lazy-load"
---

# skill: resource-references

## Name
resource-references

## Description
Define referenciable resources with @ notation for automatic context inclusion. Enables lazy-loaded resource resolution for seamless project data integration.

## Resource Schemas

### @azure:workitem://{id}
Fetches work item from Azure DevOps with automatic metadata inclusion.
- Example: `@azure:workitem://12345`
- Returns: work item title, description, status, assignee, tags

### @project:{name}
Loads project CLAUDE.md configuration and context.
- Example: `@project:savia`
- Returns: project overview, goals, tech stack, conventions

### @spec:{task-id}
Loads Software Design Document (SDD) specification for a task.
- Example: `@spec:ERA-67`
- Returns: requirements, design, acceptance criteria, technical details

### @team:{project}
Loads equipo.md with team structure and responsibilities.
- Example: `@team:savia`
- Returns: team members, roles, contact info, decision makers

### @rules:{project}
Loads reglas-negocio.md with business rules and constraints.
- Example: `@rules:savia`
- Returns: business logic, validation rules, domain constraints

### @memory:{topic}
Loads relevant memory entries by topic with semantic matching.
- Example: `@memory:deployment-strategy`
- Returns: relevant context, decisions, lessons learned

## Resolution Behavior

When an @ reference is found in user input or skill definition:
1. Detect reference pattern (lazy evaluation)
2. Resolve resource from approved sources
3. Include resolved content in context automatically
4. Cache result for session duration
5. Respect max 5 simultaneous resolutions limit

## Lazy Loading

Resources are only resolved when referenced, not during upfront parsing. This ensures:
- Minimal latency for unused references
- Efficient context utilization
- On-demand data fetching
- No unnecessary resource consumption

## Usage Examples

In skills and prompts:
```
Use @project:savia context and @rules:savia to validate decisions.
Check @spec:ERA-67 for detailed requirements before implementation.
Reference @team:savia to identify technical leads.
```

In user input:
```
"Build feature per @spec:ERA-65 with @rules:savia compliance"
```

## Limitations

- Unknown references generate warning, not error
- Only resolve from approved sources
- Max 5 simultaneous resolutions per session
- Cache valid for session duration only
- Circular references not supported

## Related

- resource-resolution rule
- /ref-list command
- /ref-resolve command
