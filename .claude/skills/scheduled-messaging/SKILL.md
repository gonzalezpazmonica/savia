---
layer: peripheral
name: scheduled-messaging
description: Usar cuando se configuran mensajes automáticos programados a plataformas de comunicación.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: communication
  savia.maturity: stable
  savia.context: fork
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Configura tareas programadas con mensajeria automatica. Soporta Slack, Google Chat, Nextcloud Talk, WhatsApp. Wizard interactivo para setup de notificaciones."
  savia.tags: "scheduled, messaging, notifications, automation"
---

# Scheduled Messaging — 5-Phase Integration Wizard

Automatiza la entrega de resultados de tareas programadas a Telegram, Slack, Teams, WhatsApp y NextCloud Talk.

---

## Plataformas Soportadas (5)

| Plataforma | Complejidad | Requisitos |
|---|---|---|
| **Telegram** | ⭐⭐ | BotFather token + chat_id |
| **Slack** | ⭐⭐ | Webhook URL |
| **Microsoft Teams** | ⭐⭐ | Webhook URL |
| **WhatsApp** | ⭐⭐⭐ | Twilio: Account SID + Auth Token |
| **NextCloud Talk** | ⭐⭐⭐ | Server URL + Token + Conversation ID |

---

## 5 Fases del Wizard

### Fase 1 — Selección de Plataforma

Menú interactivo con descripción, complejidad (⭐) y tiempo estimado (~5-15 min).

### Fase 2 — Configuración de Credenciales

Guía paso a paso por plataforma:
- **Telegram**: BotFather token + chat_id
- **Slack**: Create incoming webhook en workspace
- **Teams**: Incoming webhook en canal
- **WhatsApp**: Twilio Account SID + Auth Token + from/to numbers
- **NextCloud**: Server URL + token + conversation ID

Guardar en `.env` (nunca hardcoded).

### Fase 3 — Generación de Módulo

Crear `scripts/notify-{platform}.sh` con:
- HTTP POST a API plataforma
- Formateo markdown (donde soportado)
- Manejo de errores + reintentos (máx 3)
- Logging a `output/notifications/`
- Retorna 0 si éxito, 1 si fallo

### Fase 4 — Creación de Tarea Programada

Crear entrada en Claude Code Scheduled Tasks:
- Ejecuta acción principal (ej: `/sprint-status`)
- Captura salida
- Invoca `scripts/notify-{platform}.sh < salida`
- Registra en `output/scheduled-tasks.log`

### Fase 5 — Testing

Enviar test message a plataforma:
- ✅ Éxito → guardar configuración
- ❌ Fallo → revisar credenciales, reintentar

---

## Templates Predefinidos (5)

1. **Daily standup summary** — Standups + resumen diario
2. **Blocker alert** — Items bloqueados >2h
3. **Sprint burndown** — SP restantes vs. ideal
4. **Deployment notification** — Release exitosa
5. **Security scan** — Hallazgos vulnerabilidades

Cada template personalizable con proyecto, rol, etc.

---

## Ficheros Generados

```
scripts/notify-{platform}.sh        (máx 150 líneas)
.env                                (credenciales, nunca commitear)
output/scheduled-messaging/setup-{YYYYMMDD}.log
output/scheduled-tasks.log
output/scheduled-tasks/{task-id}.json
```

---

## Restricciones

- Máx 150 líneas por script notificación
- Reintentos: 3 máximo, backoff exponencial (1s, 2s, 4s)
- Timeout por envío: 10 segundos
- Frecuencia mínima: 5 minutos entre notificaciones
- Mensajes: UTF-8, máx 4000 caracteres

---

## Integración

Los comandos soportan `--notify {platform}` para enviar output automáticamente:

```bash
/sprint-status --notify slack --format markdown
/dev-session --notify telegram
/project-audit --notify teams
```

Ver: `@.opencode/skills/scheduled-messaging/references/platforms.md` para detalles API.
