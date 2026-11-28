# SE-308 y SE-312: reconciliación de estado

Pregunta abierta 4 de SE-537. Fecha: 2026-11-28. Rama `agent/docs-20261128-sonora-estados`.

Este informe propone estados. No cambia ninguno: lo decide la operadora.

## Resumen

| Spec | Estado actual | Estado propuesto | Motivo |
|---|---|---|---|
| SE-308 Savia Transcriptor | PROPOSED | **IMPLEMENTED con resto** | S1-S5 entregados y probados; faltan los instaladores, la verificación en Windows y macOS y el selector automático de modelo Whisper |
| SE-312 Sonora frontend | PROPOSED | **IMPLEMENTED con resto** | 9 de 11 AC cumplidas por código (AC-2 con restos internos); AC-8 y AC-11 sin verificar aquí; falta la revisión humana en Windows/Linux |

Las dos están fuera de `docs/propuestas/planning-state.json` y de `planning.d/`. SE-312 se entregó en #951.

## Qué se ejecutó y qué no

- **BATS** (`tests/test-transcriptor.bats`, `tests/test-transcriptor-digest.bats`): ejecutados, 56 ok y 0 fallos.
- **pytest de la app** (`src-pyloid/tests/`): no se pudo ejecutar. Falta el venv de la app y la colección falla con `ModuleNotFoundError: evdev`. Lo de pytest se basa en leer los tests, no en haberlos corrido.
- **vitest, lint, tsc y build**: no se ejecutaron. No hay `node_modules` en este worktree.
- **Revisión visual humana** en Windows/Linux: no se hizo.

## SE-308 — Savia Transcriptor

La spec no tiene sección de AC numeradas. Uso su hoja de ruta (§8, S1-S6) y sus escenarios de prueba (§6). Rutas relativas a `projects/savia-sonora/app/`.

### Hoja de ruta

| Slice | Cumple | Evidencia |
|---|---|---|
| S1 fork + storage en `~/.savia/transcriptor/` | Sí | `src-pyloid/services/paths.py:3,13,48-49` (`reuniones/`, log) |
| S1 captura mic + sistema en las 3 SO | Parcial | Hay backends `loopback_linux.py`, `loopback_windows.py`, `loopback_pulse.py`. La spec solo registra verificación en Linux (PipeWire); Windows y macOS sin prueba |
| S2 VAD y máquina de estados | Sí | `services/recording/vad.py`, `vad_silero.py`, `auto_trigger.py`; tests `test_vad.py:60-136`, `test_auto_trigger.py:49,73,98`, `test_settings_vad.py:21-41` |
| S3 capturas de pantalla | Sí | `services/recording/screen.py`, `session_coordinator.py`; tests `test_screen.py:65-121`, `test_session_coordinator.py:71-103` |
| S4 transcripción post-sesión (VTT + MD + meta) | Sí | `postprocessor.py`, `meeting_store.py`; tests `test_postprocessor.py:68-111`, `test_meeting_store.py:38-79` |
| S4 actualizar `index.db` | Sin verificar | `paths.py` define la ruta, pero no localicé un test que compruebe la actualización desde el postprocesador |
| S5 skill, comando y scripts de digestión | Sí | `.claude/commands/transcriptor.md`, `.claude/skills/transcriptor-digest/` (`transcriptor-scan.sh`, `transcriptor-mark-digested.sh`); BATS 56/56 ejecutados |
| S6 BATS + pytest | Sí | `tests/test-transcriptor.bats`, `tests/test-transcriptor-digest.bats`; pytest leído, no ejecutado |
| S6 builders Windows/Linux/macOS | **No** | `installer/` sigue con marca VoiceFlow: `build-linux.sh:9` (`APP_NAME="VoiceFlow"`), `VoiceFlow.desktop`, `voiceflow.iss`, `io.github.infiniv.VoiceFlow.metainfo.xml`. La propia spec lo deja sin marcar |

### Escenarios de prueba (§6)

| # | Escenario | Cumple | Evidencia |
|---|---|---|---|
| 1 | VAD START tras voz sostenida | Sí | `test_vad.py:70` |
| 2 | VAD STOP tras silencio | Sí | `test_vad.py:92`; los valores por defecto se comprueban en `test_settings_vad.py:41` |
| 3 | Intervalo de capturas | Parcial | `test_screen.py:105` prueba el bucle con parada, no la cuenta de ~8 capturas |
| 4 | Transcripción con audio real | No verificado | Los tests inyectan un transcriptor; la spec admite SKIP por hardware |
| 5 | Multi-sesión el mismo día | Parcial | `test_meeting_store.py:45` (nombre con marca de tiempo) |
| 6 | Cambio de intervalo en runtime | Sin evidencia | No encontré test |
| 7 | Música sin voz no arranca | Parcial | `test_vad.py:60` cubre voz corta; no hay caso con música contra silero |
| 8 | Rendimiento < 500 MB por hora | No verificado | Sin medición |

### Decisiones de diseño sin evidencia

- Auto-selección del modelo Whisper por idioma y capacidad (`core/model_selector.py`, §3.4): ese fichero no existe y no localicé selección automática. `services/model_catalog.py` es un catálogo, no un selector.
- Todo en `~/.savia/` y N3 local: `paths.py:3` lo cumple.

### Propuesta SE-308

**IMPLEMENTED con resto.** El núcleo (S1-S5) está entregado y probado. Resto explícito:

1. Instaladores rebrandeados y verificables en Windows, Linux y macOS (S6, sin hacer).
2. Verificación de captura mic + sistema en Windows y macOS.
3. Selector automático de modelo Whisper (§3.4), o retirarlo de la spec.
4. Escenarios 3, 4, 6, 7 y 8 sin prueba directa.

Incoherencia documental: el §8 de la spec tiene todo sin marcar y el §9 casi todo marcado.

## SE-312 — Sonora frontend

Rutas relativas a `projects/savia-sonora/app/`. Los tests de vitest existen pero no se ejecutaron.

| AC | Cumple | Evidencia |
|---|---|---|
| AC-1 tokens savia-web | Sí | `src/index.css:24-26` (radios 10/16/24), `:83` (`--primary: #6b4c9a`), `:113,165` (`--glass-blur`), `:272` (`.glass-panel`). Sombras en capas sin comprobar línea a línea |
| AC-2 sin VoiceFlow/infiniV visible | Sí, con restos internos | Tests: `Sidebar.test.tsx:29`, `StepTheme.test.tsx:8`, `StepFinal.test.tsx:8`, `MeetingImportDialog.test.tsx:12`, `MeetingRecorderPage.test.tsx:33`. Restos no visibles: clave de localStorage `voiceflow:hotkey-banner-dismissed-code` (`HotkeyStatusBanner.tsx:5`) y esquema `voiceflow://recording/` (`MeetingDetailPage.tsx:197`, `AudioPlayer.tsx:3`) |
| AC-3 `index.html` Savia Sonora, `lang="es"`, búho | Sí | `index.html:2,6,9`; `public/savia-logo.{png,svg}`, `favicon.svg`. `public/light-logo.png` y `dark-logo.png` siguen presentes; no comprobé si son el logo antiguo |
| AC-4 Sidebar/Dashboard con marca, nav en español, glass | Sí | `Sidebar.tsx:16` (`REPO_URL` a pm-workspace), `Sidebar.test.tsx:29`, `Dashboard.test.tsx` |
| AC-5 Home e History sin duplicación | Sí | `HomePage.tsx:5-6,76,184`; `HistoryPage.tsx:3-4`. `HomePage.tsx` queda en 561 líneas y `HistoryPage.tsx` en 323 (la spec los daba en 681 y 519) |
| AC-6 vistas principales en español | Sí, no exhaustivo | `lib/i18n.ts` + `i18n.test.ts`; tests de Onboarding, Popup, Meetings, Settings. La spec excluye el i18n del 100 % de cadenas |
| AC-7 focus-visible, aria-label, aria-live, retry | Sí | `index.css:211`; `HomePage.tsx:156,162,451-469`; `HistoryPage.tsx:54,60,266`. `aria-label` en todos los icon-buttons sin auditar |
| AC-8 lint, typecheck, build, version:check | **No verificado aquí** | Scripts en `package.json:12-22`. La spec §9 declara lint 0 errores, tsc y vite OK, 26 tests. Sin `node_modules` no lo reproduje |
| AC-9 `theme-color` dinámico | Sí | `App.tsx:38-39`; `App.test.tsx:31` |
| AC-10 `reduced-effects` en Linux, popup oscuro | Sí | `index.css:481-488`; `Popup.test.tsx` |
| AC-11 contratos IPC intactos | Sin evidencia directa | Ningún test lo comprueba; no revisé el diff de #951 |

Resto de la spec: §9 deja sin marcar «Revisión humana de la app en Windows/Linux». El S5 prometía limpiar los shims legacy de `index.css` (~150 líneas); no medí cuánto queda.

### Propuesta SE-312

**IMPLEMENTED con resto.** Resto explícito:

1. Revisión humana en Windows y Linux (declarada pendiente en la propia spec).
2. Reproducir AC-8 (`pnpm run lint && typecheck && build && version:check`) en un entorno con dependencias, y revisar el diff de #951 para AC-11.
3. Decidir si los restos internos `voiceflow:` (clave de localStorage y esquema de URL) se renombran o se aceptan como atribución técnica.

## Para la operadora

1. Estado de SE-308 y SE-312. Recomiendo «IMPLEMENTED con resto»: el instalador y el selector de modelo de SE-308 son huecos reales, no formalidades.
2. `planning.d/SE-308.json` y `SE-312.json` están en PROPOSED con una nota. Registrarlas no cambia el estado; el cambio lo haces tú. `roadmap.sh validate` da `PASS: planning state consistente` con los dos fragmentos.
3. SE-312 declara como padre a SE-310, y SE-537 sustituye a SE-310. El padre apunta a una spec sustituida; conviene anotarlo.
