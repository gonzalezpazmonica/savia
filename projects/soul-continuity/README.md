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
| `src/core/` | Núcleo: instantánea con TTL, libro de correcciones por operador, almacén atómico, STOP durable, configuración y perfil activo |
| `src/cli/` | CLI `soul` (`bin/soul.mjs` la lanza) |
| `src/api/` | API local: HTTPS con certificado propio, dispositivos emparejados, escucha solo en las direcciones configuradas |
| `src/credentials/` | Almacén de credenciales del sistema (Credential Manager, llavero, Secret Service) |
| `src/startup/` | Arranque sin administrador (`systemd --user`, `LaunchAgent`, tarea de inicio de sesión) |
| `bench/` | Banco de continuidad con verdad escrita antes de ejecutar (80 escenarios, dobles, mutantes) |

## Uso

```
node bin/soul.mjs status             # sin red, en frío
node bin/soul.mjs q1 | q2 | q4       # preguntas
node bin/soul.mjs q3 --since 2026-10-30T09:00:00Z
node bin/soul.mjs why <id>           # ¿por qué lo sé?
node bin/soul.mjs correct <id> resuelto
node bin/soul.mjs stop | resume      # fail-safe que sobrevive a reinicios
node bin/soul.mjs pair movil         # token de un solo uso, huella del certificado y dirección
node bin/soul.mjs serve              # API para la app
```

La configuración vive en el directorio de datos del usuario: `config.json`, con `active_profile`, `profiles`, `detail`, `agent_frontend` y `api.listen`. Ese directorio es:

- en Linux, `~/.local/share/savia/soul-continuity`;
- en macOS, `~/Library/Application Support/Savia/soul-continuity`;
- en Windows, `%LOCALAPPDATA%\Savia\soul-continuity`.

Sin perfil activo, Soul responde «no sé quién eres». Sin direcciones en `api.listen`, `serve` no arranca.

## Garantías y dónde se prueban

| Garantía | Prueba |
|---|---|
| Banco AC-3: precisión ≥ 90 % por pregunta y todos los escenarios de garantía | `npm run bench`, `test/bench-impl.test.ts` |
| Lo revocado no vuelve; libro por operador | `test/engine.test.ts`, `test/cli.test.ts` |
| AC-4d: por un frontend de agente solo salen recuentos | `test/cli.test.ts`, `test/config.test.ts` |
| AC-5: revocar borra caché y credencial; desinstalar no deja estado | `test/cli.test.ts` |
| 0 tokens en disco: el secreto solo por stdin al almacén del sistema | `test/credentials.test.ts` |
| Solo escucha en las direcciones configuradas (test de puertos) | `test/listen.test.ts` |
| Contrato de la app: 27 tests de Labs contra el servidor del producto | `test/api/contrato.test.mjs` |
| STOP durable | `test/failsafe.test.ts`, `test/serve.test.ts` |

```
npm test          # todos los tests
npm run bench     # banco contra el núcleo
npm run typecheck # tsc --strict (necesita npm install)
```
