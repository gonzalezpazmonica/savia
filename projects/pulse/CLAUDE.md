# Pulse — el latido de la planta de trabajo

> SE-518. Proyecto público junto a Soul. Estado y configuración del operador: **siempre fuera del repo**.

## Qué es

Núcleo determinista, sin modelo en el camino crítico, que publica lo que pasa en la planta de trabajo (trabajos, propuestas, latido) mediante ficheros locales que lee Soul. Python estándar ≥ 3.9, sin dependencias (D2).

## Estado: slice S1

Hecho: contratos con esquema y validador (`schemas/`, `pulse/schema.py`), lanzador que emite inicio, latido y fin con código y clase (`pulse run`), `pulse status`, `pulse inbox` y canal de respaldo (`pulse deliver`).
No hecho (slices posteriores): planificador, política de integración (S2), señales tipadas (S3), freno y volante (S4), ledger completo y métricas (S5), servicio de usuario y configuración (S7).

## Contratos (raíz de datos del usuario: `$PULSE_DATA_DIR` o `<datos de usuario>/savia/pulse`)

| Fichero | Escribe | Lee |
|---|---|---|
| `eventos.jsonl` | Pulse | Soul, `pulse status` |
| `peticiones.json` | Pulse | Soul |
| `latido.json` | Pulse | Soul, `pulse status` |
| `presencia.json` | Soul | Pulse |
| `acuses.jsonl` | Soul | Pulse |

Reglas: un único escritor por fichero; los ficheros que Pulse lee deben ser del usuario y no escribibles por grupo ni por otros (si no, `FALLIDA`); ausente = `SIN_CONECTAR`; nunca «vacío»; dato sin nivel = N4. Los esquemas de `schemas/` son la fuente de verdad también para Soul.

## Uso

```
bin/pulse run --job-id ID [--ttl S] -- orden args...   # lanza y registra inicio y fin
bin/pulse job-start|job-beat|job-finish ...            # para lanzadores externos
bin/pulse latido --pasada N [--ttl S]                  # lo llama el bucle en cada pasada
bin/pulse deliver                                      # una pasada del canal de respaldo
bin/pulse status | inbox
```

Salidas: 0 bien, 1 rechazado por el estado, 2 entrada inválida.

## Pruebas

`python3 -I projects/pulse/tests/test_pulse.py` (también desde `tests/bats/se518-s1-pulse.bats`).
