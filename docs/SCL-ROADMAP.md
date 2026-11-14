# SCL — Savia Continuous Learning Roadmap

> **HISTÓRICO (2026-09-26).** Este roadmap ya no rige. Ruta vigente: `docs/ROADMAP.md` (ADR-002); estado: `docs/propuestas/planning-state.json`.


> Roadmap propio del programa **Savia Continuous Learning (SCL)**.
> Nueva era de specs: prefijo `SCL-###` (desacoplada de `SE-###`).
> **Anclaje al roadmap general:** Era 205 en `docs/ROADMAP.md`.
> **Spec fundacional:** `docs/specs/SCL-001-aprendizaje-continuo.spec.md` (APPROVED 2026-08-16, IMPLEMENTED 2026-08-17).

---

## Tesis

La AGI no llega como un modelo preentrenado "terminado", sino como un sistema que
aprende continuamente: arranca con conocimiento mínimo, crece con la experiencia, y sus
"pesos" se gestionan como artefactos de despliegue (canary, shadow, rollback instantáneo).
El cuello de botella ya no es compute, es imaginación: el mecanismo para convertir
experiencia en conocimiento persistente.

**La vuelta para Savia:** Savia ya es la forma agnóstica a LLM de esa tesis — sus "pesos"
son texto versionado en git (CONSTITUCION + CRITERIO + memoria + skills). Lo que falta es
**cerrar el bucle**: hoy el conocimiento entra al sustrato solo por edición manual de la
operadora o por el ledger reconociendo errores *a posteriori*. SCL convierte el sustrato en
un artefacto de despliegue que **aprende de forma continua, medida y agnóstica a LLM**.

## Principios invariantes del programa

1. **El aprendizaje es sustrato, no parámetros.** Cero fine-tuning, cero acoplamiento a
   proveedor (CRIT-002, ADR-012). El modelo es un ejecutor; el bucle es un compilador de
   texto de sesión a sustrato.
2. **Savia propone, la operadora dispone.** El bucle *propone*; la activación
   `human_authored` sigue siendo humana (CRIT-031, ART-11). La CONSTITUCION y CRITERIO
   permanecen intocables por el bucle.
3. **Aprendizaje medido, no declarado.** Ningún "aprendimos" sin `ΔL` medido (p_consistent
   + divergencia + ignorancia resuelta). "Savia no aprendió" es resultado de primera clase.
4. **Por slice, según dolor demostrado.** Ningún slice se adopta por elegancia conceptual;
   se adopta si su benchmark demuestra el dolor (patrón SE-268).

---

## Fases

| Fase | Estado | Contenido | Anclaje |
|---|---|---|---|
| **F0 — Sustrato** | EXISTENTE | CONSTITUCION, CRITERIO (33 INFERRED), memoria (tier-rotate, bitemporal, consolidate), ledger SE-255 S3, calibración SE-255 S4, SaviaVaults (BM25, grafo, entity resolution), Labs L1-L6, p_consistent (SE-292 S6), multi-proveedor (ADR-012) | Eras 125-204 |
| **F1 — Cerrar el bucle** | SCL-001 **IMPLEMENTED** + SCL-001.1 **IMPLEMENTED** (hook captura + correcciones prod) | Captura canónica → ciclo de vida shadow/canary/active → métrica `L` → agnosticismo | **Era 206** |
| **F2 — Persistir + recall operativo** | SCL-002 **IMPLEMENTED** (cúpula SaviaLearning) + SCL-003 **IMPLEMENTED** (recall por prompt) | Cúpula propia de lecciones (persistencia real cross-instancia) + recuperación automática en el momento de trabajar | Era 206 |
| **F3 — Instrumentar Labs + autonomía** | SCL-004 **IMPLEMENTED** (L1 divergencia grafo-modelo → propuesta) + SCL-006 **IMPLEMENTED** (autonomía graduada por p_consistent) | Labs L1 como instrumento del bucle; autonomía L0-L3 graduada por consistencia medida | Era 206 |
| **F4 — Búsqueda híbrida** | SCL-005 **IMPLEMENTED** (venv ~/.savia/venv, recall híbrido BM25+embeddings) | Embeddings híbridos para la divergencia y el recall (ADR-003 Fase 4) | Era 206 |
| **F5 — Federación cross-dome** | SCL-007 **IMPLEMENTED** (share A2A + search-remote + import INFERRED) | Lecciones compartidas entre instancias remotas vía A2A de SaviaVaults | Era 206 |

---

## SCL-001 — Cerrar el bucle (30h, 4 slices) — IMPLEMENTED 2026-08-17

> Detalle completo: `docs/specs/SCL-001-aprendizaje-continuo.spec.md`.
> **Estado: APPROVED 2026-08-16 → IMPLEMENTED 2026-08-17.**
> Artefactos: `scripts/learning-{proposal,lifecycle,rollback,metric,report,guard}.sh`,
> regla `docs/rules/domain/scl-001-learning-loop.md`, 27 tests BATS
> (`tests/test-scl-001-*.bats`). Bucle cerrado verificado por E2E.

| Slice | Objetivo | Esfuerzo | Depende de | Valor | Estado |
|---|---|---|---|---|---|
| S1 — Captura canónica | Artefacto `learning-proposal` unificado, idempotente, registrado en el grafo de SaviaVaults | 7h | hooks de captura, SaviaVaults grafo | Entrada formal del bucle | DONE (5 AC) |
| S2 — Sustrato como artefacto de despliegue | Ciclo de vida shadow→canary→active→superseded + rollback instantáneo | 9h | S1, git, CRIT-024 | Despliegue del conocimiento | DONE (6 AC) |
| S3 — Aprendizaje medido | Métrica `L` = p_consistent + divergencia (L1) + ignorancia resuelta (L2) | 8h | SE-292 S6, Labs L1/L2 | Gate anti-autoengaño | DONE (7 AC) |
| S4 — Agnóstico a LLM | Bucle sobre texto, cero fine-tuning, prueba E2E multi-proveedor | 6h | S1-S3, ADR-012 | Cierra la tesis | DONE (6 AC) |

### Orden recomendado

```
S1 (captura, 7h) → S2 (ciclo de vida + rollback, 9h) → S3 (métrica L, 8h) → S4 (agnosticismo, 6h)
```

S1-S2 son el esqueleto (capturar + desplegar) y se sostienen sin métrica; S3 convierte el
esqueleto en bucle cerrado; S4 es verificación transversal del agnosticismo y necesita los
tres anteriores para su prueba E2E.

### Hitos medibles

- **M1 (S1):** una propuesta de aprendizaje generada por evento, idempotente y consultable
  por grafo. — **CUMPLIDO** (AC-1.1/1.3/1.4).
- **M2 (S2):** una entrada errónea activada y revertida con rollback que restaura el diff.
  — **CUMPLIDO** (AC-2.3, test E2E).
- **M3 (S3):** reporte de ventana que distingue "aprendió" de "no aprendió" con `ΔL` medido.
  — **CUMPLIDO** (AC-3.3).
- **M4 (S4):** sustrato convergente entre dos proveedores sobre el mismo escenario.
  — **CUMPLIDO** (AC-4.1/4.3).

---

## Backlog SCL (futuras, sin especificar)

> **Corrección 2026-08-22**: SCL-008 ya existe ("Acoplamiento seguro de Criteria,
> CL y Vaults"); la antigua candidata "reconciliación" pasa a **SCL-010**.
> "SE-309 knowledge governance" era drift (SE-309 = Anti-sycophancy); la
> reconciliación usa `reconciler` (SPEC-183).

**Priorización 2026-08-22** (dolor demostrado > elegancia · CRIT-019 · SE-268):

| # | Spec | Tesis | Sh | Por qué este orden |
|---|---|---|---|---|
| 1 | SE-534 S1+S2 | Fingerprint de errores → incidentes → captura SCL | ~22 | Mayor dolor: telemetría (SE-313) existe pero no agrupa ni aprende. Determinista, alto ROI/h. **IMPLEMENTADO** |
| 2 | SCL-010 | Reconciliación de lecciones duplicadas entre instancias | ~8 | F5 ya trae lecciones; sin reconciliar degradan el recall; reutiliza el 3-bucket. **IMPLEMENTADO** |
| 3 | SCL-009 | Auto-descubrimiento de instancias federadas | ~6 | Conveniencia sobre federación manual. **IMPLEMENTADO** |
| 4 | SAGI SCL-011/012/013 | Orquestador + pruebas P1-P6 (emergencia medible) | ~8+8 | Completa el programa: decide dónde vive el orquestador y lo verifica. **SCL-011/012/013 IMPLEMENTADOS** |
| 5 | SCL-014 / run-2 | Run real de pruebas con LLM (agnosticismo H2) + cierre de línea L11 | labs | Trabajo de labs (privado, CRIT-001); solo LPs sanitizadas al repo |

**Ya integrado (2026-08-22)**: SE-335 + SE-336 (Turn-SDLC; S4 alimenta L). **Orden ejecutado**: SE-534 → SCL-010 → SCL-009 → SCL-011 → SCL-012 → SCL-013.

> **Estado 2026-08-23**: SCL-001..013 IMPLEMENTED (F0-F5 + orquestador SAGI + P1-P6 e2e). El run-2 real (LLM, agnosticismo, cierre L11) queda en SaviaLabs (privado, CRIT-001). **L11 lab CERRADA** (CONFIRMA run2+run3, retorno 3/3). **L13 metacognición CERRADA 2026-08-23** (CONFIRMA 4/4 + señal real ledger). Próximo programa: L14 circuit-closing deuda estructural (preregistrada, en curso).

---

## Métricas de programa

| Métrica | Definición | Fuente |
|---|---|---|
| `L` | p_consistent + divergencia grafo-modelo + ignorancia resuelta | SCL-001 S3 |
| p_consistent | fracción de ejecuciones consistentes sobre k intentos | SE-292 S6 |
| Propuestas capturadas/activadas | ratio del embudo shadow→active | SCL-001 S1/S2 |
| `ΔL` por ventana | variación de la métrica entre ventanas | SCL-001 S3 |
| Rollbacks | entradas revertidas con causa registrada | SCL-001 S2 |

---

## Riesgos top

1. **Métrica `L` autoengaña** (mide actividad, no aprendizaje) — mitigación: base
   determinista; si `L` no separa actividad de mejora, S3 se abandona con registro.
2. **Fricción del ciclo de vida → desactivación** — mitigación: shadow invisible por
   defecto, canary opt-in, rollback es un comando.
3. **Sobre-ingeniería** — Savia ya funciona con heurística; cada slice se justifica por
   dolor demostrado, no por elegancia.
4. **"Agnóstico" como excusa para no evaluar el modelo** — el sustrato es agnóstico; el
   modelo se sigue midiendo por `L` y calibración.

---

## Anclaje al roadmap general

- **Era 205** (`docs/ROADMAP.md`): SCL-001 como Tier 0 del roadmap general.
- SCL consume, no rehace: SE-255 (ledger/calibración), SE-268 S4 (memoria dos velocidades),
  SE-292 S6 (p_consistent), SaviaVaults (grafo/provenance), Labs L1-L6.
- La CONSTITUCION y CRITERIO permanecen intocables por el bucle (CRIT-031): el bucle
  propone, la operadora dispone — "la IA propone, el humano dispone".

## SAGI — orquestador AGI sobre el bucle (L11)

**SCL-011/012/013 IMPLEMENTADOS** (orquestador `savia-orchestrator.sh`, pruebas
P1-P5 `l13-meta-pruebas.sh`/`sagi-pruebas.sh`, flujo e2e `sagi-e2e.sh`).
**L11 CERRADA 2026-08-23** (CONFIRMA run-2 + run-3, retorno 3/3). Ver
`docs/sagi-roadmap.md` (detalle privado en SaviaLabs).
