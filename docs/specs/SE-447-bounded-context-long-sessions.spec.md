---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: E
risk: L2
related_specs: [SE-439, SE-432, SE-434, SE-270, SE-446]
origin: output/research/20261020-learnings-goose-gentledot-rea.md (D6, D7, G3)
resource: https://github.com/Gentleman-Programming/gentle-dot
---

# SE-447 — Contexto acotado en sesiones largas: una sola captura viva, tope absoluto de compactación y clasificación de acciones de riesgo

## Problema

1. **Capturas acumuladas.** SE-439 define permisos, vetos y recibos por captura de pantalla, pero no
   dice qué ocurre con las imágenes ya enviadas al modelo (búsqueda de «última captura» / «only the
   last»: sin resultados en las specs). Cada paso visual vuelve a pagar todas las anteriores, y una
   imagen es de las partes más caras del contexto.
2. **Compactación solo por porcentaje.** `docs/context-compaction-policy.md` dispara en 70 % (aviso),
   80 % (compactar) y 90 % (crítico) de la ventana. Con ventanas de un millón de tokens el 80 % son
   800 000 tokens: caro y con peor calidad. No hay tope absoluto por modelo.
3. **Acciones de riesgo dentro de una ventana ya permitida.** SE-439 (peldaño 4) exige permiso por
   sesión y ventana y define vetos; no clasifica qué acción concreta dentro de la ventana permitida es
   de riesgo (enviar, pagar, borrar, confirmar) ni exige que el agente declare su intención.

## Valor y evidencia

- gentle-dot (MIT): cada llamada al modelo lleva **solo la última captura**; las anteriores se
  sustituyen por una línea de registro. Las capturas se reducen a 1280 px de lado largo y JPEG calidad
  65, y las coordenadas son sobre la última captura (`docs/design.md` §4, «Computer control»). El
  efecto es medible en tokens.
- goose (Apache-2.0): el disparador de autocompactación es el mínimo entre un porcentaje de la
  ventana y un tope absoluto (225 000 tokens por defecto), recalculado por modelo, para no cruzar el
  escalón de precio de contexto largo del proveedor.
- gentle-dot clasifica el elemento destino antes de entregar una entrada: por rol y título de
  accesibilidad, por `Return` sobre el botón por defecto o por el `intent` declarado en la llamada, con
  léxico de enviar, pagar, comprar, borrar, confirmar, transferir y sus equivalentes en español.
  Añade límite de ritmo (10 acciones por segundo) y lista fija de aplicaciones vetadas.
- No hay medición propia todavía: S1 incluye medir antes de fijar valores.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | **Medición**: tokens de una sesión gráfica de referencia con todas las capturas frente a solo la última. Sin código de producto. Fija el valor de partida y la regla de aceptación. |
| S2 | En la herramienta de captura de Space: retirar del historial del motor las imágenes previas y dejar una línea «captura N: ventana, hash, nivel de datos»; el recibo sigue en el journal. Tamaño y calidad por defecto fijados (propuesta: 1280 px, JPEG 65). |
| S3 | `COMPACT_TOKEN_CAP` por **tier** de modelo en `scripts/context-compaction-policy.sh`: disparador = mínimo entre el porcentaje y el tope. Los topes viven en `~/.savia/preferences.yaml` bajo `tiers.<frontend>` (configuración local, nunca nombres de modelo en la fuente). Sin valor configurado, el comportamiento es el actual. |
| S4 | Clasificación de acciones de riesgo sobre el árbol de accesibilidad (peldaño 2 de SE-439), léxico es/en, `intent` obligatorio en cada llamada y registrado en el recibo. Capa adicional: nunca sustituye al permiso por ventana. |

## Fuera de alcance

- Cambiar el diseño del compositor de SE-439 o sus peldaños.
- Rotación automática de sesión con traspaso (se anota para una spec posterior si S1–S3 no bastan).
- Voz local y reconocimiento de voz: sin evidencia de necesidad en este repo.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | S1 publica `docs/evidence/SE-447-S1-captures.md` con tokens por sesión de referencia (con y sin retirada) y el método; sin cifras inventadas: si no se puede medir, lo dice. |
| AC2 | Test de S2: tras 5 capturas simuladas, la petición al motor contiene 1 imagen y 4 líneas de registro con ventana, hash y nivel; el journal conserva las 5 entradas. |
| AC3 | La captura más reciente respeta tamaño y calidad por defecto (un test comprueba lado largo ≤ 1280 y que no se recodifica por encima). |
| AC4 | `bats tests/test-context-compaction-cap.bats`: con ventana 1 000 000, porcentaje 80 y tope 225 000, el disparador es 225 000; con tope ausente es 800 000 (regresión); con ventana 200 000 y tope 225 000 es 160 000. |
| AC5 | Ningún nombre de modelo aparece en la fuente versionada (`grep` del patrón de nombres de modelo sobre los ficheros tocados: sin resultados). |
| AC6 | Test de S4: sobre un árbol de accesibilidad de fixture, un botón «Enviar» y otro «Send» se clasifican de riesgo; «Cancelar» no; una llamada sin `intent` se rechaza; el `intent` aparece en el recibo. |
| AC7 | `capability-entropy.py --check` PASS y `validate-ci-local.sh --quick` verde. |

## Riesgos

- El modelo pierde memoria visual de pasos anteriores. Mitigación: la línea de registro y una
  descripción textual de cada paso; S1 mide si degrada la tarea antes de adoptar.
- El tope depende de precios de proveedor que cambian: es configuración local, no constante.
- La clasificación por texto es heurística y tiene falsos negativos con etiquetas ambiguas. Es una
  capa extra, no el control principal.
- S2 y S4 dependen de que SE-439 pase de F0: hasta entonces solo S1 y S3 son ejecutables.

## Licencia de lo reutilizado

Solo patrones; sin copia de código. gentle-dot es MIT y goose Apache-2.0. Ningún asset ni nombre de
marca de terceros.

## Esfuerzo

S1 S, S2 S, S3 S, S4 S–M.

## Decisiones pendientes de la operadora

- **D1**: valor de partida de tamaño y calidad de captura, tras ver la medición de S1.
- **D2**: valor del tope absoluto por tier (se fija en local, la spec solo exige el mecanismo).
- **D3**: si S4 es obligatoria para agentes con modelo de nube o para todos los agentes.

## Referencias cruzadas

SE-439 (sesión gráfica, de la que S2 y S4 son delta), SE-432 (escritorio infinito), SE-434 (sandbox),
SE-270 (política de compactación original), SE-446 (canal de aprobación, ortogonal pero previo).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/context-compaction-policy.sh` (S3) | script bash común | mismo script |
| Herramienta de captura y clasificador (S2, S4) | no aplica | Space / `space-server` |

### Verification protocol

- [ ] S3 con ambos frontends (sin dependencia de motor).
- [ ] S2 y S4 con OpenCode como motor.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **DUAL_BINDING**: S3 es bash común; S2 y S4 pertenecen a Space, que no depende del frontend de Claude Code.
