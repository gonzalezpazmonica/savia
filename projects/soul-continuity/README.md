# Soul Continuidad v1 (SE-490)

Gemelo operativo de solo lectura, por usuario y sin privilegios. Responde cuatro preguntas sobre las fuentes de trabajo del operador:

- Q1: qué tengo abierto;
- Q2: qué depende de mí;
- Q3: qué cambió desde un instante;
- Q4: qué compromisos con fecha hay.

Se consulta desde la CLI `soul` y desde la app de Savia Space emparejada, por la VPN del propio operador.

Es TypeScript sobre el runtime oficial de Node.js (≥ 22.6). No tiene dependencias de ejecución, ni módulos nativos, ni ejecutables propios. Spec: `docs/specs/SE-490-soul-continuity-work-laptop.spec.md`.

## Estructura

| Ruta | Qué es |
|---|---|
| `src/contract/` | Contrato compartido: afirmaciones (`claims.ts`), adaptadores (`adapter.ts`), semántica (`CONTRATO.md`), OpenAPI de la app y gramática de órdenes |
| `src/core/` | Núcleo: instantánea con TTL, libro de correcciones por operador (con el dispositivo de cada corrección), almacén atómico, STOP durable, configuración y perfil activo |
| `src/core/connectors.ts` | Registro de los adaptadores reales: solo los que el operador nombra en `connectors.enabled`; transporte HTTPS de solo lectura; revocación por adaptador |
| `src/adapters/` | Adaptadores de API (Microsoft 365, Google, Jira, Azure DevOps, GitHub) |
| `src/web/` | Adaptador `web`: navegador instalado en un perfil dedicado, recetas y cortafuegos (paquete aparte con `playwright-core`) |
| `src/attention/` | Política de atención de SE-490 (librería pura con sus evals y mutantes) |
| `src/cli/` | CLI `soul` (`bin/soul.mjs` la lanza) |
| `src/api/` | API local: HTTPS con certificado propio, dispositivos emparejados, escucha solo en las direcciones configuradas |
| `src/credentials/` | El único almacén de credenciales: el del sistema (Credential Manager, llavero, Secret Service) con un índice sin secretos de todo lo que guarda Soul |
| `src/startup/` | Arranque sin administrador (`systemd --user`, `LaunchAgent`, tarea de inicio de sesión) |
| `bench/` | Banco de continuidad con verdad escrita antes de ejecutar (80 escenarios, dobles, mutantes) |

## Uso

```
node bin/soul.mjs init trabajo --email yo@example.test   # perfil sin fuentes ni adaptadores
node bin/soul.mjs login github --token-stdin              # token al almacén del sistema
node bin/soul.mjs status             # sin red, en frío
node bin/soul.mjs q1 | q2 | q4       # preguntas
node bin/soul.mjs q3 --since 2026-10-30T09:00:00Z
node bin/soul.mjs why <id>           # ¿por qué lo sé?
node bin/soul.mjs correct <id> resuelto
node bin/soul.mjs stop | resume      # fail-safe que sobrevive a reinicios
node bin/soul.mjs pair movil         # token (se muestra una vez), huella del certificado y dirección
node bin/soul.mjs serve              # API para la app
```

La configuración vive en el directorio de datos del usuario: `config.json`, con `active_profile`, `profiles`, `detail`, `agent_frontend` y `api.listen`. Ese directorio es:

- en Linux, `~/.local/share/savia/soul-continuity`;
- en macOS, `~/Library/Application Support/Savia/soul-continuity`;
- en Windows, `%LOCALAPPDATA%\Savia\soul-continuity`.

Sin perfil activo, Soul responde «no sé quién eres». Sin direcciones en `api.listen`, `serve` no arranca. Instalación paso a paso para cualquier operador: [`docs/instalar.md`](docs/instalar.md).

## Garantías y dónde se prueban

| Garantía | Prueba |
|---|---|
| Banco AC-3: precisión ≥ 90 % por pregunta y todos los escenarios de garantía | `npm run bench`, `test/bench-impl.test.ts` |
| Lo revocado no vuelve; libro por operador | `test/engine.test.ts`, `test/cli.test.ts` |
| AC-4d: por un frontend de agente solo salen recuentos | `test/cli.test.ts`, `test/config.test.ts` |
| AC-5: revocar borra caché delta, perfil web y los tokens de todas las variantes; desinstalar borra todos los tokens indexados y no deja estado | `test/ac5-integracion.test.ts`, `test/connectors.test.ts`, `test/cli.test.ts` |
| H-1: nada activo por defecto; solo los adaptadores que nombra el operador | `test/connectors.test.ts` |
| Banco AC-3 del núcleo con los adaptadores reales de API contra los dobles | `test/bench-impl.test.ts` |
| Canal: DPoP verificado y clave ligada al dispositivo, tokens con caducidad, límites de conexión | `test/dpop.test.ts`, `test/devices.test.ts`, `test/serve.test.ts` |
| Punta a punta: init, login, pair, serve, Q1–Q4 por cursor, corrección, revoke y uninstall | `test/e2e.test.ts`, `test/instalar.test.ts` |
| 0 tokens en disco: el secreto solo por stdin al almacén del sistema; el núcleo descarta la lectura de un adaptador que devuelve el token | `test/credentials.test.ts`, `test/engine.test.ts`, `test/cli.test.ts` |
| Solo escucha en las direcciones configuradas (test de puertos) | `test/listen.test.ts` |
| Contrato de la app: 27 tests de Labs contra el servidor del producto | `test/api/contrato.test.mjs` |
| STOP durable | `test/failsafe.test.ts`, `test/serve.test.ts` |

```
npm test          # todos los tests
npm run bench     # banco contra el núcleo
npm run typecheck # tsc --strict (necesita npm install)
```

## Límites conocidos (v1)

- **DPoP**: la API verifica la prueba (ES256, `htm`, `htu`, `iat` ±60 s, `jti` de un solo uso, `ath`) y liga la clave en la **primera** conexión. Quien use el token antes que el móvil legítimo liga su clave: el token se muestra una sola vez y hay que introducirlo enseguida en la app.
- **AC-4d es de mejor esfuerzo frente a un agente adversario**: la detección del frontend usa variables de entorno y `--frontend`, y un agente podría borrarlas. Protege contra el uso normal desde Claude Code u OpenCode, no contra un agente que quiera saltárselo.
- **Política de atención de la API**: el estado (modo, avisos, alertas, pendientes, registro de demanda y mensajes del sondeo) persiste por operador en `attention-state.json` y sobrevive a reiniciar `serve`; `soul mode` se aplica en el siguiente tic. Pero las decisiones las sigue tomando la aproximación de Labs que lleva el servidor, no la librería `src/attention/` (presupuesto por ventana fija, sin franjas declaradas ni descansos). Sustituirla es el siguiente paso de la integración.
- **Credenciales**: en Windows y macOS solo se han probado con un doble, no contra el almacén real. En Windows, `Add-Type` falla bajo Constrained Language Mode: entonces el almacén da error y el token no se guarda en ningún otro sitio.
