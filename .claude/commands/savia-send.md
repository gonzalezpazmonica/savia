---
name: savia-send
description: >
  Enviar mensaje directo a un @handle en Company Savia.
  Soporta cifrado E2E y prioridad.
argument-hint: "<@handle> [--encrypt] [--priority high]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Send

**Argumentos:** $ARGUMENTS

> Uso: `/savia-send @handle` | `/savia-send @handle --encrypt` | `/savia-send @handle --priority high`

## Parámetros

- `<@handle>` — Destinatario (obligatorio). Resolver desde directory.md
- `--encrypt` — Cifrar mensaje con clave pública del destinatario (RSA+AES)
- `--priority {normal|high}` — Prioridad del mensaje (defecto: normal)

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md — Config Company Savia
2. `.opencode/skills/company-messaging/SKILL.md` — Protocolo de mensajería

## Pasos de ejecución

1. Mostrar banner: `━━━ 📤 Savia Send ━━━`
2. Verificar que company repo está configurado (leer `$HOME/.pm-workspace/company-repo`)
3. Si no hay `@handle` en argumentos → preguntar destinatario
4. Mostrar directorio de handles disponibles: `bash scripts/savia-messaging.sh directory`
5. Preguntar asunto del mensaje
6. Preguntar cuerpo del mensaje
7. Si `--encrypt` → verificar que el destinatario tiene pubkey
8. Ejecutar: `bash scripts/savia-messaging.sh send <handle> <subject> <body> [--encrypt] [--priority]`
9. Preguntar si sincronizar ahora: `bash scripts/company-repo.sh sync`
10. Mostrar banner de finalización

## Voz Savia (humano)

"Mensaje enviado a @handle. ¿Sincronizo para que lo reciba?"

## Modo agente

```yaml
status: OK
message_id: "YYYYMMDD-HHMMSS-PID"
recipient: "handle"
encrypted: true|false
```

## Restricciones

- NUNCA enviar mensajes sin confirmación del usuario
- Si `--encrypt` y no hay pubkey del destinatario → error claro
- Privacy check automático sobre el cuerpo del mensaje

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
