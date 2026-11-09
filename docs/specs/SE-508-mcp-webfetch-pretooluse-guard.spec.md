---
status: APPROVED
priority: P1
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L2
human_surface: true
related_specs: [SE-343, SE-386, SE-434, SE-436, SE-493, SE-496, SE-505, SE-507]
origin: "Informe de Savia Labs labs/research/20261102-inventario-rutas-efecto.md (hueco G8 de labs/research/20261102-arquitectura-control-efectos.md): rutas E01 (unknown), E02 (declarative) y E04 (unknown), las tres sin guard. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "APPROVED"
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

1. **Hook `PreToolUse` `.claude/hooks/mcp-effect-guard.sh`** con matcher `mcp__.*|WebFetch|WebSearch`. Lee el JSON de stdin y delega en un núcleo `lib/mcp_effect_guard.py`, el mismo que usa el binding de OpenCode.
2. **Clasificación por catálogo, no por adivinanza.** `config/mcp-effect-catalog.yaml` asigna a cada tool una clase: `read_only`, `write` o `merge`. Es el catálogo de clases de efecto que pide el inventario. Cubre los dos prefijos reales: los conectores de la cuenta (`mcp__claude_ai_<Servicio>__*`, p. ej. `mcp__claude_ai_Gmail__send_message`) y los servidores configurados en el repo (`mcp__github__*`, `mcp__savia-vaults__*`). Nombres exactos, sin comodines.
   - **El catálogo no se puede aflojar desde el árbol de trabajo.** Un agente puede editar `config/`, la ref local `origin/main` (`git update-ref`, `remote set-url` + `fetch`) y también `.git/config` (`remote set-url`, `url.<x>.insteadOf`, `core.sshCommand`), así que ni la ref local ni el remoto con nombre `origin` sirven de referencia. El núcleo usa una **URL canónica HTTPS fijada como constante en el propio núcleo** (`CANONICAL_REMOTE`; un fork la cambia con una PR en su fork) y nunca un nombre de remoto. Ejecuta `git ls-remote <URL> refs/heads/main` (tiempo máximo 3 s) y el `fetch` de ese SHA concreto **en un repositorio temporal vacío fuera del árbol**, con `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null` y sin `GIT_DIR`, de modo que ninguna configuración del repositorio de trabajo, global ni de sistema (`insteadOf`, `sshCommand`, `credential.helper`) interviene. Lee el catálogo de ese SHA con `git cat-file` en ese repositorio temporal y aplica, tool a tool, **el más estricto** entre ese y el del árbol (orden `merge` > `write` > `read_only`; una tool que falta en cualquiera de los dos cuenta como no catalogada). Editar el catálogo local solo puede endurecerlo; aflojarlo exige una PR fusionada. **No hay «último catálogo conocido»:** si el remoto no contesta o el objeto no se puede leer, se usa solo el árbol y **todo** `read_only` pasa a `ask` (falla cerrado; sin red los conectores tampoco funcionan, así que el coste es bajo). Lo mismo vale para `config/webfetch-allow-hosts`: intersección de ambas listas y, sin remoto, ningún host permitido. Con el pin de guards de Space activo (`guard-pin.ts`), ambos ficheros entran en el conjunto fijado.
   - **Consecuencia aceptada en runs autónomos:** sin remoto legible, todo `read_only` pasa a `ask` y el punto 8 lo convierte en `deny`, así que un run nocturno con la red caída o parcial no usa ningún MCP. Es el precio de fallar cerrado y queda escrito como tal; el run lo registra y sigue con lo que no necesita MCP.
   - **Límite declarado:** la URL canónica y el propio núcleo viven en el árbol, así que un agente que reescriba el núcleo también podría apagar el guard entero. Esta spec no protege el código del guard frente a su edición; eso lo cubren el pin de guards de Space (`guard-pin.ts`) y la revisión de la PR. Lo que sí garantiza es que editar el **catálogo**, la **lista de hosts**, la ref local o la configuración git no afloja nada.
   - **Inyección en tests:** la URL canónica solo se sustituye por la de un repositorio bare de fixture con `SAVIA_MCP_GUARD_TEST=1` y `BATS_TEST_FILENAME` no vacía. Los hooks heredan el entorno del proceso de Claude Code o de OpenCode fijado al arrancar, no el del shell de la tool, así que un agente no puede activarla desde una orden.
3. **Decisión:**
   - `read_only` del catálogo → no decide nada (pasa).
   - `write` → `ask`, con un motivo en llano que dice qué tool, qué destino y qué efecto («Enviar un correo a 2 personas»).
   - `merge` → `deny`, con el motivo «los merges van por `push-pr.sh --merge` o `merge-sprint.sh` con grant (SE-343)».
   - **Tool que no está en el catálogo → `ask`** (falla cerrado). Nunca pasa en silencio.
4. **WebFetch:** pasa si el host está en `config/webfetch-allow-hosts`, la URL no lleva query ni fragmento y el path mide como máximo 200 caracteres sin ningún segmento de más de 64; en otro caso, `ask` con el host y la longitud de lo que sobra. El host se normaliza antes de comparar con `urllib.parse`: minúsculas, sin punto final, IDN a punycode; una URL con userinfo (`usuario@host`) o con un puerto distinto del de su esquema → `ask` siempre; esquemas distintos de `https` → `ask`. Las redirecciones: el guard ve la URL antes de la llamada y no puede saber si redirigirá, así que no las juzga. La premisa es que WebFetch no sigue una redirección a otro host, sino que devuelve la URL nueva y esa vuelve a pasar por el guard como llamada aparte. S1 la **verifica** (documentación de la tool y una prueba manual contra un host propio que redirige, con el resultado en el PR de S1); si la premisa resulta falsa, S2 no puede pasar WebFetch al régimen «host permitido pasa»: todo WebFetch queda en `ask`. S1 registra las decisiones sin preguntar (modo `observe`) para medir cuántas preguntas generaría.
   - **Caducidad de `observe`:** la fecha límite es la constante `OBSERVE_UNTIL` del núcleo (`lib/mcp_effect_guard.py`), fijada en S1 a fecha de fusión + 14 días. El núcleo usa la **más temprana** entre la del árbol y la del `main` resuelto en el remoto (mismo mecanismo que el catálogo), así que retrasarla en el árbol no sirve. Sin remoto legible o con la constante ilegible en el árbol → `enforce`. Si el remoto se lee pero su `main` todavía no contiene `lib/mcp_effect_guard.py` (antes de fusionar S1), se usa la del árbol: aflojarla en el árbol no da nada, porque antes de la fusión no hay guard en `main` que saltar; si el fichero existe en `main` pero no define la constante → `enforce`. Llegada la fecha, el núcleo pasa solo a `enforce` aunque la operadora no haya decidido (falla cerrado por calendario, no por olvido).
   - **Runs autónomos sin `observe` para WebFetch:** en una ejecución sin persona (punto 8), WebFetch se evalúa en `enforce` desde S1, sin esperar a `OBSERVE_UNTIL`: solo pasa un host permitido sin query ni fragmento y con el path dentro del límite; lo demás es `ask` → `deny`. `observe` queda solo para sesiones con persona, que es donde se mide la fatiga de preguntas.
   - **WebSearch:** su `query` también sale a un tercero. En S1 solo se registra (modo `observe`, misma medida), también en runs autónomos: los workers de investigación nocturnos dependen de ella y no hay lista de «queries permitidas» equivalente a la de hosts. Es exfiltración residual aceptada y declarada en Riesgos; su paso a `enforce` se decide junto con WebFetch en S2.
5. **Delegación a Space, acotada y solo en OpenCode.** El modo mediado de Space corre sobre el motor de OpenCode (SE-434), y allí Space media cada llamada MCP. Por eso:
   - **El hook de Claude Code no delega nunca.** `SAVIA_GATES_PIN` y `SAVIA_MCP_GUARD` no cambian nada en `.claude/hooks/mcp-effect-guard.sh`: Space no lanza Claude Code, así que esa variable en una sesión de Claude Code solo puede ser un error o un intento de saltar el guard.
   - **El binding de OpenCode delega** las clases `write`, no catalogada y WebFetch/WebSearch solo si `SAVIA_GATES_PIN=1` **y** el pin de guards está fijado en el propio proceso del plugin (`guard-pin.ts`), que es lo que arranca Space. `SAVIA_MCP_GUARD=space` sin pin fijado no delega.
   - **La clase `merge` no se delega nunca**: el `deny` se aplica en ambos frontends con cualquier variable, porque un merge sin grant (E02) es el único efecto que esta spec rechaza siempre.
   - Cada decisión delegada deja una línea `delegated` en el registro de decisiones, para que un arranque mal configurado se vea en el resumen.
6. **Orden de evaluación, fijo:** (1) leer y validar stdin — vacío o malformado → `ask`; (2) leer catálogos — ausentes o ilegibles → `ask`; (3) clasificar; (4) `merge` → `deny`; (5) delegación del punto 5, **solo si la ejecución no es sin persona** (punto 8): un run autónomo nunca delega; (6) reglas de los puntos 3 y 4, que dan «pasa», `ask` o, en `observe`, una línea de registro; (7) ejecución sin persona → **todo** `ask` emitido en (1), (2) o (6) pasa a `deny`, sea `write`, no catalogada, entrada inválida o WebFetch/WebSearch en `enforce`.
7. **No hay interruptor para apagarlo, pero sí un bypass condicionado.** Ninguna variable apaga el guard en Claude Code. En OpenCode, el modo delegado del punto 5 sí deja de preguntar por `write`, no catalogada y WebFetch: es un bypass condicionado a que el pin de Space esté fijado. Lo que nunca se salta, en ningún frontend ni modo: el `deny` de merge, el fallo cerrado ante entrada inválida y la conversión a `deny` en runs autónomos.
8. **`ask` sin nadie delante.** En una ejecución sin persona (`SAVIA_RUN_ID` o `SAVIA_AUTONOMOUS_RUN=1` en el entorno; ver SE-507 y `autonomous-safety.md`), el núcleo convierte todo `ask` en `deny` con el mismo motivo y una línea para el resumen de la mañana (paso 7 del punto 6). Así el resultado no depende de cómo resuelva `claude -p` un `ask` según sus flags de permisos. WebFetch no tiene `observe` en runs autónomos (punto 4). WebSearch sí, hasta `OBSERVE_UNTIL`: queda registrado y es parte de lo que mide AC-11.

## Lo que he entendido

### Escenas
1. Le pides a Savia que prepare un correo para tu equipo. Antes de enviarlo te aparece: «Savia quiere enviar un correo a 3 personas (asunto: "Plan de la semana"). ¿Lo envío?». Si dices que no, el correo no sale.
2. Un agente nocturno intenta fusionar un PR con la tool de GitHub en vez de con el grant. No te despierta: la llamada se rechaza y en el resumen de la mañana lees «se bloqueó un merge por MCP; los merges van con grant».
3. Savia consulta la documentación oficial de una librería. No te pregunta nada, porque ese sitio está en tu lista. Si intenta abrir una web desconocida con datos en la dirección, te pregunta antes.

### Palabras de la persona
«Savia Viva + tokens y efectos» — 2026-11-09, respuesta de la operadora a la pregunta interactiva sobre qué specs aprobar.

### Qué SÍ será
- Una pregunta clara antes de cualquier efecto por un conector o una tool MCP que escriba.
- Un rechazo directo de los merges por MCP.

### Qué NO será
- No pregunta por las lecturas que están en el catálogo.
- No sustituye la frontera en GitHub (G1): un agente con shell sigue pudiendo llamar a la API por otra vía.

### Confirmación
- fecha: 2026-11-09
- respuesta: «Confirmo las escenas». Opción elegida por la operadora en la pregunta interactiva del 2026-11-09 en la que se le enseñaron estas escenas literalmente.

## Slice S0 — Prototipo navegable
- prototipo: los tres textos exactos de pregunta y rechazo de las escenas, y una tabla con las decisiones que habría tomado el guard sobre las llamadas MCP y WebFetch de una semana real (modo `observe`).

### Confirmación del prototipo
- fecha: pendiente (obligatoria antes de poner S1 en curso)
- respuesta: pendiente

## Criterios de aceptación

| AC | Criterio | Tipo | Test |
|---|---|---|---|
| AC-1 | Tool `read_only` del catálogo → sin decisión (exit 0, sin `permissionDecision`) | estática | `tests/hooks/test-se508-mcp-effect-guard.bats` |
| AC-2 | **Negativo:** tool `write` del catálogo (fixture `mcp__claude_ai_Gmail__send_message`, el nombre real del conector) → `ask` con destino y efecto en el motivo | estática | ídem |
| AC-2b | **Negativo (catálogo aflojado):** catálogo del árbol marca `mcp__claude_ai_Gmail__send_message` como `read_only` y el del `main` remoto como `write` → `ask`; el caso inverso (endurecer en el árbol) → aplica lo del árbol | estática (remoto = repo bare local de fixture) | ídem |
| AC-2c | **Negativo (ref local manipulada):** `refs/remotes/origin/main` reapuntada a un commit local con el catálogo aflojado y el remoto sin tocar → `ask` (manda el SHA de `ls-remote`, no la ref local) | estática | ídem |
| AC-2d | **Fail-closed (sin remoto):** `ls-remote` falla o tarda más de 3 s → toda tool `read_only` del árbol → `ask` y ningún host de WebFetch permitido; con `SAVIA_AUTONOMOUS_RUN=1` → `deny`; **negativo:** `OBSERVE_UNTIL` del árbol posterior a la del remoto → manda la del remoto |
| AC-2e | **Negativo (config git manipulada):** en el repositorio de trabajo, `remote set-url origin <bare con catálogo aflojado>`, o `url.<bare aflojado>.insteadOf=<URL canónica>` en `.git/config`, o la misma regla `insteadOf` en un `~/.gitconfig` de fixture → `ask` en los tres casos (el núcleo consulta la URL canónica en un repositorio temporal sin esa configuración) | estática | ídem |
| AC-3 | **Negativo:** `mcp__github__merge_pull_request` → `deny` citando SE-343 | estática | ídem |
| AC-4 | **Negativo:** tool que no está en el catálogo → `ask`, nunca pasa | estática | ídem |
| AC-5 | **Fail-closed:** stdin vacío, JSON malformado, `tool_input` sin URL en WebFetch, catálogo ausente o ilegible → `ask` para cualquier tool MCP, WebFetch o WebSearch, con o sin delegación; fuera del caso de delegación del punto 5, nunca exit 0 sin decisión para una tool que no sea `read_only` | estática | ídem |
| AC-6 | WebFetch a host permitido sin query → pasa; **negativo:** host permitido con query, con fragmento, con path de 201 caracteres o con un segmento de 65, o host no permitido → `ask` en `enforce` y una línea de registro en `observe`; **límite:** path de 200 caracteres → pasa | estática | ídem |
| AC-7 | **Límite:** host `docs.ejemplo.org` permitido no autoriza `docs.ejemplo.org.atacante.net`, `atacante.net/docs.ejemplo.org`, `https://docs.ejemplo.org@atacante.test/` (userinfo; `.test` es dominio reservado), `docs.ejemplo.org:8443` ni `http://docs.ejemplo.org`; sí autoriza `DOCS.Ejemplo.org.` (mayúsculas y punto final) | estática | ídem |
| AC-8 | **Negativo (Claude Code):** hook bash con `SAVIA_GATES_PIN=1` o `SAVIA_MCP_GUARD=space` y una tool `write` → `ask`, igual que sin la variable. Binding OpenCode con `SAVIA_GATES_PIN=1` y pin fijado → no decide para `write` y deja línea `delegated`; **negativo:** `SAVIA_MCP_GUARD=space` sin pin fijado → `ask`; cualquier variable con `mcp__github__merge_pull_request` → `deny` en ambos | estática | ídem + test TS del binding |
| AC-8b | **Negativo (headless):** `SAVIA_AUTONOMOUS_RUN=1` con una tool `write`, no catalogada, stdin malformado o WebFetch a host no permitido → `deny`, nunca `ask`, **también antes de `OBSERVE_UNTIL`** (WebFetch no tiene `observe` en runs autónomos); WebSearch en el mismo run antes de `OBSERVE_UNTIL` → pasa con línea de registro; ídem en OpenCode con `SAVIA_GATES_PIN=1` y pin fijado (un run autónomo no delega) | estática | ídem |
| AC-8c | `OBSERVE_UNTIL` = ayer (reloj inyectado) → el núcleo actúa en `enforce`; **límite:** `OBSERVE_UNTIL` = hoy → sigue en `observe` hasta el final del día; constante ilegible en el árbol → `enforce`; remoto sin `lib/mcp_effect_guard.py` → usa la del árbol; remoto con el fichero pero sin la constante → `enforce` | estática | ídem |
| AC-9 | Paridad: el binding de OpenCode toma la misma decisión que el hook ante las mismas entradas de AC-1..8, salvo la delegación con pin fijado, que solo existe en OpenCode y tiene su test en AC-8 | estática | `tests/hooks/test-se508-mcp-guard-parity.bats` |
| AC-10 | Ningún test puede pasar sin el guard. Los que esperan `ask` o `deny` (AC-2..8c) se ejecutan contra el árbol sin el hook y fallan. Los que esperan «pasa» o «no decide» (AC-1, el positivo de AC-6, el «sí autoriza» de AC-7, el «endurecer» de AC-2b, la delegación de AC-8, el WebSearch que pasa en AC-8b) darían lo mismo sin hook, así que se ejecutan contra un mutante del núcleo que responde `ask` a todo, y fallan | revisión | evidencia en el PR de S1 (las dos ejecuciones) |
| AC-11 | Medida de S1: decisiones que habrían sido `ask` por día en modo `observe`, sobre una semana de uso, publicada antes de que la operadora decida el paso a `enforce`. Si no se publica antes de `OBSERVE_UNTIL`, el paso automático ocurre igual: la medida informa la decisión, no la retrasa | experimento | informe en `output/` |
| AC-12 | `capability-entropy.py --check` PASS; `validate-ci-local.sh --quick` verde | CI | — |

## Plan por slices

| Slice | Entrega |
|---|---|
| S0 | Textos y tabla de decisiones en modo `observe`, confirmados por la operadora |
| S1 | Núcleo Python, hook, catálogo inicial (conectores observados, GitHub MCP, Vaults MCP) y binding OpenCode; MCP en `enforce`, WebFetch y WebSearch en `observe` hasta `OBSERVE_UNTIL` en sesiones con persona y WebFetch en `enforce` en runs autónomos; verificación de la premisa de redirecciones; AC-1..10 |
| S2 | WebFetch y WebSearch en `enforce` antes de `OBSERVE_UNTIL` si la operadora lo decide con la medida de AC-11; si no, el núcleo pasa solo en esa fecha y S2 se limita a ajustar la lista de hosts |

## Fuera de alcance

- La frontera en el servidor de GitHub (G1) y el segundo camino de merge `review-community.sh merge` (A09): son specs aparte.
- Las rutas que ocurren dentro de un script (el guard es de tools, no de subprocesos).
- Rutas del inventario descartadas para esta spec: D04 (cubierta por SE-491 y SE-496), C10 (tiene descriptor con `human_gate: required` y no hay código que publique), C11 y E03 (son guard o configuración, no rutas) y A21 (solo imprime instrucciones y `block-force-push.sh` la cubre si se ejecuta).

## Riesgos

- **Fatiga de preguntas:** por eso WebFetch empieza en `observe` y la decisión de `enforce` se toma con datos.
- **Catálogo incompleto:** una tool nueva pregunta hasta que alguien la clasifica; es el coste aceptado de fallar cerrado.
- **Límite del guard:** ve la llamada a la tool, no lo que el servidor MCP hace por dentro.
- **Exfiltración residual por WebFetch a un host permitido:** el límite de path la acota, no la elimina; una lista de hosts corta es la defensa principal.
- **Exfiltración residual por WebSearch en runs autónomos hasta `OBSERVE_UNTIL`:** la `query` sale al buscador sin pregunta. Existe hoy (no es una regresión); S1 la registra para medirla y S2 decide.
- **Delegación mal configurada:** en OpenCode, quien arranque el motor con `SAVIA_GATES_PIN=1` fuera de Space fija el pin y los `write` pasan sin pregunta. Se acepta solo porque `merge` no se delega, porque cada caso deja línea `delegated`, porque los runs autónomos no delegan y porque en Claude Code la variable no tiene efecto. Una prueba de presencia más fuerte (un canal propio de Space) queda para cuando Space la exponga: hoy el motor no ve los sockets de Space (SE-434).
- **`claude -p` lanzado sin `SAVIA_RUN_ID` ni `SAVIA_AUTONOMOUS_RUN`:** el guard no sabe que no hay persona y emite `ask`, que resuelve el modo de permisos del proceso. El lanzador de Savia exporta siempre la variable (SE-507); un `claude -p` lanzado a mano queda fuera de esta garantía.
- **Latencia y red:** `ls-remote` en cada llamada MCP o WebFetch añade hasta 3 s. Se acepta frente a una referencia falsificable; si la medida de S1 lo muestra caro, una caché verificada se decide en otra spec, no dentro del núcleo.
- **Dependencia no resuelta:** el requisito de confirmación de escenas viene de SE-505, que aún no está en `docs/specs/`.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `lib/mcp_effect_guard.py` | Núcleo compartido | Núcleo compartido |
| `.claude/hooks/mcp-effect-guard.sh` | Hook `PreToolUse`, matcher `mcp__.*\|WebFetch\|WebSearch` | — |
| `scripts/opencode-plugin/savia-gates/lib/mcp-effect-guard.ts` | — | Regla en `tool.execute.before`, como `dome-guard.ts` |
| `config/mcp-effect-catalog.yaml`, `config/webfetch-allow-hosts` | Ficheros | Los mismos |

### Verification protocol

- [ ] Funciona en runtime OpenCode con las mismas decisiones (test de paridad AC-9)
- [ ] Tests BATS cubren AC-1..8c (con 2b..2e) con negativos y el caso límite
- [ ] Falla cerrado ante entrada inesperada

### Portability classification

- [x] **DUAL_BINDING**: hook bash para Claude Code y regla de savia-gates para OpenCode sobre el mismo núcleo.

## Aprobación

APPROVED por la operadora el 2026-11-09 por pregunta interactiva («Savia Viva + tokens y efectos»), tras confirmar las escenas cuando la spec las exige. Se formaliza al fusionar la PR (SE-488). Arranca en modo observación (S1) para medir cuántas preguntas generaría antes de preguntar.
