---
layer: peripheral
name: regulatory-compliance
description: Usar cuando se valida el cumplimiento de marcos regulatorios sectoriales.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: governance
  savia.maturity: stable
  savia.context_cost: medium
  savia.developer_type: all
  savia.maturity: stable
  savia.priority: high
  savia.references: "references/sector-healthcare.md, references/sector-finance.md, references/sector-food-agriculture.md, references/sector-justice-legal.md, references/sector-public-admin.md, references/sector-insurance.md, references/sector-pharma.md, references/sector-energy-utilities.md, references/sector-telecom.md, references/sector-education.md, references/sector-defense-military.md, references/sector-transport-automotive.md, references/framework-aepd-agentic.md"
  savia.summary: "Validacion de marcos regulatorios por sector (HIPAA, GDPR, SOX...). Deteccion automatica en 5 fases con scoring ponderado. Output: informe de compliance con gaps y correcciones."
  savia.tags: "compliance, regulatory, sector-detection, gdpr"
---

# Regulatory Compliance Intelligence

## Sector Detection Algorithm (5 fases)

### Fase 1 — Domain Models (35% peso)
Buscar en estructura del proyecto: modelos de dominio, schemas DB, migraciones, DTOs.
Cada sector tiene entidades clave (Patient, Transaction, Product, Case, Citizen, Policy, Batch, Grid, Subscriber, Student, Asset, Vehicle).
Incluir también: interfaces, enums, value objects y DTOs del dominio.

### Fase 2 — Naming & Routes (25% peso)
Buscar en rutas de API, nombres de controladores, servicios, repositorios, tablas DB, middleware.
Patrones: /api/patients, /api/transactions, /api/products, /api/cases, etc.
Incluir también: nombres de carpetas (Healthcare/, Finance/), namespaces, y strings en código.

### Fase 3 — Dependencies (15% peso)
Analizar package.json, requirements.txt, .csproj, pom.xml, go.mod, Cargo.toml, composer.json, Gemfile.
Cada sector tiene packages específicos (hl7-fhir, stripe/braintree, food-traceability, etc.).
Nota: muchos proyectos no usan paquetes sectoriales — por eso esta fase tiene peso reducido.

### Fase 4 — Configuration (15% peso)
Buscar en .env, config/, appsettings.json, docker-compose.yml: claves específicas de sector.
Ejemplo: HIPAA_MODE, PCI_DSS_ENABLED, FHIR_SERVER_URL, ENS_LEVEL, etc.
Incluir también: connection strings a servicios sectoriales, URLs de APIs externas del sector.

### Fase 5 — Infrastructure & Docs (10% peso)
Buscar en README, docs/, Dockerfile, CI/CD, terraform, helm charts:
- Menciones a regulaciones o estándares (HIPAA, PCI-DSS, GDPR, ENS, etc.)
- Certificaciones, auditorías, compliance pipelines
- Variables de entorno de cumplimiento en CI/CD

## Scoring y Decisión

```
score ≥ 55%  → Sector detectado con confianza → proceder automáticamente
score 25-54% → Sector ambiguo → preguntar usuario con opciones detectadas
score < 25%  → No detectado → preguntar usuario con opción "No regulado (saltar)"
```

Si múltiples sectores puntúan >55%, considerar multi-sector (ej: pharma+food).

## Framework de Compliance Check

Para cada regulación del sector, verificar estas categorías:

### 1. Cifrado y protección de datos
- Datos sensibles cifrados at-rest (AES-256 o superior)
- Transmisión cifrada (TLS 1.2+)
- Gestión de claves documentada
- Credenciales no hardcodeadas (usar vault/secrets manager)

### 2. Audit trails
- Logging de accesos a datos sensibles (quién, cuándo, qué)
- Logs inmutables (append-only)
- Retención según normativa del sector

### 3. Control de acceso
- RBAC o ABAC implementado
- Autenticación multi-factor donde aplique
- Segregación de duties

### 4. Trazabilidad
- Cadena de custodia de datos
- Versionado de registros (soft-delete, no hard-delete)
- Capacidad de recall/rollback

### 5. Consentimiento y privacidad
- Gestión de consentimiento explícito
- Derecho al olvido implementable
- Minimización de datos

### 6. Interoperabilidad y formatos
- Formatos estándar del sector (FHIR, ISO 20022, XBRL, etc.)
- APIs documentadas según estándar
- Exportación en formatos regulados

## Clasificación de Severidad

| Severidad | Criterio | Acción |
|-----------|----------|--------|
| CRITICAL | Riesgo de breach, multa regulatoria, ilegalidad | Bloquear hasta corregir |
| HIGH | Control de seguridad/auditoría ausente | Corregir en siguiente sprint |
| MEDIUM | Mejora recomendada por la normativa | Backlog |
| LOW | Best practice del sector | Nice to have |

## Auto-Fix Templates

Fixes automáticos disponibles para:
- **Cifrado**: Añadir cifrado at-rest/in-transit a campos sensibles
- **Audit log**: Añadir middleware/interceptor de auditoría
- **RBAC**: Scaffolding de roles y permisos
- **Consentimiento**: Modelo de consentimiento + API endpoints
- **Trazabilidad**: Soft-delete + versionado de registros
- **Formatos**: Conversión a formato estándar del sector

Fixes que requieren Task manual:
- Cambios arquitectónicos (separación de capas, microservicios)
- Migración de datos existentes
- Integración con sistemas externos (eIDAS, FHIR servers)
- Certificaciones (Common Criteria, ENS nivel alto)

## Integración

- Usa `references/sector-{name}.md` bajo demanda (se carga solo el sector detectado)
- Compatible con regla `ai-governance` existente (añade capa regulatoria)
- Output en `output/compliance/` para histórico y comparación
- Re-verificación tras auto-fix para confirmar corrección
