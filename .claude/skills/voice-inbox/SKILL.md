---
layer: peripheral
name: voice-inbox
description: Usar cuando se procesan mensajes de voz para transcribirlos y convertirlos en acciones.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: business-analyst
  savia.maturity: stable
  savia.category: communication
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Transcripcion de audio y flujo audio-texto-accion. Procesa mensajes de voz, extrae intenciones y propone acciones. Input: fichero audio. Output: transcripcion + action items."
  savia.tags: "voice, transcription, audio, whatsapp"
---

# Voice Inbox — Transcripción y procesamiento de mensajes de voz

Skill para transcribir mensajes de audio recibidos por WhatsApp o Nextcloud Talk,
interpretar la intención del PM y ejecutar el comando correspondiente en pm-workspace.

## Flujo principal

```
Audio (.ogg/.opus/.m4a) → Faster-Whisper → Texto → Claude interpreta → Comando
```

1. **Descargar audio** — MCP WhatsApp `download_media` o Nextcloud Talk API
2. **Convertir formato** — ffmpeg si necesario (ogg/opus → wav 16kHz mono)
3. **Transcribir** — Faster-Whisper (local, sin enviar audio a terceros)
4. **Interpretar** — Claude analiza el texto y mapea a un comando de pm-workspace
5. **Confirmar** — Mostrar al PM la transcripción + comando propuesto antes de ejecutar
6. **Ejecutar** — Lanzar el comando tras confirmación

## Configuración de Faster-Whisper

### Instalación

```bash
pip install faster-whisper --break-system-packages
```

### Modelos recomendados

| Modelo | RAM | Velocidad | Calidad | Uso recomendado |
|---|---|---|---|---|
| `tiny` | ~1 GB | Muy rápida | Básica | Test rápido, mensajes cortos claros |
| `base` | ~1 GB | Rápida | Buena | Mensajes cortos en entorno silencioso |
| `small` | ~2 GB | Media | Muy buena | **Recomendado para uso diario** |
| `medium` | ~5 GB | Lenta | Excelente | Audio con ruido o acentos fuertes |
| `large-v3` | ~10 GB | Muy lenta | Máxima | Cuando la precisión es crítica |

El modelo se configura en `messaging-config.md` → `WHISPER_MODEL`.
Por defecto: `small` (buen equilibrio calidad/velocidad).

### Idiomas

Faster-Whisper detecta idioma automáticamente, pero se puede forzar:
- `WHISPER_LANGUAGE = "es"` → español
- `WHISPER_LANGUAGE = "auto"` → detección automática (defecto)

## Interpretación de intención

Una vez transcrito el audio, Claude recibe el texto con este prompt interno:

```
El PM ha enviado un mensaje de voz. Transcripción:
"{texto_transcrito}"

Analiza la intención y responde con:
1. Comando de pm-workspace más adecuado (con parámetros)
2. Confianza: alta/media/baja
3. Si confianza < alta → pedir confirmación al PM

Contexto: proyecto activo = {proyecto_actual}
Comandos disponibles: @docs/rules/domain/pm-workflow.md
```

### Ejemplos de mapeo voz → comando

| El PM dice... | Comando mapeado |
|---|---|
| "Ponme el estado del sprint de sala-reservas" | `/sprint-status --project sala-reservas` |
| "¿Cómo va la deuda técnica?" | `/debt-track --project {activo}` |
| "Descompón el PBI 1234 en tareas" | `/pbi-decompose 1234` |
| "Genera el informe ejecutivo del sprint" | `/report-executive --project {activo}` |
| "Hazme un audit del proyecto nuevo" | `/project-audit --project {activo}` |
| "Manda el resumen del sprint al equipo por Slack" | `/notify-slack #equipo {resumen}` |
| "¿Qué alertas de seguridad hay?" | `/security-alerts --project {activo}` |

### Casos ambiguos

Si la transcripción no mapea claramente a un comando:
- Confianza baja → mostrar transcripción + "¿Qué quieres que haga con esto?"
- Múltiples comandos posibles → listar opciones para que el PM elija
- No es un comando → tratar como mensaje informativo y archivar

## Formatos de audio soportados

| Formato | Origen típico | Conversión necesaria |
|---|---|---|
| `.ogg` (Opus) | WhatsApp | No (Faster-Whisper lo soporta) |
| `.m4a` (AAC) | iOS WhatsApp | `ffmpeg -i input.m4a output.wav` |
| `.webm` (Opus) | Nextcloud Talk web | No |
| `.wav` | General | No |

## Restricciones

- **Privacidad**: el audio se procesa LOCAL, nunca se envía a APIs externas
- **Confirmación**: SIEMPRE mostrar transcripción y comando antes de ejecutar
- **Errores de transcripción**: si el PM corrige, aprender del contexto
- Requiere `ffmpeg` instalado para conversiones de formato
- Requiere `faster-whisper` instalado (`pip install faster-whisper`)
