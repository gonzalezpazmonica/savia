# Savia Sonora — la voz y el oído de Savia

> **Proyecto unificado de interfaz hablada** · Unifica Savia Transcriptor, el
> motor TTS local (Kokoro), la conversación por voz (SE-310) y el post-proceso
> de reuniones. Creado 2026-08-07.

## Nombre

- **Nombre**: Savia Sonora
- **Slug**: `savia-sonora`
- **Histórico absorbido**: Savia Voice (SE-075, SE-042) · Savia Transcriptor (SE-308)

## Descripción

Savia Sonora es la **interfaz hablada de Savia**: su voz y su oído. Escucha
(transcripción local), habla (síntesis local), graba y participa en reuniones,
razona sobre las **cúpulas de contexto de SaviaVaults** y produce **audio
fundamentado** (briefs). Todo local-first (N3), con el mismo cerebro que el
workspace.

No es un asistente de voz genérico: es **Savia** — identidad, memoria y
conocimiento — accesible oralmente, igual que por texto.

## Scope futuro (hacia dónde crece)

| Capacidad | Estado |
|---|---|
| Grabación de reuniones (VAD + whisper + screenshots) | ✅ Implementado (ex-Savia Transcriptor) |
| Motor TTS local (Kokoro CPU, es/ing) | ✅ Implementado (SE-075 Slice 3) |
| Conversación bidireccional push-to-talk | 📐 Spec SE-310 (S0-A..I: proactividad, memoria, visión, cúpulas, briefs) |
| Digest de reuniones/conversaciones | ✅ Implementado (transcriptor-digest, meeting-digest) |
| Voice inbox (WhatsApp/Nextcloud → acción) | ✅ Implementado (voice-inbox) |
| Cúpulas de contexto (consume + alimenta) | 📐 Spec SE-310 S0-H (A2A SaviaVaults) |
| Audio briefs fundamentados (patrón NotebookLM) | 📐 Spec SE-310 S0-I |
| Voz entrenada de Savia (clonación de persona) | 🔒 SE-042 (GPU-blocked) — módulo futuro |
| Cliente móvil (continuidad cross-device) | 📱 savia-mobile-android — fase futura aparte |

## Mapa de módulos (qué consolida)

| Módulo | Origen | Rol en Savia Sonora |
|---|---|---|
| Núcleo de audio (STT) | `projects/savia-sonora/app` (ex-`savia-transcriptor`, SE-308) | Captura, VAD, whisper, screenshots, SQLite, dictado |
| Motor de síntesis (TTS) | `scripts/savia-kokoro.py`, `savia-voice-speak.sh`, `savia-voice-chunk.sh`, `scripts/lib/sentence-splitter.py` (SE-075) — **capa compartida del workspace, owned por Savia Sonora** | Kokoro CPU + chunking + protocolo `SAVIA_VOICE`/`SAVIA_TTS_CMD` |
| Conversación | Spec SE-310 (S0-A..I) | Push-to-talk, barge-in, proactividad, memoria, visión, cúpulas, briefs |
| Digest post-proceso | skill `transcriptor-digest` + `meeting-digest`/`meeting-risk-analyst` | Convierte reuniones/conversaciones en conocimiento |
| Voice inbox | skill `voice-inbox` | Entrada de voz asíncrona (WhatsApp/Nextcloud) |
| Transcript de Teams | skill `meeting-transcript-extract` | Entrada de reuniones remotas |
| Conocimiento (cúpulas) | `projects/savia-vaults` (A2A) | RAG consume + alimenta (dependencia, no se fusiona) |
| Voz entrenada | SE-042 (GPU-blocked) | Futuro: perfil de voz clonado con consentimiento |
| Cliente móvil | `projects/savia-mobile-android` | Futuro: continuidad cross-device (fuera de alcance por ahora) |

## Arquitectura conceptual

```
            ┌──────────────────────────────────────────────────┐
            │               SAVIA SONORA (app)                   │
            │                                                    │
            │  OIDOS:  STT (whisper) + VAD + dictado + voice-inbox │
            │  VOZ:    TTS (Kokoro) + chunk + briefs              │
            │  MENTE:  LLM local (Ollama) — analizar/construir/    │
            │          contestar (SE-310 §2.9)                    │
            │  MEMORIA: contexto + memory.md (S0-F)               │
            │  OJOS:   vision (S0-G, opt-in)                      │
            └───────────────┬──────────────────┬─────────────────┘
                            │ A2A (HTTP local) │ ficheros (decoplado)
              ┌─────────────▼───────────┐   ┌───▼──────────────────┐
              │ SaviaVaults (cúpulas)   │   │ ~/.savia/sonora/     │
              │  consume + alimenta     │   │  reuniones/          │
              │  (S0-H)                 │   │  conversaciones/     │
              └─────────────────────────┘   │  audio-briefs/       │
                                            └──────────────────────┘
```

**Decisión clave**: Savia Sonora **no se fusiona con SaviaVaults**. SaviaVaults
es el conocimiento (cúpulas, grafo); Savia Sonora es la interfaz hablada que lo
consume y alimenta vía A2A HTTP — mismo patrón decoplado que SE-308.

## Plan de consolidación (no destructivo)

### Fase 0 — Identidad unificada (2026-08-07)
- [x] Nombre + descripción + mapa de módulos + roadmap (Era 202)

### Fase 1 — Reubicación física (COMPLETADA 2026-08-07)
- [x] `git mv projects/savia-transcriptor → projects/savia-sonora/app` (núcleo)
- [x] Spec SE-310 → `projects/savia-sonora/specs/`
- [x] Referencias de path actualizadas (specs, README, RESUME, ROADMAP)
- [~] **Engine TTS queda en `scripts/`** (capa compartida, owned por Savia Sonora) — DECISIÓN: moverlo rompería la API TTS del workspace (protocolo SE-075, 15+ referencias: tests, propuestas, vaults, zeroclaw) y el patrón monorepo de `scripts/` como capa compartida. Los scripts Python (`savia-kokoro.py`, `sentence-splitter.py`) son el entry point cross-platform; los wrappers bash (`savia-voice-*.sh`) son conveniencia POSIX.

### Fase 2 — Migración de skills (COMPLETADA 2026-08-07)
- [x] `transcriptor-digest` rebautizada → Savia Sonora (description + SKILLS.md regenerado)
- [x] `meeting-transcript-extract`, `voice-inbox`: sin cambios funcionales — no referencian paths del app (usan `scripts/` compartidos y runtime `~/.savia/transcriptor/`)

### Fase 3 — Módulos futuros (bloqueados externamente)
- [ ] SE-042 (voz entrenada) — **GPU-blocked**; se implementa cuando haya GPU
- [ ] Savia Mobile como cliente — fase aparte tras S0 probado (decisión de la operadora)

## Estado de consolidación: COMPLETA (ejecutable 2026-08-07)

## Cross-platform (Linux / Windows / macOS)

- **App**: Python 3.10+ + Pyloid (PySide6+Qt WebEngine) + React — multiplataforma nativa. Audio: WASAPI (Win) / PipeWire (Linux) / BlackHole (macOS).
- **Engine TTS**: `savia-kokoro.py` (Python, multiplataforma) es el entry point canónico. Los wrappers bash son POSIX; la app invoca el engine vía **subprocess Python** (nunca bash) para compatibilidad Windows.
- **Runtime**: `~/.savia/transcriptor/` se mantiene (compatibilidad con datos existentes); un rename a `~/.savia/sonora/` es fase futura con migración de datos.

**Browser Support:** Chromium 130 (130.0.6723.192) de Qt WebEngine 6.9.2 (PySide6 6.9.2) con Pyloid 0.27.2 fijado en `app/uv.lock`; admite lo que esa versión soporta, sin polyfills (SE-539 D5). Medido en la biblioteca `libQt6WebEngineCore` de ese PySide6.

## Referencias

| Recurso | Path |
|---|---|
| Spec conversación | `projects/savia-sonora/specs/SE-310-savia-conversacional.spec.md` |
| Spec app original | `projects/savia-sonora/app/specs/SE-308-savia-transcriptor.spec.md` |
| Protocolo TTS | `docs/rules/domain/kokoro-voice-protocol.md` |
| SE-075 (TTS adoptado) | `docs/propuestas/SE-075-voicebox-adoption.md` |
| SE-042 (voz entrenada) | `docs/propuestas/SE-042-savia-voice-training-pipeline.md` |
| Cúpulas de contexto | `projects/savia-vaults/` (A2A `127.0.0.1:8923`) |

## OpenCode Implementation Plan

- **Portability**: SINGLE_BINDING_DEFERRED. La app es un binario independiente;
  los únicos bindings (digest skills, scripts TTS compartidos) ya son
  cross-frontend via symlink/`scripts/`.
- **Verification**: pytest (app) + BATS (`test-transcriptor.bats`) + tests de
  plugin TS del guard; SKIP justificado para audio real (requiere hardware).
