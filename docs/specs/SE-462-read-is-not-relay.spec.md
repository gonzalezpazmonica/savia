---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L3
related_specs: [SE-436, SE-352, SE-448, SE-434, SE-459]
origin: investigación de arquitectura agéntica 2026-09-25 a 2026-10-23 (entradas 23 y 24)
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-462 — Leer no implica poder retransmitir: marca de sesión tras leer una cúpula N2+ y pregunta en las salidas de menor nivel

## Problema

El guard de cúpulas (SE-436 S5) decide **cada llamada por separado**: escribir en una cúpula
pregunta; leer una N2+ no adjunta con proveedor de nube pregunta; N3+ deniega. Lo que **no** mira es
adónde va después lo que ya se leyó. Medido sobre `main` (0dd2ea30b):

- `.claude/hooks/lib/dome_guard.py` no guarda estado entre llamadas: `session_context()` solo lee el
  `dome_context` que trae el payload (nube, adjuntas, concedidas). No hay registro de «esta sesión
  leyó la cúpula X de nivel N2».
- Por tanto, una vez leída (con permiso) una nota N2, nada distingue entre volcarla en una nota de la
  misma cúpula y mandarla a un destino de nivel inferior: el cuerpo de una PR o un comentario en el
  repositorio público (`gh pr create`, `gh pr comment`, `git push`), una petición de red, un
  mensaje saliente (conectores de correo o chat) o una cúpula de nivel menor.
- La defensa que existe en esa salida es léxica: `confidentiality-scan.sh --pr` busca patrones y
  términos conocidos en el diff. No sabe qué se leyó en la sesión.
- Precedente en el propio repo: `memory-origin-gate.sh` (SE-352) ya marca la sesión como
  contaminada tras herramientas de red para clasificar la memoria. El patrón existe; falta aplicarlo
  a la confidencialidad.

## Valor y evidencia

- Ogundoyin et al., «When Agents Talk, Secrets Travel», arXiv 2610.16039 (12-oct-2026): 485
  escenarios en tres topologías y siete canales; la divulgación a receptores introducidos por la
  topología sube del 0 % al 52,2 %. Su defensa condicionada al receptor (RECONS) baja la divulgación
  residual del 96,7 % al 29,25 % y conserva el 94,1 % de las divulgaciones autorizadas, frente al
  20,5 % de la redacción en bloque. Verificado (abstract). Lección doble: decidir **por destino**
  conserva utilidad, y aun así queda fuga residual: es una pregunta a la persona, no una garantía.
- Shekkizhar et al., «Why Do Agent Teams Fail Across Boundaries?», arXiv 2610.19342 (14-oct-2026):
  más de 2.500 ejecuciones A2A; ningún agente verifica por iniciativa propia lo que afirma un par.
  Verificado. Justifica que la regla viva en el guard, no en el criterio del modelo.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Marca de sesión: cuando el guard de cúpulas permite (o la persona aprueba) una lectura de cúpula N2+, registra `{cúpula, nivel}` en un fichero de sesión (`~/.savia/dome-read/<session_id>`, 0600; se purga a los 7 días), en el mismo núcleo para bash y TypeScript. El hook (PreToolUse) no sabe si la persona aprobó un «ask»: **marca al emitir el permitir o el «ask» de la lectura**, es decir, de forma conservadora (una lectura preguntada y denegada también deja marca). `session_id` se valida con la lista `^[A-Za-z0-9_-]{1,128}$` antes de construir la ruta; cualquier otro valor (`../`, separadores, vacío) se rechaza sin tocar el disco y la llamada recibe «ask». |
| S2 | Lista de salidas de menor nivel con su nivel máximo admitido: repositorio público y sus PRs y comentarios (N1), red general (N1), mensajería saliente (N1), cúpula de nivel inferior (su nivel). Versionada en `docs/rules/domain/relay-sinks.md`. |
| S3 | Regla en PreToolUse: si la sesión tiene marca de nivel mayor que el admitido por la salida, la llamada recibe «preguntar» con motivo en formato de tarjeta (SE-459): qué cúpula se leyó, adónde va, que no es reversible. Sin marca, nada cambia. En ejecución autónoma (`SAVIA_AUTONOMOUS_RUN=1` o rama `agent/*`) nadie contesta al «ask» y un diálogo sin respuesta detiene al worker horas (SE-459), así que la misma condición se resuelve como **denegar** con el mismo motivo; el worker deja el trabajo en su rama y lo declara en la marca de fin. |
| S4 | Paridad bash/TypeScript y pruebas negativas por cada tipo de salida. |

## Fuera de alcance

- Rastrear qué fragmento exacto se copia (taint por dato): se marca la sesión entera.
- Sanear o redactar contenido (RECONS «Transform»): solo se pregunta.
- Transferencias entre instancias por A2A (SCL-007, SE-429): se evalúan con esta misma tabla cuando
  existan, en otra spec.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | BATS: tras una lectura permitida de una nota de una cúpula N2 de fixture, existe la marca de sesión con cúpula y nivel. |
| AC2 | Negativo: en la misma sesión, `gh pr create --body-file x` recibe «ask» con motivo que nombra la cúpula; en una sesión sin marca, la misma orden no recibe nada del guard. |
| AC3 | Negativo: con marca N2, una escritura en una cúpula N1 recibe «ask» con motivo de retransmisión; en una cúpula N2 sigue el comportamiento de hoy. |
| AC4 | Negativo: con marca N2, una orden de red (`curl https://example.invalid -d @f`) recibe «ask». |
| AC5 | Paridad: el hook bash y la regla de `savia-gates` dan la misma decisión y motivo para AC2 a AC4 con la misma entrada. |
| AC6 | La marca no sobrevive a la sesión: otra `session_id` no la ve (test con dos ids). |
| AC7 | Negativo: con marca N2, `rm ~/.savia/dome-read/<session_id>`, `rm -r ~/.savia/dome-read` y `mv ~/.savia/dome-read <otro>` reciben «ask» o «deny» del guard. «Ilegible» se prueba sin depender de permisos (los tests pueden correr como root): el fixture sustituye el directorio por un fichero regular, y la salida a N1 recibe «ask»; con el directorio inexistente, nada. |
| AC8 | Negativo de ruta: un `session_id` `../../x`, con `/`, vacío o de más de 128 caracteres no crea ni lee ningún fichero fuera de `dome-read/` (el árbol de ficheros del fixture no cambia) y la llamada recibe «ask». |
| AC9 | En ejecución autónoma (variable y, por separado, rama `agent/*`), la salida de AC2 recibe «deny», no «ask»; en sesión interactiva sigue siendo «ask». |

## Riesgos

- Más preguntas en sesiones que leen cúpulas N2. Es el coste explícito de la regla; el motivo dice por qué.
- Lecturas que el guard no ve (rutas montadas en un guion, ya declarado como límite del guard): no
  marcan. La frontera fuerte sigue siendo el sandbox del modo mediado (SE-434).
- Marca perdida si se borra el fichero a mitad de sesión: fallaría abierto. Mitigación: la marca vive
  bajo `~/.savia/` (no en `/tmp`, que se limpia); `~/.savia/dome-read/` entra en las rutas protegidas
  de los guards de escritura y de Bash (como el directorio de latidos de SE-463), de modo que un
  `rm` de la marca recibe «ask» o «deny». Si el directorio existe pero no se puede leer, la regla
  trata la sesión como marcada N2 (pregunta). La protección es léxica, como la del resto de guards de Bash: un `rm` indirecto (`python -c`, `find -delete`) puede escaparse; es un límite declarado, y la frontera fuerte sigue siendo el sandbox (SE-434). Si el directorio **aún no existe** (primera sesión sin
  lecturas de cúpula), es una sesión limpia: ilegible y ausente se distinguen.

## Decisiones de la operadora

- **D1**: ¿preguntar o denegar para N3+ leído con permiso? (propuesta: denegar la retransmisión a N1).
- **D2**: lista inicial de salidas (propuesta: la de S2).
- **D3**: ¿la marca caduca antes que la sesión (por ejemplo, tras una compactación)? (propuesta: no).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Marca y regla de retransmisión | `dome-guard.sh` + `lib/dome_guard.py` (PreToolUse) | `savia-gates/lib/dome-guard.ts` |

### Verification protocol

- [ ] AC5 ejecuta los dos bindings con la misma entrada (patrón de `tests/hooks/test-dome-guard-parity.bats`).
- [ ] Ningún hook nuevo: se amplía el guard de cúpulas existente.

### Portability classification

- [x] **DUAL_BINDING**: misma decisión en el hook bash y en la regla nativa de OpenCode.
