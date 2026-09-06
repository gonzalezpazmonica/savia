# Hook Portability & Risk→Enforcement Mapping (SE-388 P2/P3 — sin credenciales)

> Estado: reporte basado en probes locales reales (CLI 0.153.4, sandbox/approvals/MCP NATIVE, auth ✗). Los canaries de ejecución con modelo y la verificación MCP e2e desde Codex requieren `codex login` (credenciales de la operadora).

## Portability de hooks safety-critical (SE-388 §10/§11)

| Control | Savia contract | Claude | OpenCode | Codex mechanism | Parity | Evidencia |
|---|---|---|---|---|---|---|
| credential leak block | pre_tool_enforcement | hooks block-credential-leak | espejo | sandbox+approvals (sin PreToolUse equiv.) | UNKNOWN→reroute L3/L4 | canary fixture |
| unsafe shell block | pre_tool | validate-bash-global | espejo | sandbox policy read-only/workspace-write | EQUIVALENT (sandbox) | probe sandbox modes |
| write-scope | pre_tool | hook | espejo | approvals per command | EQUIVALENT_DIFFERENT | approvals probe |
| L3 human gate | approvals | settings | gates | approvals nativo | EQUIVALENT | approvals probe |
| L4 block | constitutional | BLOCK hooks | BLOCK | sin equivalente determinista → **BLOCKED_OR_HUMAN_REROUTE** | UNKNOWN | docs |
| receipts | post_tool | hook | plugin | sessions archive (no receipt canónico) | DEGRADED | probe |
| terminal reconciliation | workflow | SE-332 | SE-332 | resume/queue experimental | UNKNOWN | probe |

## Risk→Enforcement mapping

- L0-L1: sandbox read-only/workspace-write = enforcement nativo → **parity demostrable** (canary local).
- L2: approvals nativo + F5 reservation → **parity con mechanismo distinto** (EQUIVALENT_WITH_DIFFERENT_MECHANISM).
- L3: human gates vía approvals nativo → **EQUIVALENT** (verificar con sesión autenticada).
- L4: sin PreToolUse-equivalente determinista → **BLOCKED_OR_HUMAN_REROUTE** (no hay garantía equivalente hoy; no se declara parity).

## max_verified_risk = L2 (sin cambio hasta credenciales + canaries)

100% de controles safety-critical clasificados: 0 UNKNOWN en L0-L2 (nativos/demostrables), L3/L4 = BLOCKED_OR_HUMAN_REROUTE explícito. **0 UNKNOWN en L3/L4 se mantiene como gate** — la clasificación actual es UNKNOWN→REROUTE (no se promete lo que no se demuestra).
