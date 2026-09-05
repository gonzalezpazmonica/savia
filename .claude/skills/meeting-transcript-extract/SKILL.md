---
layer: peripheral
name: meeting-transcript-extract
description: Usar cuando se necesita extraer la transcripción de una reunión Teams desde el browser.
allowed-tools: [Read, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.argument-hint: "[--port 9222|9223] [--out-dir DIR] [--batch | --substring TEXT]"
  savia.maturity: stable
  savia.category: pm-operations
  savia.context: "Activar cuando el PM pide extraer transcripciones de reuniones Teams, digerir reuniones pendientes, o leer transcripts. Útil post-/project-update cuando hay reuniones sin digest."
  savia.context_cost: low
  savia.max_context_tokens: 6000
  savia.output_max_tokens: 2000
  savia.priority: medium
---

**Última actualización**: 2026-04-24

# /meeting-transcript-extract — Teams transcript extractor via CDP

## Objetivo

Capturar transcripciones de reuniones en Teams web sin depender de permisos de descarga VTT. Funciona para reuniones donde el usuario fue organizador O simplemente asistente. Resuelve el gap de SharePoint Stream player cuando devuelve "elemento no existe" para reuniones ajenas.

## Pre-requisitos

1. Browser-daemon ejecutándose (verificar con `scripts/ensure-daemons-auth.sh`).
2. Cuenta autenticada:
   - Puerto **9222** → cuenta1.
   - Puerto **9223** → cuenta2.
3. Tab de Teams abierto en `teams.microsoft.com/v2/` con sesión activa.

## Invocación

```bash
# Listar chats disponibles (dry-run)
python scripts/extract-teams-transcripts.py --port 9223 --out-dir /tmp/test

# Procesar todos los chats de reunión
python scripts/extract-teams-transcripts.py \
  --port 9223 \
  --out-dir projects/{slug}_main/{slug}-monica/meetings/raw \
  --batch

# Procesar un chat específico (match diacritic-insensitive)
python scripts/extract-teams-transcripts.py \
  --port 9223 \
  --out-dir projects/{slug}_main/{slug}-monica/meetings/raw \
  --substring "Demo OCV"
```

## Pipeline técnico

1. **List chats**: expandir sección Chats del tree en Teams, scroll progresivo, filtrar por chats que empiecen con `[` o `Revisi` (reuniones).
2. **Click chat**: double-click programático via `Input.dispatchMouseEvent`.
3. **Buscar botón Transcripción**: si no aparece, probar Ver resumen primero (activa el Recap pane que a veces expone la transcripción).
4. **Esperar iframe `xplatplugins.aspx`**: el Recap de Teams carga la transcripción en este iframe del tenant owner. El iframe es target CDP independiente (`type=iframe`).
5. **Scroll iframe + dedupe**: encontrar el container con mayor `scrollHeight-clientHeight`, scroll por `clientHeight*0.85` cada paso, capturar `innerText` y deduplicar líneas. Parar en 3 stalls consecutivos o end-of-scroll.
6. **Save**: `{out-dir}/YYYYMMDD-teams-{slug}.transcript.txt` con header (title + extracted timestamp).

## Estados de salida por reunión

- `ok` — transcripción capturada y guardada.
- `chat_not_found` — el chat no aparece en la vista.
- `no_transcript_btn` — la reunión no tiene grabación / transcripción disponible.
- `no_transcript_after_resumen` — click en Ver resumen no expuso el botón.
- `empty` — iframe accesible pero sin texto útil (<100 chars).

## Limitaciones conocidas

- **Chats Daily recurrentes**: solo se captura la última reunión recap; para anteriores hay que scrollear el historial del chat (no implementado).
- **Reuniones >30 días**: pueden haberse purgado de Teams.
- **Tenant URLs**: se infieren del iframe. Los valores reales NUNCA se hardcodean.
- **Teams migrado a `teams.cloud.microsoft`**: si el browser usa esta URL sin navegación explícita a `/v2/`, el chat list puede estar vacío. Forzar navegación a `teams.microsoft.com/v2/`.

## Integración con /project-update

En Fase 2 (Digestión), invocar post-digest de emails para los chats de meeting con actividad nueva en los últimos 7 días. El skill `meeting-digest` puede consumir los `.transcript.txt` generados.

## Anti-patrones

- NUNCA hardcodear tenant URLs, user principals, o identidades. Descubrir empíricamente.
- NUNCA asumir permisos: si el click devuelve `no_transcript_btn`, marcar como processed con status; no reintentar.
- NUNCA inventar dominios.

## Validación 2026-04-24

8 transcripciones capturadas en una pasada (~384 KB texto):
- Reuniones propias del usuario: OK vía SP Stream directo.
- Reuniones con el usuario como asistente: OK vía Teams iframe (breakthrough — SharePoint Stream directo denegaba acceso, Teams iframe lo expone vía Recap).
- Reuniones sin grabación: detectadas y skipped con status `no_transcript_btn`.
