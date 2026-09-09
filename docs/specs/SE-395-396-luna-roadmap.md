# Handoff Luna — arquitectura, Vaults y roadmap de investigación

Fecha: 2026-09-07. Propuesta para revisión, no modificación de prioridades oficiales.
Specs: SE-395 y SE-396, ambas PROPOSED. Ejecutor previsto: `gpt-5.6-luna`;
esto no acredita capacidades del modelo. La instrucción posterior «Implementa»
autoriza el desarrollo local dentro del alcance y gates establecidos.

## Fuentes y límites

Repositorio auditado: `0c7cd9d104134aab90d627bb9def38e2fd299d4d`.
SaviaLabs consultado realmente por MCP stdio; servidor negoció versión 0.3.0.
Lecturas: `INDEX.md`, `labs/ROADMAP.md`, roadmaps L28/L29/L30, resultados L1/L13,
notebook de ciclo L1–L10, hipótesis L14 e investigaciones L26/L27.
No se copia contenido privado del dome: sólo conclusiones técnicas minimizadas.
L15/L16 no localizados en el inventario consultado; no inferir cancelación.
Índices y roadmaps no están uniformemente actualizados. Esta revisión es una
síntesis de las líneas disponibles, no validación de cada experimento original.

L1–L10 contienen evaluaciones sintéticas deterministas: un resultado CONFIRMA
allí no demuestra utilidad operacional general. L13 también requiere ampliar
evidencia real. L14 identifica deuda estructural; L28 propone integridad,
verificación y handoff que deben integrarse con SE-391–394, no reconstruirse.
L17–L22 aparecen entregadas: priorizar mantenimiento/validación antes de rehacer.
L23 dispone de taxonomías; verificar integración en vez de repetir diseño.
L26 propone coste/calidad, gates y resiliencia: hipótesis a medir. L27 mantiene
distancia entre prototipos sintéticos y piloto real autorizado.
L30 ya tiene fixtures/herramientas: siguiente valor es backtest de decisión real.
L29 depende de hardware/decisión humana; no compras ni flashing autónomos.

## Orden propuesto por valor y dependencias

| Orden | Trabajo | Justificación/gate |
|---|---|---|
| 1 | SE-396 integridad + L14/L28 | Evita duplicación de ejecución y falsa evidencia; desbloquea confianza en todo benchmark |
| 2 | Fuente única de planning y receipts por AC | Cierre verificable y tareas ejecutables; no nuevo registry |
| 3 | Sustitución real CLI/proveedor/modelo/dominio; SE-391 cold start | Demostrar rutas existentes L2 sin elevar autoridad |
| 4 | SE-395 F0–F3 static/shadow/A-B | Ahorro plausible, condicionado a aislamiento y baseline válido |
| 5 | L26 y evaluaciones reales L1/L4/L6/L13 | Medir coste/calidad utilizando corpus y receipts comunes |
| 6 | L30 backtest; L27 piloto autorizado | Valor de decisión antes de expandir plataformas |
| 7 | L24/L25, L12, L29/RBT según demanda; L9 diferida | Necesitan demanda/evidencia o hardware; no expandir por novedad |

No se inventan scores: fórmula canónica V×U/E requiere entradas V/U/E validadas
que esta auditoría no tiene. Orden cualitativo provisional, no ranking numérico.
No cambiar prioridades canónicas sin revisión; dependencias de seguridad prevalecen.

## Contrato para cada tarea Luna

WIP=1. Equipo describe roles, no paralelismo obligatorio. Antes de empezar cargar
spec aprobada, instrucciones del proyecto, estado limpio/propiedad de archivos y
dependencias. Un slice debe caber normalmente en ≤3 archivos productivos más tests;
dividir si excede, no recortar acceptance. No elegir arquitectura por conveniencia.
Cada TASK fija objetivo, archivos permitidos, inputs, outputs, test rojo esperado,
tests de regresión, criterio STOP, evidencia y rollback reversible.
Flujo: SPEC/TASK → PLAN → EDIT → TEST → FIX → TEST → VERIFY → RECEIPT.
Si no hay fallo que corregir, FIX=NOT_NEEDED con evidencia; no fabricar defectos.
Human gates sólo por criterio/autoridad/scope/efecto externo/riesgo/UNKNOWN.
No sustituir silenciosamente el modelo solicitado si no está disponible.

## Cola inicial descompuesta

| Slice | Dependencia | Entrega y prueba decisiva |
|---|---|---|
| I01 | aprobación SE-396 | Test replay/mismatch y reserva previa en runtime/store; contador execute=1 |
| I02 | I01 | Refs/capabilities/result correlation; inválido execute=0 |
| I03 | I01 | Deadline/cancel/crash; efecto ambiguo no se reejecuta automáticamente |
| I04 | contrato de verificador existente | Observations/preflight estrictos; evidencia inventada/stale/strings rechazada |
| I05 | I04 | Separación synthetic/operational doctor; `/bin/true` no certifica L2 |
| I06 | I02/I04 | Receipts correlacionados e inmutables, sin sobrescritura |
| I07 | aprobación | Validators enums/extensions/timestamps; errores estables |
| I08 | aprobación | Corpus compartido gates Python/TS; deny/nonzero/malformed equivalentes |
| I09 | I04/I06 | Manifest closure y digest portable; mutación relevante invalida |
| V01 | aprobación | Aislamiento grafo MCP por dome; principal ajeno nunca ve nodos |
| V02 | V01 | Cache policy/revisiones/provenance y límites; revoke invalida hit |
| P01 | I06 | Planning existente reconoce YAML/omisiones/AC; no cierre por merge |
| A01 | I01–I09 | Dos adapters reales mismo flujo L2; indisponibilidad NOT_VERIFIED |
| A02 | A01 | Provider/model resolution explícita y revisión de modelo en evidence |
| A03 | A01/V01 | Dos domain packs efectivos y aislados, sin dependencia PM global |
| R00 | aprobación SE-395 | Inventario/research note y contrato preregistrado; sin router aún |
| R01 | R00/V02 | Dataset etiquetado/congelado y baseline reproducible |
| R02 | R01 | Guidance schema y selección pura determinista; policy antes de score |
| R03 | R02/I06 | Shadow sólo baseline, cero llamadas adicionales; receipt contrafactual |
| R04 | R03 | A/B aislado, adversarial y GO/NO-GO/NEEDS_MORE_EVIDENCE |

Fases pioneer/plasticity/homeostasis/multihop offline no están listas para asignar:
descomponer sólo si R04 justifica GO y los contratos están revisados. NO-GO detiene
esa línea sin impedir reparar integridad. No simular PASS de fases diferidas.

## Handoff y stop

Receipt por slice: spec/AC, SHA, diff, comandos y exit codes, tests, tipo de
evidencia, limitaciones, timestamp, siguiente dependencia. Sin datos privados.
No confundir ejecución delegada con autoridad delegada. Push, merge, activación,
datos reales sensibles y nuevos pilotos necesitan autoridad aplicable.
Al cumplir el slice, persistir receipt y continuar con el siguiente desbloqueado.
No expandir a L3/L4 ni convertir investigación en capacidad SUPPORTED.
La siguiente sesión revalida baseline antes de editar.

## Plan de ejecución hasta cierre — ampliación 2026-09-07

Objetivo: completar SE-396 y resolver empíricamente SE-395 hasta su conclusión
experimental permitida. Un NO-GO justificado cierra una hipótesis; no equivale a
implementar las fases descartadas. NEEDS_MORE_EVIDENCE deja la fase abierta.
Las líneas adicionales de Labs son prioridades futuras, fuera de esta ejecución.

### Punto de partida comprobado

I01 tiene un cambio local y dos regresiones nuevas. El turno anterior reportó
78 tests verdes, pero no demuestra cierre: `Store.acquire()` devuelve el token
de una reserva existente para la misma sesión/call, por lo que un retry tras
fallo puede ejecutar de nuevo. Lookup y acquire son transacciones separadas.
Record y release también: una caída entre ambas puede dejar reserva retenida
aunque exista resultado. Añadir pruebas de esos límites antes de completar I01.
No existe evidencia registrada de test rojo previo a ese cambio; la afirmación
anterior «con TDD» no está sustentada por la secuencia de herramientas.

### Etapas y salidas verificables

| Etapa | Trabajo | Condición para avanzar |
|---|---|---|
| E0 Preparar | Preservar cambios y archivos ajenos; aislar rama/worktree; reconciliar instrucciones, lifecycle y mapa AC→task→test | Baseline y propiedad de archivos registrados; ninguna tarea omite aceptación |
| E1 Integridad | Completar I01–I03: admisión exclusiva durable, identidad/digest, refs/capabilities, correlación, cancel/deadline y recuperación | Replay/concurrencia/crash no duplican ejecución; estado incierto se conserva y recuperación tiene contrato |
| E2 Evidencia | I04–I09: verificador, doctor, receipts, validators, gates y manifest | Evidencia inventada/sintética/stale no certifica; paridad Python/TS; receipts inmutables |
| E3 Vaults | V01–V02: grafo/cache por principal/dome, revocación, provenance y budgets | Tests cruzados no exponen datos; cache no pierde fuentes ni evade límites |
| E4 Sustitución | P01/A01–A03: planning y rutas efectivas frontend/provider/model/domain | Flujos reales equivalentes y límites registrados; ninguna dependencia indisponible se sustituye por PASS simulado |
| E5 Cold start | Nueva sesión, doctor real, C1–C14, dogfood L2, gates L3/L4 y receipts | Evidencia operacional separada; L2 sin aprobaciones mecánicas; L3 bloquea/pregunta y L4 deniega |
| E6 Investigación | R00–R04: protocolo, baseline, schema, shadow y A/B | Dataset congelado, adversarial y métricas reproducibles; GO/NO-GO/NEEDS_MORE_EVIDENCE explícito |
| E7 Experimentos posteriores | R05–R09 abajo, sólo tras GO aplicable | Beneficio incremental por mecanismo, sin violar invariantes |
| E8 Integración/cierre | Regresión, revisión, PR/CI/merge con autoridad aplicable, comprobación posterior | AC cubiertos, evidence accesible, lifecycle correcto y conclusión experimental documentada |

E1 y E2 pueden intercalar slices independientes; mantener un único escritor.
E4/E5 bloqueados por herramientas externas no detienen E6 si E2/E3 y su baseline
ya son válidos. No declarar cierre global mientras falte un gate obligatorio.

### Pruebas decisivas de integridad

Antes de ejecutar: mismo evento simultáneo en dos procesos; mismo event_id con
payload distinto; distinto event_id con mismo call/request; capability denegada;
refs ausentes/ajenas. El contador de efectos debe ser 0 o 1 según contrato.
Durante/después: excepción, resultado inválido, mismatch, cancel, timeout y caída
en cada frontera de persistencia. Reiniciar Store/runtime y repetir solicitud.
No liberar reservas por mero paso del tiempo ni afirmar exactly-once ante efectos
externos inciertos. Completar resultado y estado de reserva de manera coherente.
Añadir control positivo a cada prueba de denegación: comando que falla por otro
motivo no demuestra frontera de secretos. Usar datos protegidos de prueba sin
exponer credenciales reales en logs ni evidence.

### Extensión experimental condicionada

| Slice | Dependencia | Implementar/probar/analizar |
|---|---|---|
| R05 Pioneer | R04 GO | Persistencia e invalidación; repeated-query holdout; comparar ahorro y calidad contra static |
| R06 Branching | R04 GO | Triggers deterministas y budgets; ambiguas/conflictos; medir misses y coste incremental |
| R07 Plasticidad | R05/R06 GO | Feedback verificable, pesos bounded y decay; poisoning y overfitting; evaluar por exposición |
| R08 Homeostasis/pruning | R07 GO | Dry-run, dormancy recuperable y lifecycle; ataques de popularidad; comprobar diversidad sin desplazar mandato de policy |
| R09 Multi-hop offline | Evidencia previa y simulación revisada | Grafo fixture sin red, 2–3 hops; ciclos/explosión/budgets/provenance; ninguna ruta de producción habilitada |

Antes de cada R05–R09 redactar TASK con interfaces exactas, estados/transiciones,
archivos, fixtures y umbral incremental preregistrado. Usar ablación: añadir un
mecanismo cada vez. Ante NO-GO conservar la mejor variante anterior y documentar
qué fases dependientes quedan descartadas. Cambiar umbrales tras ver holdout
invalida esa evaluación y exige un nuevo holdout antes de afirmar mejora.

### Disciplina de ejecución, análisis y continuidad

Luna realiza una TASK por contexto manejable; no necesita permiso entre comandos
L0–L2 autorizados. Probar fallo antes del fix cuando se trate de una regresión;
ejecutar pruebas dirigidas y después las suites afectadas. Repetir sólo si hay
cambio, fallo o incertidumbre nueva. Cada tarea termina con análisis de AC,
riesgos residuales y receipt; después seleccionar siguiente dependencia lista.
Si una tarea falla, diagnosticar y corregir dentro del alcance. Si necesita una
decisión humana real, persistir diagnóstico y opciones concretas y avanzar trabajo
independiente. No usar el gate como motivo genérico para abandonar el roadmap.
Al cambiar de sesión guardar SHA/diff, archivos propios, comandos reproducibles,
tests pendientes, próximo TASK y blockers; conservar las modificaciones ajenas.

### Cierre operacional y autorización

Preparar cambios revisables y descripciones de PR por bloque coherente; no mezclar
graduación operacional con fixtures. La orden actual pide un plan: este documento
no ejecuta publicación. Verificar autoridad aplicable al publicar/mergear.
Tras merge, registrar SHA y CI del commit integrado. Terminar la sesión que causa
el defer SE-371; reconciliar AGENTS desde fuente canónica y comprobar generación
y drift cuando ya sea permitido. E5 debe usar una sesión nueva, nunca afirmar
cold-start desde la sesión implementadora. Si la interfaz no permite crearlo,
dejar un handoff ejecutable y marcar ese gate pendiente.
Entrega final: matriz AC completa, tests/CI, receipts operacionales, benchmark,
GO/NO-GO por experimento, limitaciones y lifecycle actualizado sin saltos.
Codex mantiene DEGRADED_SAFE/L2; adaptive default-off y producción one-hop.

## Avance de ejecución — 2026-09-08

- I01: implementado en PR #1112, pendiente de revisión humana E1.
- I07: implementado y verificado localmente; enums no escalares fallan con
  `ProtocolError` estable y `usage.extensions` conserva su contrato opcional.
- I02: no iniciado. Bloqueado por una decisión de contrato aún ausente: autoridad
  y resolución exactas de `context_ref`, `scope_ref` e `input_ref`. No se elige
  una implementación implícita para evitar crear una segunda fuente de verdad.
- Incidente Vaults MCP: RCA operacional persistido directamente en SaviaLabs;
  handler sano (5–93 ms), fallo atribuido a IPC `tsx` bloqueado por sandbox.
