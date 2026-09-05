---
layer: peripheral
name: meta-reflection
description: "Protocolo de las 4 meta-preguntas para cuestionar el encuadre de una tarea antes de ejecutarla. SPEC-194. Usar cuando criterion-simulation-judge activa con FRAME_DOUBT o FRAME_REJECT, o cuando el operador quiere reflexion manual antes de una decision de alto impacto."
allowed-tools: [Read, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: criterion-simulation-judge
  savia.maturity: stable
  savia.category: governance
  savia.context: workspace
  savia.context_cost: high
  savia.maturity: experimental
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
1. Consultar scripts/criterion-simulation/historical-priors.py o el KG.
2. Si hay 2 o mas reversiones con etiquetas similares en 90 dias:
   - Citar los IDs y resumir por que se revirtieron.
   - Evaluar si el encuadre actual repite el patron.
3. Si no hay precedentes: passed=true.

Resultado: {passed: bool, reasoning: str, cited_priors: [str]}

### Q3: Estado del operador

Pregunta: El estado del operador (fatiga, presion, hora, tasa de confirmacion) aumenta el riesgo de criterio relajado?

Instruccion operativa:
1. Obtener operator_state de scripts/criterion-simulation/operator-state-signals.py.
2. Senales de alerta:
   - fatigue_score >= 20 (hora atipica: 22:00-06:00)
   - override_rate >= 15 (alta tasa de confirmaciones sin reflexion)
   - pressure_score >= 15 (fecha limite cercana)
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

La razon en reaffirm debe tener >= 20 caracteres. Este requisito NO es burocracia:
es la friccion minima para que la confirmacion sea consciente y no refleja.

## Limitaciones declaradas

1. Q1 puede tener falsos positivos en tareas bien planteadas. El operador lo sabe.
2. Q2 depende de la calidad del KG. Sin historial, no hay senales.
3. Q3 hora != fatiga real. Hora 23:00 no prueba cansancio. Es un proxy.
4. Q4 puede proponer simplificaciones que ignoran contexto importante.
5. La confianza del judge NO es certeza. Es convergencia de senales heuristicas.

Ver DOMAIN.md para la diferencia conceptual entre evaluacion y reflexion.
