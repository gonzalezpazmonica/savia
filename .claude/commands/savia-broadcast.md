---
name: savia-broadcast
description: >
  Enviar el mismo mensaje a todos los @handles de Company Savia.
  Útil para notificaciones urgentes que necesitan acuse individual.
argument-hint: "[--encrypt]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Broadcast

**Argumentos:** $ARGUMENTS

> Uso: `/savia-broadcast` | `/savia-broadcast --encrypt`

## Parámetros

- `--encrypt` — Cifrar cada mensaje con la clave pública de cada destinatario

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md — Config Company Savia

## Pasos de ejecución

1. Mostrar banner: `━━━ 📡 Savia Broadcast ━━━`
2. Verificar company repo configurado
3. Preguntar: asunto del mensaje
4. Preguntar: cuerpo del mensaje
5. Mostrar lista de destinatarios (todos los @handles excepto el remitente)
6. Confirmar: "¿Enviar este mensaje a X destinatarios?"
7. Si `--encrypt` → verificar que todos tienen pubkey
8. Ejecutar: `bash scripts/savia-messaging.sh broadcast <subject> <body> [--encrypt]`
9. Preguntar si sincronizar: `bash scripts/company-repo.sh sync`
10. Mostrar banner con resumen: "Enviado a X de Y destinatarios"

## Diferencia con `/savia-announce`

- **Announce**: un solo fichero en `company-inbox/`, visible para todos
- **Broadcast**: un mensaje individual en cada inbox personal, permite respuesta

## Voz Savia (humano)

"Broadcast enviado a X personas. Cada uno lo verá en su bandeja personal."

## Modo agente

```yaml
status: OK
sent_count: 5
recipients: ["handle1", "handle2"]
```

## Restricciones

- Confirmación SIEMPRE requerida (broadcast puede generar muchos ficheros)
- Si `--encrypt` y algún destinatario no tiene pubkey → advertir y excluir
- NUNCA enviar broadcast sin mostrar lista de destinatarios primero

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
