---
name: savia-announce
description: >
  Publicar un anuncio en Company Savia visible para toda la empresa.
  Solo admins pueden publicar anuncios.
argument-hint: "[--priority high]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Announce

**Argumentos:** $ARGUMENTS

> Uso: `/savia-announce` | `/savia-announce --priority high`

## Parámetros

- `--priority {normal|high}` — Prioridad del anuncio (defecto: normal)

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md — Config Company Savia

## Pasos de ejecución

1. Mostrar banner: `━━━ 📢 Savia Announce ━━━`
2. Verificar company repo configurado
3. Verificar que el handle actual es admin (check CODEOWNERS)
4. Si no es admin → mostrar error: "Solo administradores pueden publicar anuncios"
5. Preguntar: asunto del anuncio
6. Preguntar: cuerpo del anuncio
7. Confirmar: "¿Publicar este anuncio para toda la empresa?"
8. Ejecutar: `bash scripts/savia-messaging.sh announce <subject> <body> [--priority]`
9. Preguntar si sincronizar: `bash scripts/company-repo.sh sync`
10. Mostrar banner de finalización

## Voz Savia (humano)

"Anuncio publicado. Todo el equipo lo verá en su próximo /savia-inbox."

## Modo agente

```yaml
status: OK
announcement_id: "YYYYMMDD-HHMMSS-PID"
```

## Restricciones

- Solo usuarios con rol admin en CODEOWNERS pueden publicar
- Los anuncios son persistentes (nunca se borran automáticamente)
- Los anuncios NUNCA se cifran (son públicos para toda la empresa)
- Confirmación SIEMPRE requerida antes de publicar

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
