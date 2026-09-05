---
layer: peripheral
name: savia-school
description: Usar cuando el workspace se adapta para un entorno educativo con estudiantes menores de edad.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: business-analyst
  savia.maturity: stable
  savia.category: governance
  savia.context: fork
  savia.maturity: experimental
  savia.priority: high
  savia.summary: "Entorno educativo seguro: alias obligatorios, cifrado AES-256 de evaluaciones, rubricas personalizables, portfolio de estudiante, derecho al olvido Art. 17 y exportacion GDPR Art. 15."
  savia.tags: "education, gdpr, minors, school, privacy, rubrics"
---

# Savia School — Entorno Educativo Seguro

Adapta pm-workspace para aulas donde los usuarios son estudiantes,
potencialmente menores de edad. Garantiza privacidad, cifrado y
cumplimiento RGPD/LOPD en todas las operaciones.

## Cuando usar

- Centros educativos que usan pm-workspace para gestionar proyectos
- Entornos con estudiantes menores de edad
- Cualquier contexto que requiera proteccion de datos de menores

## Funcionalidades principales

- **Matriculacion segura**: alias obligatorio, cifrado AES-256-CBC, aislamiento por estudiante
- **Evaluacion con rubricas**: niveles de logro, feedback constructivo, portfolio versionado
- **RGPD/LOPD**: Art. 15 (exportacion), Art. 17 (supresion), audit trail completo

## Comandos

`/school-setup` · `/school-enroll` · `/school-project` · `/school-submit` ·
`/school-evaluate` · `/school-rubric` · `/school-progress` · `/school-portfolio` ·
`/school-diary` · `/school-analytics` · `/school-export` · `/school-forget`

## Prerequisitos

- Clave de cifrado: `$HOME/.school-keys/encryption.key` (permisos 0600)
- Configuracion: `references/school-safety-config.md`

## Seguridad

- Datos de estudiantes son nivel N4b (solo profesor)
- El diario NO es accesible por padres por defecto
- Retencion cero dias tras salida (excepto incidentes: 7 anos)
- Filtro de contenido inapropiado activo por defecto
