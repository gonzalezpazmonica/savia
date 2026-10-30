---
name: onboard
description: >
  Onboarding guiado de una persona nueva en un proyecto: explora el proyecto, genera
  el mapa de componentes y un plan personalizado a partir de su papel, descrito en texto libre.
argument-hint: "--role \"<texto libre>\" [--project name]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Task]
model_tier: mid
context_cost: medium
tier: core
---

# /onboard — Incorporación de una persona a un proyecto

Sin roles fijos: `--role` acepta texto libre («programo backend», «coordino el ensayo clínico»,
«doy clase de física») y delega la interpretación en el flujo de `/profile-setup` (SE-484).

## Uso

- `/onboard --role "<texto libre>"` — incorporación general
- `/onboard --role "<texto libre>" --project {name}` — incorporación a un proyecto concreto

## Paso 1 — Explorar el proyecto (si hay `--project`)

1. Leer `projects/{name}/CLAUDE.md`
2. Detectar el language pack por los ficheros del proyecto
3. Recorrer la arquitectura: directorios, ficheros clave, configuración
4. Generar el mapa de componentes (módulos, servicios, dependencias)

## Paso 2 — Plan según su papel (delegado)

1. Interpretar el texto de `--role` igual que el paso 2 de `/profile-setup`: ids del catálogo
   `docs/onboarding/capabilities.yaml`, cada uno con su motivo.
2. Si la persona no tiene perfil o el plan propone cambios en el suyo, ejecutar los pasos 3-5 de
   `/profile-setup` (preguntas, plan, confirmación). Sin confirmación no se escribe nada.
3. Obtener el plan:
   `python3 scripts/onboarding-plan.py plan --input <input> --profile-dir .claude/profiles/users/<slug>`
4. Checklist = los tres `first_steps` del plan + los comandos que activa (`commands`) aplicados al
   proyecto. Si `vertical.status` es `none`, se dice y no se inventa ninguna.

## Paso 3 — Plan temporal

1. Plan por plazos (día 1, semana 1, mes 1) a partir del checklist
2. Sugerencia de mentor o persona de referencia, si el proyecto la tiene
3. Contactos y canales clave del proyecto
4. Fichero de seguimiento

## Salida

`output/onboarding/{slug}-{fecha}.md`, sin datos personales más allá del slug.

## Integración

- Flujo y catálogo: `/profile-setup` y `docs/rules/domain/profile-onboarding.md`
- Checklist de equipo: skill `team-onboarding`
- Contexto de cada papel: `docs/rules/domain/role-workflows.md`
- Organizaciones enteras: `/onboard-enterprise` (no cambia)
