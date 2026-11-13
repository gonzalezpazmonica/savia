# SE-530 S1 — Medición de H9 (primera ejecución)

Prerregistro: `docs/evidence/SE-530-S1-prerregistro.md` (commit anterior a este informe, comprobado por `tests/bats/hecho-verificado.bats`, AC-1.8).

## Resultado

**H9 confirmada**: el 81,9 % de las marcas `ESTADO: OK` de la ventana no tiene evidencia independiente registrada (200 de 244; umbral 10 %, n mínimo 200).

| Dato | Valor |
|---|---|
| Ventana | 2026-10-31 a 2026-11-13 (14 días, por fecha de modificación de la marca) |
| Marcas `ESTADO: OK` (n) | 244 |
| Marcas no OK (PARCIAL/FALLO) | 60 (fuera de n) |
| Marcas ilegibles o sin `ESTADO:` | 10 (fuera de n) |
| `verificado` | 44 |
| `declarado` | 200 |
| `refutado` | 0 |
| Sin evidencia independiente | 200 (81,9 %) |

## Por clase de evidencia (marcas OK con al menos un registro válido de la clase sobre el SHA vigente)

| Clase | Marcas | Nota |
|---|---|---|
| `autodeclaracion` | 244 | Toda marca OK lo es por construcción; no cuenta |
| `revision` | 44 | Registro de revisiones de merge-sprint, revisora distinta del autor y de la orquestadora |
| `persona` | 0 | No hay registro histórico |
| `ci_base` | 0 | No hay recolector histórico |
| `ci_propio` | 0 | No hay recolector histórico |
| `postcondicion` | 0 | No hay recolector histórico |

## Cómo se midió

```
python3 scripts/hecho-verificado.py measure --done-dir <marcas> --until 2026-11-13 --window 14 \
  --evidence <heads.jsonl> --reviews <reviews.jsonl> --repo savia
```

- `heads.jsonl`: SHA de cabeza actual de cada PR citada en una marca, obtenido de GitHub (`headRefOid`). 100 de las 134 PR citadas; las 34 restantes son números bajos de otros repositorios y no tienen cabeza, así que quedan `declarado`.
- `reviews.jsonl`: registro de revisiones del merge-sprint, con `reviewer`, `author`, `sha` y `verdict`.
- `--repo savia`: solo las PR de este repositorio reciben evidencia (ver Desviaciones).

## Sesgo y límites (declarados en el prerregistro)

- La cifra está **sesgada al alza**: solo se recolectó la clase `revision`. Un trabajo cuya PR se fusionó tras CI en verde con pruebas de la base, o que la persona confirmó, figura aquí como `declarado` porque nadie guardó ese registro.
- Qué dice y qué no dice el resultado: dice que, **con la evidencia que hoy se guarda**, 4 de cada 5 OK no tienen confirmación independiente registrada. No dice que 4 de cada 5 trabajos estén mal.
- El SHA vigente es la cabeza de la PR en el momento de medir, no en el momento de la marca. Una revisión sobre un SHA que la PR ya sustituyó cuenta como «de un SHA anterior».
- Los registros de revisión se identifican por número de PR. El registro es de este repositorio; las PR de otros repositorios se excluyen con `--repo`.
- El directorio de marcas es vivo: una marca nueva dentro de la ventana cambia las cifras. Dos ejecuciones sobre los mismos ficheros dan la misma salida (AC-1.1); entre mi ejecución de prueba y la definitiva el recuento de no-OK pasó de 59 a 60 porque un trabajador cerró una marca.

## Consecuencia según el prerregistro

H9 se confirma: la regla de S2 se mantiene y se vigila el ruido. Antes de S2 conviene un recolector de `ci_base` y `persona`; sin él, el 81,9 % mide la falta de registro tanto como la falta de verificación.
