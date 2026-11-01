---
status: PROPOSED
priority: P1
developer_type: agent-team
created: 2026-11-01
author: Savia
phase: A
risk: L2
depends_on: []
related_specs: [SE-490, SPEC-107, SPEC-194, SE-376]
origin: "Auditoría de inferencias de estado en Savia (2026-10-30), hecha a raíz de la tesis externa «Al otro lado del cansancio» y de su verificación de evidencia. Informes en el vault privado de investigación. La auditoría encontró 15 piezas: 9 contrarias, 3 compatibles y 3 neutras."
timeline:
  - from: "2026-11-01"
    learned: "2026-11-01"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-492 — Estado declarado, no inferido: sustituir las 9 inferencias de estado de la persona por declaraciones y por la demanda del sistema

## Problema

Savia atribuye estados a la persona que la usa (fatiga, carga cognitiva, «criterio relajado», riesgo de burnout) a partir de señales que esa persona no ha declarado: la hora del reloj, la duración de la sesión, la velocidad a la que el agente edita o las métricas del sprint. En dos casos, además, expone ese estado a terceros.

La auditoría de 2026-10-30 revisó 15 piezas del repo y clasificó **9 como CONTRARIAS** al criterio «la persona declara su estado, Savia no lo infiere». Las 9 siguen en `main` hoy (comprobado el 2026-11-01):

| # | Pieza | Qué infiere | De qué señal | Quién lo ve |
|---|---|---|---|---|
| A1 | `scripts/criterion-simulation/operator-state-signals.py` (`_compute_fatigue_score`) | `fatigue_score` 0–30 y `time_band` «atypical» | Hora del sistema frente a una franja fija `22:00-06:00` (`SAVIA_CS_FATIGUE_HOUR_BAND`), que la persona no ha declarado | Juez LLM, log `output/criterion-simulation/events.jsonl`, banner |
| A2 | mismo fichero (`override_rate`) | `override_rate` 0–20, «criterio relajado» | Proporción de veces que la persona mantuvo su decisión frente a la objeción (90 días) | Igual que A1 |
| A4 | `scripts/criterion-simulation/trigger-evaluator.py` (pesos `fatigue*0.3`, `override*0.2`), `.opencode/agents/criterion-simulation-judge.md`, `.claude/hooks/criterion-simulation-challenge.sh` | Activa la objeción y pide al juez evaluar el «riesgo de criterio relajado» por fatiga u hora | Suma ponderada de A1, A2 y A3 | Juez LLM; banner «operator-state signals are elevated» |
| A5 | `scripts/cognitive-debt-monitor.py` | `cognitive_load_score` 0–100 y `risk_level` hasta «critical» | Horas de sesión, ratio de verificación, tareas por hora, `hour_of_day > 20` («fatigue amplifier») | Quien lo ejecute; en «critical» recomienda revisión humana obligatoria |
| A6 | `.claude/hooks/cognitive-debt-telemetry.sh` + registro en `.claude/settings.json` + `scripts/cognitive-debt.sh` | «Fast-accept ratio, proxy for skip-verification» | Marca temporal y duración de cada Edit/Write/Task. Esas llamadas las hace el agente, pero se atribuyen a `$USER` | Log local `~/.savia/cognitive-load/<user>.jsonl`; `/cognitive-status` |
| A10 | `.claude/skills/wellbeing-guardian/SKILL.md`, `docs/rules/domain/wellbeing-config.md`, `.claude/commands/wellbeing-guardian.md` | `break_compliance_score` individual | Pausas tomadas frente a pausas «esperadas» | Se exporta a `burnout-radar` como señal individual del mapa del **equipo** |
| A11 | `.claude/commands/burnout-radar.md` | Score de riesgo de burnout 0–100 **por miembro**, mapa de calor, opción `--individual nombre` | Horas extra, sprints fallidos, WIP, repriorizaciones, caída de velocity individual, participación en retros | Quien lo ejecute, normalmente un rol de gestión |
| A12 | `.claude/commands/sustainable-pace.md` | «Wellbeing Factor = índice de burnout» | Hereda A10 y A11 | Equipo y dashboard |
| A15 | `.claude/skills/meta-reflection/SKILL.md` (Q3) | «¿El estado del operador (fatiga, presión, hora, tasa de confirmación) aumenta el riesgo de criterio relajado?»; propone «dormir y releer» | Consume A1, A2 y A3 | El modelo que reflexiona y la persona |

Hay tres hechos agravantes:

- **A6 contradice su propio comentario.** El hook dice que está «dormido salvo `enable`», pero está registrado en el `settings.json` versionado y no tiene interruptor propio. Registra en cualquier instalación que use ese fichero.
- **A11 cumple las dos condiciones a la vez:** es un «score de burnout» y además es un perfil individual que ven los superiores.
- **El umbral horario de A1 y A5 es universal.** Una persona con turno de noche o en otra zona horaria queda marcada como «fatigada» en su jornada normal. No es multioperador.

### Por qué importa

- **Evidencia.** La verificación de la tesis desaconseja expresamente cualquier inferencia de fatiga, emoción o salud a partir de actividad, teclado, voz o cámara. Tampoco hay evidencia que apoye un «score de burnout» autogenerado.
- **Marco legal.** El art. 5.1.f del AI Act **no aplica literalmente**: ninguna pieza usa biometría. Lo que sí hacen es perfilar a trabajadores, que el RGPD somete a finalidad y minimización, y al art. 22 si condiciona decisiones. Esta spec no afirma un incumplimiento legal. Afirma que el diseño contradice el principio de Savia de que la autoridad es de la persona.
- **Calidad.** Atribuir a la persona la velocidad del agente (A6) o su desacuerdo con una objeción (A2) mide al sistema y culpa a la persona.

## Qué decide esta spec

Principio: **Savia no atribuye a la persona ningún estado que ella no haya declarado, y nunca entrega a terceros datos de bienestar de una persona identificable.** En lugar de inferencias, se usan dos tipos de evidencia:

1. **Estado declarado.** Ventanas de trabajo (`work_hours_*`, `silence_weekends`, ya en el perfil, ver `wellbeing-config.md`), modo declarado (`/focus-mode`, que ya funciona así), límite de sesión declarado y capacidad declarada para el sprint. «Estás fuera de la ventana que declaraste» es un hecho sobre una declaración. «Estás fatigada» es una inferencia.
2. **Demanda del sistema.** Lo que Savia ha pedido a la persona: objeciones, banners, avisos y preguntas, cuántos fuera de su ventana declarada y cuántos le resultaron útiles según ella. Se vigila lo que el sistema pide, no lo que la persona aguanta. Es el mismo enfoque que el registro de demanda de SE-490, aplicado al workspace.

### Sustitución pieza por pieza

| # | Se retira | Se sustituye por |
|---|---|---|
| A1 | `fatigue_score`, `time_band`, `SAVIA_CS_FATIGUE_HOUR_BAND` | `declared_window`: `inside`, `outside` o `undeclared`, calculado con las ventanas del perfil activo y su zona horaria. Sin declaración devuelve `undeclared` y no aporta nada al disparador |
| A2 | `override_rate` como estado del operador | `objection_usefulness` en el registro de demanda: objeciones lanzadas y cuántas marcó la persona como útiles. Es una métrica del **sistema** y no entra en el disparador |
| A3 (arrastrada) | Nombre `pressure_score` | `declared_deadline_proximity`, sin cambio de valor: es un atributo del trabajo, no de la persona |
| A4 | Pesos de fatiga y override; la sección del juez sobre «estado del operador» | El disparador usa solo señales del trabajo (producción, seguridad, tamaño, reverts, plazo declarado) y `declared_window == outside` con su propio motivo `outside_declared_window`. El prompt del juez pregunta: «¿la persona ha declarado que no quiere decidir esto ahora, o estamos fuera de su ventana declarada?». Sin fatiga, sin hora atípica, sin tasa de confirmación |
| A5 | `cognitive_load_score`, `risk_level`, `fatigue amplifier` | Informe de demanda del sistema: recuentos por tipo, fuera de ventana declarada y utilidad marcada. Las horas de sesión solo aparecen si la persona ha declarado un límite |
| A6 | Registro del hook en el `settings.json` versionado; «fast-accept ratio» | `cognitive-debt.sh enable` escribe el hook en `.claude/settings.local.json` (gitignored), nunca en el versionado. Lo registrado describe al **agente**: tool, duración y si hubo verificación posterior. Se guarda sin `$USER`, bajo un identificador de instalación. `/cognitive-status` muestra el informe de demanda (A13 cae con A6) |
| A10 | Exportar `break_compliance_score` a `burnout-radar` | Las pausas solo las ve la persona, en su propio informe. No se exporta ningún agregado individual |
| A11 | Score por miembro, mapa de calor, `--individual` y la palabra «burnout» en la salida | `/work-conditions`: condiciones del trabajo **del equipo** (WIP frente al límite acordado, repriorizaciones a mitad de sprint, trabajo fuera de las ventanas declaradas, contado sin identificar personas). Mínimo de 3 personas por agregado; con menos, se niega con un mensaje explícito. Más la **capacidad declarada** por cada persona («esta semana puedo asumir X»), que solo ella escribe |
| A12 | «Wellbeing Factor» | Capacidad declarada del equipo y límites acordados |
| A15 | Q3 actual de meta-reflection | El mismo texto de A4: declaración y ventana. «Dormir y releer» solo como opción que la persona puede elegir, nunca como recomendación derivada de la hora |

`burnout-radar` se **renombra** a `work-conditions`, en el mismo fichero. No se deja alias: un alias mantiene la palabra y la superficie. Las referencias en docs y en otros comandos se actualizan en la misma PR.

### Multioperador

Cada instalación tiene una persona distinta. Ningún umbral horario, de duración o de ritmo es universal:

- Sin declaración no hay señal de estado. El sistema sigue funcionando solo con señales del trabajo.
- Las ventanas se interpretan en la zona horaria declarada en el perfil activo, no en la del sistema.
- Una ventana que cruza la medianoche (p. ej. `22:00`–`06:00`, turno de noche) es válida y se trata igual que una diurna.

## Criterios de aceptación

Todos los tests inyectan el reloj y el perfil: ninguno depende de la hora real de la máquina de CI.

- **AC-1 (A1, simetría horaria).** Con el mismo contexto de trabajo y **sin ventana declarada**, `trigger-evaluator.py` devuelve la misma puntuación y los mismos motivos a las 03:00 y a las 11:00. Test pytest. Sobre el código actual falla (las 03:00 añaden `atypical_hour` y 9 puntos).
- **AC-2 (A1, ventana declarada, multioperador).** Hay tres operadores sintéticos:
  - P1 con ventana `09:00`–`18:00` en `Europe/Madrid`;
  - P2 con turno de noche `22:00`–`06:00`;
  - P3 sin ventana.

  Resultados esperados:
  - A las 23:00 locales, P1 da `outside` con motivo `outside_declared_window`, P2 da `inside` sin motivo horario y P3 da `undeclared` sin motivo horario.
  - Caso límite: la hora exacta de fin de ventana (18:00 para P1) da `outside`, y la de inicio (09:00) da `inside`.
  - Caso negativo: una ventana mal formada (`25:00-06:00`) da `undeclared` y deja un aviso en stderr. No se inventa ninguna ventana por defecto.
- **AC-3 (A1, A2 y A4: ausencia estructural).** Un test BATS recorre `scripts/`, `.claude/hooks/`, `.claude/skills/`, `.claude/commands/` y `.opencode/agents/`. Falla si aparece alguno de estos términos: `fatigue_score`, `time_band`, `override_rate`, `SAVIA_CS_FATIGUE_HOUR_BAND`, `cognitive_load_score`, `fatigue amplifier`, `break_compliance_score` o `burnout_score`.
  - Lista de exclusión cerrada: `docs/propuestas/` (histórico) y la propia spec.
  - El test se comprueba contra `main` actual, donde debe fallar.
  - Además, un fixture con `fatigue_score` en un fichero temporal dentro del alcance demuestra que el test detecta el término.
- **AC-4 (A2).** `objection_usefulness` se calcula solo a partir de marcas explícitas de la persona (`useful` o `not_useful`). Una objeción sin marca cuenta como `unmarked`, nunca como «no útil». Test con un registro sintético de 10 objeciones: 3 útiles, 2 no útiles y 5 sin marca. Resultado esperado: `{useful:3, not_useful:2, unmarked:5}`. El valor no aparece en la entrada del disparador; el test lo comprueba inspeccionando el dict que recibe `evaluate`.
- **AC-5 (A4, juez y banner).** El prompt de `criterion-simulation-judge.md` no contiene «fatiga», «fatigue», «hora atípica», «atypical» ni «criterio relajado» aplicado a la persona, y sí contiene la pregunta sobre la declaración y la ventana. El banner del hook ya no dice «operator-state signals are elevated». Con `outside_declared_window` dice que la acción ocurre fuera de la ventana declarada y cuál es esa ventana. Test BATS con entrada JSON por stdin, en ambos sentidos: dentro de la ventana no hay mención horaria; fuera, sí.
- **AC-6 (A5, informe de demanda).** `cognitive-debt-monitor.py` (o su sustituto, con el mismo nombre de comando) produce `demand_report` con recuentos por tipo (`objection`, `banner`, `nudge`, `question`), `outside_declared_window` y utilidad marcada. No contiene `score`, `risk_level` ni ningún campo sobre la persona.
  - Con un límite de sesión declarado, incluye `session_hours` y `over_declared_limit`. Sin límite, ninguno de los dos.
  - Caso negativo: una línea corrupta del registro se cuenta en `skipped_lines`. No hace fallar el informe ni se ignora en silencio.
- **AC-7 (A6, registro solo local).**
  - (a) `.claude/settings.json` versionado no contiene `cognitive-debt-telemetry`. Test BATS.
  - (b) `cognitive-debt.sh enable`, con `SAVIA_SETTINGS_OVERRIDE` apuntando a un directorio temporal, escribe el hook en `settings.local.json` y deja `settings.json` byte a byte igual. Se comprueba con hash antes y después.
  - (c) `disable` lo retira de `settings.local.json`.
  - (d) Sin `settings.local.json` previo, `enable` lo crea con JSON válido.
  - (e) Caso negativo: con un `settings.local.json` corrupto, `enable` sale con código distinto de 0 y no lo sobrescribe.
- **AC-8 (A6, sin atribución a la persona).** Una línea del registro de telemetría no contiene `$USER`, nombre ni correo, y no contiene el campo `fast_accept`. El fichero se llama por identificador de instalación. Test que ejecuta el hook con `USER=persona-prueba` y comprueba que esa cadena no aparece ni en el nombre ni en el contenido del fichero. `cognitive-debt.sh forget` sigue borrando el registro (test existente, se adapta a la nueva ruta).
- **AC-9 (A10).** Ni `wellbeing-guardian` (skill, comando y regla) ni `work-conditions` mencionan una exportación de datos de pausas. Ninguno de los dos lee el registro de pausas de otra persona. Test BATS de ausencia de `break_compliance` y de cualquier ruta de lectura cruzada entre los dos.
- **AC-10 (A11, condiciones del equipo).**
  - (a) `.claude/commands/burnout-radar.md` no existe y `.claude/commands/work-conditions.md` sí.
  - (b) `work-conditions` no acepta `--individual` y su salida definida no contiene columnas por persona, «burnout» ni «score».
  - (c) Define el mínimo de 3 personas por agregado y el mensaje de negativa por debajo.
  - (d) La capacidad declarada se lee de un campo que escribe la propia persona; ningún otro rol tiene una orden para escribirlo.
  - (e) No queda ninguna referencia a `burnout-radar` fuera de `docs/propuestas/` y `CHANGELOG*`.

  `work-conditions` es un comando de prompt, sin script. Por eso estos AC son estructurales (test BATS sobre el fichero), y la PR lo declara así: no hay test de comportamiento del modelo.
- **AC-11 (A12).** `sustainable-pace.md` no contiene «Wellbeing Factor» ni «burnout», y obtiene la capacidad del equipo de las declaraciones de AC-10(d). Test BATS.
- **AC-12 (A15).** La Q3 de `meta-reflection/SKILL.md` coincide con el texto fijado en A4. `tests/test-meta-reflection.bats` se actualiza: deja de esperar «fatiga» y pasa a esperar «ventana declarada». Debe fallar sobre el texto actual.
- **AC-13 (sin regresión del resto de la capa).** Siguen en verde los tests existentes de criterion-simulation y cognitive-debt que no tratan de las señales retiradas:
  - `tests/scripts/test_criterion_simulation_trigger.py`;
  - `tests/test-criterion-simulation-hook.bats`;
  - `tests/scripts/test_cognitive_debt.py`;
  - `tests/bats/test-cognitive-debt.bats`;
  - `tests/structure/test-cognitive-debt-phase-1.bats`;
  - `scripts/test-wellbeing-guardian.sh`.

  Los casos que afirmaban la inferencia retirada se **sustituyen** por los de AC-1 a AC-12 y la PR los lista uno a uno. No se borra ninguna aserción sin sustituirla.
- **AC-14 (paridad de frontends).** La misma entrada JSON por stdin al hook de objeción produce la misma decisión invocada desde la ruta de Claude Code y desde el plugin de OpenCode, o se marca SKIP con el motivo si el plugin no enruta ese hook. Test BATS.
- **AC-15 (documentación coherente).** `docs/cognitive-debt-guide.md`, `docs/rules/domain/cognitive-debt-protocol.md`, `docs/rules/domain/criterion-simulation-honesty.md` y `docs/rules/domain/wellbeing-config.md` describen el estado declarado y la demanda del sistema, y no prometen inferencias que ya no existen. Las specs históricas SPEC-107 y SPEC-194 no se reescriben; reciben una nota «sustituido en parte por SE-492».

## Fuera de alcance

- **Las 3 piezas COMPATIBLES y las 3 NEUTRAS.** A3 solo se renombra, porque A4 lo arrastra. A13 cae con A6. A7 (aviso de sesión con 4 h por defecto) y A9 (nudges de pausa) quedan para otra spec: no infieren estado, aunque A7 tiene un umbral universal.
- Barrer inferencias con otros nombres en `projects/` o en los agentes de reuniones. La auditoría no los cubrió; queda como deuda declarada.
- Medir si alguien usa estas piezas en la práctica.
- Cambios en Soul Continuidad (SE-490): ya nace con estado declarado y registro de demanda.
- Instrumentos de bienestar (REQ, NASA-TLX, WHO-5). Esta spec retira inferencias; no añade mediciones.

## Riesgo y rollback

- **Riesgo L2.** Toca hooks opt-in y comandos de prompt; no toca gates de autoridad.
- **Pérdida de función:** la capa de objeción deja de dispararse por la hora en instalaciones sin ventana declarada. Es intencionado y se dice en el CHANGELOG.
- **Registros existentes:** `~/.savia/cognitive-load/<user>.jsonl` queda donde está. El fragmento de CHANGELOG explica cómo borrarlo con `cognitive-debt.sh forget`. No se migra: contiene la atribución que se retira.
- **Rollback:** revertir la PR. No hay migración de datos.

## Plan

| Slice | Contenido | AC |
|---|---|---|
| 1 | Señales: `declared_window`, retirada de fatiga y override, disparador, juez, banner, meta-reflection | AC-1 a AC-5, AC-12, AC-14 |
| 2 | Cognitive-debt: informe de demanda y registro solo local, sin atribución | AC-6 a AC-8 |
| 3 | Comandos de equipo: `work-conditions`, `sustainable-pace`, `wellbeing-guardian` | AC-9 a AC-11 |
| 4 | Test de ausencia estructural, documentación y notas en SPEC-107 y SPEC-194 | AC-3, AC-13, AC-15 |

Cada slice es una PR Draft independiente desde `main`, sin PRs apiladas. El slice 4 se abre cuando los tres anteriores estén fusionados, porque su test de ausencia los verifica a todos.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `criterion-simulation-challenge.sh` | `.claude/hooks/`, registrado en `settings.json` | hoy **no** lo enruta ningún plugin de `.opencode/plugins/` (comprobado el 2026-11-01). Esta spec no lo porta: AC-14 queda en SKIP con ese motivo hasta que exista el port |
| `cognitive-debt-telemetry.sh` | solo en `.claude/settings.local.json` tras `enable` | no se registra en el plugin; `cognitive-debt.sh status` lo dice explícitamente |
| `criterion-simulation-judge` | `.opencode/agents/criterion-simulation-judge.md` | el mismo fichero vía AGENTS.md |
| `work-conditions`, `sustainable-pace`, `wellbeing-guardian` | `.claude/commands/` | `.opencode/commands` (enlace al mismo directorio) |
| `meta-reflection` | `.claude/skills/meta-reflection/SKILL.md` | registro de skills, mismo fichero |
| Scripts Python | `scripts/criterion-simulation/`, `scripts/cognitive-debt-monitor.py` | los mismos, sin binding |

### Verification protocol

- [ ] AC-14: la misma decisión del hook de objeción en ambos frontends, o SKIP justificado.
- [ ] Los tests de AC-1 a AC-12 no dependen del frontend: son scripts y ficheros.
- [ ] Ningún hook nuevo. El de telemetría deja de estar registrado en el fichero versionado.

### Portability classification

- [x] **DUAL_BINDING**: la lógica está en scripts Python y bash, y en ficheros de comando, skill y agente que comparten ambos frontends. Salvedad: el hook de objeción solo existe hoy en Claude Code. Es opt-in (`SAVIA_CRITERION_SIMULATION=off` por defecto) y esta spec no cambia esa asimetría; la deja declarada en AC-14.
