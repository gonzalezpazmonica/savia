---
name: Crear Tenant
description: Crea un workspace aislado por departamento/equipo con perfiles de usuario, configuración de proyecto, herencia de perfiles empresariales y control de acceso basado en roles
developer_type: all
agent: task
context_cost: high
tier: extended
---

# /tenant-create — Crear Tenant Aislado

Crea un workspace independiente para departamentos, equipos o divisiones dentro de la organización. Savia, tu asesora de confianza en infraestructura empresarial, te guiará en este proceso.

## Sintaxis

```
/tenant-create {nombre} [--template default|minimal|enterprise] [--isolation full|shared] [--lang es|en]
```

## Parámetros

- **nombre**: Identificador único del tenant (máx 50 caracteres, alfanuméricos + guiones)
- **--template**: Plantilla inicial (default: estructura completa, minimal: essentials, enterprise: full-featured)
- **--isolation**: Nivel de aislamiento
  - `full`: Perfiles separados, reglas personalizadas, comandos específicos del tenant
  - `shared`: Reglas compartidas, datos separados por tenant (default)
- **--lang**: Idioma de la configuración (es|en, default: es)

## Niveles de Aislamiento

### Full Isolation (Aislamiento Completo)
- Perfiles de usuario independientes por tenant
- Reglas y políticas personalizadas
- Comandos específicos del tenant
- Workspace completamente separado
- Ideal para: Divisiones autónomas, departamentos con políticas distintas

### Shared Isolation (Aislamiento Compartido)
- Reglas base compartidas entre todos los tenants
- Datos y usuarios separados por tenant
- Configuración de proyecto independiente
- Reutilización de comandos globales
- Ideal para: Múltiples equipos con estructura similar

## Estructura Creada

```
tenants/{nombre}/
├── config/
│   ├── profiles.yaml        # Perfiles de usuario del tenant
│   ├── project.yaml         # Configuración de proyecto
│   ├── company-profile.yaml # Herencia del perfil empresarial
│   └── roles.yaml           # Control de acceso basado en roles
├── commands/                # Comandos específicos (si isolation: full)
├── templates/               # Plantillas del tenant
├── data/
│   ├── users.json          # Usuarios del tenant
│   ├── projects.json       # Proyectos del tenant
│   └── audit.log           # Auditoría de acciones
└── metadata.yaml           # Información del tenant
```

## Contenido de Configuración

### metadata.yaml
- ID único del tenant
- Nombre y descripción
- Nivel de aislamiento
- Plantilla base utilizada
- Fecha de creación
- Propietario/Administrador
- Límites de uso (opcional)

### roles.yaml
- Roles disponibles: admin, manager, member, viewer
- Permisos por rol
- Asignación de usuarios
- Políticas de escalado

### company-profile.yaml (Herencia Empresarial)
- Estructura organizacional
- Valores y políticas de la empresa
- Directrices de marca
- Estándares de gobernanza
- Inheritable a todos los tenants

## Casos de Uso

**Departamento de Ingeniería**
```
/tenant-create ingenieria --template enterprise --isolation full --lang es
```

**Equipo de Marketing (estructura compartida)**
```
/tenant-create marketing --template default --isolation shared --lang es
```

**Startup Division (minimal)**
```
/tenant-create startup --template minimal --isolation full --lang es
```

## Validaciones

- Nombre único en toda la organización
- Roles válidos para el tenant
- Acceso a perfil empresarial confirmado
- Capacidad de almacenamiento disponible

## Salida Esperada

```
✓ Tenant 'ingenieria' creado exitosamente

Workspace:      tenants/ingenieria/
Aislamiento:    full
Plantilla:      enterprise
Roles:          admin, manager, member, viewer
Usuarios:       admin@org.com
Estado:         activo

Próximos pasos:
1. /tenant-invite ingenieria --email user@org.com --role member
2. /tenant-config ingenieria --workspace engineering
3. Configurar políticas específicas del tenant
```

## Integración

- Habilita multi-tenancy en pm-workspace
- Base para /tenant-share
- Permite gobernanza por departamento
- Facilita delegación de administración

## Notas de Savia

Como tu asesora de confianza, recomiendo:
- Usa `full` para divisiones autónomas
- Usa `shared` para múltiples equipos similares
- Planifica el crecimiento esperado
- Configura auditoría desde el inicio
- Documenta políticas específicas del tenant

---
**Era 12: Team Excellence & Enterprise** | Comando 247/249
