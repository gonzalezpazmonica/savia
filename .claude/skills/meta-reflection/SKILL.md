---
layer: peripheral
name: meta-reflection
description: "Protocolo de las 4 meta-preguntas para cuestionar el encuadre de una tarea antes de ejecutarla. SPEC-194. Usar cuando criterion-simulation-judge activa con FRAME_DOUBT o FRAME_REJECT, o cuando el operador quiere reflexion manual antes de una decision de alto impacto."
allowed-tools: [Read, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: criterion-simulation-judge
  savia.maturity: beta
  savia.category: governance
  savia.context: workspace
  savia.context_cost: high
  savia.priority: high
  savia.summary: "Protocolo de meta-reflexion estructurado en 4 preguntas: Q1 encuadre vs problema real, Q2 precedentes historicos, Q3 estado del operador, Q4 reformulacion alternativa. Produce reafirmacion o reformulacion consciente. No es criterio real: heuristica de pausa declarada como tal."
  savia.tags: "meta-reflection, criterion-simulation, spec-194, frame, governance"
  savia.trigger_keywords: "frame challenge, meta-reflexion, criterion-simulation, FRAME_DOUBT, FRAME_REJECT"
  savia.user-invocable: True
---

# Skill: meta-reflection

> Protocolo para las 4 preguntas meta-reflexivas del Criterion Simulation Layer.
> Ver SPEC-194 y DOMAIN.md para contexto conceptual.

## Cuando cargar

Auto-load cuando:
- Hook criterion-simulation-challenge.sh emite FRAME_DOUBT o FRAME_REJECT.
- Operador quiere reflexion manual antes de aprobar una spec de alto impacto.
- Tarea tiene etiquetas de impacto alto (seguridad, produccion, seguridad humana).

Manual: /skill load meta-reflection

## Declaracion obligatoria

Esta capa NO es criterio real. Es una simulacion heuristica de pausa.
El operador siempre decide. La capa solo interpela.

Frase invariante que debe aparecer en todo output del judge:
"soy simulacion de meta-reflexion, no tu criterio. Tu decides."

## Protocolo — Las 4 meta-preguntas

### Q1: Verificacion de encuadre

Pregunta: La solucion propuesta responde al problema real, o a uno parecido pero distinto?

Instruccion operativa:
1. Leer el problem_statement original de la tarea.
2. Leer el proposed_solution (spec, PR, plan).
3. Comparar: la solucion propuesta resuelve el problema, o solo responde a el?
   - "Deberiamos hacer X?" vs "Como hacemos X?" son preguntas distintas.
   - Falla tipica: spec resuelve "como implementar cache" cuando el problema
     real es "por que hay latencia alta".
4. Buscar evidencia textual de divergencia: citar frases especificas.

Resultado: {passed: bool, reasoning: str con evidencia}

### Q2: Precedentes historicos

Pregunta: Hay tareas similares que fracasaron por encuadre (no por ejecucion) en los ultimos 90 dias?

Instruccion operativa:
1. Ejecutar `python3 scripts/criterion-simulation/historical-priors.py --task-json '{"tags": [...]}'`
   (o stdin): hasta 10 filas `FRAME_DOUBT`/`FRAME_REJECT` de la tabla `frame_reaffirmations`
   del KG (`SAVIA_KG_DB`, `.savia-kg/graph.db`; esquema de `scripts/kg-schema-migrate-cs.py`)
   en la ventana `--lookback` (90), con etiquetas por subcadena literal (`ai` casa con `maintenance`).
   Sin tags ni flags no hay similitud: `count: 0`. `source` dice por que: absent, no_table, no_tags,
   ok o unreadable (exit 0 siempre). Hoy ningun script escribe esa tabla: sin poblarla, Q2 no tiene senal.
2. Si hay 2 o mas reversiones con etiquetas similares en 90 dias (trigger-evaluator suma +20):
   - Citar los IDs y resumir por que se revirtieron.
   - Evaluar si el encuadre actual repite el patron.
3. Si no hay precedentes: passed=true.

Resultado: {passed: bool, reasoning: str, cited_priors: [str]}

### Q3: Estado del operador

Pregunta: El estado del operador (fatiga, presion, hora, tasa de confirmacion) aumenta el riesgo de criterio relajado?

Instruccion operativa:
1. Obtener operator_state con `python3 scripts/criterion-simulation/operator-state-signals.py`
   (solo datos locales, sin red). Salida: `{fatigue_score, pressure_score, override_rate, time_band}`.
2. Senales de alerta y como se calculan:
   - fatigue_score toma solo 0, 15 o 30. 30 (`atypical`) dentro de la franja
     `SAVIA_CS_FATIGUE_HOUR_BAND` (22:00-06:00, inclusiva por hora); 15 (`transition`)
     a 2 horas o menos de un borde, contando a traves de medianoche. Alerta: 30.
   - override_rate (0-20) = reaffirm / (reaffirm + reframe) en los ultimos 90 dias del
     log de reaffirmation-log.py (`SAVIA_CS_REAFFIRMATION_LOG`). Mide cuantas veces se
     mantuvo el encuadre interpelado en vez de reformularlo. Alerta: >= 15.
   - pressure_score (0-20) = `deadline_proximity` (0.0-1.0, clave exacta) de `~/.savia/preferences.yaml`
     x 20; admite coma decimal ("0,8") y comentario final; nan/inf valen 0. Alerta: >= 15.
3. Si hay senales: NO juzgar al operador. Nombrar la senal sin dramatizar.
4. Proponer mitigacion: "revisar manana", "consultar a un par", "dormir y releer".

Resultado: {passed: bool, reasoning: str, mitigation: str}

### Q4: Reformulacion alternativa

Pregunta: Existe una formulacion mas simple del problema que resolveria el caso critico con menos cambio?

Instruccion operativa:
1. Leer el problem_statement buscando el caso critico (el 20% que genera el 80% del valor).
2. Proponer en 1-2 frases una formulacion alternativa mas acotada si existe.
3. Evaluar si esa alternativa resolveria el caso critico con menos riesgo.
4. Si no hay alternativa razonable: proposed_reframe=null, would_solve=false.

Resultado: {proposed_reframe: str|null, would_solve: bool}

## Protocolo de replacement

Si el veredicto es FRAME_DOUBT o FRAME_REJECT, el operador tiene dos opciones:

Opcion A — Reafirmar el encuadre conscientemente:
```
python3 scripts/criterion-simulation/reaffirmation-log.py reaffirm \
  --task TASK_ID \
  --reason "razon de minimo 20 caracteres que demuestre reflexion real"
```

Opcion B — Reformular el problema:
```
python3 scripts/criterion-simulation/reaffirmation-log.py reframe \
  --task TASK_ID \
  --new-statement "nuevo problem statement"
```

La razon en reaffirm debe tener >= 20 caracteres sin contar el relleno (se recortan
los extremos y los blancos repetidos cuentan como uno). `--task` no puede estar vacio.
Cualquier rechazo sale con exit 2 sin escribir; sin subcomando, exit 1. Este requisito
NO es burocracia: es la friccion minima para que la confirmacion sea consciente y no refleja.

## Activacion (trigger-evaluator)

`python3 scripts/criterion-simulation/trigger-evaluator.py --task-json '{...}'` suma: production
+25, security +30, human_safety +50, estimated_hours > 16 +15, fatigue x 0.3, pressure x 0.2,
override_rate x 0.2 y +20 con >= 2 priors (tope 100). Activa con score >= `SAVIA_CS_TRIGGER_THRESHOLD`
(50). JSON invalido o no objeto: exit 1 con `activate: false`. Si una senal no carga o el KG es
ilegible, vale 0, avisa en stderr y queda en `signals_degraded`, que el hook (opt-in,
`SAVIA_CRITERION_SIMULATION=on`, nunca bloquea) guarda en events.jsonl con `priors_source`.

## Limitaciones declaradas

1. Q1 puede tener falsos positivos en tareas bien planteadas. El operador lo sabe.
2. Q2 depende de la calidad del KG; hoy la tabla no se alimenta sola y sin historial no hay senal.
3. Q3 hora != fatiga real. Hora 23:00 no prueba cansancio. Es un proxy.
4. Q4 puede proponer simplificaciones que ignoran contexto importante.
5. La confianza del judge NO es certeza. Es convergencia de senales heuristicas.

Ver DOMAIN.md para la diferencia conceptual entre evaluacion y reflexion.
