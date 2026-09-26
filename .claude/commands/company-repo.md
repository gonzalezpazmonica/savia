---
name: company-repo
description: >
  Gestionar el repositorio Company Savia: crear, conectar, estado, sincronizar.
  El repositorio compartido de la empresa para conocimiento, mensajería y estado.
argument-hint: "[create|connect|status|sync]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# Company Repo

**Argumentos:** $ARGUMENTS

> Uso: `/company-repo create` | `/company-repo connect` | `/company-repo status` | `/company-repo sync`

## Parámetros

- `create` — CEO/CTO inicializa el repo de la empresa (pide URL git, nombre org)
- `connect` — Empleado se une al repo (pide URL git, genera handle del perfil)
- `status` — Estado de sincronización, último pull, mensajes sin leer
- `sync` — Pull + push con detección de conflictos

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md — Config Company Savia
2. `.opencode/skills/company-messaging/SKILL.md` — Protocolo de mensajería

## Pasos de ejecución

### Modo `create`

1. Mostrar banner: `━━━ 🏢 Company Savia — Crear Repo ━━━`
2. Preguntar: URL del repositorio Git (ej: `https://github.com/org/company-savia.git`)
3. Preguntar: Nombre de la organización
4. Obtener handle del perfil activo (identity.md → name → slugify)
5. Ejecutar: `bash scripts/company-repo.sh create <url> <org> <handle>`
6. Si no hay keypair → preguntar si generar: `bash scripts/savia-crypto.sh keygen`
7. Mostrar resultado + banner de finalización

### Modo `connect`

1. Mostrar banner: `━━━ 🔗 Company Savia — Conectar ━━━`
2. Preguntar: URL del repositorio Git
3. Obtener handle y nombre del perfil activo
4. Ejecutar: `bash scripts/company-repo.sh connect <url> <handle> <name> <role>`
5. Si no hay keypair → preguntar si generar
6. Mostrar resultado + banner de finalización

### Modo `status`

1. Ejecutar: `bash scripts/company-repo.sh status`
2. Mostrar resultado formateado

### Modo `sync`

1. Ejecutar: `bash scripts/company-repo.sh sync`
2. Mostrar resultado

## Voz Savia (humano)

Savia guía el proceso con calidez:
- Create: "Vamos a crear el espacio compartido de tu empresa..."
- Connect: "Te conecto con el equipo..."

## Modo agente

```yaml
status: OK
action: "create|connect|status|sync"
result: {output del script}
```

## Restricciones

- `create` requiere permisos de push al repo Git
- `connect` requiere que el repo ya exista
- NUNCA almacenar credenciales Git en el repo de la empresa
- Privacy check antes de cada sync

⚡ /compact — Ejecuta para liberar contexto antes del siguiente comando
