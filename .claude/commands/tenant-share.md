---
name: Compartir Recurso Entre Tenants
description: Comparte recursos (playbooks, templates, skills, reglas) entre tenants con flujo de aprobación controlado, versionado y prevención de deriva de configuración
developer_type: all
agent: task
context_cost: high
tier: extended
---

# /tenant-share — Compartir Recursos Entre Tenants

Comparte skills, playbooks, plantillas y reglas entre tenants de forma controlada. Savia gestiona aprobaciones, versionado y auditoría de recursos compartidos.

## Sintaxis

```
/tenant-share {recurso} [--from tenant] [--to tenant] [--type playbook|template|skill|rule] [--lang es|en]
```

## Parámetros

- **recurso**: Nombre único del recurso a compartir (máx 100 caracteres)
- **--from**: Tenant propietario del recurso (default: tenant activo)
- **--to**: Tenant destino (si no se especifica, compartir con todos)
- **--type**: Tipo de recurso (playbook, template, skill, rule)
- **--lang**: Idioma de la configuración (es|en, default: es)

## Tipos de Recursos

### Playbooks
- Procedimientos automatizados reutilizables
- Captura de flujos de trabajo
- Inclusión de decisiones y bifurcaciones
- Versionado automático

### Templates
- Plantillas de documentos
- Modelos de configuración
- Esquemas de datos
- Parametrizables por tenant

### Skills
- Comandos especializados
- Funcionalidades reutilizables
- Con dependencias resolubles
- Control de versión semántico

### Rules
- Reglas de validación
- Políticas de negocio
- Restricciones organizacionales
- Heredables y overrideable por tenant

## Flujo de Aprobación

```
Origen solicita compartir
    ↓
Metadatos validados
    ↓
Revisor: team lead / admin
    ↓
Aprobado/Rechazado (feedback)
    ↓
Si aprobado → versionado + sincronización a destino
```

## Versionado de Recursos

```
playbooks/
├── campana-marketing-v1.0.yaml    # Original
├── campana-marketing-v1.1.yaml    # Fix menor
└── campana-marketing-v2.0.yaml    # Cambio mayor (requiere re-aprobación)
```

Cambios menores (patch): Auto-propagación a tenants que usan v1.*
Cambios mayores (minor/major): Notificación, los tenants deciden actualizar

## Prevención de Config Drift

- Hash SHA-256 de cada versión
- Detección automática de desvíos
- Alertas si un tenant modifica recurso compartido
- Recuperación a versión origen con confirmación

## Casos de Uso

**Compartir playbook de onboarding con todos**
```
/tenant-share onboarding-employees --type playbook --to "*" --lang es
```

**Compartir skill de reporte entre dos tenants**
```
/tenant-share report-sprint --from ingenieria --to marketing --type skill --lang es
```

**Compartir template de contrato legal**
```
/tenant-share contract-template --type template --from rrhh --to "*" --lang es
```

## Salida Esperada

```
✓ Recurso compartido: onboarding-employees (v1.0)

Tipo:           playbook
Origen:         ingenieria
Destino:        todos los tenants
Aprobación:     ✓ aprobado por team-lead
Versionado:     SHA-256: abc123def456...
Auditoría:      registrada

Tenants que recibieron:
- marketing (actualizado)
- ventas (actualizado)
- rrhh (actualizado)
- startup (actualizado)

Próximos pasos:
1. Los tenants pueden usar /tenant-install onboarding-employees
2. Cambios futuros → /tenant-update-share
3. Revocar acceso → /tenant-unshare
```

## Auditoría

Cada compartición registra:
- Quién compartió, cuándo, desde dónde
- Qué recurso, versión, hash
- Quién aprobó
- Cambios detectados post-compartición

## Integración

- Habilita reutilización sin duplicación
- Previene drift de configuración
- Facilita gobernanza corporativa

---
**Era 12: Team Excellence & Enterprise** | Comando 248/249
