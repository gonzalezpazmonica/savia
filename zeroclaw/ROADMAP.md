# SaviaClaw Roadmap — De hardware a autonomia

> Estado: v1.0-prep | Ultima revision: 2026-03-22
> Objetivo: Savia con presencia fisica, voz, sensores y acción en el mundo real.

---

## Fase 0 — Fundamentos (COMPLETADA)

- [x] Firmware ESP32 (MicroPython): selftest, heartbeat, LCD, WiFi, comandos
- [x] Host bridge: serial bidireccional con JSON
- [x] Setup script: flash + deploy automatizado
- [x] Brain Bridge: ask → Claude CLI → LCD
- [x] Daemon systemd: reconexion automatica, background
- [x] Guardrails: 7 gates deterministas (size, rate, PII, storage, command, cleanup, audit)
- [x] Tests: 23 tests sin hardware (bridge + guardrails)
- [x] Context Guardian: detección de contradicciones en reuniones

## Fase 1 — Estabilidad (COMPLETADA)

- [x] RotatingFileHandler en daemon (log no crece indefinidamente)
- [x] Signal handling (SIGTERM/SIGINT → shutdown limpio)
- [x] Health check: status.json legible por scripts externos
- [x] Auto-recovery: detección de estado stuck (120s), restart del serial
- [x] Daemon status command: `--status` flag
- [x] Daemon refactorizado: daemon + daemon_util (ambos <=150 lineas)
- [x] Tests del daemon: 9 tests sin hardware

## Fase 2 — Voz (EN CURSO)

### 2a — Voice module basico (HECHO)
- [x] TTS: espeak-ng + spd-say fallback (offline, sin cloud)
- [x] STT: integración Whisper (local, modelo base)
- [x] Voice module: `voice.py` con `--say`, `--listen`, `--test`
- [x] Listen-and-respond loop: mic → STT → Claude → TTS → speaker
- [x] Tests de voz: 7 tests sin hardware
- [x] Wake word: VAD energy-based + whisper keyword match + cooldown
- [x] Voice daemon: thread integrado en daemon con `--voice`
- [x] LCD sync: muestra estado de voz en LCD via serial thread-safe
- [x] Tests wake word: 7 tests sin hardware (46 total)
- [x] PipeWire/PulseAudio audio env fix para arecord
- [x] Calibracion umbral VAD para Jabra Evolve 65

### 2b — Savia Voice daemon next-gen (HECHO — pendiente test hardware)
- [x] Arquitectura full-duplex con Silero VAD + faster-whisper + Claude stream-json
- [x] SessionManager: sesión persistente con `--resume`, streaming por frases
- [x] ~~TTS dual: Kokoro 82M local (200ms/frase) + edge-tts Elvira fallback~~ — retirado el 2026-11-26 con `savia-voice/` (SE-537 D6); la conversación por voz pasa a Sonora
- [x] Pre-cache TTS: 64 frases (fillers, stalls, respuestas comunes, 0ms)
- [x] Conversation model: clasificacion de overlaps (backchannel/stop/collaborative)
- [x] Barge-in: solo "para"/"callate" interrumpe, el resto se guarda como follow-up
- [x] Fillers asincrono (3s) y stalls (8s) mientras el LLM piensa
- [x] Config: YAML con defaults + local override
- [x] Tests: 31 tests unitarios sin hardware (77 total)
- [x] E2E test framework con audio sintetico
- [x] Docs: arquitectura, investigacion, roadmap next-gen

### 2c — Pendiente test con hardware
- [ ] Probar daemon next-gen con mic + speaker del host
- [ ] Medir latencias reales (first-audio target: <4s)
- [ ] Ajustar VAD threshold con ambiente real
- [ ] Verificar barge-in con Jabra (AEC no necesario con auriculares)

> Detalle del roadmap de voz: `docs/voice-next-gen-roadmap.md`

## Fase 3 — Sensores y mundo fisico

- [ ] BME280: temperatura, humedad, presion (I2C)
- [ ] Sensor de luz (ADC)
- [ ] Alertas autonomas: umbrales → notificación
- [ ] Logging de series temporales en host
- [ ] Dashboard de sensores (consola o web local)

## Fase 4 — Actuadores

- [ ] Servo/motor control con limites de seguridad (ROB-01, ROB-02)
- [ ] E-stop fisico (ROB-06)
- [ ] Rate limiting en comandos de actuador (ROB-10)
- [ ] Watchdog por actuador (ROB-01)

## Fase 5 — Autonomia

- [ ] Behavior Tree engine en firmware (tick-based)
- [ ] Tareas programadas: monitoreo periodico sin host
- [ ] OTA firmware update con firma (ROB-04)
- [ ] Modo offline: ESP32 opera con rutinas locales si pierde host

## Fase 6 — Reunion y colaboracion

- [ ] Meeting mode completo: transcripcion + diarizacion + digest
- [ ] Voice enrollment (embeddings, con consentimiento RGPD)
- [ ] Participante proactiva: intervencion en ventanas de silencio
- [ ] Integración con sprint: action items → backlog

---

## Relación con SPECs de Context Intelligence

La investigacion de OpenViking + Fabrik-Codek (2026-03-22) produjo SPECs que
afectan tanto a pm-workspace core como a SaviaClaw:

| Spec | Que | Impacto en SaviaClaw | Tier |
|------|-----|---------------------|------|
| SPEC-011 | Roadmap unificado | Prioriza todo el backlog | T1 |
| SPEC-012 | Progressive loading L0/L1/L2 | Reduce contexto del daemon | T1 |
| SPEC-013 | Session memory extraction | Auto-persiste decisiones de voz | T2 |
| SPEC-014 | Competence model | Savia adapta lenguaje por dominio | T3 |
| SPEC-015 | Context gate | Skip scoring en prompts triviales | T1 |
| SPEC-016 | Intelligent compact | Zero-loss al compactar sesiones | T2 |

> Detalle completo: `docs/propuestas/SPEC-011-context-intelligence-roadmap.md`
> SPECs individuales: `docs/propuestas/SPEC-012` a `SPEC-016`

Nota: SPEC-010 N3 (Voz en Tier 4 del roadmap unificado) ya esta parcialmente
cubierto por savia-voice (Fase 2b; retirado el 2026-11-26, SE-537 D6). La prioridad real es Fase 2c (test hardware).

---

## Principios inmutables

1. **Offline-first**: todo funciona sin internet. Cloud es bonus, no requisito.
2. **Fail-safe**: si algo falla, Savia para. No hay degradacion en seguridad.
3. **Privacy-first**: audio y fotos son N3 minimo (RGPD Art. 9).
4. **Hardware-verified**: nada se mergea sin probar en el ESP32 fisico.
5. **150 lineas max**: aplica también al firmware y host.

## Dependencias de hardware

| Componente | Estado | Necesario para |
|------------|--------|----------------|
| ESP32 DevKit | Conectado | Todo |
| LCD 16x2 I2C | Conectado | Fase 0+ |
| Microfono USB/host | Por probar | Fase 2c |
| Speaker/buzzer | Por probar | Fase 2c |
| Jabra Evolve 65 | Disponible | Fase 2c (mic+spk) |
| BME280 | Pendiente | Fase 3 |
| Servo SG90 | Pendiente | Fase 4 |
