# Plantillas

## A. Ficha de harness (JSON)

Una ficha por harness hijo (solo si se usa metaharness, experimental). Los costes se rellenan con mediciones; sin medida, `null`.

```json
{
  "id": "revisora-lectura",
  "descripcion": "Revisa un diff en solo lectura y emite un veredicto con formato fijo",
  "capacidades": ["revision-correccion"],
  "gobierno": "solo-lectura",
  "invocacion": {
    "cwd": "<carpeta de trabajo>",
    "modelo": "<modelo>",
    "herramientas": ["Read", "Grep", "Glob"],
    "timeout_s": 600
  },
  "coste": {"arranque_tokens": null, "medido": "<tarea, segundos, coste>"},
  "evidencia": "<fichero de salida y postcondición que lo acredita>",
  "puntos_fuertes": "<donde ganó, con la medida>",
  "puntos_debiles": "<donde perdió, con la medida>"
}
```

Gobiernos válidos: `contrato` (autoridad dada por un contrato aprobado por la persona), `solo-lectura`, `propio`. Nunca un modo sin permisos.

## B. Encargo autocontenido a un hijo

```
Objetivo: <una frase>
Contexto mínimo: <rutas a leer; lo que NO hay que asumir>
Herramientas permitidas: <lista>
Límites: <ficheros que puede escribir; tiempo; turnos; presupuesto>
Salida: <ruta del informe>. Primera línea: <formato del veredicto>.
Éxito: <comando o comprobación que lo demuestra>
OBLIGATORIO al terminar, aunque falles: escribir el informe y la marca de fin.
Cierra con 1-3 líneas.
```

## C. Plan de sprint

```
Sprint: <id>   Ventana: <inicio>-<fin>   Autoridad: <grant o contrato; caducidad>
Presupuesto: <dinero/tokens>
Agentes simultáneos máx.: <n>  (política de: <cuenta | máquina | orden expresa>)
Disco/RAM: <límites>
Parada: <fichero de parada; n fallos seguidos; presupuesto agotado>

| Unidad | Ámbito (ficheros) | Depende de | Modelo | Éxito verificable | Reintentos máx. | Estado |
|---|---|---|---|---|---|---|

Reglas del sprint:
1. Una rama y un PR por unidad, en borrador.
2. Revisor distinto del autor, con veredicto en la primera línea.
3. Vigilantes con lista de vistos. En cada despertar, agentes esperados frente a vivos.
4. Decisiones pendientes en lote, al final del turno, con todo lo demás despachado.
5. Merges solo con grant vigente para el manifiesto exacto.
6. Informe final: qué se hizo, qué falló, coste, qué queda.
```

## D. Fichero de progreso (flujo largo)

```
# Progreso
Objetivo: <...>
Última actualización: <fecha>
Hecho: <lista con commit/PR>
En curso: <unidad, rama, último paso>
Siguiente: <un solo paso concreto>
Bloqueos: <...>
Cómo comprobar el estado: <comando>
Decisiones tomadas (no reabrir): <...>
```

Al reanudar: leer este fichero, el historial git y la lista de tareas; ejecutar la comprobación básica; solo entonces seguir.
