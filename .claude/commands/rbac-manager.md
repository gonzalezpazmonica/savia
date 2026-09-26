---
name: rbac-manager
description: "Role-based access control — grant, revoke, audit roles and permissions"
allowed-tools: [Read, Glob, Grep, Write, Edit, Bash]
argument-hint: "[grant|revoke|audit|check] {user} {role} [--project proj] [--reason motivo]"
model_tier: mid
context_cost: low
tier: core
---

# /rbac-manager — Control de acceso basado en roles

> Skill: @.opencode/skills/rbac-management/SKILL.md
> Regla: @docs/rules/domain/rbac-model.md
> Integración: @.opencode/commands/team-orchestrator.md

Gestiona la asignación de roles a usuarios, revocación de permisos, auditoría
de accesos y verificación de permiso pre-comando.

Soporta 4 roles (Admin, PM, Contributor, Viewer) con herencia y alcance
global o por proyecto.

## Subcomandos

### `/rbac-manager grant {user} {role} [--scope global|proj-list]`

Asigna un rol a un usuario:
- Valida que el usuario existe en `.claude/profiles/{user}`
- Valida que quien ejecuta (active user) es Admin
- Escribe `.claude/profiles/{user}/role.md`
- Registra en audit trail
- Output: confirmación con rol anterior (si lo hay) y timestamp

Ejemplos:
```
/rbac-manager grant carlos-mendoza PM --scope global
/rbac-manager grant ana-garcia Contributor --scope "[sala-reservas, erp-migration]"
```

### `/rbac-manager revoke {user} [--reason causa]`

Revoca rol (degrada a Viewer):
- Verifica que el usuario existe
- Valida que quien ejecuta es Admin
- Guarda rol anterior con timestamp en role.md
- Registra motivo en audit
- Output: confirmación del cambio

Ejemplo:
```
/rbac-manager revoke carlos-mendoza --reason "Acabó contrato"
```

### `/rbac-manager audit [--user user] [--from YYYY-MM-DD] [--to YYYY-MM-DD]`

Consulta el audit trail con filtros:
- `--user`: filtrar por usuario
- `--from`/`--to`: rango de fechas (ISO 8601)
- Sin filtros: últimas 100 acciones

Output: tabla de eventos + estadísticas (total, denegaciones, usuarios con + denegaciones)

Ejemplo:
```
/rbac-manager audit --user monica-gonzalez --from 2026-03-01
```

### `/rbac-manager check {user} {command} [--project proj]`

Verifica si un usuario puede ejecutar un comando:
- Lee rol y scope del usuario
- Consulta matriz de permisos de `rbac-model.md`
- Si es scope-limited, verifica que el proyecto está autorizado
- Output: ✅ CAN / ❌ CANNOT + motivo + sugerencia

Ejemplo:
```
/rbac-manager check carlos-mendoza infra-create
/rbac-manager check ana-garcia sprint-plan --project sala-reservas
```

## Matriz de permisos (resumen)

| Categoría | Comandos | Admin | PM | Contributor | Viewer |
|---|---|---|---|---|---|
| Sprint | sprint-plan, sprint-review | ✅ | ✅ | — | — |
| Backlog | backlog-groom, pbi-create | ✅ | ✅ | — | — |
| Report | report-executive, ceo-report | ✅ | ✅/— | — | ✅ |
| Code | pr-review, spec-generate, code-audit | ✅ | — | ✅ | ✅ |
| Deploy | azure-pipelines apply, infra-create | ✅ | — | — | — |
| Org | team-orchestrator, rbac-manager | ✅ | — | — | — |

**Leyenda:** ✅ = permitido, — = denegado, ✅/— = depende de contexto

## Integración

| Consumidor | Relación |
|---|---|
| `/team-orchestrator assign` | Asigna rol RBAC según función |
| Pre-command hook | Ejecuta `/rbac-manager check` antes de cada comando |
| `/profile-setup` | Solicita rol inicial al crear perfil |
| Audit reports | `/report-executive` incluye resumen de accesos denegados |

## Flujo de referencia

**Al ejecutar cualquier comando:**

1. Session inicia → lee active-user.md → obtiene handle
2. Pre-command hook ejecuta: `/rbac-manager check {user} {command}`
3. Si check = ❌ CANNOT → DETENER, mostrar error + sugerencia
4. Si check = ✅ CAN → continuar ejecución
5. Al terminar → registrar acción en `output/rbac-audit.jsonl`

**Para nuevos usuarios:**

1. `/profile-setup` pregunta: "¿Cuál es tu rol en el equipo?"
2. Opciones: Admin | PM | Contributor | Viewer | Custom
3. Si custom → `/rbac-manager grant {handle} {role}` (requiere Admin)
4. Confirmar y guardarse en identity.md

## Notas de seguridad

- NUNCA revisar contraseñas o secrets (este comando solo gestiona roles)
- Audit trail es inmutable (append-only, nunca borrar líneas)
- Denegaciones se registran incluso si fallan por otra razón
- Para revocar a Admin: eliminación manual de perfil (requiere confirmación)
