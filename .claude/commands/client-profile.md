---
name: client-profile
description: "Gestión de perfiles de cliente en SaviaHub"
model_tier: mid
context_cost: medium
allowed_tools: ["Bash", "Read", "Write", "Edit", "Task"]
tier: core
---

# /client-profile — Gestión de perfiles de cliente

> Reglas: @docs/rules/domain/client-profile-config.md
> Dependencia: @docs/rules/domain/savia-hub-config.md

## Subcomandos

### /client-create {nombre}

Crea un nuevo directorio de cliente en SaviaHub.

**Flujo:**
1. Verificar que SaviaHub existe (`$SAVIA_HUB_PATH/.git`)
2. Generar slug kebab-case del nombre (sin acentos, minúsculas)
3. Verificar que `clients/{slug}/` no existe (idempotente)
4. Crear estructura:
   ```
   clients/{slug}/
   ├── profile.md      ← Identidad del cliente (frontmatter YAML + secciones)
   ├── contacts.md     ← Personas de contacto con roles
   ├── rules.md        ← Reglas de negocio y dominio
   └── projects/       ← Directorio de proyectos (vacío)
   ```
5. Actualizar `clients/.index.md` con nueva fila
6. Commit: `[savia-hub] client: create {slug}`
7. Si hay remote y no flight-mode → push automático

**Output:**
```
🏢 Cliente "{nombre}" creado en SaviaHub
   Slug: {slug}
   Path: $SAVIA_HUB_PATH/clients/{slug}/

   Próximos pasos:
   • Edita profile.md con los datos del cliente
   • Añade contactos en contacts.md
   • /client-show {slug} para verificar
```

### /client-show {slug}

Muestra el perfil completo de un cliente.

**Flujo:**
1. Leer `clients/{slug}/profile.md` → extraer frontmatter
2. Leer `clients/{slug}/contacts.md` → tabla de contactos
3. Leer `clients/{slug}/rules.md` → resumen de reglas
4. Listar `clients/{slug}/projects/` → proyectos asociados
5. Mostrar resumen formateado

**Output:**
```
🏢 {nombre} ({slug})
   Sector: {sector} · Desde: {since}
   Contactos: {N} personas
   Proyectos: {N} activos
   Reglas: {N} definidas
   Última edición: {date}
```

### /client-edit {slug} [sección]

Abre la sección indicada del perfil para edición.
Secciones válidas: `profile`, `contacts`, `rules`.
Sin sección → abre `profile.md` por defecto.

**Flujo:**
1. Verificar que `clients/{slug}/` existe
2. Leer fichero de la sección
3. Mostrar contenido actual + permitir edición
4. Guardar cambios
5. Commit: `[savia-hub] client: update {slug}/{section}`
6. Si hay remote y no flight-mode → push automático

### /client-list

Lista todos los clientes en SaviaHub.

**Flujo:**
1. Leer `clients/.index.md`
2. Si está desactualizado → regenerar desde directorios
3. Mostrar tabla formateada

**Output:**
```
🏢 Clientes en SaviaHub ({N} total)

   | Slug | Nombre | Sector | Proyectos | Última edición |
   |------|--------|--------|-----------|----------------|
   | ...  | ...    | ...    | ...       | ...            |
```

## Errores

- SaviaHub no existe → sugerir `/savia-hub init`
- Cliente ya existe → mostrar datos actuales, sugerir `/client-show`
- Slug no encontrado → listar clientes similares
