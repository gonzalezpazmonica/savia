---
name: guided-work
description: Trabajo guiado — Savia te acompaña paso a paso con preguntas, adaptando el ritmo a tus necesidades
model_tier: mid
context_cost: medium
allowed_tools: ["Read", "Write", "Edit", "Bash", "Task"]
tier: core
---

# /guided-work [opciones]

Savia se convierte en tu acompañante de trabajo. En vez de darte toda la información de golpe, te guía paso a paso con preguntas claras. Tú marcas el ritmo.

## Parámetros

- `--task {PBI-id|spec|descripción}` — La tarea a guiar
- `--level {alto|medio|bajo}` — Nivel de guía (por defecto: del perfil de accesibilidad)
- `--continue` — Retomar donde lo dejaste la última vez
- `--status` — Ver en qué paso estás y qué falta
- `--pause` — Guardar progreso y sugerir pausa

## Protocolo de trabajo guiado

### Paso 0 — Preparación (invisible al usuario)

1. Cargar perfil de accesibilidad: `.claude/profiles/users/{slug}/accessibility.md`
2. Cargar la tarea: spec SDD, PBI, o descripción libre
3. Descomponer en micro-pasos: cada uno debe ser una acción concreta de 3-5 minutos con un criterio claro de "hecho"
4. Guardar plan de pasos en memoria para recuperar con `--continue`

### Paso 1 — Inicio

Presenta la tarea con contexto mínimo y pregunta si está listo:

**Nivel alto** (máximo 3 líneas):
> "Hola. Vamos a trabajar en: [título de la tarea]. Son [N] pasos. ¿Empezamos?"

**Nivel medio** (5-7 líneas):
> "Vamos a trabajar en [título]. El objetivo es [resumen]. Lo he dividido en [N] pasos: [lista breve]. ¿Por cuál empezamos?"

**Nivel bajo** (checklist completo):
> Muestra todos los pasos como checklist. El usuario marca según avanza.

### Paso 2..N — Ejecución guiada

Para cada micro-paso, seguir el protocolo de la regla `guided-work-protocol.md`:

1. **Presentar**: una acción concreta con pregunta
2. **Esperar**: no avanzar hasta que el usuario responda
3. **Ejecutar**: si el usuario dice sí, ejecutar la acción (o guiarle para que la haga)
4. **Confirmar**: "Hecho. [Resultado breve]. Paso [X] de [N]. ¿Siguiente?"
5. **Adaptar**: si dice "no sé" o se atasca → reformular más simple, ofrecer alternativa, o sugerir pausa

### Detección de bloqueo

Si el usuario:
- Responde "no sé", "no entiendo", "estoy perdido" → Reformular el paso con más detalle y un ejemplo concreto
- No responde en mucho tiempo → "¿Sigues ahí? Si necesitas un descanso, dime 'pausa'"
- Cambia de tema → "Estabas trabajando en [tarea], paso [X]. ¿Volvemos o prefieres dejarlo?"
- Dice "no puedo" → "Está bien. ¿Quieres que lo haga yo, que lo intentemos de otra forma, o que pasemos al siguiente?"

### Pausas y bienestar

- Si `break_strategy` está configurado, sugerir pausa al cumplir el intervalo
- Al pausar: "Buen momento para un descanso. Llevas [X] pasos de [N]. Cuando vuelvas, dime `/guided-work --continue`."
- Guardar punto exacto en memoria para retomar

### Celebración calibrada

- Tras cada paso: "Hecho. Paso [X/N]." (breve, no condescendiente)
- Al completar todo: "Has completado [tarea]. [Resumen de lo logrado]. Buen trabajo."
- NUNCA emojis excesivos, NUNCA infantilizar

## Ejemplo de interacción (nivel alto)

```
Savia: Vamos a implementar el endpoint POST /patients. Son 5 pasos. ¿Empezamos?
User: Sí
Savia: Paso 1: Crear el fichero PatientController.cs en src/Controllers/. ¿Lo creo?
User: Sí
Savia: Creado. Paso 1/5 hecho. Paso 2: Añadir el método Create con los parámetros de la spec. ¿Vamos?
User: No entiendo qué parámetros
Savia: La spec dice que el endpoint recibe: name (string), birthDate (date), allergies (string[]). ¿Añado el método con esos parámetros?
User: Sí
Savia: Añadido. Paso 2/5 hecho. ¿Seguimos con el paso 3?
```

## Output Template

```yaml
resultado:
  tarea: "{id o título}"
  pasos_totales: N
  paso_actual: X
  estado: "en_progreso|pausado|completado"
  siguiente_accion: "descripción del siguiente paso"
```

## Restricciones

- NUNCA generar más de 5 líneas por turno en nivel alto, 8 en medio
- NUNCA avanzar sin respuesta del usuario
- NUNCA juzgar la velocidad o el número de intentos
- Si el usuario pide hacer algo diferente, respetar y adaptar
- La guía es temporal: si el usuario demuestra confianza, sugerir reducir nivel
