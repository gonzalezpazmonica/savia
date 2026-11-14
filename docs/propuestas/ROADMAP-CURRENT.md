# Roadmap Current (GENERATED — no editar; fuente: planning-state.json)

Fase A · WIP 6/6. Estado y cola canónicos; ADR-002.

## Cola de sesiones (orden por gates, sin fechas)

- **S22 · P0 · fase A** — Gemelo operativo y Savia usable
  Acción: Terminar Soul Continuidad v1 y la app de conversación sobre lo ya fusionado (SE-490: PRs #1440–#1447); cada entrega se prueba en el dispositivo de la persona antes de pedirle nada. La puerta de comprensión (SE-505) ya rige como regla y como comprobación de validate.
  Entrada: Specs aprobadas; escenas y prototipo confirmados donde SE-505 lo exige. El código de Space vive en su repo; aquí se registra spec, evidencia y cierre.
  Salida: Una persona no técnica usa el gemelo y la app sin órdenes crípticas; AC de usabilidad verificados en su dispositivo; evidencia enlazada por AC.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: es el producto que se usa a diario; SE-514 y SE-507 se muestran aquí; esfuerzo: slices pequeños por pantalla o fuente; ocupa hueco WIP.

- **S26 · P0 · fase A** — Coste por turno: contexto fijo a la mitad y guardas sin bloqueos falsos
  Acción: SE-511: medir y reducir el contexto fijo que se carga en cada turno. SE-510: un despachador por evento y registro de cada bloqueo, con la clase FORMA o POLÍTICA que traía SE-475.
  Entrada: SE-510 y SE-511 aprobadas (2026-11-09, escenas confirmadas). SE-511: la medición empieza ya; el recorte del contexto solo tras la validación D4 con el método de EXP-509, que se cortó por cuota sin resultados. Cada una necesita su prototipo S0 confirmado antes de S1.
  Salida: Tokens fijos por turno medidos antes y después en los dos frontends; bloqueos falsos contados antes y después; ningún guard de política debilitado.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: la cuota semanal se agotó dos noches seguidas (2026-11-07 y 2026-11-08) y paró la cola; abarata todo lo demás; esfuerzo: medición pequeña; reducción media.

- **S23 · P0 · fase A** — Fundamentos de efectos y autoridad: construir en orden
  Acción: Construir en este orden: SE-488 (aprobación por fusión), SE-508 (control previo de MCP y WebFetch: hoy no hay ninguno, arranca en observación), SE-493 (ledger de efectos), SE-498 (STOP y revocación), SE-496 (contrato de delegación). SE-512 se aprueba por el camino de SE-488, sin tercer formato de firma. SE-491, SE-499 y SE-494 siguen por decidir; SE-502 queda aplazada hasta tener las tres primeras.
  Entrada: SE-493, SE-496, SE-498 y SE-508 aprobadas (2026-11-09, escenas confirmadas); falta el prototipo S0 de cada una antes de S1. Una en curso cada vez; riesgo alto: revisión humana del PR concreto. SE-512, SE-491, SE-499 y SE-494 siguen PROPOSED.
  Salida: Cada spec decidida; las aprobadas con sus AC y pruebas negativas en los dos frontends; ninguna ruta de efecto nueva sin su gate.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: Savia Viva (SE-513 S3, SE-515 S3–S4), el sprint nocturno y el modo mediado de Space dependen de este bloque; esfuerzo: cinco specs medianas en serie; cuatro decisiones pendientes.

- **S27 · P0 · fase A** — Revisión de graduación de lo ya entregado
  Acción: 22 specs figuran APPROVED o DEFERRED con sus artefactos y PRs ya en main. Revisar AC por AC, ejecutar sus tests y registrar completion con revisión humana, o anotar el slice que falta. No se reimplementa nada.
  Entrada: La evidencia de partida es existencia de artefactos y PRs fusionadas (lectura del 2026-11-09), no verificación de cada AC. La graduación la decide la operadora spec a spec.
  Salida: Cada una IMPLEMENTED con completion y revisión humana, o con su resto anotado y devuelto a la cola. El número de APPROVED sin implementar baja de 63 según lo verificado.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: saca de la cola hasta 22 specs sin escribir código y deja ver el backlog real; esfuerzo: revisión por lotes de cinco; sin hueco WIP.

- **S03 · P0 · fase A** — Deuda de calidad con pruebas de comportamiento
  Acción: Remedir deuda certificada y elegir el siguiente grupo por riesgo/uso; conservar umbral >=80 y ratchet; usar #1180 como evidencia de entrega, no como cierre de toda la wave.
  Entrada: WIP actual; inventario actualizado; aprobación de avance de wave cuando corresponda.
  Salida: Reducción de deuda demostrada por comportamiento discriminante, baseline publicado y excepciones explícitas; no certificar por presencia de ficheros.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: hace fiables los gates; esfuerzo: grupo pequeño; no prometer cierre de 128 skills por sesión.

- **S04 · P0 · fase B** — Graduación operacional del harness
  Acción: Ejecutar H04 con autorización específica; revisión humana H09 y procedencia A01c; actualizar completion por AC y decidir cierre.
  Entrada: Baseline A demostrado; H04 real requiere autorización y coste; sin autograduación.
  Salida: H04/H09 y regresión operacional documentadas; completion y revisión humana; límites L3/L4 intactos.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: abre frontera TEE/AEK; esfuerzo: 4-8 h de análisis compartido históricamente estimadas; costes de canaries a acordar.

- **S24 · P1 · fase A** — Savia Viva A0: auditoría del estado real y sondas, sin cambios de autoridad
  Acción: Slice S0 de las tres specs de Savia Viva R6: matriz de cobertura de rutas de efecto por frontend, desglose del recall por criterio, tabla de soporte de cambio en caliente por harness, medición de peticiones a la persona y fixtures de las sondas P0–P15. Solo lectura y fixtures.
  Entrada: SE-513, SE-514 y SE-515 aprobadas (2026-11-09) con escenas confirmadas; S0 es solo lectura y fixtures, más los prototipos de SE-513 y SE-514. No ocupa hueco WIP.
  Salida: Informe con observado, inferido y no verificado, commits y hashes fijados, dominio piloto elegido con tres casos y tres contraejemplos, y condiciones de NO-GO escritas antes de medir.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: decide si el resto de Savia Viva se construye, se recorta o se descarta; esfuerzo: tres slices pequeños de lectura.

- **S25 · P1 · fase A** — Savia Space 0.2 y la seguridad de su canal de aprobación
  Acción: Cerrar Space 0.2 (SE-428) y seguir por modo mediado (SE-434), experiencia (SE-432), proyectos y cúpulas (SE-436) e interoperabilidad (SE-429). SE-446 S0: sonda de autoaprobación contra el servidor real; si encuentra una vía abierta, su mitigación pasa a P0. SE-443, SE-447, SE-430, SE-435 y SE-439 después.
  Entrada: Specs aprobadas; hueco WIP temporal de SE-428 (addendum ADR-002). El código vive en el repo de Space.
  Salida: Space 0.2 cerrado y el WIP vuelve a 3; informe de la sonda por vía y test permanente de que el agente no contesta su propio aviso.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: la política por herramienta presupone un canal de aprobación seguro; S22 se apoya en Space; esfuerzo: un slice cada vez dentro del hueco de Space.

- **S32 · P1 · fase A** — Terminar lo empezado
  Acción: Cerrar los restos de specs con entregas parciales en main: SE-426 (firma con secreto de CI), SE-500 (S3 en adelante), SE-501 (tras #1472, #1488 y #1490) y SE-470 (tras S2, #1487).
  Entrada: Specs aprobadas; inventario del resto de cada una antes de abrir trabajo.
  Salida: Cada una con su resto hecho o descartado por escrito y pasada a S27.
  Necesidad: media; urgencia: media; valor: medio; desbloqueo: reduce trabajo abierto a medias; esfuerzo: restos pequeños.

- **S19 · P1 · fase A** — Medir jueces y relevos antes de confiar en ellos
  Acción: SE-469: 30 casos de los golden sets en vivo con tope de gasto e IC95 por tribunal. SE-474: proveedor independiente opcional; la métrica de hallazgos que solo ve el segundo proveedor se mide una vez y la comparte con SE-476. SE-471 ya está en main (#1486) y pasa a S27.
  Entrada: SE-469 ya APPROVED y después de SE-468; SE-474 sigue PROPOSED y necesita decisión de la operadora.
  Salida: Informe de concordancia con IC95 y decisión según kill criterion; decisión registrada sobre SE-474.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: da el primer dato de acierto de los tribunales que pesan en merges y separa el OK autodeclarado de lo validado; esfuerzo: SE-469 medio (M); SE-474 por decidir.

- **S28 · P1 · fase C** — Lecciones con ámbito y aprobación auténtica
  Acción: Un solo esquema de lección: SE-473 es la dueña (ámbito, evidencia, caducidad, refutación y, nuevo, tipo de acción y punto de control); SE-497 parte 2 conserva el paso a activa (recibo, firma humana verificable, rollback, ninguna cifra concede autoridad). SE-409 se reduce a retirada por desuso. SE-460 declara que su sello local es higiene, no aprobación.
  Entrada: SE-473 S0 ya aprobado: medir primero. Aprobación de SE-497 por la operadora; S1–S2 de SE-473 necesitan nueva aprobación tras S0.
  Salida: Medición de S0 publicada; esquema único decidido; una cadena de firma falsificada no activa una lección (test negativo).
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: sin esto SE-515 no pasa de orientativa; esfuerzo: S0 pequeño; SE-497 parte 2 media.

- **S29 · P1 · fase C** — Savia Viva: recall trazado, vinculación en sombra y admisión duradera
  Acción: SE-515 S1–S2: prueba de entrega del recall, métrica marcada como no medida cuando usa valores fijos, resolvedor de aplicabilidad por metadatos en sombra y evaluación en casos reservados. SE-513 S1–S2: admisión y salida en una transacción y promoción por regla.
  Entrada: S24 publicada con resultado que lo justifique; S28 con el esquema decidido; cada slice de SE-515 a partir de S1 necesita su propia aprobación, según la spec.
  Salida: Ablación con y sin recall publicada (cero cambios es resultado válido); GO, NO-GO o retirada de la vinculación orientativa; cero entradas admitidas perdidas bajo cortes.
  Necesidad: media; urgencia: baja; valor: por demostrar; desbloqueo: primera evidencia de si una lección cambia una decisión; esfuerzo: slices pequeños; el experimento manda.

- **S05 · P1 · fase B** — TEE v1.1 y frontera AEK en solo lectura
  Acción: Reescribir SE-401 a TEE v1.1 como arquitectura de referencia (F0 de solo lectura); el motor de autoridad va por SE-496 y su modelo por SE-502, no por fases nuevas de SE-401. SE-386 y SE-394 quedan sustituidas (2026-11-09). Mapear issuer/EEP/evidence con L31 F0 y contrato común de tres frontends.
  Entrada: SE-396 graduada; contrato/frontera y spec aprobados; Labs máximo una línea activa.
  Salida: Mapa revisado, exclusiones y bypass explícitos, pruebas negativas READ_ONLY, contrato EEP común; namespace AEK- ya decidido.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: evita duplicar autoridad; esfuerzo: F0 L31 8-16 h estimadas; implementación aparte.

- **S06 · P1 · fase C** — Un laboratorio de conformidad y benchmark
  Acción: Unificar matriz negativa, bypass, caos, receipts y replay; baseline con trazas y selección fijadas. SE-495 y SE-503 (PROPOSED) aportan el banco de tareas reales y el verificador por proyecto. Las sondas adversariales de Savia Viva (P12, P14) se alojan aquí, sin suite paralela. Último slice: piloto de suite de conformidad sobre un solo contrato (SE-452).
  Entrada: Gate B y corpus/contratos pinned; no ejecutar todos los experimentos Labs a la vez.
  Salida: Cero violaciones de invariantes bajo fallos en los tres frontends y cuatro niveles de replay; evidencia auditable.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: evidencia para portabilidad y pilotos; esfuerzo: slices por frontend/invariante.

- **S30 · P1 · fase D** — Atención humana y aprobaciones contestables
  Acción: SE-458 (tope y lotes de PRs en revisión), SE-459 S1 y S3 (tarjeta), SE-492 (estado declarado, no inferido), SE-507 (latido de runs, con el digest de SE-471 leyendo del ledger) y, encima, la cola única de SE-514. SE-461 a SE-463: composición de efectos, marca de sesión y cobertura de supervisión.
  Entrada: Aprobación de SE-492 y SE-507 por la operadora, con escenas confirmadas (SE-505). SE-514 ya aprobada (2026-11-09): su S1 va después de S22.
  Salida: Peticiones a la persona medidas antes y después; ningún permiso inferido del silencio; cada spec con sus negativos.
  Necesidad: media; urgencia: media; valor: alto; desbloqueo: protege el recurso más escaso; SE-515 con revisión obligatoria necesita esta cola; esfuerzo: slices pequeños independientes.

- **S31 · P1 · fase D** — Vaults: de la recuperación medida al contexto gobernado
  Acción: SE-489: decidir la promoción de las rutas ya construidas y medidas (M0–M7). SE-482 queda como paraguas sin F6 ni la parte de F4 que SE-489 ya cubre; SE-486 es su F1 (admisión del conocimiento).
  Entrada: Aprobación de SE-482 y SE-486 por la operadora; evaluación privada en Labs.
  Salida: Decisión de promoción con datos; F1 con cierre seguro y pruebas negativas.
  Necesidad: media; urgencia: baja; valor: alto; desbloqueo: las lecciones y la evidencia de Savia Viva se sirven desde Vaults; esfuerzo: SE-489 decisión; SE-486 media.

- **S14 · P2 · fase D** — Higiene de contexto, instalación y operación
  Acción: SE-448 S0 y canario; SE-449 regla y lectura en el tribunal; SE-450 auditoría de instaladores; SE-454 invariantes negativos como tests; SE-465 y SE-466 dependencias sin fijar y avisos OSV. SE-472 solo si el bucle nocturno que gobierna sigue en uso. SE-472 se retira si ese bucle ya no se usa. SE-464 sin dependientes: se decide al llegar; SE-506 aplazada.
  Entrada: Specs aprobadas salvo SE-464 (PROPOSED) y SE-506 (aplazada); se ejecutan por separado, una por vez; sin hueco WIP nuevo.
  Salida: Cada slice publica su evidencia (render, tribunal, auditoría) y no activa nada por defecto sin medición. Los invariantes de SE-454 llevan caso negativo y declaran lo que no demuestran.
  Necesidad: media; urgencia: baja; valor: medio; desbloqueo: reduce superficie sin bloquear otras fases; esfuerzo: slices pequeños independientes.

- **S21 · P2 · fase D** — Verificación honesta tras la revisión de Anthropic Research
  Acción: SE-476: acuerdo de jueces del mismo proveedor como correlacionado y autorrevisión fuera de la verificación. SE-477: IC, diferencia pareada y censura en comparativas. SE-479: casos imposibles dentro del alcance con control posible. SE-475 (clase del bloqueo) se hace dentro de SE-510.
  Entrada: Aprobación de SE-476, SE-477 y SE-479 por la operadora (PROPOSED); SE-475 queda absorbida por SE-510 (S26); SE-479 S3 después de SE-468 y SE-477; sin hueco WIP nuevo.
  Salida: Cada spec aprobada o descartada; las aprobadas con sus AC verificados, tests que fallan antes y pasan después, y paridad bash/TS donde aplica.
  Necesidad: media; urgencia: baja; valor: medio; desbloqueo: frena los rodeos ante bloqueos de política y evita contar como evidencia independiente lo que no lo es; SE-477 da la estadística que usan SE-469 y SE-479; esfuerzo: cuatro specs de slices pequeñas (S); SE-475 S2 y SE-479 S2 medianas.

- **S07 · P2 · fase D** — Kernel mínimo y portabilidad
  Acción: Ablación acotada F0 revisada; SAM F5/F6; runtime/canaries comunes y coste de complejidad. Curación de skills sólo si demuestra utilidad.
  Entrada: Gate C; revisión F0 antes de F1; ninguna retirada unilateral.
  Salida: Reducción sin regresiones ni autoridad ampliada; canaries por frontend/tier y decisión de simplificación.
  Necesidad: media; urgencia: media; valor: alto; desbloqueo: reduce coste de adopción; esfuerzo: probes antes de retirar componentes.

- **S08 · P2 · fase E** — Adopción y contexto de ficheros completo
  Acción: Instalación limpia/doctor; desktop y docs; Vaults adaptativo bajo evaluación. Files: serving/tus autenticado, snapshot/CAS, digest/citas/visor y lifecycle; después formatos remotos/media/email/conectores/Teams según demanda.
  Entrada: Gate D y autorización/revocación/scanner/restore de Files verificados. D08 S3 y paquetes Labs propuestos requieren aprobación; SE-289 S4 conforme ADR-002.
  Salida: Una persona ajena instala y usa un flujo seguro con citas y doctor verde; ampliar perfiles sólo tras conformance.
  Necesidad: media; urgencia: baja; valor: alto; desbloqueo: uso externo verificable; esfuerzo: un flujo de adopción y un perfil de formato cada vez.

- **S34 · P2 · fase D** — Savia Viva: un dominio con verificador externo y revalidación
  Acción: SE-515 S3–S4: una obligación comprobada por un verificador determinista en un gate existente, con el modelo instruido para ignorarla, y revalidación si cambian política, recurso o época de STOP entre el plan y el efecto.
  Entrada: S29 con GO; S23 con SE-493 y SE-498 implementadas en la ruta piloto; S28 con aprobación auténtica disponible.
  Salida: El efecto inválido se bloquea en la ruta cubierta aunque el modelo ignore la lección; garantía declarada por ruta; canario con retirada.
  Necesidad: condicionada; urgencia: baja; valor: por demostrar; desbloqueo: convierte una lección en garantía comprobable, o lo descarta con datos; esfuerzo: un dominio; medio.

- **S09 · P3 · fase F** — Piloto acotado y evidencia de valor
  Acción: AEK/AEOS en shadow antes de efectos; medir calidad, coste y atención humana; reevaluaciones Labs y prospectiva con decisiones reales. Hipótesis opcional del piloto (propuesta externa SE-516 del 2026-11-09, evaluada como solape y sin ID): comparar, dentro del mismo techo de autoridad y sobre clases de trabajo de efecto equivalente, la supervisión actual con una variante de más verificación automática; vector calidad verificada/coste observado/tiempo/riesgo, y atención humana solo si hay observación consentida; salida KEEP_BASELINE, MORE_EVIDENCE, RECOMMEND_REVIEW o NO_GO. Una recomendación no concede ni cambia permisos.
  Entrada: Gates A-E; un piloto y una línea Labs; consentimiento, target/verifier/recovery/stop y autoridad específica. Para la hipótesis de supervisión: SE-515 S1 publicada (ablación P10), SE-477 aprobada o su equivalente en el informe, y una fuente de atención con consentimiento; si faltan, la hipótesis se queda en NO_GO documental.
  Salida: Resultado positivo o negativo trazable y decisión de mantener/simplificar; sin claim de ROI con datos sintéticos. Si la hipótesis se ensayó: informe con IC pareado y censura, dos clases de trabajo como máximo, o su cierre NO_GO por falta de fuentes; sin ROI con datos sintéticos ni elección de modalidad que exija un permiso inexistente.
  Necesidad: condicionada; urgencia: baja; valor: por demostrar; desbloqueo: justifica expansión futura; esfuerzo: presupuesto/corpus por piloto.

## Iniciativas aprobadas o en curso

Integrada en main no significa graduada; delivery no sustituye completion y revisión humana.

- SE-376 [IMPLEMENTING] Quality Debt Burn-down — evidencia: 2026-09-27: el 133→48 de #1097 era inflado (121 tests de presencia en #1097 y 5 en #1100, score 23; 130 skills marcadas stable sin evidencia). Criterio endurecido: Calibrated exige test certificado >=80. Deuda real 128/137 (incluye 3 skills GRC de #1142); vuelta a wave 0 (baseline 133). Objetivo final 0 o excepciones aprobadas pendiente.
- SE-392 [APPROVED] Runtime común de Savia para Codex y OpenCode — evidencia: Spec persistida; equivalencia funcional y E2E aún no demostradas.
- SE-395 [APPROVED] Savia Vaults Adaptive Connectivity — evidencia: PR #1122: aislamiento de grafo por dome. PR #1131: V02 de cache por principal/policy/contenido, provenance y límites mergeada con 349 tests SaviaVaults. Experimento adaptativo permanece pendiente.
- SE-396 [IMPLEMENTING] Harness operational integrity & verifiable substitution — evidencia: PRs #1112/#1113/#1122/#1129/#1130/#1131/#1132/#1133/#1135 mergeadas. H02/H10/A01b/A01c: autoridad previa al executor, composición aislada y sustitución operacional Codex/OpenCode. Auditoría AC local: docs/evidence/SE-396-closure-review-20260924.md; 127 tests dual-cli, 18 de planificación y gate canónico previo 6/6. Doctor nativo permanece DEGRADED_SAFE; recibo A01c requiere revisión de procedencia. Actualización 2026-09-30: #1183 integrado (5b03a196), canaries de sesión y validación de recibo implementados, sin ejecución real. Informe delta: docs/evidence/SE-396-closure-review-20260928.md.
- SE-398 [APPROVED] Savia Desktop Runtime & Surface Support — evidencia: docs/specs/SE-398-f0-desktop-runtime-discovery.md
- SE-399 [APPROVED] Savia Visual Installer & Environment Bootstrap — evidencia: docs/specs/SE-399-f0-installer-discovery.md
- SE-400 [APPROVED] Model-Agnostic Savia Ablation & Minimal Sufficient Kernel — evidencia: docs/specs/SE-400-f0-model-agnostic-ablation-inventory.md
- SE-401 [APPROVED] Intent-to-Effect Execution Architecture (I2E) — evidencia: docs/specs/SE-401-intent-to-effect-execution-architecture.spec.md
- SE-403 [APPROVED] Benchmark evidence: trazas, frontera, hash de selección — evidencia: PR #1171 mergeada 2026-09-28 sin review registrada; graduación pendiente de revisión humana (completion.human_review). Spec: docs/specs/SE-403-benchmark-evidence-frontier.spec.md · integrada #1171; revisar evidencia/graduación
- SE-404 [APPROVED] Proceso proporcional: G13 v2 y una corrección por revisión — evidencia: PR #1170 mergeada 2026-09-28 sin review registrada; graduación pendiente de revisión humana (completion.human_review). Spec: docs/specs/SE-404-proportional-process-gates.spec.md · integrada #1170; revisar evidencia/graduación
- SE-408 [APPROVED] Automatización móvil por árbol de accesibilidad (mobile-mcp) bajo soberanía — evidencia: docs/specs/SE-408-mobile-accessibility-automation.spec.md
- SE-409 [APPROVED] Bucle experiencia → skill con curación y retirada — evidencia: docs/specs/SE-409-experience-to-skill-loop.spec.md
- SE-426 [IMPLEMENTING] Firma de confidencialidad con secreto de CI y HMAC siempre verificado — evidencia: docs/specs/SE-426-confidentiality-hmac-ci-key.spec.md
- SE-428 [IMPLEMENTING] Savia Space como sustituto de OpenCode, con OpenCode como motor — evidencia: docs/specs/SE-428-savia-space-orchestrator-opencode-engine.spec.md
- SE-429 [APPROVED] Savia Space interoperable: API con JWT y OpenAPI, MCP y A2A — evidencia: docs/specs/SE-429-savia-space-interop-api-mcp-a2a.spec.md
- SE-430 [APPROVED] Savia Space Mobile: cliente Android de Savia Space — evidencia: docs/specs/SE-430-savia-space-mobile.spec.md
- SE-431 [APPROVED] Savia Soul: la Savia proactiva dentro de Savia Space — evidencia: docs/specs/SE-431-savia-soul.spec.md
- SE-432 [APPROVED] Savia Space: escritorio infinito y experiencia — evidencia: docs/specs/SE-432-savia-space-infinite-desktop-experience.spec.md
- SE-433 [APPROVED] merge-sprint: merges autónomos bajo autorización humana previa — evidencia: docs/specs/SE-433-merge-sprint.spec.md
- SE-434 [APPROVED] Savia Space: modo mediado con sandbox propio como frontera — evidencia: docs/specs/SE-434-savia-space-mediated-sandbox.spec.md
- SE-435 [APPROVED] Savia Space: distribución agnóstica (paquetes nativos y savia-space setup) — evidencia: docs/specs/SE-435-savia-space-distribution.spec.md
- SE-436 [APPROVED] Savia Space: proyectos y cúpulas desde Space — evidencia: docs/specs/SE-436-savia-space-projects-and-domes.spec.md
- SE-439 [APPROVED] Savia Space: sesión gráfica agéntica sobre Linux — evidencia: docs/specs/SE-439-savia-space-agentic-session.spec.md
- SE-442 [APPROVED] Cadena de suministro de la CI: acciones fijadas por SHA, Dependabot, CodeQL, Scorecard y divulgación coordinada — evidencia: docs/specs/SE-442-ci-supply-chain-hardening.spec.md
- SE-443 [APPROVED] Gobierno de conectores MCP: malware de paquetes, secretos tipados, importación, política por herramienta y doctrina de diseño — evidencia: docs/specs/SE-443-mcp-connector-governance.spec.md
- SE-444 [APPROVED] Autoridad del verificador en los criterios de aceptación y cobertura no verificada explícita — evidencia: docs/specs/SE-444-verifier-authority-ac-closure.spec.md
- SE-445 [APPROVED] Salvaguardas de ejecución autónoma: repetición bloqueante, presupuesto de turnos, revisor de acciones y criterio de éxito — evidencia: docs/specs/SE-445-autonomous-execution-safeguards.spec.md
- SE-446 [APPROVED] Canal de aprobación inalcanzable para el agente: prueba de autoaprobación y mitigación — evidencia: docs/specs/SE-446-approval-channel-agent-unreachable.spec.md
- SE-447 [APPROVED] Contexto acotado en sesiones largas: una sola captura viva, tope absoluto de compactación y clasificación de acciones de riesgo — evidencia: docs/specs/SE-447-bounded-context-long-sessions.spec.md
- SE-448 [APPROVED] Fuga por salida de contenido externo: token canario, lista de destinos de URL e ID estable de hallazgos — evidencia: docs/specs/SE-448-external-content-leak-canary-urls.spec.md
- SE-449 [APPROVED] Estado epistémico en hallazgos e informes: observado, derivado, inferido, desconocido — evidencia: docs/specs/SE-449-epistemic-status-in-reports.spec.md
- SE-450 [APPROVED] Instaladores aditivos e idempotentes y propiedad de procesos con identidad de arranque — evidencia: docs/specs/SE-450-installer-and-process-ownership-hygiene.spec.md
- SE-451 [APPROVED] Gobernanza de contribuciones: DCO frente a CLA y metadatos de licencia por fichero — evidencia: docs/specs/SE-451-contribution-governance-dco.spec.md
- SE-452 [APPROVED] Suite de conformidad ejecutable publicada junto a cada contrato de interoperabilidad — evidencia: docs/specs/SE-452-contract-conformance-suites.spec.md
- SE-453 [APPROVED] Contrato de resultado de los gates: limpio, hallazgos y desconocido — evidencia: docs/specs/SE-453-gate-result-contract.spec.md
- SE-454 [APPROVED] Invariantes negativos como tests sobre fuentes sensibles y aserción de red en analizadores — evidencia: docs/specs/SE-454-negative-invariant-tests.spec.md
- SE-465 [APPROVED] Dependencias de instalación sin fijar: imágenes, instaladores remotos, npm y pip — evidencia: docs/specs/SE-465-pinned-install-dependencies.spec.md
- SE-466 [APPROVED] 214 avisos OSV en los lockfiles y una auditoría de CI que no puede fallar — evidencia: docs/specs/SE-466-dependency-vulnerability-triage.spec.md
- SE-467 [APPROVED] El auditor de tests puntúa el idioma del nombre, no el caso probado — evidencia: docs/specs/SE-467-auditor-language-bias.spec.md
- SE-458 [APPROVED] Presupuesto de atención humana: tope de PRs esperando revisión, lotes y prioridad — evidencia: docs/specs/SE-458-human-review-attention-budget.spec.md
- SE-459 [APPROVED] Aprobaciones contestables: tarjeta de aprobación en lenguaje llano — evidencia: docs/specs/SE-459-contestable-approval-card.spec.md
- SE-460 [APPROVED] Reactivación revalidada: automatizaciones y memoria con vigencia, procedencia y autoridad — evidencia: docs/specs/SE-460-revalidated-reactivation-context.spec.md
- SE-461 [APPROVED] Composición de efectos: combinaciones prohibidas en contratos de Yema y pruebas negativas — evidencia: docs/specs/SE-461-effect-composition-contracts.spec.md
- SE-462 [APPROVED] Leer no implica poder retransmitir: marca de sesión tras leer una cúpula N2+ — evidencia: docs/specs/SE-462-read-is-not-relay.spec.md
- SE-463 [APPROVED] Cobertura de supervisión: reconciliar llamadas con lo que vieron los guards y fallar cerrado — evidencia: docs/specs/SE-463-supervision-coverage-reconciliation.spec.md
- SE-455 [APPROVED] Ingeniería inversa para la soberanía tecnológica: REA como herramienta externa opcional con puerta de autorización — evidencia: docs/specs/SE-455-reverse-engineering-sovereignty.spec.md
- SE-456 [APPROVED] Tests que no pueden fallar: detector de vacuidad y criterio de evidencia de REA en la QA — evidencia: docs/specs/SE-456-test-vacuity-evidence-criteria.spec.md
- SE-457 [APPROVED] Skill harness-architecture: arquitectura de harness, metaharness, flujos largos, bucles y sprints — evidencia: docs/specs/SE-457-harness-architecture-skill.spec.md
- SE-468 [APPROVED] El gate de evals debe poder fallar — evidencia: docs/specs/SE-468-honest-evals-gate.spec.md
- SE-469 [APPROVED] Tribunales medidos con sus propios golden sets — evidencia: docs/specs/SE-469-tribunal-golden-set-live-runs.spec.md
- SE-470 [APPROVED] Integridad de los artefactos de evaluación — evidencia: docs/specs/SE-470-eval-artifact-integrity.spec.md
- SE-471 [APPROVED] Relevo nocturno con evidencia: declarado, validado y aceptado — evidencia: docs/specs/SE-471-overnight-handoff-evidence-digest.spec.md
- SE-472 [APPROVED] Vigencia de la autoridad comprobada antes de cada tarea nocturna — evidencia: docs/specs/SE-472-overnight-per-task-authority-check.spec.md
- SE-473 [APPROVED] Lecciones contrastables: ámbito, evidencia, revalidación y refutación — evidencia: docs/specs/SE-473-contestable-lessons.spec.md
- SE-480 [APPROVED] Vaults: RAG autónomo (recarga del registro y sincronización por el servicio) — evidencia: docs/specs/SE-480-vaults-rag-autonomous.spec.md
- SE-481 [APPROVED] Vaults: clasificación con cierre seguro y polaridad en la búsqueda léxica — evidencia: docs/specs/SE-481-vaults-classification-fail-closed.spec.md
- SE-485 [APPROVED] Vaults: cinco fallos de la auditoría SVTC-00 — evidencia: docs/specs/SE-485-vaults-audit-fixes.spec.md
- SE-487 [APPROVED] Clon limpio neutral y arranque en Windows — evidencia: docs/specs/SE-487-clean-clone-neutral-and-windows.spec.md
- SE-483 [APPROVED] Identidad: Savia, metaorquestadora agéntica de I+D+i — evidencia: docs/specs/SE-483-savia-identity-rd-metaorchestrator.spec.md
- SE-484 [APPROVED] Onboarding adaptativo: Savia se configura para cualquier persona — evidencia: docs/specs/SE-484-adaptive-onboarding.spec.md
- SE-488 [IMPLEMENTING] Aprobaciones por fusión de PR (operación solo móvil) — evidencia: docs/specs/SE-488-approvals-by-pr-merge.spec.md
- SE-489 [APPROVED] Vaults: recuperación adaptativa construida y medida (estructura, grafo, reranker, router y cuantización) — evidencia: docs/specs/SE-489-vaults-adaptive-retrieval-empirical.spec.md
- SE-490 [APPROVED] Soul Continuidad v1: gemelo operativo en el portátil de trabajo, de solo lectura y con comunicación bidireccional — evidencia: docs/specs/SE-490-soul-continuity-work-laptop.spec.md
- SE-496 [APPROVED] Ontología operativa gobernada: la autoridad vive fuera del modelo — evidencia: docs/specs/SE-496-governed-operational-ontology-authority.spec.md
- SE-500 [APPROVED] Merge-sprint sin realineación manual: fragmentos de planificación, integración en línea y plan ordenado — evidencia: docs/specs/SE-500-merge-sprint-sin-realineacion.spec.md
- SE-498 [APPROVED] STOP global y revocación entre ejecutores — evidencia: docs/specs/SE-498-global-stop-cross-executor-revocation.spec.md
- SE-501 [APPROVED] Derivados fuera de las PR: firma de confidencialidad, SAM y manifiesto de reglas generados en main — evidencia: docs/specs/SE-501-derivados-fuera-de-las-pr.spec.md
- SE-504 [APPROVED] Savia usable: una app como la de Claude o ChatGPT, conectada a Soul y Space — evidencia: docs/specs/SE-504-savia-usable-conversacion-documentos-contexto.spec.md
- SE-505 [APPROVED] Puerta de comprensión: escenas confirmadas antes de la spec, prototipo antes del código — evidencia: docs/specs/SE-505-puerta-de-comprension.spec.md
- SE-508 [APPROVED] Guard previo para tools MCP con escritura y para WebFetch — evidencia: docs/specs/SE-508-mcp-webfetch-pretooluse-guard.spec.md
- SE-510 [APPROVED] Guardas sin bloqueos falsos y un despachador por evento — evidencia: docs/specs/SE-510-guardas-sin-bloqueos-falsos-despachador.spec.md
- SE-511 [IMPLEMENTING] Contexto fijo por turno a la mitad o menos — evidencia: docs/specs/SE-511-contexto-fijo-por-turno-a-la-mitad.spec.md
- SE-512 [APPROVED] Grant de política para el sprint nocturno — evidencia: docs/specs/SE-512-grant-de-politica-nocturno.spec.md
- SE-513 [APPROVED] Admisión duradera de cambios de intención y comprobación previa — evidencia: docs/specs/SE-513-admision-duradera-y-comprobacion-previa.spec.md
- SE-514 [APPROVED] Atención humana: una sola cola de preguntas, con su porqué — evidencia: docs/specs/SE-514-atencion-humana-cola-unica.spec.md
- SE-515 [APPROVED] Aprendizaje aplicado: de la lección recuperada a la obligación comprobada — evidencia: docs/specs/SE-515-aprendizaje-aplicado-obligacion-comprobada.spec.md
- SE-517 [APPROVED] Motor de Space con suscripción ChatGPT (OAuth) — evidencia: docs/specs/SE-517-space-motor-suscripcion-chatgpt-oauth.spec.md
- SE-518 [APPROVED] Pulse: el latido de la planta de trabajo — evidencia: docs/specs/SE-518-pulse-latido.spec.md
- SE-527 [APPROVED] Recorte de agentes sobrantes (14 de 90, en cuatro slices) — evidencia: docs/specs/SE-527-recorte-de-agentes-sobrantes.spec.md
- SE-528 [APPROVED] Tres arreglos de seguridad: web, puente y cúpulas — evidencia: docs/specs/SE-528-seguridad-web-puente-cupulas.spec.md
- SE-530 [APPROVED] Hecho verificado: ningún trabajo se da por bueno por su propia palabra — evidencia: docs/specs/SE-530-hecho-verificado.spec.md
- SE-531 [APPROVED] Ficha de harness ejecutable: capacidades del runtime y supervisión del proceso hijo — evidencia: docs/specs/SE-531-ficha-de-harness-ejecutable.spec.md
- SE-532 [APPROVED] Catálogo de agentes con esquema, referencias comprobadas y retirada explícita (3 slices) — evidencia: docs/specs/SE-532-catalogo-de-agentes-con-esquema-y-retirada.spec.md
