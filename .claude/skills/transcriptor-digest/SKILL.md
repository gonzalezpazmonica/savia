---
layer: peripheral
name: transcriptor-digest
description: "Usar cuando se detectan carpetas nuevas en el directorio de reuniones del transcriptor o se quiere digerir transcripciones y capturas de reuniones capturadas por Savia Sonora (ex-Savia Transcriptor). Triggers: digerir reuniones, transcriptor, reuniones nuevas, digest de la reunion, capturas de la reunion."
metadata:
  savia.maturity: stable
---

# transcriptor-digest

Savia Sonora (ex-Savia Transcriptor) captura reuniones automaticamente (audio + transcripcion + capturas de pantalla). Esta skill digiere ese contenido para alimentar el contexto del proyecto.

## Pipeline

1. **SCAN**: listar reuniones sin digerir:
   ```bash
   bash scripts/transcriptor-scan.sh
   ```
   Detecta carpetas en el directorio de reuniones cuyo meta.json no tiene digested: true.

2. **DIGEST**: por cada reunion nueva:
   - Leer transcript.md / transcript.vtt con el agente meeting-digest → notas estructuradas
   - Analizar capturas/*.png con visual-digest → contexto visual
   - Cruzar con reglas de negocio del proyecto → meeting-risk-analyst → alertas

3. **STORE**: guardar el digest en la memoria del proyecto (SaviaVaults, nivel N3)

4. **MARK**: marcar la reunion como digerida:
   ```bash
   bash scripts/transcriptor-mark-digested.sh <carpeta>
   ```

## Estructura de reunion

Cada reunion es una carpeta timestamped con:
- audio.wav — audio de la sesion (mic + sistema)
- transcript.vtt — transcripcion con timestamps
- transcript.md — transcripcion markdown
- capturas/*.png — screenshots periodicos
- meta.json — metadata (duracion, modelo, digerido)

## Confidencialidad

- Los datos de reunion son N3 — locales, NUNCA al repo
- El digest generado SI puede ir a SaviaVaults (memoria del proyecto)
- Las capturas pueden contener datos sensibles (emails, codigos) — digerir con cuidado
- Nunca subir audio ni capturas crudas a ningun repositorio

## Configuracion

- SAVIA_TRANSCRIPTOR_DIR (default: directorio home del usuario + .savia/transcriptor)
- Los thresholds de VAD y intervalo de capturas se configuran en la app
