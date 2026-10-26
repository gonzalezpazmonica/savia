---
status: APPROVED
approved_at: 2026-10-27
approved_by: "operadora, AskUserQuestion 2026-10-27 (alcance aprobado: S1-S2)"
priority: P1
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: B
risk: L3
related_specs: [SE-429, SE-434, SE-244, SE-446, SE-452]
origin: output/research/20261020-learnings-goose-gentledot-rea.md (G4, G5, D2, D3, D4, D5, R6)
resource: https://github.com/aaif-goose/goose
---

# SE-443 — Gobierno de conectores MCP: malware de paquetes, secretos tipados, importación, política por herramienta y doctrina de diseño

## Problema

Savia consume y expone servidores MCP, y Savia Space va a conectar MCP de terceros (SE-429 S14c
dejó una plantilla desactivada). Hoy:

- Habilitar un MCP `npx`/`uvx` no comprueba si el paquete tiene un aviso de malware. SE-244 escanea
  vulnerabilidades de dependencias, no paquetes maliciosos. `docs/rules/domain/mcp-security.md` y
  `mcp-catalog-policy.md` no mencionan OSV ni avisos `MAL-*`.
- `mcp-security.md` exige secretos por referencia a variable de entorno, pero como regla de texto:
  nada valida en el alta que un secreto no acabe en `command`, `args` o `url` (visible en `ps`).
- Un MCP ya conectado se ejecuta con todas sus herramientas. SE-434 deja el MCP «fuera del sandbox»
  con acceso garantizado, y `agent-permission-levels.md` decide por agente, no por herramienta.
- Quien llega a Space con OpenCode o Claude Code ya configurado tiene que recrear a mano sus MCP.
- No existe una regla de diseño de herramientas MCP (búsqueda de «tool design» en
  `docs/rules/domain/`: sin resultados) y hay MCP propios en curso (savia-vaults, Space).

## Valor y evidencia

Tres proyectos públicos revisados (clones superficiales, sin ejecutar nada) convergen en el mismo patrón:

- **goose** (Apache-2.0): antes de lanzar una extensión `npx`/`uvx` extrae paquete y versión,
  consulta OSV y rechaza si hay `MAL-*` (`extension_malware_check.rs`); admite una allowlist remota
  de extensiones (`GOOSE_ALLOWLIST`). Su fallo ante red caída es abrir; aquí se cierra.
- **gentle-dot** (MIT): el motor solo ve `http://127.0.0.1/mcp/<id>` con una clave por arranque;
  un proxy oculta las herramientas que cambian cosas en modo solo lectura y exige
  `readOnlyHint: true` **y** estar en una lista curada para ejecutar sin preguntar; los secretos
  `${input:NAME}` solo pueden ir en entorno o cabeceras; importa en lectura las configs de otros
  clientes como borradores `needs_setup`; la config de conectores lleva un HMAC.
- **REA** (MIT): doctrina escrita de diseño de herramientas MCP (forma por pregunta, efectos
  declarados con veracidad, catálogo completo sin truncar esquemas, argumentos de prompts como datos
  no confiables).

No se ha podido contrastar cómo implementa Space hoy el alta de conectores: las slices S3–S5 se
verifican contra el código de `space-server` cuando exista (SE-428 sigue IMPLEMENTING).

## Alcance

| Slice | Entrega | Depende de |
|---|---|---|
| S1 | Doctrina `docs/rules/domain/mcp-tool-design.md` (≤150 líneas): forma, efectos declarados, catálogo completo, argumentos como datos no confiables, orden del catálogo sin significado. Lint de los esquemas servidos por savia-vaults MCP. | — |
| S2 | Comprobación de malware al habilitar: subcomando `--osv` de `scripts/mcp-security-audit.sh` (sin script nuevo). Solo se envían nombre y versión públicos del paquete (N1). Se invoca desde `/marketplace-install`, `/mcp-recommend` y el alta de conectores de Space, **nunca al arrancar** (el arranque no usa red). Deja recibo. | — |
| S3 | Secretos tipados: `${secret:NAME}` solo en `env` y `headers`; el alta rechaza ese marcador en `command`, `args` y `url`, y rechaza literales con forma de credencial. Extiende el principio 1 de `mcp-security.md`. | SE-429 S14c |
| S4 | Importación en solo lectura de las configs de OpenCode y Claude Code (sintaxis `${VAR}`, `${env:VAR}`, `{env:VAR}`). Cada entrada queda como borrador `needs_setup`, con nivel de datos desconocido, y pasa por S2 y S3 antes de activarse. Nunca se copia un secreto, solo la referencia. | S2, S3 |
| S5 | Política por herramienta en Space: tres estados por conector (oculto, preguntar, permitir) y regla «`readOnlyHint` **y** lista curada» para ejecutar sin preguntar. Allowlist firmada opcional para despliegues de equipo (fail-closed si la firma no valida). HMAC de la configuración de conectores, con apartado y aviso en el doctor. | SE-434, SE-446 |

## Fuera de alcance

- Typosquatting aún no marcado como `MAL-*` en OSV: se declara como límite, no se promete.
- Activar sin aprobación cualquier conector importado.
- Proxy MCP con ocultación por modo si SE-428 0.2 no lo permite: S5 queda como diseño con prueba de concepto.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `docs/rules/domain/mcp-tool-design.md` existe, ≤150 líneas, y `bats tests/test-mcp-tool-design.bats` valida con un cliente MCP de prueba que el catálogo de savia-vaults se sirve completo con esquemas válidos. |
| AC2 | Con una respuesta OSV simulada que incluye `MAL-2026-0001` para `evil-pkg@1.0.0`, `mcp-security-audit.sh --osv npx evil-pkg@1.0.0` sale con código 1 y nombra el aviso. Con `left-pad@1.3.0` sin avisos sale con 0. |
| AC3 | Con la red de OSV inaccesible, `--osv` sale con código 2 (`ASK`), nunca 0, y en modo mediado (SE-434) el alta no continúa sin confirmación de la persona. |
| AC4 | La petición a OSV contiene únicamente `{ecosystem, name, version}`; test que inspecciona el cuerpo capturado. |
| AC5 | El alta rechaza `{"command":"npx","args":["srv","--token","${secret:GH}"]}` y `{"url":"https://h/?k=${secret:GH}"}` y acepta `{"env":{"TOKEN":"${secret:GH}"}}`. |
| AC6 | La importación de un `opencode.json` de fixture con un token literal produce un borrador `needs_setup` sin el literal (el texto del token no aparece en ningún fichero escrito) y con nivel de datos desconocido. |
| AC7 | Una herramienta con `readOnlyHint: true` fuera de la lista curada pregunta; una dentro de la lista y sin la pista pregunta; solo cumplir las dos ejecuta sin preguntar. |
| AC8 | Una allowlist con firma inválida o sin ella hace que el alta falle cerrada con mensaje claro. |
| AC9 | Alterar a mano la configuración de conectores firmada hace que el arranque la aparte y que el doctor lo avise. |
| AC10 | `bash scripts/validate-ci-local.sh --quick` verde y `capability-entropy.py --check` PASS. |

AC3–AC9 que dependan de `space-server` se cierran contra su código real, no contra un doble: ese
es el sentido de SE-444.

## Riesgos

- Salida de red a `osv.dev` al habilitar: debe constar en el entorno de red de SE-434.
- `readOnlyHint` es declarativo y puede mentir: por eso la conjunción con la lista curada.
- La allowlist remota es un punto de ataque: firma obligatoria o descarga fijada por HTTPS.
- Las configs ajenas contienen secretos en claro: se leen para extraer referencias, no se copian.
- La clave del HMAC en Linux vive en el almacén de secretos y es legible por procesos del mismo
  usuario mientras está desbloqueado (límite que el propio gentle-dot admite). La garantía real solo
  existe junto al aislamiento de SE-434.

## Licencia de lo reutilizado

Solo patrones; no se copia código. goose es Apache-2.0, gentle-dot y REA son MIT. gentle-dot excluye
de la licencia sus marcas: no se usa ningún nombre ni asset suyo. Si más adelante se reutiliza código,
se conserva su LICENSE/NOTICE y se marcan los cambios. La API pública de OSV se consulta como servicio.

## Esfuerzo

S1 S, S2 S–M, S3 S, S4 S–M, S5 M. Total M–L repartido en slices independientes; S1 y S2 no esperan a Space.

## Decisiones pendientes de la operadora

- **D1**: ante red caída en el chequeo OSV, preguntar (propuesta) o bloquear siempre.
- **D2**: lista curada de herramientas de solo lectura: quién la mantiene y dónde vive (propuesta: versionada en el repo, revisada por PR).
- **D3**: allowlist de equipo: solo local firmada, o también remota por HTTPS fijado.

## Referencias cruzadas

SE-429 (interop MCP), SE-434 (sandbox, D-MED-4), SE-244 (vulnerabilidades, complementaria), SE-446
(canal de aprobación: S5 lo presupone seguro), SE-452 (suite de conformidad), SE-444 (autoridad del verificador).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/mcp-security-audit.sh --osv` | invocado desde `/marketplace-install` y `/mcp-recommend` | mismo script desde el plugin `savia-gates` y desde `space-server` |
| `docs/rules/domain/mcp-tool-design.md` | regla leída bajo demanda | idéntica (fichero común) |
| Alta de conectores (S3–S5) | no aplica | `space-server` |

### Verification protocol

- [ ] S1–S2 funcionan con ambos frontends (el script no depende del motor).
- [ ] Tests cubren ambos caminos de invocación (comando y alta de Space), o SKIP justificado en S3–S5 hasta que exista `space-server`.
- [ ] Si se añaden hooks, registrados en `savia-gates`.

### Portability classification

- [x] **DUAL_BINDING**: S1–S2 son bash común; S3–S5 viven en Space, que ya es independiente del frontend.
