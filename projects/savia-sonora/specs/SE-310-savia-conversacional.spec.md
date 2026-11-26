# Spec: SE-310 — Savia Conversacional (S0): interfaz de voz bidireccional en Savia Transcriptor

**Task ID:**        SE-310
**PBI padre:**      SE-310 — Savia conversacional: Savia habla con la operadora (extension de SE-308)
**Sprint:**         2026-08
**Fecha creacion:** 2026-08-07
**Creado por:**     Savia (auditoria de capacidades de voz existentes)

**Developer Type:** agent-team
**Asignado a:**     python-developer + frontend-developer (React)
**Estado:**         SUPERSEDED por SE-537 (2026-11-26): el cerebro pasa a la sesión de Claude de Savia; Ollama queda descartado

**Decisiones de diseño (2026-08-07, propuestas para aprobacion):**

| Decision | Eleccion | Justificacion |
|---|---|---|
| Alcance S0 | **Conversacion bidireccional push-to-talk** | Cierra "Savia habla conmigo" con lo ya existente. Participacion en vivo en S1/S2 (fuera de alcance) |
| Entrada de voz | **Reusar dictado push-to-talk existente** (release-to-send) | Ya captura audio por hotkey + transcribe con faster-whisper; cero infra nueva |
| Hotkey conversacion | **SEPARADO del dictado** (default `ctrl+alt+win`) | El dictado pega en el cursor; la conversacion envia al LLM. El mismo hotkey no puede hacer ambos: el release seria indeterminado. Hotkey propio con callbacks propios |
| Cerebro | **Reusar `OpenAICompatibleProvider`** (OpenAI/Groq/OpenRouter/LM Studio/Ollama) | Ya existe con streaming; default Ollama = todo local N3 |
| Salida de voz | **`TTSProvider` pluggable**: backend `subprocess` + `none` | Patron `$SAVIA_TTS_CMD` de SE-075 (placeholders `{out}/{text}`); reutiliza `savia-kokoro.py` si esta en PATH/visible |
| TTS por defecto | **`none` (solo texto)** | Misma filosofia que `SAVIA_VOICE=off` (SE-075): no hablar sin opt-in explicito |
| Control de voz | **Un solo switch `voice_enabled` + backend config** | `voice_enabled=false` fuerza no hablar (toggle runtime); `tts_backend=none` es el backend por defecto. Si `voice_enabled=true` pero `tts_backend=none` → el toggle no hace nada visible (doc de settings lo aclara); no hay mas estados |
| Latencia de TTS | **Chunking por frase** (sentence-buffer) + **cap de cola** | Streaming del LLM → TTS por frase. La cola SERIAL tiene tope (default 3 frases): si el LLM va mas rapido que Kokoro, las frases viejas se descartan (barge-in) para que la voz no llegue 30s tarde |
| Audio output | **sounddevice OutputStream** (dependencia ya presente) | Reproduce WAV en el altavoz sin dependencias nuevas |
| Persistencia | **Append por mensaje** en `conversaciones/YYYY-MM-DD-HH-MM.md` | Cada mensaje completo se persiste al terminar (no al cerrar sesion): sobrevive a un cierre de app; `digested` en `index.db` |
| Concurrencia | **Conversacion y grabacion de reunion coexisten** | Dictado ya coexiste con grabacion; la conversacion usa el mismo path de captura push-to-talk (mismo arbitraje de device que el dictado) |
| Confidencialidad | **N3 local**: audio nunca sale de la maquina | STT local (whisper), TTS local (Kokoro); solo TEXT al endpoint LLM configurado; API keys via keyring |
| Sistema de prompt | **Inyectable** (default identidad Savia) | Config `conversation.system_prompt`; evita hardcodear la personalidad |
| Arquitectura (SE-310, de Pipecat) | **Pipeline de etapas modulares** en vez de servicio monolitico | Patron de Pipecat (pipecat-ai): audio → VAD → STT → contexto → LLM → split → TTS → audio. Cada etapa es un procesador reemplazable; S1/S2 (streaming STT, wake word, sidecar en reuniones) son nuevas etapas, no reescrituras |
| Contexto (SE-310, de Pipecat) | **ContextAggregator por presupuesto de tokens** | Sustituye `max_history`+truncado por char: agrega mensajes hasta un presupuesto de tokens, con resumen rodante si se excede (patron `LLMContextAggregator`). Conversaciones largas degradan con gracia |
| Puente a herramientas (SE-310, de JARVIS/LiveKit) | **Tool-calling del LLM → acciones de Savia** | Patron "LLM controlador + ejecutores" de JARVIS (HuggingGPT) y `function_tool` de LiveKit: Savia no solo conversa, puede INVOCAR skills/comandos del workspace desde la conversacion (con confirmacion) |
| Barge-in (SE-310, de Pipecat/Vocode) | **Interrupcion de primera clase** | Si el usuario pulsa el hotkey mientras Savia habla → corta TTS+LLM al instante (no espera al boton). Patron estandar de voice agents |
| Feedback de "pensando" (SE-310, de LiveKit) | **Cue sonoro sutil mientras el LLM procesa** | Enmascara la latencia (2-5s): tono corto o "shimmer" mientras `state=thinking`, igual que LiveKit background audio |
| Proactividad (SE-310, de Alexa+) | **Savia habla sin que la llames** (opt-in) | Triggers programados o por evento (digest de reunion, briefs) inyectan un mensaje hablado+UI. Default OFF; NUNCA interrumpe una reunion en RECORDING; horas de silencio configurables |
| Memoria (SE-310, de Alexa+/Siri) | **Enganche a la memoria de Savia** (decoplado por ficheros) | Lee un contexto en el arranque de sesion (preferencias/proyecto activo) e inyecta en el system prompt; al cerrar, escribe "memory candidates" que el workspace digiere en la auto-memory (patron SE-308: la app escribe, Savia digiere) |
| Contexto multimodal (SE-310, de Gemini Live) | **Savia ve la pantalla** (opt-in) | En cada turno de usuario, captura screenshot (mss, ya dep) y lo adjunta al LLM si el modelo es vision-capable. Default OFF (privacidad); degrada a texto si el modelo no ve o falla la captura |
| Cupulas de contexto (SE-310, de SaviaVaults) | **Savia consume y alimenta las cupulas de Savia Vaults configuradas** | `VaultBridge` (A2A HTTP, localhost:8923): CONSUME (search+context de domes en cada turno, RAG sobre el conocimiento) y ALIMENTA (share de notas de conversacion al dome configurado). Gate de confidencialidad: solo domes <= nivel permitido segun endpoint LLM (local → hasta N4b; cloud → solo N1/N2) |
| Flujo de inferencia (SE-310) | **Analizar → Construir → Contestar, con grounding en cupulas** | El LLM (1) ANALIZA el turno contra el contexto recuperado de las cupulas, (2) CONSTRUYE la respuesta fundamentada (+ tools via ToolsBridge si hace falta), (3) CONTESTA por voz y escribe el conocimiento de vuelta a la cupula (VaultFeed) |
| Audio Briefs (SE-310, de NotebookLM) | **Contenido hablado de formato largo fundamentado en las cupulas** | Patron Audio Overviews de NotebookLM (discusion tipo podcast entre hosts AI, grounded en fuentes): Savia genera briefs hablados (resumen del proyecto, del sprint, de una cupula) — no turn-by-turn: LLM escribe el guion desde las cupulas → TTS → fichero de audio + transcripto digerible |
| Perfil de voz (SE-310, de NotebookLM) | **Voz seleccionable sin clonar a nadie** | `conversation.voice_profile`: voz de Kokoro (ef_dora, af_heart, ...) configurable. Difiere de SE-042 (clonar VOZ HUMANA sin consentimiento: prohibido — Nota legal: caso de voz clonada sin permiso en NotebookLM 2025) |
| Cita hablada (SE-310, de NotebookLM) | **Savia cita la fuente de la cupula mientras habla** | Toggle `brief.cite_spoken`: "segun mi nota en <path>..." al referirse a conocimiento recuperado (los hosts de Audio Overviews referencian las fuentes verbalmente) |

**Effort Estimation (Dual Model):**

| Dimension | Value |
|---|---|
| Agent effort | 1080 min (estimacion inicial; +proactividad/memoria/vision/cupulas/briefs) |
| Human effort | 42 h |
| Review effort | 150 min |
| Context risk | low |
| Agent-capable | partial (audio real requiere humano) |
| Fallback | Si agente falla: humano necesita 21h |

---

## 1. Contexto y Objetivo

Savia Transcriptor (SE-308, fork de VoiceFlow) ya **graba reuniones** de forma
autonoma: VAD (silero-vad) detecta voz, graba `audio.wav` + screenshots y
transcribe localmente con faster-whisper. El workspace ya tiene **voz de salida**
local: SE-075 Slice 3 (Kokoro 82M, CPU, espanol) implementado el 2026-06-24
(`scripts/savia-kokoro.py`, `scripts/savia-voice-speak.sh`, `savia-voice-chunk.sh`).

**Hueco**: nadie ha unido las dos mitades. Savia puede ESCUCHAR (transcriptor)
y puede HABLAR (Kokoro), pero no hay un bucle conversacional: la operadora no
puede decirle algo por microfono y recibir respuesta por voz en una conversacion
continua.

**Objetivo S0**: convertir Savia Transcriptor en una **interfaz conversacional
de Savia** para el objetivo "hablar conmigo":

1. La operadora pulsa el hotkey de push-to-talk (reusado del dictado) y habla.
2. El Transcriptor transcribe localmente (faster-whisper).
3. Envia el texto al cerebro (OpenAICompatibleProvider → Ollama/OpenRouter, con
   el system prompt de Savia).
4. Transmite la respuesta en streaming a la UI **y** la sintetiza por frases
   (TTSProvider → Kokoro via subprocess) reproduciendola por el altavoz.
5. Guarda el transcripto de la conversacion en `~/.savia/transcriptor/conversaciones/`
   para que Savia la digiera despues (transcriptor-digest), como ya hace con reuniones.

**Diferenciador**: no es un chat de voz genérico. Es la misma Savia (identidad,
memoria, skills) hablando por el mismo pipeline local N3 que el workspace usa
por texto. La conversacion queda persistida como un artefacto digerible, igual
que una reunion.

---

## 2. Arquitectura

### 2.1 Bucle conversacional (pipeline modular, patron Pipecat)

Cada etapa es un procesador reemplazable. S0 cablea las etapas A-F; las etapas
para S1/S2 (STT en streaming, wake word, transporte de reunion) se anaden como
nuevos procesadores sin tocar los existentes.

```
┌──────────────────────────────────────────────────────────────────────┐
│                    Savia Transcriptor (app)                            │
│                                                                        │
│  AUDIO_IN ──► VAD ──► STT ──► CONTEXT ──► LLM ──► SPLIT ──► TTS ──► AUDIO_OUT
│   (hotkey)   (silero) (whisper) (agg)     (stream)  (frases) (kokoro)
│      │              ▲           ▲
│      │              │           │ VaultContext (CONSUME, S0-H): search+read
│      │              │           │   de domes configurados -> bloque 'CUPULAS'
│      │              │           │   en el contexto (RAG sobre conocimiento)
│      │              │           │   + VisionContext (S0-G, opt-in)
│      │              └───────────┴── MemoryContext (S0-F): preferencias/proyecto
│      │
│      └──► barge-in: si el hotkey se pulsa durante SPEAKING, corta
│           TTS + LLM al instante (interrupcion de primera clase)
│           │
│           ▼
│  ┌────────────────┐    ┌──────────────────────────────────────────┐   │
│  │ ToolsBridge    │◄───│ LLM tool-calling → acciones de Savia     │   │
│  │ (S0-A: solo    │    │ (skills/comandos del workspace, con      │   │
│  │  confirmacion) │    │  confirmacion). Patron JARVIS controller │   │
│  └────────────────┘    └──────────────────────────────────────────┘   │
│                                                                        │
│  VaultFeed (ALIMENTA, S0-H, post-sesion): escribe la nota de la        │
│  conversacion en el dome configurado (POST /share) — el conocimiento   │
│  vuelve a la cupula. MemoryBridge (S0-F) escribe memory.md aparte.     │
│                                                                        │
│  ┌──────────────────┐   ┌───────────────────────────────┐             │
│  │ TTSProvider      │   │ ConversationStore             │             │
│  │  subprocess/none │   │ ~/.savia/transcriptor/        │             │
│  └─────────┬────────┘   │   conversaciones/YYYY-MM-DD/  │             │
│            │ WAV        └───────────────┬───────────────┘             │
│  ┌─────────▼────────┐                    │                             │
│  │ AudioOutput      │                    ▼                             │
│  │ (sounddevice)    │        Savia digiere via transcriptor-digest     │
│  └──────────────────┘                                                 │
└──────────────────────────────────────────────────────────────────────┘

  Fuera del app (decoplado): SaviaVaults A2A server (127.0.0.1:8923)
  expone /search, /context/{path}, /stats, /share (Bearer auth, rate-limit).
  VaultBridge habla con el; las cupulas configuradas viven en
  savia-vaults.domes.json (con nivel de confidencialidad N1-N4b).

  Etapas S1/S2 (futuras, NO en S0): STT-streaming + wake-word (S1),
  transporte de reunion tipo "sidecar" sobre el bus de audio (S2),
  timestamps por palabra (WhisperX) para interrupcion precisa (S2).
```

### 2.2 Contratos

```python
# services/conversation/tts_provider.py
class TTSProvider(Protocol):
    # TODAS las implementaciones son NO-BLOQUEANTES: encolan en un worker
    # thread y devuelven al instante (nunca congelan la UI). Reproduccion
    # SERIAL: una frase por vez; la siguiente espera a que termine la anterior.
    def speak(self, text: str) -> None: ...
    def stop(self) -> None: ...            # corta cola + audio en curso (interrupcion)

class SubprocessTTS:
    """Backend subprocess. Contrato: el comando escribe el audio en `{out}`
    (WAV 16kHz mono) y recibe el texto en `{text}` (patron SE-075).
    Ejemplo default: kokoro | python3 savia-kokoro.py --text {text} --output {out} --json
    Si el comando no existe o falla -> degrada a none (no rompe la conversacion)."""
    def __init__(self, command_template: str, playback: AudioOutput,
                 worker: "SerialAudioQueue"): ...

class NoopTTS:
    """Backend none: solo texto. Es el default (opt-in de voz)."""

def build_tts(settings) -> TTSProvider: ...

# services/conversation/audio_output.py
class AudioOutput:
    """Reproduce WAV 16kHz mono via soundfile.read + sounddevice.OutputStream.
    Stop() corta el stream actual. Sin dependencias nuevas."""

# services/conversation/conversation_service.py
class ConversationMessage(TypedDict):
    role: Literal["user", "assistant"]
    content: str
    timestamp: str

# services/conversation/context_aggregator.py
class ContextAggregator:
    """Agrega el historial al LLM bajo un PRESUPUESTO DE TOKENS (no conteo de
    mensajes). Mantiene system_prompt + ultimos N mensajes dentro del budget;
    si se excede, descarta los mas antiguos y (opcional) anade un resumen
    rodante de una linea. Pattern: LLMContextAggregator de Pipecat."""

# services/conversation/tools_bridge.py
class ToolsBridge:
    """Traduce tool-calls del LLM a acciones de Savia (skills/comandos del
    workspace). En S0: SOLO acciones de solo-lectura o que requieren
    confirmacion explicita del usuario en la UI antes de ejecutar. El LLM
    recibe la lista de tools disponibles como function calling."""

class ConversationService:
    """Orquesta push-to-talk -> transcribe -> LLM stream -> TTS -> persist.
    Ejecuta en background thread; la UI recibe eventos IPC (nunca bloqueo)."""
    def __init__(self, transcriber, llm: OpenAICompatibleProvider,
                 tts: TTSProvider, store: ConversationStore,
                 context: ContextAggregator, tools: ToolsBridge,
                 system_prompt: str): ...

    def on_push_to_talk_released(self, audio: np.ndarray) -> None: ...
        # 1. transcribe audio (REUSA el modelo whisper global ya cargado, sin recargar)
        # 2. si transcripto vacio/silencio -> descarta, no envia nada al LLM
        # 3. add user msg -> stream llm (max_history)
        #    on token: event conversation:token (UI live) + sentence-buffer
        #    frase completa -> tts.speak(frase)
        # 4. on complete: persist to store, event conversation:state=idle
        # 5. on error: event conversation:error, estado recuperable

    def cancel(self) -> None: ...          # interrumpir respuesta: para LLM stream + tts.stop()
    def reset(self) -> None: ...           # nueva conversacion
    def history(self) -> list[ConversationMessage]: ...
```

**Hotkey / desambiguacion**: el dictado (`ctrl+win`) y la conversacion
(`ctrl+alt+win`) son hotkeys DISTINTOS. El `HotkeyService` registra callbacks
separados: el release del hotkey de conversacion llama a
`ConversationService.on_push_to_talk_released` (nunca al path de dictado).
Si el usuario pulsa ambos hotkeys a la vez, gana el primero registrado; el
segundo release se ignora hasta que el primero complete (guard anti-solapamiento).

**Arbitraje de device de audio**: el push-to-talk de conversacion captura por
el MISMO path que el dictado (ya coexiste con la grabacion de reunion en SE-308).
No se abre un segundo stream sobre el device del mic mientras el dictado o la
reunion lo usan — se serializa la captura push-to-talk con un lock de un solo
usuario a la vez. Si el lock esta tomado (reunion grabando), el push-to-talk de
conversacion se encola y arranca al soltar la reunion (max wait 2s, si no → aviso).

**Estado ocupado**: mientras el estado NO es `idle` (transcribiendo/pensando/
hablando), un nuevo push-to-talk se rechaza con `conversation:notice`
("Savia esta respondiendo") salvo que se cancele primero. Evita colas de
peticiones sin control y respuestas solapadas.

**Carga del modelo whisper**: lazy-load compartido con el resto de la app. La
primera conversacion puede pagar la carga del modelo (segundos); el spec NO
exige recargar por conversacion. El modelo usado es el global configurado; si se
quiere menor latencia, la operadora configura un modelo pequeno (settings).

**IPC contract (Pyloid bridge, backend → frontend):**

| Evento | Payload | Significado |
|---|---|---|
| `conversation:state` | `idle\|listening\|transcribing\|thinking\|speaking\|error` | Maquina de estados visible en UI |
| `conversation:message` | `{role, content, timestamp}` | Mensaje completo (user o assistant), persistido al completar |
| `conversation:token` | `{delta}` | Token parcial en streaming |
| `conversation:error` | `{message, recoverable}` | Fallo de LLM/TTS, UI no se corrompe; NO incluye prompt ni tokens |
| `conversation:history` | `messages[]` | Al abrir la vista: carga la sesion persistida en curso (o vacio si es nueva) |
| `conversation:notice` | `{kind, text}` | Avisos no-bloqueantes: "voz no disponible, respondo por texto" (una vez por sesion), "hotkey en uso", etc. |

**Interrupcion (barge-in)**: el usuario puede parar la respuesta de Savia de
DOS formas, ambas con el mismo `ConversationService.cancel()`:
1. Segundo pulso del hotkey (o boton UI) durante `speaking`/`thinking`.
2. **Barge-in automatico**: pulso del hotkey durante `speaking` corta TTS+LLM
   al instante — Savia "para de hablar cuando le interrumpes" (patron estandar
   de voice agents, Pipecat/Vocode). La parte ya completada queda persistida.

**Feedback de "pensando"**: mientras `state=thinking` (latencia LLM 2-5s), la
UI muestra el estado Y se reproduce un cue sonoro sutil (configurable, default
off) para que el usuario sepa que Savia esta procesando. Cue != voz: un tono
corto o shimmer, nunca contenido hablado (no confunde al mic).

**Sentence buffer**: flushes en `.?!\n` o tras N chars (N=180 default). Si una
frase excede N sin puntuacion, se corta por el ultimo espacio (no bloquea el stream).

**Cola TTS (barge-in)**: `SerialAudioQueue` reproduce UNA frase a la vez. Si
llegan mas de `tts_queue_cap` (default 3) frases pendientes, la mas antigua se
descarta (la voz no se acumula detras del texto). El texto de la UI SIEMPRE
muestra la respuesta completa aunque la voz se descarte.

**Redaccion en logs**: `transcriptor.log` NUNCA registra el contenido de
mensajes de conversacion (solo eventos: `conversation:started`, `message:ok`,
`error:llm_timeout`, con duraciones/IDs). El contenido vive solo en
`conversaciones/*.md` y `index.db` (ambos N3).

### 2.3 Configuracion (settings)

| Clave | Default | Descripcion |
|---|---|---|
| `conversation.enabled` | `true` | Activa la vista y el hotkey de conversacion |
| `conversation.hotkey` | `ctrl+alt+win` | Hotkey push-to-talk SEPARADO del dictado (`ctrl+win`); release = enviar al LLM |
| `conversation.max_seconds` | `60` | Limite de duracion del push-to-talk; el audio mas largo se corta y avisa (bound de input a whisper) |
| `conversation.llm_endpoint` | (reusa global) | OpenAI-compatible endpoint; `http://localhost:11434/v1` (Ollama) |
| `conversation.llm_model` | (reusa global) | Modelo |
| `conversation.llm_api_key` | keyring | Via keyring (ya en VoiceFlow); vacio = endpoint local sin auth |
| `conversation.llm_timeout_s` | `30` | Timeout por turno; al expirar → `conversation:error` recuperable (el provider global usa read 120s; la conversacion exige respuesta en 30s) |
| `conversation.system_prompt` | Identidad Savia | Texto inyectable; default identidad de Savia |
| `conversation.personality_style` | `savia` | Estilos de tono (patron Alexa+ Brief/Chill/Sweet/Sassy): `savia` (default, radical-honesty) \| `brief` \| `chill` \| `sweet` \| `sassy`. Se inyecta como instruccion de tono ADICIONAL al system_prompt (no cambia capacidades) |
| `conversation.context_token_budget` | `8000` | Presupuesto de tokens del historial enviado al LLM (ContextAggregator); los mensajes fuera de presupuesto se descartan o se resumen |
| `conversation.tools_enabled` | `false` | Habilita tool-calling → ToolsBridge (acciones de Savia con confirmacion). Off en S0 default: primero la conversacion limpia |
| `conversation.thinking_cue` | `false` | Reproduce el cue sonoro de "pensando" durante la latencia del LLM |
| `proactive.enabled` | `false` | Habilita triggers proactivos (S0-E). SIEMPRE respeta quiet_hours y RECORDING |
| `proactive.schedule` | `` | Cron-like de mensajes programados (brief, recordatorio) |
| `proactive.quiet_hours` | `22:00-07:00` | Ventana en la que NUNCA se habla proactivamente |
| `proactive.event_dir` | `~/.savia/transcriptor/events/` | Fuente de eventos del workspace (ficheros .json) |
| `conversation.memory_context_enabled` | `true` | Inyecta contexto (preferencias/proyecto activo) al system prompt (S0-F) |
| `conversation.memory_persist` | `true` | Escribe `memory.md` con memory candidates al cerrar sesion (S0-F) |
| `conversation.vision_enabled` | `false` | Captura de pantalla en cada turno si el modelo es vision-capable (S0-G). Default OFF por privacidad |
| `conversation.vision_model_capable` | `false` | Declara si el modelo LLM configurado acepta imagenes (evita prueba y error) |
| `vaults.enabled` | `false` | Habilita la integracion con las cupulas de SaviaVaults (S0-H). Default OFF |
| `vaults.base_url` | `http://127.0.0.1:8923` | Endpoint A2A de SaviaVaults |
| `vaults.config_path` | `projects/savia-vaults/savia-vaults.domes.json` | Cupulas configuradas (domes) + nivel de confidencialidad |
| `vaults.auth_token` | (de config/keyring) | Bearer token del A2A server |
| `vaults.domes` | `[]` | Domes a consultar; vacio = todos los configurados (respetando el gate) |
| `vaults.max_confidentiality` | `N2` | Nivel maximo a CONSUMIR. Default conservador N2; la operadora lo sube a N4b SOLO con endpoint LLM local |
| `vaults.top_k` | `3` | Notas relevantes a inyectar por turno (cruzando domes) |
| `vaults.write_dome` | (defaultDome) | Dome donde VaultFeed escribe las notas de conversacion |
| `vaults.write_path_prefix` | `conversaciones/` | Prefijo de path para las notas escritas |
| `conversation.voice_profile` | `ef_dora` | Voz de Kokoro para Savia (seleccionable, sin clonacion). Aplica a conversacion y briefs |
| `brief.enabled` | `false` | Habilita Audio Briefs de formato largo (S0-I). Default OFF |
| `brief.format` | `solo` | `solo` (monologo) \| `dialogo` (Savia + co-host sintetico, patron NotebookLM) |
| `brief.cite_spoken` | `false` | Savia cita la fuente verbalmente al referirse a contenido de cupulas |
| `brief.max_minutes` | `10` | Duracion objetivo del brief (el guion lo respeta) |
| `brief.focus` | `` | Tema/angulo del brief (guidance, patron NotebookLM); vacio = global |
| `conversation.tts_backend` | `none` | `none` \| `subprocess` |
| `conversation.tts_command` | `` | Plantilla `{out}`/`{text}` (ej. `savia-kokoro --text {text} --output {out} --json`); WAV temporal en `~/.savia/transcriptor/tmp-tts/` con limpieza al arrancar |
| `conversation.tts_queue_cap` | `3` | Frases pendientes max en la cola TTS; exceso = descartar la mas antigua (barge-in) |
| `conversation.voice_enabled` | `false` | Interruptor runtime (sin recargar): hablar si/no. Inefectivo si `tts_backend=none` (doc de settings lo aclara) |

### 2.4 Persistencia

```
~/.savia/transcriptor/conversaciones/
├── 2026-08-07-18-00.md        # transcripto en markdown, estilo transcript.md
└── index.db                   # SQLite, misma DB que MeetingStore
```

Tabla `conversations` (aditiva, no toca las tablas de reuniones):

```sql
CREATE TABLE IF NOT EXISTS conversations (
    id          INTEGER PRIMARY KEY,
    started_at  TEXT NOT NULL,          -- ISO-8601
    dir         TEXT NOT NULL UNIQUE,   -- conversaciones/YYYY-MM-DD-HH-MM/
    message_count INTEGER NOT NULL DEFAULT 0,
    digested    INTEGER NOT NULL DEFAULT 0,
    meta_path   TEXT NOT NULL
);
```

`ConversationStore` reutiliza el patron de `MeetingStore` (carpeta por sesion,
`meta.json` con flag `digested`) para que `transcriptor-digest` y `meeting-digest`
puedan digerir conversaciones igual que reuniones, sin cambios en el skill.
El `transcripto` en `conversaciones/*.md` usa el mismo formato que
`transcript.md` de las reuniones (hablante: texto).

---

## 2.5 Proactividad (S0-E) — Savia habla sin que la llames

```python
# services/conversation/proactive_trigger.py
class ProactiveSource(Protocol):
    def poll(self) -> Optional[str]: ...   # texto candidato, o None

class ScheduledSource:
    """Cron-like (reutiliza patron automation-scheduler del workspace):
    briefs, recordatorios. Config `proactive.schedule` (cron) + `proactive.text`."""
class EventSource:
    """Eventos del workspace: digest de reunion completado, PBI bloqueado, etc.
    Fuente por fichero: el workspace escribe `~/.savia/transcriptor/events/*.json`
    y el app lo consume (patron decoplado SE-308)."""

class ProactiveTrigger:
    """Orquesta fuentes → mensaje 'proactive' hablado + UI + persistido.
    GATES OBLIGATORIOS (no negociables):
      - NO disparar si estado == RECORDING (reunion grabando) o conversacion activa
      - NO disparar fuera de horas de silencio (`proactive.quiet_hours`)
      - Inyecta como mensaje `role=proactive` en la UI; el LLM NO responde salvo
        que el usuario conteste (entonces continua como conversacion normal)
    """
```

**Por que este diseno**: la proactividad mas segura es una NOTIFICACION hablada,
no una conversacion no solicitada. Savia dice una linea (brief, alerta, digest) y
se calla; si el usuario responde, la conversacion continua normal. Eso evita el
problema de asistentes que "hablan solos" sin control.

## 2.6 Memoria (S0-F) — enganche a la memoria de Savia

```python
# services/conversation/memory_bridge.py
class MemoryBridge:
    """Conexion DECOPLADA con la memoria de Savia (patron SE-308: la app
    escribe ficheros, el workspace los digiere). NUNCA llama a memory-store.sh
    directamente (acoplamiento)."""

    def load_context(self) -> str:
        """LECTURA al arrancar la sesion:
        - `~/.savia/preferences.yaml` (preferencias, alert_style, tone)
        - `~/.savia/context-active.md` (proyecto activo, generado por el workspace)
        Si faltan → "" (no rompe). Se inyecta como bloque 'CONTEXTO' del system prompt."""
        ...

    def persist_memory(self, session_dir: Path, messages: list) -> Path:
        """ESCRITURA al cerrar la sesion:
        `conversaciones/<sesion>/memory.md` con hechos/decisiones/preferencias
        (extraidos por el LLM en el ultimo turno, o el usuario los dicta).
        El workspace lo digiere en la auto-memory (memory-agent / savia-memory)."""
        ...
```

**Efecto**: Savia recuerda entre conversaciones (recuerda la pizza vegetariana,
el proyecto activo, el tono preferido) sin que el app se acople al motor de
memoria. Es el mismo patron que las reuniones: la app produce el artefacto, el
workspace lo digiere.

## 2.7 Contexto multimodal (S0-G) — Savia ve la pantalla (opt-in)

```python
# services/conversation/vision_context.py
class VisionContext:
    """En cada turno de usuario, si `vision.enabled`, captura la pantalla
    actual (mss, ya dependencia) → downscale a max 1280px → lo adjunta al
    mensaje del LLM como imagen (OpenAI-compatible content con image_url/data URL).

    REGLAS:
      - Degrada a texto si: el modelo configurado no es vision-capable,
        la captura falla, o el endpoint no acepta imagenes (comprobado por
        `vision.model_capable` en settings, no por prueba y error).
      - SOLO se envia al endpoint LLM configurado; si es Ollama local con
        modelo vision (llava/gemma3), la imagen no sale de la maquina (N3).
      - Default OFF: ver la pantalla es sensible. La UI muestra un indicador
        visible cuando esta activo (privacidad por diseño)."""
```

**Nota de privacidad**: activar vision envia capturas de pantalla al endpoint
LLM. Si el endpoint es cloud, las capturas salen de la maquina — el usuario
debe saberlo. Se recomienda vision SOLO con endpoint local (Ollama vision).

## 2.8 Integracion con SaviaVaults (S0-H) — Savia consume y alimenta las cupulas

SaviaVaults (`projects/savia-vaults/`) es el almacen de conocimiento de Savia:
**cupulas de contexto** (domes) con nivel de confidencialidad (N1-N4b),
busqueda BM25, notas con frontmatter y grafo de conocimiento. El A2A server
(`127.0.0.1:8923`) expone `/search`, `/context/{path}`, `/stats`, `/share`,
`/domes` (lista de cupulas con su confidencialidad) y `/search?dome=` (busca
en una cupula concreta o en todas, fusionando resultados con el campo `dome`).
**Mejora implementada (2026-08-07)**: multi-dome A2A + indice cacheado por
fingerprint (mtime) — el `/search` ya no reconstruye el indice en cada request
(antes colgaba con vaults grandes o node_modules). El sistema de voz se conecta
a el de forma DECOPLADA (mismo patron SE-308: la app habla HTTP, nunca acopla a
`savia-vaults`).

```python
# services/conversation/vault_bridge.py
class VaultBridge:
    """Cliente A2A de SaviaVaults (HTTP localhost). Lee las cupulas
    configuradas de savia-vaults.domes.json + savia-vaults.config.json
    (port, auth). Sin dependencia del codigo de savia-vaults: solo HTTP."""

    def __init__(self, base_url: str, auth_token: str, domes: list[DomeSpec],
                 max_confidentiality: str): ...

    def list_domes(self) -> list[DomeInfo]:
        """GET /domes — descubre las cupulas activas y su nivel de
        confidencialidad (sustituye a leer domes.json a mano; la fuente es el
        server)."""

    def search(self, query: str, top_k: int = 3, dome: Optional[str] = None) -> list[VaultHit]:
        """GET /search?q=&maxResults=&dome= — BM25 sobre una cupula o todas.
        Cada hit lleva el campo `dome` (de donde viene). Aplica el GATE DE
        CONFIDENCIALIDAD: solo consulta domes con confidentiality <=
        max_confidentiality (usa list_domes para filtrar ANTES de buscar)."""

    def read(self, vault: str, path: str) -> Optional[Note]:
        """GET /context/<vault>/<path> — nota completa (frontmatter+content)."""

    def write(self, vault: str, path: str, content: str) -> Optional[Receipt]:
        """POST /share — escribe una nota en el dome (ALIMENTAR)."""

class VaultContext:
    """Etapa CONSUME del pipeline: antes de construir el contexto LLM, busca
    en las cupulas y adjunta las notas relevantes como bloque 'CUPULAS'.
    Sin resultados relevantes -> degrada a contexto de conversacion (no rompe)."""

class VaultFeed:
    """Etapa ALIMENTA (post-sesion): escribe la nota de la conversacion en el
    dome configurado (`vaults.write_dome`, default el defaultDome de domes.json):
    `conversaciones/YYYY-MM-DD-HH-MM.md` (transcripto) + nota breve de
    hechos/decisiones. Falla del servidor -> degrada a local (no pierde nada:
    ConversationStore ya persistio localmente)."""
```

**Gate de confidencialidad (no negociable)**: el nivel de confidencialidad que
la conversacion puede CONSUMIR depende del endpoint LLM:

| Endpoint LLM | `vaults.max_confidentiality` permitido | Razon |
|---|---|---|
| Ollama local (endpoint localhost) | `N4b` (todo) | El contenido no sale de la maquina |
| Cloud (OpenRouter/OpenAI/...) | `N2` maximo | El contenido de cupulas viaja al proveedor; N3/N4b jamas |

El gate se aplica ANTES de la consulta (un dome sobre el limite NO se consulta,
ni se inyecta su contenido en el prompt). Es configuracion explicita
(`vaults.max_confidentiality`), no inferencia del app.

## 2.9 Flujo de inferencia: como Savia analiza, construye y contesta

El sistema de voz consume inferencia en TRES fases por turno. La inferencia
(local via Ollama por defecto) es el UNICO lugar donde se razona; las etapas
de audio (STT/TTS) son deterministicas y no usan el LLM.

```
TURNO DEL USUARIO (push-to-talk)
  │
  ├─ 1. ANALIZAR  (comprender el turno en su contexto)
  │     • STT transcribe (whisper, deterministico)
  │     • ContextAggregator reune: system_prompt + historial + memoria
  │       (S0-F) + CUPULAS recuperadas (S0-H) + pantalla (S0-G, opt-in)
  │     • EL LLM interpreta la intencion DEL TURNO CONTRA ESE CONTEXTO:
  │       "que pide, que sabemos, que falta"  → no contesta todavia
  │
  ├─ 2. CONSTRUIR (razonar la respuesta fundamentada)
  │     • El LLM genera la respuesta GROUNDED en el bloque CUPULAS y memoria
  │       (cita fuentes de la cupula si las usa: path de la nota)
  │     • Si hace falta accion → tool-call via ToolsBridge (vault_query,
  │       skills/comandos) CON confirmacion (AC-12)
  │     • Streaming: los tokens salen a la UI y al sentence-buffer
  │
  └─ 3. CONTESTAR (hablar y devolver conocimiento)
        • TTS por frases → altavoz (barge-inable)
        • Al completar: VaultFeed escribe la nota en la cupula (S0-H)
          + MemoryBridge escribe memory.md (S0-F) + ConversationStore
        • La conversacion queda digerible por transcriptor-digest
```

**Regla de fundamentacion**: si la respuesta del LLM usa contenido de una
cupula, DEBE citarla (path de la nota) en el texto (para la UI) o en metadata
(para el digest). Evita que Savia presente conocimiento recuperado como
inventado. El sistema prompt lo exige explicitamente.

## 2.10 Audio Briefs fundamentados (S0-I) — contenido hablado de formato largo

Patron de NotebookLM (Audio Overviews): generar audio conversacional de formato
largo a partir de una base de conocimiento, en vez de respuestas turn-by-turn.
Savia produce briefs hablados grounded en las cupulas: "resumen hablado del
proyecto", "digest hablado del sprint", "explicame esta cupula".

```python
# services/conversation/audio_brief.py
class AudioBriefGenerator:
    """Genera contenido hablado de formato largo desde las cupulas.

    Fases (reutiliza el pipeline, sin etapas nuevas de audio):
      1. RECOPILAR: VaultContext recupera notas relevantes de los domes
         configurados (mismo consume de S0-H), mas VaultFeed-style digest.
      2. GUIONIZAR: el LLM escribe el guion (no turn-by-turn) con formato
         `solo` (monologo Savia) o `dialogo` (Savia + co-host, patron
         NotebookLM de 2 hosts). Aplica focus/tono (guidance) y la cita
         hablada si `brief.cite_spoken`.
      3. SINTETIZAR: TTS por frases (pipeline existente) → fichero
         `~/.savia/transcriptor/audio-briefs/YYYY-MM-DD-HH-MM/`
         (audio.wav + guion.md + meta.json con las fuentes citadas).
      4. PUBLICAR: queda en ConversationStore/MarkingStore; `transcriptor-digest`
         puede digerir el guion (es conocimiento nuevo para las cupulas).
    """

    def generate(self, prompt: str, format: Literal['solo','dialogo']='solo',
                 focus: Optional[str]=None, max_minutes: int = 10) -> Brief: ...
```

**Grounded y trazable**: el guion referencia los paths de las notas usadas
(metadata `sources` en meta.json). Es el mismo principio de citacion de 2.9,
aplicado a contenido de formato largo.

**Ethics guard (no negociable)**: el `dialogo` usa la voz de Savia y un co-host
sintetico generico. NUNCA clona la voz de una persona sin su consentimiento
(leccion del caso de voz clonada sin permiso en NotebookLM, 2025; alineado con
los principios eticos de Savia y con SE-042 que queda GPU-blocked y aparte).

---

## 3. Inputs/Outputs

### Outputs
- Texto de respuesta en streaming (UI)
- Voz sintetizada por el altavoz (si `voice_enabled` y `tts_backend` != none)
- `~/.savia/transcriptor/conversaciones/YYYY-MM-DD-HH-MM.md` — transcripto persistido
- Eventos IPC al frontend: `conversation:message`, `conversation:token`,
  `conversation:error`, `conversation:state`

---

## 4. Constraints and Limits

- **Local-first**: audio (entrada y salida) nunca sale de la maquina. Solo el
  TEXT del prompt viaja al endpoint LLM configurado. Si el endpoint es Ollama
  local, todo permanece N3 local.
- **Sin nuevos deps**: sounddevice, httpx, numpy, faster-whisper ya estan en
  `pyproject.toml`. El backend subprocess no exige empaquetar Kokoro en la app:
  usa el comando del sistema si existe; si no, degrada a `none`.
- **Latencia objetivo**: primera frase por voz < 5s desde el release del hotkey
  (whisper small + Ollama + Kokoro ~4s por 0.625s de audio). La respuesta
  completa por voz puede exceder (cola acotada); el texto es inmediato.
  **Honestidad vs industria 2026**: los voice agents cloud (OpenAI Realtime,
  Gemini Live) apuntan a <1s con speech-to-speech end-to-end. 5s es el
  presupuesto LOCAL-FIRST (N3) de SE-310 — aceptable para asistente personal,
  no compite con cloud. Palancas de optimizacion documentadas: streaming TTS
  por frase (ya), modelo whisper pequeno (config), Ollama con prompt-caching,
  y futuro colapso a speech-to-speech local cuando exista un modelo CPU/ONNX
  de calidad (ver seccion 12).
- **Concurrencia**: si hay una reunion en RECORDING, el push-to-talk de
  conversacion se serializa con un lock (max 2s de espera) y no interfiere con
  la grabacion.
- **No graba silencio**: solo captura cuando el hotkey esta pulsado, y como
  maximo `conversation.max_seconds` (default 60s).
- **Idioma conocido**: whisper auto-detecta; Kokoro sintetiza es/ing. Otros
  idiomas se transcriben pero suenan en la voz configurada (limitacion conocida,
  no bloquea S0).
- **Voz opt-in**: sin `voice_enabled` + backend configurado, Savia responde
  solo por texto (misma filosofia que `SAVIA_VOICE=off`).
- **Privacidad**: API keys via keyring, nunca en config plana ni logs; los logs
  de la app no contienen el contenido de conversaciones.

**Security review (gate pre-implementacion, SE-310)**: la feature trata datos
personales (voz de la operadora, contenido de conversaciones). Requisitos
minimos antes de implementar: (a) revisar que el audio nunca se escribe fuera
de `~/.savia/transcriptor/`; (b) que el subprocess de TTS no pase texto con
shell-expansion insegura (usar `subprocess` con lista de args / `shlex`, nunca
`shell=True`); (c) que `conversation:error` no filtre el contenido del prompt ni
tokens; (d) `digested=1` se respeta en el skill (no re-procesar). El audio de la
operadora es N3 (datos personales) — el code review E1 cubre estas 4 comprobaciones.

---

## 5. Test Scenarios

1. **Bucle completo (fakes)**: push-to-talk simulado → transcriber fake → LLM fake
   stream → TTS fake graba la frase → se persiste el transcripto.
2. **Voice off**: `voice_enabled=false` o `tts_backend=none` → la respuesta sale
   por texto, el TTS no se invoca (TTS fake registra 0 llamadas).
3. **Backend subprocess**: comando plantilla valido → se ejecuta con `{out}`
   y `{text}` sustituidos; comando inexistente → degrada a none, no rompe.
4. **LLM no alcanzable**: endpoint caido → evento `conversation:error`, la UI
   muestra error, la conversacion no se corrompe, reintento posible.
5. **Streaming**: el LLM fake emite tokens parciales → la UI los muestra en
   vivo y el sentence-buffer encola frases completas.
6. **Historia acotada**: 25 mensajes con `max_history=20` → el contexto enviado
   al LLM tiene 20, el resto se conserva en la UI/almacen.
7. **Persistencia**: tras N mensajes, `conversaciones/YYYY-MM-DD-HH-MM.md`
   contiene el transcripto y `index.db` registra la conversacion.
8. **Concurrencia**: con una reunion en RECORDING activa, un push-to-talk de
   conversacion se transcribe sin interrumpir la grabacion.
9. **System prompt**: el LLM fake verifica que `conversation.system_prompt`
   esta en el primer mensaje del contexto.
10. **Perf**: round-trip con modelos reales < 5s en hardware medio.
11. **Transcripcion vacia**: push-to-talk con silencio → `on_push_to_talk_released`
    descarta el audio, no envia nada al LLM, no rompe el estado.
12. **Cancelar**: mientras el LLM emite, `cancel()` corta el stream y el TTS
    (TTS fake registra `stop()`), la UI vuelve a `idle`, la conversacion queda
    parcial persistida sin corromperse.
13. **No bloqueo de UI**: el bucle corre en background; `conversation_service`
    nunca bloquea el hilo principal (verificable con un fake lento + timeout
    en el hilo UI).
14. **Shell-safe TTS**: el subprocess usa lista de args / `shlex.split`, nunca
    `shell=True` (test de inyeccion: texto con `; rm -rf` no ejecuta).
15. **Hotkeys desambiguados**: el release del hotkey de conversacion NUNCA
    invoca el path de dictado (mock del dictado registra 0 llamadas).
16. **Cap de cola TTS**: LLM fake rapido + TTS fake lento → nunca mas de
    `tts_queue_cap` pendientes; la frase mas antigua se descarta.
17. **Persistencia en cierre**: la app se "cierra" a mitad de respuesta → el
    `conversaciones/*.md` ya contiene los mensajes completados hasta ese punto
    (append por mensaje, no por sesion).
18. **Arbitraje de device**: reunion en RECORDING → push-to-talk de conversacion
    se encola y arranca al soltar (o avisa tras 2s); no abre segundo stream
    sobre el mic.
19. **max_seconds**: un push-to-talk mantenido 90s con `max_seconds=60` corta a
    los 60s y emite `conversation:notice`.
20. **Logs sin contenido**: tras una conversacion real, `transcriptor.log` no
    contiene ninguna cadena de los mensajes (solo eventos).
21. **Barge-in**: con la UI en `speaking`, el pulso del hotkey llama a
    `cancel()` (LLM fake registra cancel, TTS fake registra `stop()`), estado
    vuelve a `idle`, lo ya hablado queda persistido.
22. **Contexto por tokens**: 60 mensajes con `context_token_budget=8000` →
    el LLM fake recibe un payload <= presupuesto y los mensajes mas antiguos
    se descartan/resumen, no se envian enteros.
23. **Tool-call**: con `tools_enabled=true`, el LLM fake emite un tool-call →
    `ToolsBridge` lo traduce y la accion queda PENDIENTE de confirmacion en la
    UI (no se ejecuta sin `confirmar`).
24. **Cue de pensando**: con `thinking_cue=true`, durante `state=thinking` se
    reproduce el cue (AudioOutput fake registra 1 cue); nunca contenido hablado.
25. **Personalidad**: con `personality_style=chill`, el LLM fake verifica que el
    system prompt incluye la instruccion de tono adicional (sin cambiar el
    system_prompt de identidad ni las capacidades).
26. **Proactivo — gates**: con `proactive.enabled=true` y un evento en
    `event_dir`, el trigger inyecta el mensaje; durante `state=RECORDING` o en
    `quiet_hours` NO dispara (registra 0 inyecciones).
27. **Proactivo — respuesta**: tras un mensaje `proactive`, el LLM fake NO
    genera respuesta; si el usuario responde por push-to-talk, continua como
    conversacion normal.
28. **Memoria — contexto**: con `memory_context_enabled=true` y un
    `~/.savia/context-active.md` presente, el system prompt incluye el bloque
    CONTEXTO; sin fichero, no rompe (system prompt limpio).
29. **Memoria — persistencia**: al cerrar la sesion, `conversaciones/<sesion>/memory.md`
    existe y `transcriptor-scan.sh` lo lista como digerible.
30. **Vision — opt-in**: con `vision_enabled=false`, mss NO se invoca (fake
    registra 0 capturas); con `true` y `vision_model_capable=false`, degrada a
    texto (el mensaje al LLM no incluye imagen).
31. **Vault CONSUME**: con `vaults.enabled=true`, el A2A fake devuelve 2 notas
    relevantes → el contexto LLM incluye el bloque CUPULAS con ambas; con 0
    resultados, el contexto es de conversacion pura (sin bloque).
32. **Vault GATE**: con `vaults.max_confidentiality=N2` y un dome `N4b`, el
    A2A fake registra que ese dome NO se consulto; un dome `N1` si.
33. **Vault ALIMENTA**: al cerrar, `VaultBridge.write` recibe el path y
    contenido correctos; con el servidor caido, no lanza (degradacion local).
34. **Vault inferencia fundamentada**: el LLM fake recibe el bloque CUPULAS y
    su respuesta incluye el path de la nota citada (assert sobre el contexto
    y la metadata de citacion).
35. **Audio brief solo**: con `brief.enabled=true`, generar un brief con
    formato `solo` produce el guion (LLM fake), lo pasa por el TTS fake y
    escribe audio.wav + guion.md + meta.json (con sources).
36. **Audio brief dialogo**: formato `dialogo` produce guion de 2 voces
    (Savia + co-host generico); el TTS fake recibe 2 voces distintas y la
    voz del co-host es sintetica generica (assert: no usa voz de persona).
37. **Cita hablada**: con `brief.cite_spoken=true`, el guion incluye "segun mi
    nota en <path>"; con `false`, no. `voice_profile` cambia el arg de voz
    del TTS fake.

---

## 6. Ficheros a Crear/Modificar

### Crear (proyecto `projects/savia-sonora/app/`)

| Fichero | Proposito |
|---|---|
| `specs/SE-310-savia-conversacional.spec.md` | Esta spec |
| `src-pyloid/services/conversation/conversation_service.py` | Orquestador del bucle |
| `src-pyloid/services/conversation/tts_provider.py` | `TTSProvider` + `SubprocessTTS` + `NoopTTS` |
| `src-pyloid/services/conversation/context_aggregator.py` | Contexto por presupuesto de tokens (patron Pipecat) |
| `src-pyloid/services/conversation/tools_bridge.py` | Tool-calling → acciones de Savia (con confirmacion) |
| `src-pyloid/services/conversation/sentence_splitter.py` | Split por frase (espanol, abreviaturas) |
| `src-pyloid/services/conversation/conversation_store.py` | Persistencia + `index.db` |
| `src-pyloid/services/conversation/audio_output.py` | Reproduccion WAV (sounddevice) |
| `src-pyloid/services/conversation/proactive_trigger.py` | Triggers proactivos con gates (S0-E) |
| `src-pyloid/services/conversation/memory_bridge.py` | Lectura de contexto + escritura de memory.md (S0-F) |
| `src-pyloid/services/conversation/vision_context.py` | Captura de pantalla opt-in (S0-G) |
| `src-pyloid/services/conversation/vault_bridge.py` | Cliente A2A de SaviaVaults (search/read/write + gate) (S0-H) |
| `src-pyloid/services/conversation/vault_context.py` | Etapa CONSUME: RAG sobre cupulas (S0-H) |
| `src-pyloid/services/conversation/vault_feed.py` | Etapa ALIMENTA: escribe nota de conversacion en el dome (S0-H) |
| `src-pyloid/services/conversation/audio_brief.py` | Generador de Audio Briefs fundamentados (S0-I) |
| `src-pyloid/tests/test_proactive_trigger.py` | pytest gates de proactividad |
| `src-pyloid/tests/test_memory_bridge.py` | pytest lectura/escritura de memoria |
| `src-pyloid/tests/test_vision_context.py` | pytest vision + degradacion |
| `src-pyloid/tests/test_vault_bridge.py` | pytest A2A client + gate de confidencialidad |
| `src-pyloid/tests/test_vault_context.py` | pytest consume + degradacion |
| `src-pyloid/tests/test_vault_feed.py` | pytest alimenta + fallback local |
| `src-pyloid/tests/test_audio_brief.py` | pytest brief solo/dialogo + citacion |
| `src-pyloid/tests/test_conversation_service.py` | pytest bucle con fakes |
| `src-pyloid/tests/test_tts_provider.py` | pytest backends TTS |
| `src-pyloid/tests/test_sentence_splitter.py` | pytest splitter |
| `src-pyloid/tests/test_conversation_store.py` | pytest persistencia |
| `src/components/ConversationPage.tsx` | UI de conversacion |
| `src/pages/Conversation.tsx` | Pagina/panel en el dashboard |

### Modificar

| Fichero | Cambio |
|---|---|
| `src-pyloid/app_controller.py` | Cablear ConversationService, hotkey separado, eventos IPC |
| `src-pyloid/server.py` | Handlers IPC `conversation:*` |
| `src-pyloid/services/settings.py` | Claves de la seccion 2.3 |
| `src-pyloid/main.py` | Inicializar servicio |
| `src/App.tsx` | Ruta/pestana Conversacion |
| `src/components/Sidebar.tsx` | Navegacion |
| `docs/README.md` | Documentar el modo conversacional |
| `scripts/transcriptor-scan.sh` (workspace) | Escanear tambien `conversaciones/` (mismo formato `meta.json`/`digested`) — habilitador de AC-2 |
| `.claude/skills/transcriptor-digest/SKILL.md` | Solo doc: mencionar que escanea reuniones Y conversaciones (sin cambio de logica) |

---

## 7. Criterios de Aceptacion

- [ ] **AC-1** — Push-to-talk → Savia responde por voz (o texto si voz off);
      la PRIMERA frase audible sale en < 5s con modelos locales. La respuesta
      completa por voz puede tardar mas (cola TTS acotada por `tts_queue_cap`),
      pero el texto en UI es inmediato en streaming.
- [ ] **AC-2** — El transcripto se persiste por mensaje en
      `conversaciones/YYYY-MM-DD-HH-MM.md` y `index.db`; `transcriptor-scan.sh`
      se extiende para listar `conversaciones/` sin digerir (mismo formato
      `meta.json` con `digested`), y `transcriptor-digest` las digiere sin
      cambios de logica del skill.
- [ ] **AC-3** — `TTSProvider` es pluggable: `none` y `subprocess` (plantilla
      `{out}`/`{text}`, degradacion a none si falla), con tests de ambos.
- [ ] **AC-4** — La conversacion coexiste con la grabacion de reunion activa
      (lock de captura push-to-talk serializado; el push-to-talk de conversacion
      se encola si la reunion graba, max 2s).
- [ ] **AC-5** — N3: audio de entrada/salida local; solo TEXT al LLM; API keys
      via keyring; logs sin contenido de conversacion.
- [ ] **AC-6** — pytest del bucle con fakes (10+ tests) y los tests SE-308
      existentes siguen pasando sin cambios.
- [ ] **AC-7** — Hotkeys desambiguados: dictado (`ctrl+win`) y conversacion
      (`ctrl+alt+win`) con callbacks separados; release de conversacion NUNCA
      pasa por el path de dictado.
- [ ] **AC-8** — Cola TTS acotada: con un LLM fake rapido y un TTS fake lento,
      nunca hay mas de `tts_queue_cap` frases pendientes y la voz no se acumula
      (barge-in descarta la mas antigua).
- [ ] **AC-9** — Pipeline modular: cada etapa (VAD/STT/contexto/LLM/split/TTS)
      es un procesador reemplazable; los tests prueban el cableado con fakes
      y S1/S2 solo anaden etapas sin tocar las existentes.
- [ ] **AC-10** — Barge-in: el pulso del hotkey durante `speaking` corta TTS+LLM
      al instante y deja la conversacion persistida y recuperable.
- [ ] **AC-11** — Contexto por presupuesto de tokens: el payload al LLM nunca
      supera `context_token_budget` en conversaciones largas.
- [ ] **AC-12** — `tools_enabled=false` por default; con `true`, los tool-calls
      se muestran en la UI y NO se ejecutan sin confirmacion explicita.
- [ ] **AC-13** — Proactividad (S0-E): con `proactive.enabled=true`, un trigger
      programado/evento inyecta un mensaje `proactive` hablado+UI; NUNCA
      dispara durante RECORDING ni en quiet_hours; el LLM no responde salvo
      que el usuario conteste.
- [ ] **AC-14** — Memoria (S0-F): al arrancar la sesion, el contexto cargado
      (si existe) aparece en el system prompt; al cerrar, se escribe
      `conversaciones/<sesion>/memory.md` con los memory candidates, y el
      workspace puede digerirlo sin cambios de `transcriptor-scan`.
- [ ] **AC-15** — Vision (S0-G): con `vision_enabled=true` y
      `vision_model_capable=true`, el turno de usuario adjunta la captura;
      si el modelo no es vision-capable o la captura falla, degrada a texto
      sin romper; con `vision_enabled=false` nunca se captura pantalla.
- [ ] **AC-16** — Cupulas CONSUME (S0-H): con `vaults.enabled=true` y domes
      configurados, el contexto LLM incluye el bloque CUPULAS con las notas
      recuperadas (top-k, cruzando domes); sin resultados relevantes degrada
      a contexto de conversacion sin romper.
- [ ] **AC-17** — Cupulas GATE (S0-H): un dome con `confidentiality >`
      `vaults.max_confidentiality` NUNCA se consulta ni su contenido entra en
      el prompt; cambiar `max_confidentiality` a `N4b` con endpoint cloud queda
      bloqueado (validacion cruzada endpoint↔nivel).
- [ ] **AC-18** — Cupulas ALIMENTA (S0-H): al cerrar la sesion con
      `vaults.enabled=true`, VaultFeed escribe la nota de conversacion en el
      `vaults.write_dome` via POST /share; si el servidor falla, degrada a
      local (ConversationStore ya persistio) sin perder nada.
- [ ] **AC-19** — Inferencia fundamentada (2.9): si la respuesta del LLM usa
      contenido de una cupula, la cita (path de la nota) en el texto/metadata;
      test verifica que el bloque CUPULAS llega al LLM y que la cita aparece.
- [ ] **AC-20** — Audio Brief (S0-I): con `brief.enabled=true`, generar un brief
      produce `audio-briefs/YYYY-MM-DD-HH-MM/` con audio.wav + guion.md +
      meta.json; el guion referencia las fuentes usadas (metadata `sources`);
      formato `dialogo` usa Savia + co-host sintetico generico (nunca voz de
      una persona).
- [ ] **AC-21** — Voz y citacion (S0-I): `conversation.voice_profile` cambia la
      voz de Kokoro sin clonacion; con `brief.cite_spoken=true`, el guion
      incluye frases de citacion verbal ("segun mi nota en <path>").

---

## 8. Roadmap de Implementacion (dentro de S0)

### S0-A — Núcleo backend conversacional
- [ ] `ConversationStore` + `sentence_splitter` + `AudioOutput` (con tests)
- [ ] `ContextAggregator` (presupuesto de tokens) + `ToolsBridge` (confirmacion)
- [ ] `TTSProvider` (`none` + `subprocess`) con degradacion
- [ ] `ConversationService` con el bucle completo por etapas (fakes) + barge-in

### S0-B — Integracion app + UI
- [ ] Settings + cableado en `app_controller.py`/`server.py` (hotkey separado)
- [ ] `ConversationPage.tsx` (streaming, toggle voz, mic, boton cancelar)
- [ ] Persistencia por mensaje + flag `digested`

### S0-C — Integracion workspace (AC-2)
- [ ] `transcriptor-scan.sh` escanea `conversaciones/` sin digerir
- [ ] Digest end-to-end de una conversacion via `transcriptor-digest`

### S0-D — Verificacion real
- [ ] Round-trip real con Ollama + Kokoro en hardware de la operadora
- [ ] Actualizar README y `savia-sonora/app/CLAUDE.md`
- [ ] CI: pytest suite verde + BATS `test-transcriptor.bats` intacto

### S0-E — Proactividad (opt-in)
- [ ] `ProactiveTrigger`: fuentes programadas (schedule) y por evento (digest)
- [ ] Regla: nunca hablar durante una reunion RECORDING; horas de silencio
- [ ] Inyeccion hablada + UI + persistencia como mensaje `proactive`

### S0-F — Memoria (enganche a Savia)
- [ ] `MemoryBridge` LECTURA: contexto (preferencias/proyecto activo) → system prompt
- [ ] `MemoryBridge` ESCRITURA: memory candidates por sesion → `~/.savia/transcriptor/conversaciones/<sesion>/memory.md`
- [ ] Digest de memory.md en la auto-memory del workspace (skill/agente)

### S0-G — Contexto multimodal (opt-in, vision)
- [ ] `VisionContext`: captura screenshot en el turno de usuario (mss, downscale)
- [ ] Adjunto al LLM SOLO si modelo vision-capable; degradacion a texto
- [ ] Privacidad: default OFF; N3 local si Ollama con modelo vision

### S0-H — Cupulas de contexto (SaviaVaults, consume + alimenta)
- [ ] `VaultBridge`: cliente A2A (search/read/write) + gate de confidencialidad
- [ ] `VaultContext`: RAG sobre domes configurados en cada turno (bloque CUPULAS)
- [ ] `VaultFeed`: escribe nota de conversacion en el write_dome (POST /share)
- [ ] Flujo de inferencia 2.9 (analizar/construir/contestar) con citacion
- [ ] End-to-end contra el A2A server real de savia-vaults (solo-lectura + 1 write de prueba)

### S0-I — Audio Briefs fundamentados (patron NotebookLM)
- [ ] `AudioBriefGenerator`: recopilar (VaultContext) → guionizar (solo/dialogo) → sintetizar (TTS) → publicar
- [ ] `audio-briefs/` (audio.wav + guion.md + meta.json con sources)
- [ ] `voice_profile` + cita hablada (`brief.cite_spoken`)
- [ ] Trigger: comando de conversacion + integracion con S0-E (proactivo)
- [ ] Ethics guard: dialogos solo con co-host sintetico generico

---

## 9. Fuera de alcance (S1/S2 + no-alcance)

**En alcance de SE-310** (slices S0-E/F/G, opt-in): proactividad, memoria,
contexto multimodal. **NO se incluye** continuidad con Savia Mobile por ahora
(se evalua en una spec/fase aparte cuando el modo conversacional este probado).

La arquitectura de pipeline modular (seccion 2.1) deja el camino allanado. La
siguiente fase se construye sobre patrones de la industria ya estudiados:

- **S1 — "Modo escucha" + wake word**: STT en streaming de baja latencia
  (faster-whisper por segmentos VAD, no batch al final), wake word
  (OpenWakeWord/Porcupine) y deteccion de fin de turno (endpointing por
  puntuacion — Vocode — o semantic turn detection — LiveKit, transformer).
  Timestamps por palabra (WhisperX, forced alignment) para interrupcion
  precisa. Savia escucha la reunion y resumen en vivo, sin hablar.
- **S2 — "Participacion por voz"**: Savia como **sidecar agent** sobre el bus
  de audio de la reunion (patron multi-agente de Pipecat: un pipeline por
  agente, coordinados por un bus). Politica de intervencion, TTS hacia la
  reunion con cancelacion de eco / ruteo (virtual cable), diarizacion
  (pyannote/WhisperX) para saber quien habla.
- **Voice cloning** (SE-042, GPU) y multi-voz (XTTS/Coqui).
- **Telefonia/Zoom**: patron `zoom_dial_in` de Vocode — llamadas entrantes con
  agente LLM — se evalua cuando S2 madure.
- **Savia Mobile (continuidad cross-device)**: NO en SE-310 — fase aparte.

---

## 10. Referencias de arquitectura (investigacion 2026-08-07)

| Repo | Que aporta a SE-310 | Estado |
|---|---|---|
| [Pipecat](https://github.com/pipecat-ai/pipecat) (pipecat-ai, ~2.5k★, Apache-2.0) | Pipeline de etapas modulares (VAD→STT→LLM→TTS), interrupcion/barge-in, context aggregator por tokens, transportes (incl. Local = app de escritorio), Kokoro+Silero+Ollama ya integrados, multi-agente sidecar (S2), Pipecat Flows | Framework de referencia para S0 y S2 |
| [Vocode](https://github.com/vocodedev/vocode-core) (MIT) | `StreamingConversation` = transcriber+agent+synthesizer pluggable; endpointing por puntuacion; `zoom_dial_in` (participacion en reuniones) | Patron de conversacion y S2 |
| [LiveKit Agents](https://github.com/livekit/agents) (Apache-2.0) | AgentSession (vad/stt/llm/tts), semantic turn detection (transformer), push-to-talk multi-usuario, background/thinking audio, function tools, test con LLM-judges | Turn-taking (S1), tools, testing |
| [JARVIS / HuggingGPT](https://github.com/microsoft/JARVIS) (Microsoft) | LLM como controlador + modelos expertos como ejecutores (4 etapas: plan→select→execute→respond) | Concepto "Jarvis" = Savia ya lo cumple (LLM + 83 agentes/skills); SE-310 lo hace accesible por voz via ToolsBridge |
| [WhisperX](https://github.com/m-bain/whisperX) (m-bain, BSD-2) | Timestamps por palabra (forced alignment wav2vec2), VAD-based batching, diarizacion (pyannote) | Dependencia de S1/S2 (interrupcion precisa, quien habla) |
| [NotebookLM / Gemini Notebook](https://notebooklm.google.com/) (Google) | **Audio Overviews**: discusion podcast entre 2 hosts AI grounded en tus fuentes; customizacion 2025 (add-your-voice, focus, guidance, episodios largos); cita las fuentes verbalmente. Tambien: caso legal de voz clonada sin permiso (2025) | S0-I: Audio Briefs fundamentados; perfil de voz sin clonacion; cita hablada; ethics guard (prohibido clonar voz humana sin consentimiento) |

Decision: NO se adopta ningun framework como dependencia en S0 (la app ya tiene
su stack VoiceFlow/faster-whisper/sounddevice). Solo se copian los PATRONES:
pipeline modular, barge-in, context aggregator, tools bridge, thinking cue.

---

## 10. OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Skill `transcriptor-digest` (consumidor) | `.claude/skills/transcriptor-digest/SKILL.md` | Symlink via `.opencode/skills/` |
| Scripts TTS workspace (`savia-kokoro.py`, `savia-voice-speak.sh`) | `scripts/` compartidos | `scripts/` compartidos |
| BATS `tests/test-transcriptor.bats` | Ruta compartida | Selector dinámico `.deps.json` |
| Comando `/transcriptor` | `.claude/commands/transcriptor.md` | `.opencode/commands/` (symlink) |

La app de escritorio (`src-pyloid/`, React) es un binario independiente (SE-308);
no consume bindings de Claude Code/OpenCode. El unico punto de acoplamiento es
el backend TTS subprocess, que invoca un comando externo configurable — si apunta
a `scripts/savia-kokoro.py`, ese script es shared y corre igual en cualquier motor.

### Verification protocol

- [ ] Funciona en runtime OpenCode (no solo Claude Code) — la app es agnostica;
      el TTS subprocess y el digest consumen paths compartidos
- [ ] Tests cubren ambos paths: pytest (app) + BATS (digest) — o SKIP justificado
      para audio real (requiere hardware)
- [ ] Si se anade algo a `.claude/skills/` o `.opencode/hooks/`: registrado en
      plugin `savia-gates`

### Portability classification

- [ ] **PURE_BASH** — logica en bash sin bindings de frontend, runs identico en cualquier motor
- [ ] **DUAL_BINDING** — implementado para Claude Code Y OpenCode desde Slice 1
- [x] **SINGLE_BINDING_DEFERRED** — app de escritorio independiente; el unico
      binding (digest de conversaciones) reutiliza `transcriptor-digest` ya
      cross-frontend via symlink; sin work adicional de port
- [ ] **CLAUDE_CODE_ONLY** — no aplica

---

## 11. Riesgos y mitigaciones

| Riesgo | Prob. | Impacto | Mitigacion |
|---|---|---|---|
| Kokoro no disponible en la maquina de la operadora | Media | Sin voz | Backend subprocess con degradacion a `none`; documentar instalacion SE-075 Slice 3 |
| Latencia LLM local alta (modelo grande en Ollama) | Media | Round-trip > 5s | Config de modelo; streaming visible en UI; TTS por frase enmascara la espera; cue de "pensando" (patron LiveKit) avisa de forma no verbal |
| Eco si Savia habla mientras hay reunion grabando | Baja en S0 | Calidad de grabacion | S0 usa altavoz solo en conversacion (no dentro de la reunion); eco es problema de S2 (fuera de alcance) |
| Bucle de audio (mic recoge el altavoz) | Baja en S0 | Respuesta transcrita a si misma | El push-to-talk es explicito y no se autoactiva; sin wake word no hay autoescucha |
| Drift con SE-308 (archivos ya existentes) | Baja | Rompe tests | AC-6 exige tests SE-308 intactos; cambios solo aditivos |
| Sobre-ingenieria (pipeline modular muy abstracto) | Media | Complejidad innecesaria en S0 | El pipeline se limita a 6 etapas concretas; los procesadores son clases pequenas con fakes en tests; se documenta que S1/S2 solo anaden etapas |
| Tool-calling sin confirmacion (Savia ejecuta algo por voz) | Baja | Accion no deseada | `tools_enabled=false` por default; con `true`, TODA accion queda pendiente de confirmacion explicita en la UI (test 23, AC-12) |

---

## 12. Alineacion con tendencias 2026 (Alexa+, Gemini Live, Siri, OpenAI Realtime)

Comparativa del estado del arte en interfaces de voz (investigacion 2026-08-07)
contra SE-310. Verdicto: **bien alineado en las tendencias centrales; dos gaps
honestos (latencia y speech-to-speech end-to-end) con palancas documentadas.**

| Tendencia 2026 | Referencia | SE-310 | Estado |
|---|---|---|---|
| **Generativo + agente** (asistentes que ORQUESTAN servicios) | Alexa+ "experts" (10k+ servicios, Bedrock LLMs); JARVIS controlador+ejecutores; OpenAI Realtime con tools/MCP; Gemini Live function calling | `ToolsBridge`: tool-calling del LLM → acciones de Savia (83 agentes/skills) con confirmacion | ✅ Alineado. `tools_enabled=false` por default es una decision de seguridad deliberada (Savia propone, humano dispone — regla autonomia), no un gap |
| **Barge-in / interrupcion** (table stakes) | Gemini Live barge-in; OpenAI Realtime turn handling; Pipecat/Vocode | Barge-in de primera clase (hotkey corta TTS+LLM al instante) | ✅ Alineado |
| **Speech-to-speech end-to-end** (modelos que colapsan STT+LLM+TTS) | OpenAI `gpt-realtime-2.1` (s2s + razonamiento); Gemini Live; Ultravox | Pipeline por etapas (whisper+LLM+Kokoro) — eleccion correcta para local-first N3 | ⚠️ Gap honesto. Se documenta la opcion de colapsar las etapas a un unico "stage S2S local" cuando exista un modelo CPU/ONNX de calidad. El pipeline modular (sec. 2.1) lo permite sin reescritura |
| **Latencia conversacional** | Cloud: <1s TTFB; "conversational latency" objetivo de la industria 2026 | <5s primera frase (local-first) | ⚠️ Gap honesto. Palancas: whisper pequeno, prompt-caching Ollama, streaming por frase, futuro S2S. Ver Constraints |
| **Personalidad configurable** | Alexa+ estilos Brief/Chill/Sweet/Sassy | `conversation.personality_style` (savia/brief/chill/sweet/sassy) | ✅ Alineado (nuevo) |
| **Proactividad + memoria** | Alexa+ proactive (trafico, ofertas) + memoria personal; Siri personal context (2026) | S0-E: triggers proactivos opt-in con gates (quiet_hours, no-RECORDING). S0-F: MemoryBridge lectura de contexto + escritura de memory.md digerible | ✅ En alcance (S0-E/S0-F, opt-in) |
| **On-device / privacidad** | Apple Foundation Models on-device; Alexa+ privacy dashboard | Local-first N3: audio nunca sale, solo TEXT al LLM configurado | ✅ Diferenciador real vs cloud |
| **Turn-taking (fin de turno)** | LiveKit semantic turn detection; Vocode endpointing; OpenAI turn lifecycle | S0: push-to-talk explicito; S1: turn detection | ✅ Ruta correcta en el roadmap |
| **Multimodal (vision)** | Gemini Live vision; GPT realtime vision; Pipecat multimodal | S0-G: VisionContext opt-in (captura de pantalla → modelo vision-capable, degrada a texto; default OFF) | ✅ En alcance (S0-G, opt-in) |
| **Knowledge grounding (RAG sobre conocimiento personal)** | Alexa+ "deep knowledge" (documentos/emails/fotos); Gemini context grounding; SaviaVaults es el equivalente local | S0-H: VaultContext consume cupulas (BM25 over domes) + VaultFeed alimenta — Savia razona SOBRE su propio conocimiento | ✅ En alcance (S0-H) — diferenciador: grounding sobre las cupulas locales N3 |
| **Audio de formato largo fundamentado** | NotebookLM Audio Overviews (discusion podcast entre 2 hosts AI, grounded en fuentes; custom 2025: add-your-voice, focus, guidance, episodios largos) | S0-I: Audio Briefs — guion del LLM desde las cupulas → TTS → fichero digerible. `solo` o `dialogo` (Savia + co-host sintetico). Citacion hablada opcional | ✅ En alcance (S0-I) — Savia no solo conversa, PRODUCE audio fundamentado bajo demanda |
| **Continuidad cross-device** | Alexa+ Echo↔telefono↔web | NO en SE-310: solo desktop; Savia Mobile se evalua en fase aparte | ➡️ Fuera de alcance (por decision de la operadora, 2026-08-07) |

**Decision**: S0 mantiene el enfoque local-first de etapas discretas (patron de
los frameworks OSS Pipecat/Vocode/LiveKit) y NO adopta speech-to-speech cloud
(romperia N3). Las dos tendencias con gap (latencia, s2s) quedan documentadas
con palancas y un futuro "stage S2S local" sin reescritura.
