---
name: integration-status
description: Dashboard de estado de todas las integraciones — APIs, webhooks, MCP, conectividad
developer_type: all
agent: task
context_cost: low
model_tier: fast
tier: core
---

# /integration-status

> 🦉 Savia te muestra qué está conectado y qué necesita atención.

---

## Cargar perfil de usuario

Grupo: **Infrastructure** — cargar:

- `identity.md` — nombre
- `projects.md` — proyectos
- `preferences.md` — language

---

## Subcomandos

- `/integration-status` — dashboard completo
- `/integration-status --check {integration}` — verificar una integración
- `/integration-status --repair {integration}` — intentar reparar conexión

---

## Flujo

### Paso 1 — Verificar todas las integraciones

Para cada integración configurada, comprobar:
1. Credenciales válidas (no expiradas)
2. Endpoint accesible (ping/health check)
3. Último evento recibido (freshness)
4. Rate limits restantes

### Paso 2 — Presentar dashboard

```
📡 Integration Status — {fecha}

  Azure DevOps:
    Estado: 🟢 Conectado
    PAT expira: 2026-06-15 (105 días)
    Último sync: hace 3 min
    Rate limit: 847/1000 restantes

  GitHub:
    Estado: 🟢 Conectado
    Token: válido
    Webhooks: 3 activos, 0 errores
    Último evento: hace 12 min

  MCP Server:
    Estado: 🟡 Parado
    Herramientas: 6 configuradas
    Última sesión: hace 2 días

  Webhooks:
    Estado: 🟢 3/3 activos
    Eventos hoy: 47
    Errores hoy: 0
```

### Paso 3 — Alertas y recomendaciones

```
⚠️ Atención requerida:

  1. PAT Azure DevOps expira en <30 días → renovar
  2. MCP Server parado >24h → ¿reiniciar?
  3. Webhook #2 sin eventos >1h → verificar fuente
```

### Paso 4 — Reparación guiada

Si `--repair`: intentar reconectar, renovar tokens, reiniciar servicios.

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: integration_status
integrations_total: 4
integrations_healthy: 3
integrations_warning: 1
alerts: 1
alert_detail: "PAT expiring in 28 days"
```

---

## Restricciones

- **NUNCA** mostrar tokens/PATs completos — solo últimos 4 caracteres
- **NUNCA** renovar credenciales sin confirmación del usuario
- **NUNCA** enviar datos de estado a servicios externos
- Los health checks deben ser no-destructivos (solo lectura)
- Reparación automática solo para reconexión — no para credenciales
