---
context_tier: L3
---

# Criterio de evidencia en los tests (SE-456)

> Un test que no puede fallar no prueba nada. Criterio tomado de REA (MIT, `docs/testing.md`), reescrito para BATS.
> Lo hace cumplir `scripts/test-auditor-engine.py` (vacuidad) y el ratchet de `scripts/ci-test-quality-gate.sh`.

## Los seis puntos

1. **Los nombres no dan profundidad.** Que un test se llame «rejects invalid input» no demuestra nada. Lo que cuenta es la
   aserción que fallaría si el código se rompiera.
2. **Una aserción que no puede fallar no añade cobertura.** Ni `… || true`, ni un `run` cuyo resultado nadie mira.
3. **Desconocido no es aprobado.** `fail`, `unknown`, `unsupported`, `truncated` y `skipped` nunca suman como `pass`.
   Un gate que no pudo evaluar sale distinto de 0 (`checker-fail-closed.md`, SE-453).
4. **Skip con nombre.** Si falta la autoridad (proveedor real, red, herramienta), `skip "sin <qué>"`, nunca un `return 0`
   silencioso ni un test que pasa en vacío. La cobertura no verificada se declara (SE-444).
5. **Al podar, se conservan** los casos de entrada malformada, cancelación, limpieza, permisos, capacidad e identidad del
   objetivo. Antes de borrar una regresión se cita el test que la sustituye.
6. **Que algo se descubra no demuestra que se use.** Ni la validez de un esquema ni una palabra clave en la descripción
   prueban que una herramienta o una skill se seleccione bien: eso se mide con tareas representativas (evals de disparo).

## Antipatrones y su arreglo

**V1 — aserción anulada**

```bash
# Antes: pasa aunque la atestación no tenga hash
grep -q "sha256" "$f" || true
# Después
grep -q "sha256" "$f"
```

**V2 — `run` sin ninguna aserción detrás**

```bash
# Antes: el gate puede salir con 0, con 1 o reventar; el test pasa igual
run bash scripts/pr-plan.sh --gate-mode
true
# Después
run bash scripts/pr-plan.sh --gate-mode
[ "$status" -eq 1 ]
[[ "$output" == *"FAIL"* ]]
```

**V3 — estado ignorado (débil, se informa pero no bloquea)**

```bash
# Antes: comprueba el efecto, pero un hook que revienta después de escribir pasa
run bash "$HOOK"
grep -q '"budget_exceeded":true' "$log"
# Después
run bash "$HOOK"
[ "$status" -eq 0 ]
grep -q '"budget_exceeded":true' "$log"
```

Si el comportamiento correcto es «nunca bloquear» (un hook que siempre sale 0), se comprueba explícitamente:
`[ "$status" -eq 0 ]`. Así el test documenta la intención en vez de ignorarla.

## Qué hacer si al reparar un test falla

Es el objetivo: el test destapa un defecto que estaba oculto. Se arregla la causa o se abre un issue con el fallo y se
deja el test en rojo fuera del ratchet. Nunca se vuelve a anular. Ver `feedback_root_cause_always`.

## Lo que el detector no demuestra

- Detecta V1 y V2 por patrones de línea dentro de los bloques `@test`. No ve la vacuidad que se esconde en funciones
  auxiliares, en `set +e` ni en `bash -c "… || true"`.
- No mide si una aserción discrimina (que falle ante una mutación): eso es trabajo del revisor y de las pruebas de
  mutación.
- No cubre `|| ` seguido de otras formas de anular (`|| ls`, `|| continue`), un `skip` incondicional, ni `@test` con
  `{` en otra línea. Los heredocs que contienen `run …` dentro de un `@test` pueden dar falsos positivos.
- Su cifra es una cota inferior de los tests vacíos, no un censo.

## Ratchet

`.ci-baseline/test-vacuity.count` congela el número actual y `.ci-baseline/test-vacuity.findings` sus identidades
(fichero, `@test`, tipo). El gate falla con un hallazgo que no esté en la línea base aunque el recuento no suba: arreglar
uno y añadir otro no pasa. Menos hallazgos pasan y piden regenerar la línea base en el mismo PR con
`bash scripts/ci-test-quality-gate.sh --update-vacuity-baseline` (el test de coincidencia lo exige). Subir la línea base
exige justificación en el PR: nada la protege más que la revisión. Sin línea base, o sin `tests/` que escanear, el gate
falla cerrado.

La identidad es (fichero, nombre del `@test`, tipo): dos hallazgos del mismo tipo en un mismo test cuentan por recuento.
