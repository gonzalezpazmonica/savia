# MCP Curated Catalog

> **SPEC-141** — Catálogo curado de servers MCP para Savia + OpenCode v1.14+.
> Ningún server arranca al inicio (Rule #19). El usuario los activa bajo demanda.

## Cómo activar un server

1. Lee el `.jsonc.example` correspondiente.
2. Verifica el checklist de seguridad (sección "Checklist BlueRock" abajo).
3. Copia el bloque `mcp.<server>` a tu `opencode.jsonc`.
4. Si es OAuth: ejecuta `opencode mcp auth <server>` para autorización inicial.
5. Reinicia OpenCode.

## Checklist BlueRock (obligatorio)

Antes de activar cualquier server público (no nuestro):

- [ ] **No SSRF**: el server NO recibe URLs arbitrarias del LLM sin sandboxing.
- [ ] **Auth obligatoria**: el server requiere API key, OAuth o token. NUNCA `oauth: false` sin token.
- [ ] **Commit recency**: último commit del repo upstream <30 días.
- [ ] **Scope mínimo**: declarado en `_savia_meta.scope`, read-only por defecto.
- [ ] **Audit OK**: `bash scripts/audit-mcp-templates.sh <template>` pasa.

## Plantillas disponibles

### Servers públicos (terceros)

| Server | Tipo | Auth | Uso típico |
|---|---|---|---|
| `github` | local (stdio) | PAT/OAuth | Issues, PRs, code search en repos GitHub |
| `context7` | local (stdio) | API key | Docs vivas por versión — mata invención de APIs |
| `linear` | remote (sse) | OAuth | Sync con backlog Linear |
| `atlassian` | remote (sse) | OAuth | Jira + Confluence (Streamable HTTP post 2026-06-30) |
| `sentry` | remote (sse) | OAuth | Bug ingestion |
| `slack` | remote (sse) | OAuth | Connectors / mensajería |
| `cloudflare-workers` | remote (sse) | OAuth | Despliegues Workers |

### Skills propias expuestas como MCP stdio

| Server | Skill subyacente | Tools expuestos |
|---|---|---|
| `savia-memory` | `savia-memory` | recall, save, stats |
| `savia-recall` | `savia-recall` (futuro) | semantic-search, bm25, entity-match |
| `knowledge-graph` | `knowledge-graph` | query, traverse, neighbors |
| `savia-space` | Savia Space (SE-429) | sessions_list, evidence_read, run_status, run_submit, run_cancel, approval_status |

## Streamable HTTP workaround

OpenCode v1.14 no soporta nativamente HTTP Streamable (issue [#8058](https://github.com/anomalyco/opencode/issues/8058)).
Para servers Streamable-only (ej. Atlassian post 2026-06-30):

```jsonc
{
  "mcp": {
    "atlassian": {
      "type": "local",
      "command": ["npx", "-y", "mcp-remote", "https://mcp.atlassian.com/v1/sse", "--transport", "http-only"],
      "_savia_meta": { "scope": "read:issues", "auth": "oauth", "transport_workaround": "mcp-remote stdio wrapper" }
    }
  }
}
```

## Auditoría

`scripts/audit-mcp-templates.sh` verifica cada plantilla:
- JSON válido y schema OpenCode `mcp` compliance.
- Sin secretos hardcoded (regex de PATs/keys).
- `type` ∈ {`local`, `remote`}.
- `_savia_meta.scope` declarado.
- Si remote: `oauth: true` o `oauth: false` con token efímero documentado.

## Política

Ver `docs/rules/domain/mcp-catalog-policy.md`.
