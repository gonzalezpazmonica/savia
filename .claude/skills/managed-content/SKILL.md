---
layer: peripheral
name: managed-content
description: Usar cuando se regeneran secciones auto-generadas en documentos con marcadores de seguridad.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: governance
  savia.maturity: stable
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Gestiona secciones auto-generadas con marcadores safe-regeneration. Permite actualizar contenido automatico sin tocar contenido manual. Comandos: /managed-sync, /managed-scan."
  savia.tags: "managed-content, markers, auto-generated, sync"
---

# Managed Content Markers

Safe regeneration pattern for auto-generated content in pm-workspace. Managed markers protect manual content while allowing automatic updates to generated sections.

## Marker Format

```markdown
<!-- managed-by: pm-workspace | section: {name} | updated: {ISO-date} -->
... auto-generated content ...
<!-- end-managed: {name} -->
```

Each managed section includes:
- **managed-by**: Tool/system responsible for regeneration
- **section**: Named identifier for the content block
- **updated**: ISO 8601 timestamp of last regeneration

## Three-Phase Workflow

### Phase 1: Scan
Find all files with managed markers in the workspace. List:
- File path
- Section name
- Last updated timestamp
- Freshness status (e.g., "stale" if > 7 days old)

### Phase 2: Regenerate
Re-generate content between markers while:
- Preserving everything outside managed sections
- Updating timestamp to current date
- Validating marker integrity

### Phase 3: Validate
Verify no content outside markers was modified. Abort if:
- Markers are malformed
- Content outside markers changed unexpectedly

## Use Cases

| File | Section | Purpose |
|------|---------|---------|
| CLAUDE.md | skills-catalog | Auto-generated list of all skills |
| CLAUDE.md | commands-summary | Count of commands by category |
| CLAUDE.md | agents-registry | Registry of all agents |
| pm-workflow.md | command-counts | Category counts with trends |
| plugin.json | capabilities | Computed capability counts |
| README.md | feature-list | Feature matrix auto-generated |

## Safety Guarantees

- Content outside markers is **NEVER** modified
- Markers include timestamp for tracking freshness
- Regeneration is preview-first; requires `--apply` flag to persist
- Failed validation prevents write operations

## Integration Points

- `managed-sync`: Regenerate all marked sections
- `managed-scan`: Audit all markers and freshness
- `managed-content` rule: Enforcement for new auto-generated content
