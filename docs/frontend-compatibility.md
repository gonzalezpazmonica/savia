# Savia: Codex y OpenCode en el mismo directorio

Ambos pueden abrir el repositorio. El contexto operativo se carga desde
`AGENTS.md`, generado por `scripts/agents-md-generate.sh`, que indica leer
`CLAUDE.md`, identidad, reglas críticas y perfil activo.

| Recurso | OpenCode | Codex |
|---|---|---|
| Contexto | `opencode.json` instructions + AGENTS.md | AGENTS.md |
| Skills compartidas | `.opencode/skills` | `.agents/skills` |
| Fuente de skills | `.claude/skills` | `.claude/skills` |
| Agentes nativos | `.opencode/agents` y opencode.json | El índice no registra subagentes |
| Hooks | Plugins de `.opencode/plugins` | No hereda los hooks de OpenCode |
| MCP | opencode.json | Configuración propia de Codex |

Reiniciar Codex después de instalar el enlace de skills. Los catálogos no
sustituyen la lectura de cada SKILL.md ni convierten los permisos de OpenCode
en permisos de Codex. La ausencia de `.codex/config.toml` no impide abrir el
repositorio: Codex puede usar su configuración de usuario.

## Sesiones simultáneas

En un mismo directorio se comparten archivos, rama e índice Git. Acordar qué
archivos modifica cada sesión y serializar operaciones Git. No cambiar ramas
ni descartar o incluir cambios ajenos. Para ramas independientes, usar worktrees.
El registro de sesiones es cooperativo; no bloquea escritores que lo ignoran.
Consultar `rules/domain/parallel-session-protocol.md` antes de operaciones Git.

## Verificación local

```bash
codex --version
opencode --version
bash scripts/agents-md-generate.sh --check
bash scripts/opencode-config-validate.sh --check
bats tests/structure/test-agents-md-generate.bats tests/structure/test-agents-md-drift-check.bats
```

Estas comprobaciones no acreditan llamadas a proveedores ni equivalencia de
hooks. En Codex deben ejecutarse explícitamente los gates aplicables; no debe
considerarse validada una revisión que solo habría ejecutado un hook ausente.

## Perfil de autonomía Codex

`scripts/configure-codex.sh` proyecta `autonomous-l2` sólo cuando pasan probes
reales de sandbox y enforcement. No modifica `config.toml`, no usa bypasses y
rechaza sobrescribir un perfil ajeno. `scripts/workspace-doctor.sh
--codex-autonomy` muestra el estado efectivo; `scripts/codex-autonomy-canaries.sh`
ejecuta contratos y probes. La fuente semántica es
`scripts/dual-cli/autonomy.py`; la configuración Codex es una proyección.

Estado comprobado con Codex 0.153.4: `DEGRADED_SAFE`, techo L2. Un perfil
AppArmor específico permite ejecutar el sandbox sin desactivar la restricción
global de user namespaces. La proyección usa el permission profile nativo de
Codex y una regla filesystem `deny` para `~/.codex/auth.json`; no mezcla este
modelo con el `sandbox_mode` legado. Los probes reales deniegan cat, redirección
shell, Python, procesos hijo, symlink, rutas relativas y traversal, mientras la
escritura del workspace permanece habilitada. L3/L4 continúan
`BLOCKED_OR_HUMAN_REROUTE`; esta evidencia no eleva el techo sobre L2.

Fuentes oficiales de Codex:
- https://learn.chatgpt.com/docs/agent-configuration/agents-md
- https://learn.chatgpt.com/docs/build-skills
- https://learn.chatgpt.com/docs/permissions
