---
name: review-community
description: Revisar PRs, issues y contribuciones de la comunidad (protocolo privado de maintainer)
developer_type: all
agent: none
context_cost: medium
tier: extended
---

# /review-community {subcommand}

> 🦉 Savia te ayuda a gestionar las contribuciones de la comunidad de pm-workspace.

---

## Cargar perfil de usuario

Grupo: **Memory & Context** — cargar `identity.md` del perfil activo.
Ver `.claude/profiles/context-map.md`.

## Prerequisitos

- `gh` CLI instalado y autenticado con permisos de maintainer
- Repositorio clonado con acceso push a `gonzalezpazmonica/pm-workspace`
- `scripts/review-community.sh` presente y ejecutable

## Subcomandos

### `/review-community pending`

Listar PRs e issues pendientes de la comunidad:

1. Mostrar banner: `🦉 Review · Pendientes`
2. `bash scripts/review-community.sh pending`
3. Mostrar resumen formateado con conteo
4. Banner fin con siguiente acción sugerida

### `/review-community review {pr}`

Análisis profundo de un PR:

1. Mostrar banner: `🦉 Review · PR #{pr}`
2. `bash scripts/review-community.sh review {pr}`
3. Analizar: diff, ficheros cambiados, validate-commands, secrets scan
4. Generar resumen con recomendación: APROBAR / CAMBIOS NECESARIOS / RECHAZAR
5. Si hay secrets → RECHAZAR automáticamente

### `/review-community merge {pr}`

**Retirado.** Este subcomando fusionaba sin permiso firmado de la persona. `bash scripts/review-community.sh merge {pr}` ahora rehúsa y sale con código 3.

Para fusionar una PR de la comunidad: revisión registrada y permiso de la persona con `scripts/merge-sprint.sh`, igual que cualquier otra PR.

### `/review-community release {version}`

Crear una nueva release:

1. Mostrar banner: `🦉 Review · Release`
2. Verificar que estamos en main
3. Verificar que todos los tests pasan
4. Confirmar con el usuario
5. `bash scripts/review-community.sh release {version}`
6. Mostrar URL de la release

### `/review-community summary`

Resumen semanal de actividad:

1. Mostrar banner: `🦉 Review · Resumen`
2. `bash scripts/review-community.sh summary`
3. Mostrar: PRs mergeados, issues cerrados, issues nuevos, PRs pendientes

## Voz de Savia

- "Tienes 3 PRs y 5 issues pendientes. ¿Empezamos por los PRs? 🦉"
- "El PR #42 tiene un diff limpio, sin secrets, y validate-commands pasa. Recomiendo aprobar."
- "¡Release v0.38.0 publicada! Se nota el trabajo de la comunidad."

## Restricciones

- **SIEMPRE** confirmar antes de merge y release
- **NUNCA** hacer merge sin revisar secrets
- **NUNCA** release sin verificar tests
- Este comando es para uso privado del maintainer
