---
layer: peripheral
name: transcriptor-digest
description: "Usar cuando se detectan carpetas nuevas en el directorio de reuniones del transcriptor o se quiere digerir transcripciones y capturas de reuniones capturadas por Savia Sonora (ex-Savia Transcriptor). Triggers: digerir reuniones, transcriptor, reuniones nuevas, digest de la reunion, capturas de la reunion."
metadata:
  savia.maturity: beta
---

# transcriptor-digest

Savia Sonora (ex-Savia Transcriptor) captura reuniones automaticamente (audio + transcripcion + capturas de pantalla). Esta skill digiere ese contenido para alimentar el contexto del proyecto.

## Pipeline

1. **SCAN**: listar reuniones sin digerir:
   ```bash
   bash scripts/transcriptor-scan.sh
   ```
   Imprime en stdout, una por linea, las reuniones TRANSCRITAS cuyo meta.json
   no tiene `digested: true` (booleano; un string "true" no cuenta).
   - Una reunion sin meta.json o sin la clave `transcribed` cuenta como transcrita
     si tiene transcript.md o transcript.vtt.
   - Las reuniones en grabacion o transcripcion (`transcribed: false`) NO se
     listan: van a stderr como `PENDIENTE:`. Digerirlas y marcarlas ahora
     perderia lo que se transcriba despues.
   - meta.json ilegible: stderr `ERROR: meta.json ilegible en <reunion>`; no se lista.
   - `--all` lista todas con `digested=` y `transcribed=`. Argumento desconocido: exit 2.
   - Sin directorio de reuniones: exit 0, stdout vacio (aviso en stderr).

2. **DIGEST**: por cada reunion nueva:
   - Leer transcript.md / transcript.vtt con el agente meeting-digest → notas estructuradas
   - Analizar capturas/*.png con visual-digest → contexto visual
   - Cruzar con reglas de negocio del proyecto → meeting-risk-analyst → alertas

3. **STORE**: guardar el digest en la memoria del proyecto (SaviaVaults, nivel N3)

4. **MARK**: marcar la reunion como digerida:
   ```bash
   bash scripts/transcriptor-mark-digested.sh [--force] <carpeta>
   ```
   Solo despues de que el digest este guardado (paso 3). `<carpeta>` es el nombre
   que da el scan o una ruta con `/`.
   - Exit 0: marcada (anade `digested_at`) o ya lo estaba (idempotente).
   - Exit 3: reunion sin transcribir; no se toca. `--force` la marca igualmente.
   - Exit 1: uso, carpeta inexistente, `.`/`..`, meta.json ilegible o no objeto,
     python3 ausente o fallo de escritura. Nunca imprime "Marcada" si no marco.
   - Escritura atomica (temporal + rename) y relectura de verificacion; conserva
     el resto de campos y los permisos. Si falta meta.json en una reunion
     transcrita, lo crea.

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
- La app (MeetingStore y el postprocesador) escribe meta.json sin rename atomico;
  la atomicidad garantizada es la de este script.
- Los thresholds de VAD y intervalo de capturas se configuran en la app
