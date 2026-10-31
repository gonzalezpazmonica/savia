# Roadmap Current (GENERATED — no editar; fuente: planning-state.json)

Fase A · WIP 4/4. Estado y cola canónicos; ADR-002.

## Cola de sesiones (orden por gates, sin fechas)

- **S01 · P0 · fase A** — Estado consistente y baseline reproducible
  Acción: Hecho: SE-407 S1–S4 integrados (#1208–#1210, #1214) e IMPLEMENTED; SE-425 (#1220) cierra el hueco de lockfiles. Siguiente: mantener validate-ci-local como predicado.
  Entrada: Disponible dentro del WIP actual; no ampliar superficie.
  Salida: Predicado único reproducible, artefactos frescos, fallos desglosados con RCA y recibo de cierre; ninguna suite fallida ocultada.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: desbloquea todo el cierre; esfuerzo: slice pequeño; baseline variable.

- **S10 · P0 · fase A** — Cadena de suministro de la CI
  Acción: Fijar a SHA las 20 referencias uses: sueltas, test BATS que falle ante nuevas, Dependabot de acciones, CodeQL y Scorecard sin silenciar alertas, y política de divulgación con plazo. Delta S5: lock con hashes y --require-hashes para lo que instala install-memory-deps.sh y para los pip install sin fijar de la CI.
  Entrada: SE-442 ya APPROVED; falta la decisión D1-D3. Al implementarse ocupa hueco WIP o se ejecuta como mantenimiento acotado por decisión expresa; no depende de otras iniciativas. Delta S5: decisión D4 sobre torch.
  Salida: Test BATS verde con caso negativo, todas las acciones por SHA, Dependabot semanal agrupado, primeros runs de CodeQL y Scorecard enlazados como evidencia; ninguna alerta silenciada sin causa raíz. Delta S5: lock con hashes verificado por test y CI sin pip install suelto salvo la excepción registrada.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: protege cada PR de la cola; esfuerzo: slice pequeño (S).

- **S18 · P0 · fase A** — Evals que pueden fallar
  Acción: SE-468: resultado unknown mientras el runner no ejecute el artefacto, sin placeholder 0,80 en modo vivo, sin PASS sin baseline y prueba de sabotaje que impide declarar evaluado un dataset (AC7 condicional; el findings con sabotaje es criterio de salida de SE-469).
  Entrada: SE-468 ya APPROVED (operadora, 2026-10-26); falta la decisión D1 (motivos de hueco en SE-453); sin dependencias abiertas.
  Salida: Con la skill saboteada el gate nunca da PASS ni declara el dataset evaluado: sin ejecutor real el resultado es unknown (AC7 condicional, decisión de la operadora 2026-10-26); modo vivo sin juez sale ≠0; el comentario de la PR distingue evaluado de no evaluado; tests con caso negativo.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: quita una garantía falsa de cada PR de skills, agentes y hooks; desbloquea SE-381 y SE-469; esfuerzo: slice pequeño (S).

- **S02 · P0 · fase A** — Seguridad, evidencia y cierre de Vaults/Files
  Acción: Hecho: Files/Vaults base IMPLEMENTED (SE-410–422, SE-412 con AC3 aceptado), SE-424, SE-423 (#1216, #1218) y SE-425 (#1220: lockfiles y CI de savia-vaults).
  Entrada: Revisión/diseño ahora; ejecutar delta nuevo sólo con aprobación y hueco WIP. Streaming/HTTP (SE-421/422, ya integrados) exige autorización vigente y revocación: revisar en este lote. Pendientes privados de evaluación/operación se consultan sólo en Labs.
  Salida: Matriz entrega vs evidencia vs pendiente; decisión humana de graduación por spec; delta de identidad acotado y revisable, sin activar SSO ni conceder authority de efectos.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: protege contexto y serving; esfuerzo: revisión por lote; delta a estimar tras probe.

- **S03 · P0 · fase A** — Deuda de calidad con pruebas de comportamiento
  Acción: Remedir deuda certificada y elegir el siguiente grupo por riesgo/uso; conservar umbral >=80 y ratchet; usar #1180 como evidencia de entrega, no como cierre de toda la wave.
  Entrada: WIP actual; inventario actualizado; aprobación de avance de wave cuando corresponda.
  Salida: Reducción de deuda demostrada por comportamiento discriminante, baseline publicado y excepciones explícitas; no certificar por presencia de ficheros.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: hace fiables los gates; esfuerzo: grupo pequeño; no prometer cierre de 128 skills por sesión.

- **S11 · P0 · fase A** — Autoridad del verificador en el cierre
  Acción: Regla y plantilla con autoridad requerida y obtenida por AC; informe de cobertura no verificada en validate-ci-local sin cambiar el predicado.
  Entrada: SE-444 ya APPROVED; informe-only, compatible con lo ya integrado.
  Salida: Informe de cobertura no verificada visible, predicado de cierre sin cambios (regresión a cero) y decisión explícita sobre pasar a bloqueo con datos de dos cierres reales.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: hace honestos los cierres de S03 y S04; esfuerzo: slice pequeño (S).

- **S04 · P0 · fase B** — Graduación operacional del harness
  Acción: Ejecutar H04 con autorización específica; revisión humana H09 y procedencia A01c; actualizar completion por AC y decidir cierre.
  Entrada: Baseline A demostrado; H04 real requiere autorización y coste; sin autograduación.
  Salida: H04/H09 y regresión operacional documentadas; completion y revisión humana; límites L3/L4 intactos.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: abre frontera TEE/AEK; esfuerzo: 4-8 h de análisis compartido históricamente estimadas; costes de canaries a acordar.

- **S12 · P1 · fase A** — Salvaguardas de ejecución autónoma
  Acción: Guard de repetición bloqueante en ramas agent/*, presupuesto de turnos visible, success_checks en automatizaciones; revisor de acciones opt-in como último slice.
  Entrada: SE-445 ya APPROVED; doble opt-in (SPEC-186) para el revisor; probado en los dos frontends.
  Salida: Las tres repeticiones bloquean en agent/*, el agente ve su presupuesto, las automatizaciones declaran éxito, y el revisor falla cerrado en tiers 3/4.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: hace cumplir autonomous-safety donde hoy es texto; esfuerzo: S1, S2 y S4 pequeños; S3 medio.

- **S17 · P1 · fase A** — Contrato de resultado de los gates
  Acción: S0 auditar escáneres y guards blocking (vocabulario, dependencia ausente, topes); contrato que extiende checker-fail-closed; guards sin jq degradan a grep o salen 2; topes que producen unknown.
  Entrada: SE-453 ya APPROVED; falta la decisión D1-D3; S2 probado en los dos frontends.
  Salida: Auditoría publicada, contrato con tabla de correspondencia, guards blocking que no salen 0 sin evaluar, test de dependencia ausente en no-verde y contador baseline de unknown congelado.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: evita falsos verdes en los gates de los que dependen merge-sprint y la CI; alimenta la cobertura no verificada de SE-444; esfuerzo: S0, S1 y S2 pequeños; S3 medio.

- **S19 · P1 · fase A** — Medir jueces y relevos antes de confiar en ellos
  Acción: SE-469: 30 casos de los golden sets en vivo con tope de gasto e IC95 por tribunal. SE-471: digest de solo lectura del relevo nocturno en declarado/validado/aceptado con tope de decisiones.
  Entrada: SE-469 y SE-471 ya APPROVED (operadora, 2026-10-27); SE-469 después de SE-468; sin hueco WIP nuevo (SE-471 es solo lectura).
  Salida: Informe de concordancia con IC95 y decisión según kill criterion; digest con tests negativos y medición de OK no validados; retirada si no reduce el tiempo de relevo.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: da el primer dato de acierto de los tribunales que pesan en merges y separa el OK autodeclarado de lo validado; esfuerzo: SE-469 medio (M); SE-471 pequeño (S); independientes.

- **S16 · P1 · fase A** — Decisión de gobernanza de contribuciones
  Acción: Decidir DCO, CLA o ninguno; si DCO, texto en CONTRIBUTING y workflow sin checkout de código del PR; REUSE solo si hay demanda.
  Entrada: Decisión D1-D4 de la operadora; un CLA de relicenciación contradiría LICENSE-ENTERPRISE.md y exige antes spec propia con revisión legal.
  Salida: Decisión registrada; si DCO, check activo con exención documentada y mensaje claro para quien contribuye.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: cada contribución externa sin constancia no se puede recuperar después; esfuerzo: decisión + slice pequeño (S).

- **S13 · P1 · fase B** — Seguridad del canal de aprobación y de los conectores de Space
  Acción: SE-446 S0: sonda de autoaprobación contra el space-server real. SE-443 S1-S2: doctrina de diseño MCP y comprobación de malware al habilitar; S3-S5 cuando space-server lo permita.
  Entrada: Specs SE-446 y SE-443 aprobadas (2026-10-27); usa el hueco temporal de SE-428 (no abre otra iniciativa en curso); si S0 encuentra una vía abierta, S1 de SE-446 pasa a P0 y adelanta a todo lo demás de Space.
  Salida: Informe de sonda por vía, test permanente de que el agente no contesta su propio ask, comprobación OSV con recibo, secretos tipados rechazados en command/args/url.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: la política por herramienta presupone un canal de aprobación seguro; esfuerzo: S0 pequeño; S1-S2 pequeños; S3-S5 medianos.

- **S05 · P1 · fase B** — TEE v1.1 y frontera AEK en solo lectura
  Acción: Reescribir SE-401 a Sufficiency/Commitment/Outcome/Disposition/AuthorityLease; mapear issuer/EEP/evidence con L31 F0 y contrato común de tres frontends. Revisar entregas existentes de contratos/proceso.
  Entrada: SE-396 graduada; contrato/frontera y spec aprobados; Labs máximo una línea activa.
  Salida: Mapa revisado, exclusiones y bypass explícitos, pruebas negativas READ_ONLY, contrato EEP común; namespace AEK- ya decidido.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: evita duplicar autoridad; esfuerzo: F0 L31 8-16 h estimadas; implementación aparte.

- **S06 · P1 · fase C** — Un laboratorio de conformidad y benchmark
  Acción: Unificar matriz negativa, bypass, caos, receipts y replay; graduar cierres parciales; baseline con trazas/selección fijadas. Último slice: piloto de suite de conformidad ejecutable sobre un solo contrato (SE-452).
  Entrada: Gate B y corpus/contratos pinned; no ejecutar todos los experimentos Labs a la vez.
  Salida: Cero violaciones de invariantes bajo fallos en los tres frontends y cuatro niveles de replay; evidencia auditable.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: evidencia para portabilidad y pilotos; esfuerzo: slices por frontend/invariante.

- **S14 · P2 · fase D** — Higiene de contexto y operación
  Acción: SE-448 S0 (superficies de render) y canario; SE-449 regla y lectura en el tribunal; SE-450 auditoría de instaladores y locks con identidad. SE-448 S4 (defang) y categoría third-party-directive; SE-454 invariantes negativos como tests.
  Entrada: Specs ya aprobadas (2026-10-27); se ejecutan por separado, uno por vez; sin hueco WIP nuevo.
  Salida: Cada slice publica su evidencia (render, tribunal, auditoría) y no activa nada por defecto sin medición. Los invariantes de SE-454 llevan caso negativo y declaran lo que no demuestran.
  Necesidad: media; urgencia: baja; valor: medio; desbloqueo: reduce superficie sin bloquear otras fases; esfuerzo: cinco slices pequeños independientes.

- **S20 · P2 · fase D** — Integridad de evaluación, vigencia nocturna y lecciones revocables
  Acción: SE-470: etiqueta eval-integrity en CI y detector determinista de trazas. SE-472: check de grant antes de cada tarea del bucle nocturno. SE-473 S0: medir lecciones sin ámbito, evidencia ni fecha.
  Entrada: SE-470, SE-472 y SE-473 ya APPROVED (operadora, 2026-10-27); de SE-473 solo S0, S1-S2 necesitan nueva aprobación tras el resultado de S0; SE-470 condicionada a H3/H4; SE-472 a SE-343.
  Salida: Cada slice publica su medición y sus tests con caso negativo; nada pasa a bloqueo sin datos.
  Necesidad: media; urgencia: baja; valor: medio; desbloqueo: cierra vectores documentados fuera pero no observados aún; cada slice decide si sube o se mata; esfuerzo: tres slices pequeños independientes; SE-473 S2 medio.

- **S21 · P2 · fase D** — Verificación honesta tras la revisión de Anthropic Research
  Acción: SE-475: prefijo FORMA/POLÍTICA en los bloqueos de hook con biblioteca bash+TS. SE-476: acuerdo de jueces del mismo proveedor como correlacionado y autorrevisión fuera de la verificación. SE-477: IC, diferencia pareada y censura en comparativas. SE-479: casos imposibles dentro del alcance con control posible.
  Entrada: Aprobación de SE-475, SE-476, SE-477 y SE-479 por la operadora (las cuatro PROPOSED); SE-479 S3 después de SE-468 y SE-477; sin hueco WIP nuevo.
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

- **S15 · P2 · fase E** — Contexto acotado de la sesión gráfica
  Acción: Medir tokens con y sin retirada de capturas, tope absoluto de compactación por tier, y después la herramienta de captura y la clasificación de acciones.
  Entrada: Spec SE-447 aprobada (2026-10-27); S2 y S4 esperan a que SE-439 salga de F0.
  Salida: Medición publicada, tope configurable sin nombres de modelo en la fuente y test de una sola imagen viva.
  Necesidad: media; urgencia: baja; valor: medio; desbloqueo: abarata sesiones largas de Space; esfuerzo: S1 y S3 pequeños; S2 y S4 tras SE-439 F0.

- **S09 · P3 · fase F** — Piloto acotado y evidencia de valor
  Acción: AEK/AEOS en shadow antes de efectos; medir calidad, coste y atención humana; reevaluaciones Labs y prospectiva con decisiones reales.
  Entrada: Gates A-E; un piloto y una línea Labs; consentimiento, target/verifier/recovery/stop y autoridad específica.
  Salida: Resultado positivo o negativo trazable y decisión de mantener/simplificar; sin claim de ROI con datos sintéticos.
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
- SE-489 [APPROVED] Vaults: recuperación adaptativa construida y medida (estructura, grafo, reranker, router y cuantización) — evidencia: docs/specs/SE-489-vaults-adaptive-retrieval-empirical.spec.md
