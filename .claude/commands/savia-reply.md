---
name: savia-reply
description: >
  Responder a un mensaje en Company Savia con threading automático.
argument-hint: "<msg_id> [--encrypt]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Reply

**Argumentos:** $ARGUMENTS

> Uso: `/savia-reply <msg_id>` | `/savia-reply <msg_id> --encrypt`

## Parámetros

- `<msg_id>` — ID del mensaje original al que responder (obligatorio)
- `--encrypt` — Cifrar la respuesta con la clave pública del remitente original

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md — Config Company Savia

## Pasos de ejecución

1. Mostrar banner: `━━━ 💬 Savia Reply ━━━`
2. Verificar company repo configurado
3. Buscar mensaje original por ID (unread, read, company-inbox)
4. Mostrar mensaje original como contexto
5. Preguntar: "¿Qué quieres responder?"
6. Ejecutar: `bash scripts/savia-messaging.sh reply <msg_id> <body> [--encrypt]`
7. El reply hereda el thread del original (o crea uno nuevo si no tiene)
8. Preguntar si sincronizar: `bash scripts/company-repo.sh sync`
9. Mostrar banner de finalización

## Voz Savia (humano)

"Respuesta enviada a @{remitente}. El hilo queda vinculado."

## Modo agente

```yaml
status: OK
reply_id: "YYYYMMDD-HHMMSS-PID"
thread: "original_thread_id"
reply_to: "original_msg_id"
```

## Restricciones

- El mensaje original debe existir en el repo local
- Threading usa campo `thread` (ID del primer mensaje del hilo)
- Si el original no tiene thread → el reply usa el msg_id original como thread

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
