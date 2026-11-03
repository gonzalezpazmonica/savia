---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L2
human_surface: true
related_specs: [SE-343, SE-386, SE-434, SE-436, SE-493, SE-496]
origin: "Informe de Savia Labs labs/research/20261102-inventario-rutas-efecto.md (hueco G8 de labs/research/20261102-arquitectura-control-efectos.md): rutas E01 (unknown), E02 (declarative) y E04 (unknown), las tres sin guard. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
---

# SE-508 — Guard previo para tools MCP con escritura y para WebFetch

## Problema (verificado en origin/main 3e094038d, 2026-11-03)

En Claude Code, ninguna llamada a una tool MCP ni a `WebFetch` pasa por un guard antes de ejecutarse:

- `.claude/settings.json` solo registra en `PreToolUse` con matcher `*` el hook `savia-budget-guard.sh`, que avisa del presupuesto y **no mira el nombre de la tool ni sus argumentos** (`.opencode/hooks/savia-budget-guard.sh:13-16`).
- Para `mcp__.*` solo hay un `PostToolUse` (`.claude/hooks/twin-posttooluse.sh`), que corre después del efecto y no hace nada sin `TWIN_HOOK_ENABLED`.
- Para `WebFetch` solo hay `PostToolUse` (`context-drop-after-use.sh`, `judge-auto-router.sh`).
- En OpenCode, ningún guard de `.opencode/plugins/guards/` trata tools MCP; solo `context-drop-after-use.ts` menciona `WebFetch`, y es posterior.

Rutas del inventario que esto deja abiertas:

| ID | Ruta | Estado | Riesgo |
|---|---|---|---|
| E01 | Conectores de la cuenta (enviar y reenviar correo, compartir y crear en Drive, eventos de calendario, tableros de Miro) | unknown | Mensaje a personas o datos fuera, sin pasar por nada del repo |
| E02 | `mcp__github__merge_pull_request` / `create_pull_request` (plantilla `.opencode/mcp-templates/github.jsonc.example`) | declarative | Si se activa, un merge salta el grant firmado de SE-343, la reserva F5 y los hooks de merge, que solo miran `Bash` |
| E04 | `WebFetch` | unknown | La URL o la query pueden sacar datos o llamar a un endpoint con efecto |

## Discovery: qué ya existe

| Pieza | Dónde | Por qué no basta |
|---|---|---|
| Puerta de Yema | Yema `nucleo/puerta.py` (deniega tools desconocidas) | Solo para sesiones de Yema |
| Modo mediado de Space | `<servidor>_*: ask` (repo privado de Space, SE-434) | Solo con Space delante |
| `dome-guard.sh` | `.claude/hooks/dome-guard.sh:1-26` | Precedente del patrón (PreToolUse con `ask`, doble binding con savia-gates y test de paridad), pero solo para cúpulas |
| Descriptores de capacidad | SE-386, `contracts/capabilities/*.yaml` | Según el inventario, de las 53 rutas externas solo `pr.merge` y `social.linkedin.publish` tienen descriptor; ninguna tool MCP |

Conclusión: el hueco es real. Se reutiliza el patrón de `dome-guard.sh` con su núcleo en Python y binding doble; no hace falta un mecanismo nuevo.

## Qué decide esta spec

1. **Hook `PreToolUse` `.claude/hooks/mcp-effect-guard.sh`** con matcher `mcp__.*|WebFetch`. Lee el JSON de stdin y delega en un núcleo `lib/mcp_effect_guard.py`, el mismo que usa el binding de OpenCode.
2. **Clasificación por catálogo, no por adivinanza.** `config/mcp-effect-catalog.yaml` asigna a cada tool una clase: `read_only`, `write` o `merge`. Es el catálogo de clases de efecto que pide el inventario.
3. **Decisión:**
   - `read_only` del catálogo → no decide nada (pasa).
   - `write` → `ask`, con un motivo en llano que dice qué tool, qué destino y qué efecto («Enviar un correo a 2 personas»).
   - `merge` → `deny`, con el motivo «los merges van por `push-pr.sh --merge` o `merge-sprint.sh` con grant (SE-343)».
   - **Tool que no está en el catálogo → `ask`** (falla cerrado). Nunca pasa en silencio.
4. **WebFetch:** pasa si el host está en `config/webfetch-allow-hosts` y la URL no lleva query; en otro caso, `ask` con el host y la longitud de la query. S1 registra las decisiones sin preguntar (modo `observe`) para medir cuántas preguntas generaría; el paso a `enforce` lo decide la operadora con esa medida.
5. **Delegación:** con `SAVIA_GATES_PIN=1` (modo mediado de Space) o `SAVIA_MCP_GUARD=space`, el hook no decide; manda el guard de Space.
6. **No hay interruptor para apagarlo.** Solo existe la delegación del punto 5.

## Lo que he entendido

### Escenas
1. Le pides a Savia que prepare un correo para tu equipo. Antes de enviarlo te aparece: «Savia quiere enviar un correo a 3 personas (asunto: "Plan de la semana"). ¿Lo envío?». Si dices que no, el correo no sale.
2. Un agente nocturno intenta fusionar un PR con la tool de GitHub en vez de con el grant. No te despierta: la llamada se rechaza y en el resumen de la mañana lees «se bloqueó un merge por MCP; los merges van con grant».
3. Savia consulta la documentación oficial de una librería. No te pregunta nada, porque ese sitio está en tu lista. Si intenta abrir una web desconocida con datos en la dirección, te pregunta antes.

### Palabras de la persona
No hay palabras literales de la operadora sobre este guard. La necesidad sale del inventario G8 (huecos 2 y 9 del informe) y de la regla vigente «La IA propone, el humano dispone» (`docs/rules/domain/autonomous-safety.md`).

### Qué SÍ será
- Una pregunta clara antes de cualquier efecto por un conector o una tool MCP que escriba.
- Un rechazo directo de los merges por MCP.

### Qué NO será
- No pregunta por las lecturas que están en el catálogo.
- No sustituye la frontera en GitHub (G1): un agente con shell sigue pudiendo llamar a la API por otra vía.

### Confirmación
- fecha: pendiente
- respuesta: pendiente. Falta enseñar las escenas y, sobre todo, cuántas preguntas generaría WebFetch (medida de S1) antes de aprobar.

## Slice S0 — Prototipo navegable
- prototipo: los tres textos exactos de pregunta y rechazo de las escenas, y una tabla con las decisiones que habría tomado el guard sobre las llamadas MCP y WebFetch de una semana real (modo `observe`).

### Confirmación del prototipo
- fecha: pendiente (obligatoria antes de poner S1 en curso)
- respuesta: pendiente

## Criterios de aceptación

| AC | Criterio | Tipo | Test |
|---|---|---|---|
| AC-1 | Tool `read_only` del catálogo → sin decisión (exit 0, sin `permissionDecision`) | estática | `tests/hooks/test-se508-mcp-effect-guard.bats` |
| AC-2 | **Negativo:** tool `write` del catálogo (fixture `mcp__gmail__send_message`) → `ask` con destino y efecto en el motivo | estática | ídem |
| AC-3 | **Negativo:** `mcp__github__merge_pull_request` → `deny` citando SE-343 | estática | ídem |
| AC-4 | **Negativo:** tool que no está en el catálogo → `ask`, nunca pasa | estática | ídem |
| AC-5 | **Fail-closed:** stdin vacío, JSON malformado, catálogo ausente o ilegible → `ask` para cualquier tool MCP; nunca exit 0 sin decisión | estática | ídem |
| AC-6 | WebFetch a host permitido sin query → pasa; **negativo:** host permitido con query, o host no permitido → `ask` en `enforce` y una línea de registro en `observe` | estática | ídem |
| AC-7 | **Límite:** host `docs.ejemplo.org` permitido no autoriza `docs.ejemplo.org.atacante.net` ni `atacante.net/docs.ejemplo.org` | estática | ídem |
| AC-8 | `SAVIA_GATES_PIN=1` → el hook no decide (delegación a Space) | estática | ídem |
| AC-9 | Paridad: el binding de OpenCode toma la misma decisión que el hook ante las mismas entradas de AC-1..8 | estática | `tests/hooks/test-se508-mcp-guard-parity.bats` |
| AC-10 | Cada test se ejecuta contra el árbol sin el hook y falla (el guard no existe), y pasa con él | revisión | evidencia en el PR de S1 |
| AC-11 | Medida de S1: decisiones `ask` por día en modo `observe` sobre una semana de uso, publicada antes de pasar WebFetch a `enforce` | experimento | informe en `output/` |
| AC-12 | `capability-entropy.py --check` PASS; `validate-ci-local.sh --quick` verde | CI | — |

## Plan por slices

| Slice | Entrega |
|---|---|
| S0 | Textos y tabla de decisiones en modo `observe`, confirmados por la operadora |
| S1 | Núcleo Python, hook, catálogo inicial (conectores observados, GitHub MCP, Vaults MCP) y binding OpenCode; MCP en `enforce`, WebFetch en `observe`; AC-1..10 |
| S2 | WebFetch en `enforce` si la operadora lo decide con la medida de AC-11 |

## Fuera de alcance

- La frontera en el servidor de GitHub (G1) y el segundo camino de merge `review-community.sh merge` (A09): son specs aparte.
- Las rutas que ocurren dentro de un script (el guard es de tools, no de subprocesos).
- Rutas del inventario descartadas para esta spec: D04 (cubierta por SE-491 y SE-496), C10 (tiene descriptor con `human_gate: required` y no hay código que publique), C11 y E03 (son guard o configuración, no rutas) y A21 (solo imprime instrucciones y `block-force-push.sh` la cubre si se ejecuta).

## Riesgos

- **Fatiga de preguntas:** por eso WebFetch empieza en `observe` y la decisión de `enforce` se toma con datos.
- **Catálogo incompleto:** una tool nueva pregunta hasta que alguien la clasifica; es el coste aceptado de fallar cerrado.
- **Límite del guard:** ve la llamada a la tool, no lo que el servidor MCP hace por dentro.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `lib/mcp_effect_guard.py` | Núcleo compartido | Núcleo compartido |
| `.claude/hooks/mcp-effect-guard.sh` | Hook `PreToolUse`, matcher `mcp__.*\|WebFetch` | — |
| `scripts/opencode-plugin/savia-gates/lib/mcp-effect-guard.ts` | — | Regla en `tool.execute.before`, como `dome-guard.ts` |
| `config/mcp-effect-catalog.yaml`, `config/webfetch-allow-hosts` | Ficheros | Los mismos |

### Verification protocol

- [ ] Funciona en runtime OpenCode con las mismas decisiones (test de paridad AC-9)
- [ ] Tests BATS cubren AC-1..8 con negativos y el caso límite
- [ ] Falla cerrado ante entrada inesperada

### Portability classification

- [x] **DUAL_BINDING**: hook bash para Claude Code y regla de savia-gates para OpenCode sobre el mismo núcleo.

## Aprobación

Spec PROPOSED. Requiere la confirmación de escenas de la operadora (SE-505) antes de pasar a APPROVED. Esta PR solo añade documentación; ningún agente la fusiona sin grant.
