# Hooks: Salvaguardas Programáticas No Eludibles

65 hooks .sh protegidos contra vendor lock-in. El directorio está symlinked a
`.opencode/hooks/` para compatibilidad cross-frontend. OpenCode ejecuta los 5
hooks Tier-1 como ports TypeScript nativos en `.opencode/plugins/guards/`; el
resto vía bridge `savia-gates` (Bun shell API + env var inyección).

## Arquitectura dual

| Frontend | Mecanismo | Hooks activos |
|----------|-----------|---------------|
| Claude Code | `.claude/settings.json` → stdin JSON | 61/65 registrados |
| OpenCode | `savia-foundation.ts` (nativo) + `savia-gates` (bridge) | 5 nativos + 61 bridge |

## Categorías

### Tier 1 — Seguridad Crítica (5)
Ports TypeScript en `.opencode/plugins/guards/`. Cobertura dual .sh + .ts.

| Hook | Función |
|------|---------|
| `block-credential-leak` | Detecta secretos, claves API, tokens en comandos |
| `block-gitignored-references` | Bloquea acceso a archivos en .gitignore |
| `prompt-injection-guard` | Detecta intentos de inyección en prompts |
| `validate-bash-global` | Bloquea comandos destructivos (rm -rf /, chmod 777, curl\|bash) |
| `tdd-gate` | Refuerza TDD — tests antes que código |

### Seguridad (7)
| Hook | Función |
|------|---------|
| `block-force-push` | Bloquea force-push a main/master |
| `block-infra-destructive` | Bloquea terraform destroy sin aprobación |
| `block-branch-switch-dirty` | Bloquea cambio de rama con cambios sin commit |
| `block-project-whitelist` | Whitelist de proyectos accesibles |
| `compliance-gate` | CHANGELOG, tamaño ficheros, frontmatter |
| `data-sovereignty-gate` | Gate de soberanía de datos |
| `dome-guard` | Guard de cúpulas (SE-436 S5): escritura en una cúpula → ask (propuesta); lectura N2 no adjunta en nube → ask; N3+ → deny. Gemelo nativo en savia-gates (`lib/dome-guard.ts`), con prueba de paridad |

### Hooks PreToolUse (26)
Validación previa a ejecución de herramientas. Bloquean con exit 2.

`acm-enforcement`, `agent-dispatch-validate`, `agent-hook-premerge`,
`agent-tool-call-validate`, `ast-comprehend-hook`, `delegation-guard`,
`live-progress-hook`, `memory-verified-gate`, `plan-gate`,
`prompt-hook-commit`, `responsibility-judge`, `savia-budget-guard`,
`tool-call-healing`, `user-prompt-intercept`, `validate-layer-contract`

### Hooks PostToolUse (13)
Post-ejecución — logging, captura, telemetría.

`acm-turn-marker`, `agent-trace-log`, `ast-quality-gate-hook`,
`bash-output-compress`, `competence-tracker`, `compress-agent-output`,
`data-sovereignty-audit`, `dual-estimation-gate`, `memory-auto-capture`,
`pbi-history-capture`, `post-edit-lint`, `post-report-write`,
`token-tracker-middleware`

### Sesión (7)
Gestión del ciclo de vida de sesión.

| Hook | Evento |
|------|--------|
| `session-init` | SessionStart — bootstrap del workspace |
| `shield-autostart` | SessionStart — arranque del shield local |
| `emergency-mode-readiness` | SessionStart — verificación modo emergencia |
| `session-end-memory` | SessionEnd — snapshot de memoria de sesión |
| `session-end-snapshot` | Stop — snapshot de contexto |
| `stop-quality-gate` | Stop — quality gate final |
| `stop-memory-extract` | Stop — extracción profunda de memoria |
| `pre-compact-backup` | PreCompact — backup pre-compactación |
| `scope-guard` | Stop — verificación de scope |
| `emotional-regulation-monitor` | Stop — monitor de estrés de sesión |
| `postponement-judge` | Stop — juez de postergación |

### Subagentes (2)
| Hook | Evento |
|------|--------|
| `subagent-lifecycle` | SubagentStart + SubagentStop |
| `task-lifecycle` | TaskCreated + TaskCompleted |

### UI/UX (6)
| Hook | Evento |
|------|--------|
| `memory-prime-hook` | UserPromptSubmit — priming de contexto |
| `stress-awareness-nudge` | UserPromptSubmit — nudge anti-estrés |
| `cwd-changed-hook` | CwdChanged |
| `file-changed-staleness` | FileChanged |
| `instructions-tracker` | InstructionsLoaded |
| `cognitive-debt-hypothesis-first` | (no registrado — fase 1 SPEC-107) |

### Auditoría y regeneración (2)
| Hook | Evento |
|------|--------|
| `agents-md-auto-regenerate` | Stop — regenera AGENTS.md |
| `pre-commit-review` | Stop — revisión pre-commit |

### No registrados (4 huérfanos)
Existen en filesystem pero no en settings.json. Pendientes de activación.

`android-adb-validate`, `cognitive-debt-hypothesis-first`,
`cognitive-debt-telemetry`, `recommendation-tribunal-pre-output`

## Provider-agnostic compliance

Todos los hooks usan este patrón para resolver el directorio del proyecto:
```bash
GIT_DIR_TARGET="${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$PWD}}"
```

Ningún hook hardcodea paths a `.claude/` sin fallback. El bridge `savia-gates`
inyecta `CLAUDE_PROJECT_DIR` como env var desde `PM_WORKSPACE_ROOT` cuando se
ejecuta bajo OpenCode, garantizando backward compatibility con hooks legacy.

## Registro

61 hooks registrados en `.claude/settings.json` (17 eventos). 4 hooks en
filesystem pendientes de registro. La configuración se comparte entre
frontends vía el bridge `savia-gates/lib/manifest.ts` que lee settings.json
y mapea eventos a eventos OpenCode equivalentes.
