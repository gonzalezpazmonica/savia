---
status: PROPOSED
priority: P1
developer_type: agent-team
created: 2026-09-07
related_specs: [SE-391, SE-393, SE-394, SE-395]
risk: L2
implementation_model: gpt-5.6-luna
---

# SE-396 — Harness agnóstico: integridad operacional y sustitución verificable

## Auditoría y valoración

Baseline: `0c7cd9d104134aab90d627bb9def38e2fd299d4d`, post-SE-394.
Auditoría local de código, reproducciones acotadas y consulta MCP a SaviaLabs;
no auditoría exhaustiva ni validación cold-start. No código cambiado aquí.
Valoración: contratos de separación útiles, pero agnosticismo operacional parcial.
Prioridad: ejecución/evidencia fiable antes de nuevas abstracciones o capacidades.
No promover Codex de DEGRADED_SAFE ni superar L2 por esta spec.

## Avance implementado

Esta entrega cubre únicamente la base de H01 y la ruta HTTP local de H07. El
runtime reserva antes de invocar el adapter, reproduce eventos ya confirmados,
conserva como ambigua una ejecución interrumpida y confirma journal/liberación
en una sola transacción. El bridge de OpenCode ejecuta el Shield HTTP local con
token, timeout y semántica fail-closed, incluso si se configura como asíncrono.
Los demás hallazgos continúan abiertos; este avance no completa ni aprueba la
spec, no cambia el nivel de autonomía y requiere los gates y revisión habituales.

Mejoras existentes que se conservan: puertos de adapter, filtrado de proveedor
desconocido con prefijo, resolución de dependencias/ciclos de domain packs,
manifest ampliado y bloqueo de configuración de hooks ausente/corrupta.

## Hallazgos y aceptación requerida

| ID | Evidencia y gap | Reparación/criterio de aceptación |
|---|---|---|
| H01 | `scripts/dual-cli/runtime.py:handle` ejecuta adapter antes de `Store.record`; no lease previo | Reservar/deduplicar antes de ejecutar. Replay idéntico no vuelve a invocar adapter; payload distinto con mismo ID rechaza. Crash no reejecuta efecto ambiguo automáticamente |
| H02 | Mismo flujo omite refs/capabilities reales; acepta result request_id ajeno | Resolver refs autorizadas, intersectar capabilities, validar correlación y policy antes de execute; rechazo sin efectos |
| H03 | `contracts.py:verify_observation` acepta lookup con verified=True; preflight permite observaciones vacías y truthiness de strings | Validación estricta de booleanos, procedencia, subject, versión, environment, digest y vigencia; ausencia/untrusted/stale nunca certifica |
| H04 | `codex_profile.py` acepta SAVIA_CODEX_TEST_MODE y probes `/bin/true` como éxito L2 | Fixtures aisladas de graduación/configuración; receipts SYNTHETIC no pueden ser evidencia operacional; doctor real con controles positivos y negativos |
| H05 | `autonomy.py:write_receipt` no correlaciona request/execution y sobrescribe destino | Validar y correlacionar antes de persistir; append/identidad inmutable, replay idempotente y mismatch rechazado |
| H06 | `contracts.py` enums con listas lanzan TypeError; usage.extensions admitido y después rechazado | Todo input inválido produce ProtocolError estable; extensiones y timestamps cumplen contrato probado |
| H07 | `scripts/opencode-plugin/savia-gates/lib/shell-bridge.ts` sólo bloquea exit2/decision:block | Paridad Python/TS en nonzero, malformed JSON, continue:false, deny/ask; hooks de seguridad no fire-and-forget |
| H08 | `config.py:build_manifest` omite ejecutores/validators relevantes | Closure de archivos y policies efectiva; cambio relevante invalida evidencia; hash estable entre checkouts equivalentes |
| H09 | `savia-bridge.py` exige Claude; gateway/resolver/routing aún separados | Cablear rutas existentes al contrato común, no otro gateway. Dos adapters reales prueban mismo flujo; sin CLI/proveedor forzado en core |
| H10 | Domain packs resuelven pero no se observó consumidor productivo de composición | Composición/precedencia/aislamiento explícitos; pruebas de dos dominios independientes sin reglas PM globales forzadas |
| H11 | planning-state omite specs recientes; validator PASS no detecta YAML/omisiones | Reconciliar autoridad SE-378 existente, validar status YAML y evidencia AC; merge no equivale a graduación |
| H12 | Vaults cache sin principal/policy/revisión; grafo MCP global pese a selección de dome | Tests adversariales por dome/principal; cache con provenance y límites; condición previa a canary SE-395 |

## Reproducciones de esta auditoría

R1: adapter de fixture anuncia `read`; evento exige capability no anunciada y
refs inexistentes. Dos dispatch iguales ejecutaron dos veces, sin lease; ambos
aceptaron resultado con otro request_id. Es el camino Python con adapter inyectado:
el daemon por defecto sin adapters registrados no demuestra explotación desplegada.
R2: observation de 2000 con subject/environment ajenos y ref inventada aceptada
mediante mapping verified=True. Preflight con strings `"false"` en checks,
observaciones vacías y certified=True devolvió certified=True sin gaps.
R3: `SAVIA_CODEX_TEST_MODE=1`, PATH mínimo y probes `/bin/true` devolvieron PASS/L2
sin probar instalación/auth/sandbox reales. CI sintética no equivale a doctor real.
R4: writer persistió request A/execution B y posterior llamada sobrescribió receipt.
R5: enum lista provocó TypeError; usage.extensions objeto provocó rechazo.
R6: manifest real no incluía codex_profile.py, autonomy.py, state.py, protocol.py,
domain_packs.py ni config.py. H07/H09/H10/H12 son inspección estática: requieren
regresión ejecutable antes de afirmar impacto real. No se intentó leer secretos.
Los 9 tests de harness contracts ejecutados pasaron: cobertura existente no detecta
estos casos. No se ejecutó CI completa ni doctor/canaries reales en esta auditoría.

## Contrato de implementación

Reutilizar Store/protocol/adapters/contracts/receipts/registry existentes. No crear
segunda verdad, permisos nuevos ni sistema paralelo de evidencia. Runtime debe
negociar schema, aplicar deadlines/cancel y no confundir cancel solicitado con
efecto cancelado. No prometer exactly-once ante caída tras efecto externo: conservar
estado incierto y exigir reconciliación humana cuando corresponda.
Evidence distingue UNIT/SYNTHETIC/INTEGRATION/OPERATIONAL; flags del caller no
conceden confianza. Elegir autoridad verificadora existente tras inventario;
si no existe contrato autorizado suficiente, STOP y decisión humana.
Pruebas de sustitución separan frontend, proveedor, modelo y dominio; ausencia
de instalación/autorización → NOT_VERIFIED, nunca PASS con mocks.
Manifest debe cubrir configuración efectiva sin copiar secretos a evidence.

## Plan, límites y Definition of Done

Orden H01–H08 y H12 → H11 → H09–H10 → evidencia operacional. Detalle de slices
en `SE-395-396-luna-roadmap.md`. Cada slice: test rojo → mínimo cambio → tests
dirigidos → regresión/lint → receipt. Revisor humano conserva decisiones.
AC: todos los hallazgos cuentan con regresión; paridad de gates; replay/cancel/
crash/mismatch seguros; evidencia no falsificable por self-assertion; aislamiento
de dominio; sustitución real documentada o limitaciones explícitas sin cierre total.
CI verde y revisión requerida antes del cierre; seguir lifecycle canónico.
La spec por sí sola no autoriza publicación, push ni merge; esas operaciones
requieren la autoridad externa correspondiente. AGENTS.md sigue protocolo
SE-371; no regenerar durante una sesión que provoca defer.
