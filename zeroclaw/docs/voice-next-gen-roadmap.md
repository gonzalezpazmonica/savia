# ZeroClaw Voice — Roadmap Next-Gen

> **Retirado el 2026-11-26.** El daemon `zeroclaw/savia-voice/` descrito aquí se retiró por decisión de la operadora (SE-537 D6), con su fallback a edge-tts en la nube. La conversación por voz sigue en Savia Sonora (SE-537). Este documento queda como antecedente.

> Investigacion marzo 2026. Estado del arte en conversación por voz.

---

## Donde estamos (v2)

- Arquitectura turn-based: hablar → esperar → respuesta → esperar
- Latencia total: 15-25s por turno
- Mic bloqueado mientras Savia piensa o habla
- Sin barge-in (no puedes interrumpir)

## Donde necesitamos llegar

- Full-duplex: escuchar y hablar simultaneamente
- Barge-in: el usuario interrumpe y Savia para
- Feedback asincrono: "dame un momento" mientras piensa
- Streaming TTS: empieza a hablar la primera frase sin esperar
- Latencia objetivo: <5s al primer audio de respuesta

---

## 3 Gaps criticos y como resolverlos

### Gap 1: Mic siempre abierto (full-duplex)

**Problema**: `is_processing = True` bloquea el mic.

**Solucion**: Separar en 3 hilos independientes con colas:

```
Hilo 1 (AUDIO):   mic → VAD → cola_audio (NUNCA se para)
Hilo 2 (PIPELINE): cola_audio → STT → LLM → cola_tts
Hilo 3 (SPEAKER):  cola_tts → TTS → altavoz
```

El hilo de audio SIEMPRE esta escuchando. Si detecta habla
mientras Savia habla (barge-in), envia senal al hilo speaker
para que pare la reproduccion.

**Referencia**: [full_duplex_assistant](https://github.com/leo007-htun/full_duplex_assistant),
[LiveKit agents](https://github.com/livekit/agents)

### Gap 2: Streaming TTS (first-audio latency)

**Problema**: Esperamos respuesta COMPLETA antes de sintetizar.

**Solucion**: Leer tokens parciales del stream-json de Claude Code
y sintetizar frase a frase.

```
Claude genera: "Hola la usuaria, | aquí tienes | el resumen."
                    ↓ TTS         ↓ TTS          ↓ TTS
                 (reproduce)   (en cola)      (en cola)
```

Con `--include-partial-messages`, Claude Code emite `stream_event`
con tokens individuales. Acumulamos hasta un punto/coma y lanzamos
TTS de esa frase mientras siguen llegando tokens.

**Impacto estimado**: First-audio de 7-13s → 2-4s

**Referencia**: [OpenAI Realtime API](https://platform.openai.com/docs/guides/realtime),
[Softcery voice architecture](https://softcery.com/lab/ai-voice-agents-real-time-vs-turn-based-tts-stt-architecture)

### Gap 3: Barge-in (interrupcion)

**Problema**: No puedes interrumpir a Savia.

**Solucion**: El hilo de audio monitorea VAD incluso durante
reproduccion. Si detecta habla del usuario:

1. Para la reproduccion TTS inmediatamente
2. Descarta las frases pendientes en cola
3. Captura nueva utterance del usuario
4. La pasa al pipeline normal

**Requisito**: Acoustic Echo Cancellation (AEC) para que el VAD
no confunda la voz de Savia (por altavoz) con la del usuario.
En PC con auriculares/Jabra no es problema. Con altavoz+mic
abierto se necesita AEC (speexdsp o webrtcvad).

**Referencia**: [NVIDIA PersonaPlex](https://research.nvidia.com/labs/adlr/personaplex/),
[Gnani barge-in](https://www.gnani.ai/resources/blogs/real-time-barge-in-ai-for-voice-conversations-31347)

---

## Plan de implementación

### v2.1 — Feedback asincrono (HECHO)
- "Dame un momento" cuando LLM tarda >5s
- "Sigo trabajando" cada 8s adicionales
- Timeout 60s en vez de 30s

### v2.2 — Streaming TTS por frases (HECHO)
- Leer stream_event de Claude Code (session.py ask_streaming)
- Acumular tokens hasta punto/coma (text_utils.py split_sentences)
- Lanzar TTS por frase, reproducir en secuencia (tts.py queue_sentence)
- Kokoro 82M local como engine principal (24kHz, ~200ms/frase)
- edge-tts como fallback automatico

### v2.3 — Mic siempre abierto + barge-in (HECHO)
- Audio callback non-blocking (daemon.py on_audio, NUNCA se para)
- VAD activo durante reproduccion (tts.is_playing + was_overlap)
- Barge-in: cancel() para audio + vacia cola TTS
- Pipeline en thread separado (process_with_model)

### v2.4 — Conversation Model + Pre-cache (HECHO)
- Clasificacion de overlaps: backchannel/collaborative/stop/followup
- Backchannels se ignoran, solo "para"/"callate" interrumpen
- Collaborative overlaps se guardan como follow-up post-turno
- Pre-cache TTS: 64 frases pre-generadas (0ms first-audio)
- Fillers contextuales (3s) y stalls (8s) mientras el LLM piensa
- generate_cache.py para pre-generar WAVs en disco

### v2.5 — Reuniones (modo transcript)
- Whisper small para precision
- Diarizacion con pyannote/ECAPA-TDNN
- Transcripcion continua sin turnos
- Digestión post-reunion con meeting-digest agent

### v3.0 — ESP32 como satelite
- Firmware ESP32: I2S + WebSocket + WakeNet
- Audio streaming bidireccional
- ZeroClaw como mic/speaker remoto del daemon

---

## Métricas objetivo

| Métrica | v2 actual | v2.3 | v3.0 |
|---------|-----------|------|------|
| First-audio | 8-13s | <4s | <3s |
| Turn total | 15-25s | 6-10s | 5-8s |
| Barge-in | No | Si | Si |
| Duplex | No | Si | Si |
| STT accuracy | ~90% | ~90% | ~92% |

---

## Fuentes

- [Full Duplex Assistant](https://github.com/leo007-htun/full_duplex_assistant)
- [LiveKit Agents](https://github.com/livekit/agents) — framework realtime
- [FireRedChat](https://arxiv.org/html/2509.06502v1) — full-duplex cascaded
- [NVIDIA PersonaPlex](https://research.nvidia.com/labs/adlr/personaplex/)
- [OpenAI Realtime API](https://platform.openai.com/docs/guides/realtime)
- [Voice AI Stack 2026](https://www.assemblyai.com/blog/the-voice-ai-stack-for-building-agents)
- [Gnani Barge-in](https://www.gnani.ai/resources/blogs/real-time-barge-in-ai-for-voice-conversations-31347)
- [Softcery Architecture](https://softcery.com/lab/ai-voice-agents-real-time-vs-turn-based-tts-stt-architecture)
