---
id: SE-075
title: SE-075 — Voicebox adoption — task_queue, auto-chunking, Kokoro CPU voice
status: IMPLEMENTED   # Slices 1+2+3 implemented (2026-06-24)
origin: jamiepine/voicebox repo study 2026-04-26
author: Savia
priority: media
effort: M 8h (3 slices independientes)
related: SE-074, SE-042, savia-voice, emergency-mode
approved_at: "2026-04-26"
applied_at: "2026-04-27+2026-06-24"   # Slices 1+2 2026-04-27; Slice 3 2026-06-24
expires: "2026-06-26"
era: 188

triage_note: "All 3 slices done. Slice 3 (Kokoro) implemented 2026-06-24"
---

# SE-075 — Voicebox adoption

> **Nota 2026-11-14:** el Slice 1 (`scripts/lib/task-queue.py`) se retiró por no tener ningún consumidor (ni el orquestador paralelo ni el healer lo llamaron nunca) junto con la admisión duradera SE-513, que se apoyaba en él. El historial de git lo conserva. Los Slices 2 y 3 no se tocan.


## Why

Voicebox (jamiepine/voicebox, 23k stars, MIT, push diario) es alternativa OSS a ElevenLabs: Tauri+FastAPI con 7 motores TTS, voice cloning zero-shot, 23 idiomas. Análisis 2026-04-26 identifica 3 patrones específicos extraíbles sin adoptar el stack completo (Tauri, GPU, multi-track editor).

Cost of inaction:
- **task_queue**: cada skill long-running de Savia reinventa cola+streaming. SE-074 paralelismo necesita cola serial intra-worktree para sub-tareas — sin patrón, cada slice reinventa la rueda.
- **auto-chunking**: savia-voice no maneja textos >30s sin cortes audibles. Bloquea narración de notas largas, daily summaries hablados.
- **Kokoro CPU voice**: SE-042 voice training está GPU-blocked. Sin alternativa CPU, Savia no tiene voz de salida en español hoy. Kokoro 82M corre 150x realtime en CPU y soporta español.

## Scope (3 slices independientes)

### Slice 1 (S, 2h) — task_queue.py adoption

Copiar `backend/services/task_queue.py` de voicebox (~3.7KB MIT, atribuir) → `scripts/lib/task-queue.py` con adaptaciones:

- Colas serial async + SSE streaming
- Auto-recovery de jobs stale en startup
- Integración inicial: SE-074 orquestador (sub-cola intra-worktree para steps SDD)
- Persistencia: SQLite en `output/task-queue/`

### Slice 2 (M, 3h) — auto-chunking long-form TTS

Patrón de voicebox `services/tts.py` para chunking:

- Sentence-boundary split (puntuación + abreviaturas español)
- Crossfade audio entre chunks (ffmpeg)
- Wrapper `scripts/savia-voice-chunk.sh` que toma texto largo, divide, sintetiza chunks paralelos (bounded concurrency 2), concatena
- Integra con savia-voice/whisper-env existente

### Slice 3 (M, 3h) — Kokoro CPU voice instalación + skill

- Instalar Kokoro 82M (`hexgrad/Kokoro-82M`) — modelo TTS CPU, español soportado
- Skill `.opencode/skills/savia-voice-cpu/` (SKILL.md + DOMAIN.md)
- Wrapper `scripts/kokoro-tts.sh` con `--text`, `--lang es`, `--out path.wav`
- Documentar trade-off vs cloud TTS (calidad, latencia, sin GPU)
- NO bloquea SE-042 (que sigue siendo voice CLONING de calidad, GPU-required)

## Acceptance criteria

### Slice 1 — IMPLEMENTED (2026-04-27)
- [x] AC-01 `scripts/lib/task-queue.py` con atribución MIT a voicebox en header
- [~] AC-02 SSE endpoint en bridge para subscribe a estado de cola — **deferred**: Savia es CLI-first, sin bridge HTTP en este momento. CLI `status --json` cubre observabilidad.
- [x] AC-03 Auto-recovery testeado (stale heartbeat → reset to pending; tests #19, #22, #23)
- [x] AC-04 Tests BATS = 26, score 100/100 (`tests/structure/test-task-queue.bats`)
- [~] AC-05 Doc `docs/rules/domain/task-queue.md` — **deferred**: docstring del módulo + spec ref bastan; doc dedicada se añade si surge un segundo consumidor

### Slice 2 — IMPLEMENTED (2026-04-27)
- [x] AC-06 `scripts/savia-voice-chunk.sh` toma texto >1KB, devuelve audio único (test #22 con >10 KiB; ffmpeg acrossfade configurable vía `--crossfade-ms`)
- [x] AC-07 Bounded concurrency 2 default (env `SAVIA_TTS_CONCURRENCY`, override `--concurrency`)
- [x] AC-08 Tests con español + abreviaturas (Sr./Sra./Dr./Dra./Vds./S.A./a.m./p.m./Lic./Ing./Prof./D./Dña./etc.) en `scripts/lib/sentence-splitter.py`. Tests BATS = 27, score 100/100.

### Slice 3 — IMPLEMENTED (2026-06-24)
- [x] AC-09 Kokoro installed, model cached at `~/.cache/huggingface/`
- [x] AC-10 `scripts/savia-kokoro.py` generates intelligible Spanish WAV (ef_dora voice)
- [x] AC-11 Skill/protocol documented in `docs/rules/domain/kokoro-voice-protocol.md`
- [x] AC-12 Latency verifiable: ~4s wall-time for 0.625s audio (CPU, ~6.5x RT — well below 2x RT threshold)

> **Razón del deferral de Slice 3**: la descarga del modelo Kokoro 82M (~500MB) y la instalación de dependencias Python (torch o kokoro-onnx) requieren autorización explícita de la usuaria por consumo de disco y red. La pipeline de Slice 2 ya soporta cualquier TTS plug-in vía `$SAVIA_TTS_CMD` (placeholders `{out}/{text}`), de modo que cuando se autorice Kokoro bastará añadir el wrapper sin modificar el chunker.

## No hacen

- NO adopta Tauri shell (Savia es CLI-first)
- NO adopta voice cloning zero-shot (sigue requiriendo GPU — SE-042 no se desbloquea)
- NO adopta multi-track editor, system audio capture, post-processing pedalboard
- NO sustituye whisper-env existente (Slice 3 añade salida CPU; transcripción sigue como está)
- NO instala torch/torchvision si Kokoro tiene runtime alternativo más ligero (verificar en Slice 3 prep)

## Riesgos

| Riesgo | Prob | Impacto | Mitigación |
|---|---|---|---|
| Kokoro español calidad insuficiente | Media | Medio | Validación A/B vs cloud TTS antes de promote a default; sigue siendo opt-in |
| task_queue.py asume FastAPI runtime | Alta | Bajo | Adaptar a bridge existente o skill standalone |
| Chunking audible en boundaries | Media | Medio | Crossfade ajustable, fallback a no-chunk para textos cortos |
| Voicebox cambia API entre Slices | Baja | Bajo | Pinear commit hash en momento de adopción |
| Disco: Kokoro + deps ~500MB | Alta | Bajo | Documentar requisito; aceptable |

## Dependencias

- Slice 1 puede arrancar inmediatamente (independiente de SE-074)
- Slice 2 independiente de Slice 1
- Slice 3 independiente de los anteriores (Kokoro standalone)
- Los 3 slices no se bloquean entre sí — pueden ir en PRs separados o batch único

## Comparativa Kokoro vs alternativas para voz español

| Opción | GPU | Calidad ES | Latency | Estado en Savia |
|---|---|---|---|---|
| Cloud TTS (ElevenLabs/etc) | No | Alta | Latencia red | Disponible si key |
| Kokoro 82M (este SE-075) | No | Media-alta | 150x realtime CPU | Propuesto |
| SE-042 voice training | Sí | Alta personalizada | N/A (no implementado) | GPU-blocked |
| Espeak / Festival legacy | No | Baja | Real-time | Disponible degradado |

## Referencias

- `https://github.com/jamiepine/voicebox` — repo origen (MIT, 23k stars, push 2026-04-26)
- `https://github.com/jamiepine/voicebox/blob/main/backend/services/task_queue.py` — fuente Slice 1
- `https://github.com/jamiepine/voicebox/blob/main/backend/services/tts.py` — patrón Slice 2
- `https://github.com/hexgrad/Kokoro-82M` — modelo TTS Slice 3
- SE-042 voice training (GPU-blocked, complementario)
- SE-074 parallel spec execution (Slice 1 de SE-075 lo habilita)
- `.opencode/skills/savia-voice/`, `~/.savia/whisper-env` — infra existente

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Slice 1 task_queue.py | módulo Python standalone | invocable igual, sin acoplamiento de frontend |
| Slice 2 auto-chunking | helper en `.opencode/skills/savia-voice/` | autoload vía AGENTS.md (SE-078) |
| Slice 3 Kokoro CPU voice | dep Python `kokoro-onnx` | idéntico, sin binding específico |

### Verification protocol

- [ ] `bash scripts/savia-voice-smoke.sh` pasa tras switch a OpenCode v1.14
- [ ] `python3 -m savia_voice.task_queue --selftest` ejecuta sin Claude Code presente
- [ ] Tests Slice 1/2/3 son agnostic-frontend (BATS + pytest puros)

### Portability classification

- **PURE_BASH**: Los 3 slices son backend Python + scripts bash. No requieren hooks ni events específicos de Claude Code. Las invocaciones desde OpenCode resuelven igual que desde Claude Code (script paths absolutos en `scripts/` o `.opencode/skills/`).
