---
name: zeroclaw-meeting
description: "Live meeting transcription via ZeroClaw — speaker diarization, voice identification, and digest."
argument-hint: "start | stop | voice enroll <name> | voice list | voice delete <name> | status"
allowed-tools: [Read, Bash, Write]
model_tier: mid
context_cost: medium
tier: core
---

# /zeroclaw meeting — Reuniones en vivo con ZeroClaw

> Regla: `@docs/rules/domain/zeroclaw-meeting-protocol.md`
> Seguridad: `@docs/rules/domain/zeroclaw-sensory-protocol.md`

## Subcomandos

### `/zeroclaw meeting start`

Inicia grabación de reunión:
1. Verificar ZeroClaw conectado (serial o WiFi)
2. Emitir aviso audible: "Reunión siendo transcrita"
3. LED rojo = grabando
4. Iniciar pipeline: audio → diarization → STT → transcript

### `/zeroclaw meeting stop`

Detiene grabación:
1. Flush último buffer de audio
2. Ejecutar meeting-digest agent sobre transcript
3. Generar resumen + action items + decisiones
4. Borrar audio crudo
5. Guardar digest en projects/{proyecto}/

### `/zeroclaw meeting voice enroll <name>`

Aprender la voz de una persona:
1. Pedir consentimiento explícito
2. Grabar 10-15 segundos de habla
3. Extraer embedding con SpeechBrain ECAPA-TDNN
4. Guardar en ~/.savia/zeroclaw/voiceprints/ (N4b)

### `/zeroclaw meeting voice list`

Listar voces registradas con fecha de enrollment.

### `/zeroclaw meeting voice delete <name>`

Borrar voiceprint (RGPD derecho de supresión).

### `/zeroclaw meeting status`

Estado: ¿grabando? ¿cuánto tiempo? ¿speakers detectados?

## Restricciones

```
SIEMPRE → Aviso audible antes de grabar (consentimiento)
SIEMPRE → LED rojo visible durante grabación
SIEMPRE → Borrar audio crudo tras transcripción
SIEMPRE → Voiceprints clasificados N4b (solo PM)
NUNCA → Grabar sin aviso a los presentes
NUNCA → Enviar audio o voiceprints a APIs externas
NUNCA → Compartir voiceprints entre proyectos
```
