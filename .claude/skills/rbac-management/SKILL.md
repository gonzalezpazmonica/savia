---
layer: peripheral
name: rbac-management
description: "Usar cuando se gestionan roles, permisos o se audita el acceso de usuarios."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: governance
  savia.context: fork
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Control de acceso basado en roles: grant, revoke, audit. Gestiona permisos por usuario/equipo/proyecto. Output: matriz de permisos + log de cambios."
  savia.tags: "rbac, permissions, roles, access-control"
---

# Skill: RBAC Management

> Orquestación de flujos de gestión de roles y permisos
> Regla: @docs/rules/domain/rbac-model.md

## Flujo 1: Grant role

Asignar un rol a un usuario con auditoría.

**Entradas:**
- `user_handle`: nombre del usuario
- `role`: Admin | PM | Contributor | Viewer
- `scope`: "global" o JSON list ["proj-a", "proj-b"]
- `granter_handle`: quién asigna (debe ser Admin)

**Pasos:**

1. Validar que `granter` tiene rol Admin
2. Verificar que el usuario existe en `.claude/profiles/{user}`
3. Escribir `.claude/profiles/{user}/role.md` con los datos
4. Registrar la acción en `output/rbac-audit.jsonl`
5. Confirmar: "✅ {user} ahora es {role} (scope: {scope})"

**Ejemplo output:**
```
✅ carlos-mendoza asignado como PM (scope: global)
   Rol anterior: Contributor
   Cambio: 2026-03-05T10:15:00Z por monica-gonzalez
```

## Flujo 2: Revoke role

Revocar rol (degradar a Viewer).

**Entradas:**
- `user_handle`: nombre del usuario
- `reason`: motivo de revocación

**Pasos:**

1. Leer rol actual de `.claude/profiles/{user}/role.md`
2. Guardar rol actual como `previous_role`
3. Escribir nuevo rol: `Viewer` con `revoked_at` timestamp
4. Registrar en audit con `reason`
5. Confirmar: "✅ {user} revocado de {previous_role} → Viewer. Motivo: {reason}"

**Restricción:** No se puede revocar a Admin (requiere eliminación manual de perfil).

## Flujo 3: Audit

Consultar el log de auditoría con filtros.

**Parámetros:**
- `--user {handle}`: acciones del usuario
- `--date-from {YYYY-MM-DD}`: desde fecha
- `--date-to {YYYY-MM-DD}`: hasta fecha
- `--action grant|revoke|execute`: tipo de acción

**Salida:**

Tabla con resultados:
```
| Timestamp | User | Command | Allowed | Role | Reason |
|-----------|------|---------|---------|------|--------|
| 2026-03-05T10:00 | monica | sprint-plan | true | PM | — |
| 2026-03-05T10:30 | carlos | infra-create | false | Contributor | Admin only |
```

Estadísticas:
- Total acciones auditadas: 1.247
- Acciones denegadas: 23 (1.8%)
- Usuario con + denegaciones: carlos-mendoza (8)

## Flujo 4: Check

Verificar si un usuario puede ejecutar un comando.

**Parámetros:**
- `user`: handle del usuario
- `command`: nombre del comando
- `project`: (opcional) si es scope-limited

**Salida:**
```
✅ monica-gonzalez CAN sprint-plan
   Rol: PM | Scope: global | Permiso: PM+

❌ carlos-mendoza CANNOT infra-create
   Rol: Contributor | Requerido: Admin | Motivo: Deploy only
   Sugerencia: Solicitar permiso a admin
```

## Sección Errors

**Errores manejados:**
- User not found → "❌ Usuario {handle} no existe en perfiles"
- Invalid role → "❌ Rol {role} no válido (Admin|PM|Contributor|Viewer)"
- Permission denied → "❌ Solo Admin puede asignar roles"
- Role.md malformed → "❌ Fichero {path} corrompido, contactar admin"
- Audit.jsonl no accesible → "❌ Permiso insuficiente en output/rbac-audit.jsonl"

## Sección Security

- NUNCA escribir rol.md sin validar granter es Admin
- NUNCA loguear datos sensibles en audit (solo handles y comandos)
- Audit trail es append-only: NUNCA modificar líneas existentes
- Si se detecta modificación manual de role.md → alerta al humano
- Rotación de audit: cuando audit.jsonl > 10MB → mover a histórico

**Restricción:** Este skill se ejecuta en contexto `fork` aislado, no contamina
el contexto principal. El output se resume en <100 tokens para el PM.
