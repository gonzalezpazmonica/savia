---
name: savia-inbox
description: >
  Ver bandeja de entrada personal y anuncios de empresa en Company Savia.
  Muestra mensajes sin leer, permite leer mensajes individuales.
argument-hint: "[--unread-only] [read <msg_id>]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Inbox

**Argumentos:** $ARGUMENTS

> Uso: `/savia-inbox` | `/savia-inbox read <msg_id>` | `/savia-inbox --unread-only`

## Parámetros

- (sin args) — Mostrar resumen de inbox (mensajes sin leer + anuncios)
- `read <msg_id>` — Leer un mensaje específico (lo marca como leído)
- `--unread-only` — Solo mostrar mensajes sin leer

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md — Config Company Savia

## Pasos de ejecución

### Modo listado (sin args)

1. Mostrar banner: `━━━ 📬 Savia Inbox ━━━`
2. Verificar company repo configurado
3. Ejecutar: `bash scripts/savia-messaging.sh inbox`
4. Formatear salida con colores y prioridades
5. Si hay mensajes cifrados → indicar con 🔒
6. Mostrar acciones sugeridas: "Usa `/savia-inbox read <id>` para leer un mensaje"

### Modo lectura (`read <msg_id>`)

1. Ejecutar: `bash scripts/savia-messaging.sh read <msg_id>`
2. Si el mensaje está cifrado → descifrar: `bash scripts/savia-crypto.sh decrypt <body>`
3. Mostrar contenido completo formateado
4. Sugerir: "¿Quieres responder? Usa `/savia-reply <msg_id>`"

## Voz Savia (humano)

- Sin mensajes: "Todo limpio, no tienes mensajes pendientes."
- Con mensajes: "Tienes X mensajes sin leer. ¿Empiezo por el más reciente?"
- Anuncio nuevo: "Hay un anuncio nuevo de @admin — ¿lo leo?"

## Modo agente

```yaml
status: OK
unread_personal: 3
unread_announcements: 1
messages: [{id, from, subject, date, priority, encrypted}]
```

## Restricciones

- Marcar como leído solo al ejecutar `read <msg_id>`, no al listar
- Mensajes cifrados requieren clave privada local
- NUNCA mostrar contenido cifrado sin descifrar

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
