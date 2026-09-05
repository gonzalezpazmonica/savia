---
layer: peripheral
name: personal-vault
description: "Usar cuando se lee o escribe el repositorio personal del usuario (perfil, preferencias, memoria)."
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.context: pm-workspace personal data management
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.summary: "Gestion del repositorio personal del usuario (nivel N3). Perfil, preferencias, memoria, instintos, cache. Cifrado AES-256, sync via git. Comandos vault-*."
  savia.user-invocable: True
---

# Personal Vault — Repositorio Personal del Usuario

> Nivel de confidencialidad: N3 (USUARIO)
> Solo visible para la persona que usa el workspace.

---

## Que es el Personal Vault

Repositorio git dedicado que consolida TODOS los datos personales del usuario
en un unico lugar versionado y portable. Sustituye la dispersion actual de
datos en 5+ ubicaciones sin historial ni portabilidad.

## Ubicacion

- **Default**: `~/.savia/personal-vault/`
- **Configurable**: variable `VAULT_PATH` en `pm-config.local.md`
- **Git remote**: Gitea local (futuro: Gitlab/Azure DevOps segun empresa)

## Estructura del vault

```
~/.savia/personal-vault/
├── .git/
├── CLAUDE.md          ← config para Savia
├── README.md          ← documentacion
├── profile/           ← identity, tone, workflow, tools, preferences, accessibility
├── rules/             ← reglas personales (*.md)
├── globals/           ← CLAUDE.md personal (preferencias globales)
├── instincts/         ← registry.json (patrones aprendidos)
├── memory/            ← MEMORY.md + topic files (memoria cross-project N3)
├── cache/             ← confidence-log.jsonl, context-usage.log
└── history/           ← sync-log.jsonl
```

## Estrategia de sincronizacion

El vault es la **fuente de verdad**. Las ubicaciones originales se convierten
en junctions (Windows NTFS) o symlinks (Unix) que apuntan al vault:

- `.claude/profiles/users/{slug}/` → `vault/profile/`
- `~/.claude/rules/` → `vault/rules/`
- `~/.claude/CLAUDE.md` → `vault/globals/CLAUDE.md`
- `.claude/instincts/` → `vault/instincts/`

**Excepcion**: auto-memory (`~/.claude/projects/*/memory/`) usa copia
unidireccional porque mezcla datos N3 y N4. Solo las entradas N3
(feedback, workspace features) se copian al vault.

## Comandos

- `/vault-init` — Crear vault, migrar datos, crear junctions
- `/vault-sync` — Commit + push al remote
- `/vault-status` — Salud: junctions, cambios, remote
- `/vault-restore` — Clonar desde remote + recrear junctions
- `/vault-export` — Archivo cifrado AES-256 portable

## Integracion

- **session-init**: avisa si hay cambios sin commit >24h (prioridad media)
- **profile-onboarding**: sugiere vault-init tras crear perfil
- **profile-edit**: sugiere vault-sync tras editar perfil
- **backup-protocol**: vault-export reutiliza cifrado AES-256-CBC existente
- **travel-pack**: incluye vault en el paquete portable

## Reglas

1. El vault SOLO contiene datos N3 (personales, cross-project)
2. NUNCA mezclar datos de proyecto (N4) en el vault
3. NUNCA mezclar datos de empresa (N2) en el vault
4. Junctions/symlinks son el mecanismo de integracion, NO copias
5. Si un junction esta roto, Savia avisa y ofrece reparar
