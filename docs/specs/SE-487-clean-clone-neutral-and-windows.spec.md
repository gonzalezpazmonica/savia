---
status: APPROVED
priority: P0
developer_type: agent-team
created: 2026-10-30
approved_at: 2026-10-30
author: Savia
phase: D
risk: L2
related_specs: [SPEC-185, SPEC-110, SE-483, SE-484]
origin: incidente 2026-10-30 — una persona clonó Savia en Windows con Claude Code. Savia la trató como si fuera la persona que mantiene el repo y no pudo ejecutar ninguna herramienta porque faltaba Git Bash. Aprobada por la operadora (AskUserQuestion, «Sí, P0 ya»).
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-487 — Clon limpio neutral y arranque en Windows

## Problema (verificado en origin/main 7e1fdd9f9)

1. **Identidad de otra persona en un clon limpio.**
   - `docs/critical-facts.md` está versionado y lo importa CLAUDE.md en cada turno.
   - Lo genera `scripts/generate-critical-facts.sh` a partir del perfil local (`.claude/profiles/active-user.md`, gitignored), así que el fichero versionado lleva el slug, el idioma y la fecha de activación de quien lo generó.
   - Cualquier clon arranca creyendo que la persona usuaria es esa.
   - Además es una fuga de datos de la mantenedora en un repo público.
2. **Rutas personales en CLAUDE.md.** La sección «Savia Mobile» lleva rutas absolutas de la máquina de la mantenedora (`/home/<usuaria>/Android/Sdk`).
3. **Windows sin Git Bash.**
   - Claude Code ejecuta los hooks de bash con Git Bash. Si no lo encuentra, todo PreToolUse falla y bloquea hasta las lecturas.
   - `install.ps1` instala Git, pero no verifica que Claude Code encuentre `bash.exe` (variable `CLAUDE_CODE_GIT_BASH_PATH`).
   - Quien clona a mano no recibe ningún aviso antes del fallo.

## Requisitos

### R1 — Ficheros versionados neutros
- `docs/critical-facts.md` versionado **no contiene** datos de ninguna persona:
  - nada de slug, nombre, fecha de activación ni idioma de un perfil concreto;
  - solo invariantes del workspace.
- Los hechos de la persona activa los inyecta el arranque (`session-init.sh`, ya lee el perfil) como contexto de sesión, desde el perfil local gitignored.
- Sin perfil, el contexto dice «Sin perfil: no sé quién eres» y propone `/profile-setup`. **Nunca** se supone una identidad.
- `generate-critical-facts.sh`:
  - genera el fichero versionado sin datos personales;
  - si hace falta una versión con datos del usuario, la escribe en un fichero local ignorado por git y nunca en el versionado.
- SPEC-185 y `tests/test-critical-facts-cap.bats` se ajustan; el cap de 150 tokens se mantiene.
- Lo mismo vale para cualquier otro fichero versionado que se carga al arrancar (CLAUDE.md, AGENTS.md, `.opencode/CLAUDE.md`, los @imports de CLAUDE.md): se auditan todos.

### R2 — CLAUDE.md sin rutas personales
- La sección «Savia Mobile» queda con variables (`$JAVA_HOME`, `$ANDROID_HOME`) y una referencia a la configuración local.
- Los valores concretos van al `CLAUDE.local.md` de cada persona, que es gitignored.
- La orquestadora mueve los de la mantenedora a su `CLAUDE.local.md` fuera de la PR.

### R3 — Guardia de CI contra datos personales
Un test (bats) y un paso de CI que fallan si un fichero versionado cargado al arranque contiene:
- un slug de perfil de `.claude/profiles/users/*` distinto de `template`;
- rutas `/home/<nombre>/` o `C:\Users\<nombre>\`;
- el nombre de la persona del perfil local, si existe.

Lista de ficheros: los @imports de CLAUDE.md, CLAUDE.md, AGENTS.md, `.opencode/CLAUDE.md` y `docs/critical-facts.md`. El test incluye un caso negativo (fixture con un slug inyectado: falla) y uno positivo.

### R4 — Windows
- **`install.ps1`:**
  - tras instalar o detectar Git, localiza `bash.exe` de Git for Windows en las rutas estándar y en `git --exec-path`;
  - si Claude Code no lo encuentra por PATH, fija `CLAUDE_CODE_GIT_BASH_PATH` en las variables de usuario y avisa de que hay que abrir una terminal nueva;
  - si no hay `bash.exe`, falla con un mensaje claro.
- **README** (y la sección de instalación de los traducidos, si existe): en el paso 1 de Windows, requisito «Git for Windows (incluye Git Bash)» y qué hacer si Claude Code dice «Git Bash wasn't found».
- **CLAUDE.md:** una línea de arranque. Si las herramientas fallan con «Git Bash wasn't found» o «bash no se reconoce», Savia explica que hay que instalar Git for Windows o fijar `CLAUDE_CODE_GIT_BASH_PATH` y abrir una sesión nueva, y no intenta nada más hasta entonces.
- **`scripts/windows-links.sh`** y el aviso del arranque se revisan para que no den por hecha una máquina Linux.

## Criterios de aceptación

- **AC-1:** en un clon limpio sin `.claude/profiles/active-user.md`, el contexto de arranque, CLAUDE.md y sus @imports no contienen datos de ninguna persona, y el arranque dice «Sin perfil» (test).
- **AC-2:** con un perfil local de fixture, el arranque inyecta su slug. `git status` sigue limpio: no se escribe nada versionado (test).
- **AC-3:** la guardia R3 falla con el fixture contaminado y pasa en el árbol limpio. Corre en la CI de PR.
- **AC-4:** `install.ps1` contiene la detección de `bash.exe` y la fijación de `CLAUDE_CODE_GIT_BASH_PATH`. Hay un test que analiza el script (Pester si está disponible; si no, un bats con grep estructurado del bloque) y verifica los mensajes.
- **AC-5:** el README de Windows menciona el requisito y la solución del error.
- **AC-6:** `validate-ci-local.sh --quick`, SAM FRESH, `critical-facts-cap` y equality-shield en verde.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Hechos de sesión | `session-init.sh` (SessionStart) | mismo script vía plugin savia-gates |
| critical-facts | @import en CLAUDE.md | AGENTS.md generado |

### Verification protocol

- [ ] El arranque es neutral en ambos frontends
- [ ] La guardia de CI es independiente del frontend

### Portability classification

- [x] **DUAL_BINDING**
