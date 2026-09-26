---
name: transcriptor
description: Gestionar Savia Transcriptor — escanear reuniones capturadas, digerir transcripciones y capturas, marcar como digeridas.
model_tier: mid
context_cost: medium
complexity_tier: mode1
tier: core
---

# /transcriptor

Gestiona las reuniones capturadas por Savia Transcriptor.

## Subcomandos

- /transcriptor scan — listar reuniones sin digerir
- /transcriptor digest — digerir todas las reuniones nuevas (transcripcion + capturas → notas de proyecto)
- /transcriptor digest <carpeta> — digerir una reunion especifica
- /transcriptor mark <carpeta> — marcar una reunion como digerida
- /transcriptor status — estado del transcriptor (reuniones, discos, ultimo)

## Flujo de digest

Para cada reunion nueva:
1. bash scripts/transcriptor-scan.sh → lista de carpetas
2. Por carpeta: leer transcript.md + capturas/*.png
3. Delegar a meeting-digest (notas estructuradas) + visual-digest (contexto visual)
4. Cruzar con reglas de negocio → alertas
5. Guardar digest en SaviaVaults (N3)
6. bash scripts/transcriptor-mark-digested.sh <carpeta>

## Confidencialidad

Los datos de reunion son N3 — locales, nunca al repo. El digest si puede
guardarse en la memoria del proyecto. Nunca subir audio/capturas crudas.
