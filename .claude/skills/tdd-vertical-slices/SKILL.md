---
layer: peripheral
name: tdd-vertical-slices
description: "Test-driven development with vertical-slice red-green-refactor cycles. Use when applying TDD to a new feature or bug fix, when user mentions 'red-green-refactor', 'tdd', 'test-first', 'vertical slice' — explicitly avoids the 'horizontal slicing' anti-pattern (write all tests first, then all code) which produces brittle implementation-coupled tests."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: any
  savia.maturity: stable
  savia.context: fork
  savia.maturity: stable
  savia.summary: "Disciplina TDD por slices verticales: 1 test → 1 implementación → repeat. El anti-pattern de horizontal slicing (todos los tests primero, luego todo el código) produce tests acoplados a implementación; aquí se prohíbe explícitamente."
  savia.trigger_keywords: "tdd, test-first, red-green, vertical slice, anti-horizontal"
---

## Subagent Scope Guard

> If you were dispatched as a subagent to execute a specific delegated task,
> **skip this skill's full orchestration workflow**. Execute only the assigned
> task, report result (DONE / DONE_WITH_CONCERNS / BLOCKED), and return.
> This guard prevents runaway skill activation in nested agent contexts.

# TDD vertical-slices

Pattern adoption from `mattpocock/skills/tdd/SKILL.md` (MIT, 26.4k⭐) — clean-room re-implementation, no source copied. SE-083 Slice única.

## Core principle

Los tests verifican **behavior** a través de public interfaces, no detalles de implementación. El código puede cambiar entero; los tests no deberían. Un test que se rompe cuando refactorizas pero el behavior no cambia, está testeando past la interface — está mal cortado.

## Anti-pattern: horizontal slicing

**NO escribas todos los tests primero, luego todo el código.** Eso es horizontal slicing — tratar RED como "escribir todos los tests" y GREEN como "escribir todo el código".

Produce **tests-de-mentira**:

- Tests escritos en bulk testean behavior *imaginado*, no *real*
- Acabas testeando la **forma** de las cosas (data structures, function signatures) en lugar del behavior user-visible
- Tests insensibles a cambios reales: pasan cuando el behavior se rompe, fallan cuando el behavior está bien
- Outrun your headlights: te comprometes con la estructura del test antes de entender la implementation

## Vertical slicing: tracer bullets

Recorrido correcto:

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED → GREEN: test1 → impl1
  RED → GREEN: test2 → impl2
  RED → GREEN: test3 → impl3
  ...
```

Cada test responde a lo que aprendiste del ciclo anterior. Como acabas de escribir el código, sabes exactamente qué behavior importa y cómo verificarlo.

## Workflow

### 1. Planning

Antes de escribir código:
- Confirma con la usuaria qué interface necesita cambiar
- Confirma qué behaviors testear (prioriza)
- Identifica oportunidades de **deep modules** (interface pequeña, implementation profunda) — ver `docs/rules/domain/architectural-vocabulary.md` (SE-082)
- Lista los behaviors a testear (NO los pasos de implementation)
- Pide aprobación de la usuaria

### 2. Tracer bullet

Escribe UN test que confirme UNA cosa del sistema:

```
RED:   Test del primer behavior → falla
GREEN: Código mínimo para pasar → pasa
```

Tu tracer bullet — prueba que el path funciona end-to-end.

### 3. Incremental loop

Para cada behavior pendiente:

```
RED:   Siguiente test → falla
GREEN: Código mínimo para pasar → pasa
```

Reglas:
- Un test cada vez
- Sólo el código suficiente para pasar el test actual
- NO anticipes tests futuros
- Tests focados en behavior observable

### 4. Refactor

Tras todos los tests verdes, busca refactor candidates:
- Extraer duplicación
- Profundizar modules (mover complejidad detrás de interfaces simples)
- Aplicar SOLID donde sea natural
- Considerar qué revela el código nuevo sobre el código existente
- Correr tests tras cada refactor step

**Nunca refactorizes mientras estás RED.** Llega a GREEN primero.

## Per-cycle checklist

```
[ ] Test describe behavior, no implementation
[ ] Test usa public interface only
[ ] Test sobreviviría refactor interno
[ ] Código mínimo para este test
[ ] No features especulativas añadidas
```

## Cross-references

- `docs/rules/domain/architectural-vocabulary.md` (SE-082) — Module/Interface/Seam/Adapter discipline. Aplica al diseño de la interface antes de escribir el primer test.
- `.opencode/agents/test-architect.md` — agente que aplica TDD; consulta este skill antes de generar suites.

## Anti-patterns

**❌ Horizontal slicing**: escribir todos los tests antes de cualquier implementación → tests acoplados a implementación, fallos en cascada al refactorizar, behavior imaginado en lugar de real.
**✓ Correcto**: un test → un ciclo RED/GREEN → siguiente test.

**❌ Slice demasiado grueso**: abarcar >1 comportamiento observable en un slice → fallo de RED/GREEN imposible de aislar, refactor bloqueado.
**✓ Correcto**: cada slice verifica exactamente un comportamiento observable a través de la interfaz pública.

**❌ Over-mocking**: mockear todo incluyendo el sistema bajo test → los tests pasan siempre porque nunca ejecutan código real, los bugs de integración se ocultan.
**✓ Correcto**: mockear solo dependencias externas (red, I/O, tiempo); el sistema bajo test ejecuta código real.

**❌ Test-after**: implementar primero y añadir tests retroactivamente → los tests documentan la implementación existente en lugar de guiarla, cero valor de diseño.
**✓ Correcto**: RED antes de cualquier implementación — el test que falla prueba que el behavior no existe aún.

## Atribución

`mattpocock/skills/tdd/SKILL.md` — MIT — pattern only, prosa propia. La disciplina anti-horizontal-slicing es la contribución central de Pocock que pm-workspace adopta explícitamente.
