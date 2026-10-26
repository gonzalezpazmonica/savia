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
  Entrada: Aprobación de SE-442 y decisión D1-D3. Al implementarse ocupa hueco WIP o se ejecuta como mantenimiento acotado por decisión expresa; no depende de otras iniciativas. Delta S5: decisión D4 sobre torch.
  Salida: Test BATS verde con caso negativo, todas las acciones por SHA, Dependabot semanal agrupado, primeros runs de CodeQL y Scorecard enlazados como evidencia; ninguna alerta silenciada sin causa raíz. Delta S5: lock con hashes verificado por test y CI sin pip install suelto salvo la excepción registrada.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: protege cada PR de la cola; esfuerzo: slice pequeño (S).

- **S18 · P0 · fase A** — Evals que pueden fallar
  Acción: SE-468: resultado unknown mientras el runner no ejecute el artefacto, sin placeholder 0,80 en modo vivo, sin PASS sin baseline y prueba de sabotaje que debe dar findings.
  Entrada: Aprobación de SE-468 y decisión D1 (motivos de hueco en SE-453); sin dependencias abiertas.
  Salida: Con la skill saboteada el gate no da PASS; modo vivo sin juez sale ≠0; el comentario de la PR distingue evaluado de no evaluado; tests con caso negativo.
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
  Entrada: Aprobación de SE-444; informe-only, compatible con lo ya integrado.
  Salida: Informe de cobertura no verificada visible, predicado de cierre sin cambios (regresión a cero) y decisión explícita sobre pasar a bloqueo con datos de dos cierres reales.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: hace honestos los cierres de S03 y S04; esfuerzo: slice pequeño (S).

- **S04 · P0 · fase B** — Graduación operacional del harness
  Acción: Ejecutar H04 con autorización específica; revisión humana H09 y procedencia A01c; actualizar completion por AC y decidir cierre.
  Entrada: Baseline A demostrado; H04 real requiere autorización y coste; sin autograduación.
  Salida: H04/H09 y regresión operacional documentadas; completion y revisión humana; límites L3/L4 intactos.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: abre frontera TEE/AEK; esfuerzo: 4-8 h de análisis compartido históricamente estimadas; costes de canaries a acordar.

- **S12 · P1 · fase A** — Salvaguardas de ejecución autónoma
  Acción: Guard de repetición bloqueante en ramas agent/*, presupuesto de turnos visible, success_checks en automatizaciones; revisor de acciones opt-in como último slice.
  Entrada: Aprobación de SE-445; doble opt-in (SPEC-186) para el revisor; probado en los dos frontends.
  Salida: Las tres repeticiones bloquean en agent/*, el agente ve su presupuesto, las automatizaciones declaran éxito, y el revisor falla cerrado en tiers 3/4.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: hace cumplir autonomous-safety donde hoy es texto; esfuerzo: S1, S2 y S4 pequeños; S3 medio.

- **S17 · P1 · fase A** — Contrato de resultado de los gates
  Acción: S0 auditar escáneres y guards blocking (vocabulario, dependencia ausente, topes); contrato que extiende checker-fail-closed; guards sin jq degradan a grep o salen 2; topes que producen unknown.
  Entrada: Aprobación de SE-453 y decisión D1-D3; S2 probado en los dos frontends.
  Salida: Auditoría publicada, contrato con tabla de correspondencia, guards blocking que no salen 0 sin evaluar, test de dependencia ausente en no-verde y contador baseline de unknown congelado.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: evita falsos verdes en los gates de los que dependen merge-sprint y la CI; alimenta la cobertura no verificada de SE-444; esfuerzo: S0, S1 y S2 pequeños; S3 medio.

- **S19 · P1 · fase A** — Medir jueces y relevos antes de confiar en ellos
  Acción: SE-469: 30 casos de los golden sets en vivo con tope de gasto e IC95 por tribunal. SE-471: digest de solo lectura del relevo nocturno en declarado/validado/aceptado con tope de decisiones.
  Entrada: Aprobación de cada spec; SE-469 después de SE-468; sin hueco WIP nuevo (SE-471 es solo lectura).
  Salida: Informe de concordancia con IC95 y decisión según kill criterion; digest con tests negativos y medición de OK no validados; retirada si no reduce el tiempo de relevo.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: da el primer dato de acierto de los tribunales que pesan en merges y separa el OK autodeclarado de lo validado; esfuerzo: SE-469 medio (M); SE-471 pequeño (S); independientes.

- **S16 · P1 · fase A** — Decisión de gobernanza de contribuciones
  Acción: Decidir DCO, CLA o ninguno; si DCO, texto en CONTRIBUTING y workflow sin checkout de código del PR; REUSE solo si hay demanda.
  Entrada: Decisión D1-D4 de la operadora; un CLA de relicenciación contradiría LICENSE-ENTERPRISE.md y exige antes spec propia con revisión legal.
  Salida: Decisión registrada; si DCO, check activo con exención documentada y mensaje claro para quien contribuye.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: cada contribución externa sin constancia no se puede recuperar después; esfuerzo: decisión + slice pequeño (S).

- **S13 · P1 · fase B** — Seguridad del canal de aprobación y de los conectores de Space
  Acción: SE-446 S0: sonda de autoaprobación contra el space-server real. SE-443 S1-S2: doctrina de diseño MCP y comprobación de malware al habilitar; S3-S5 cuando space-server lo permita.
  Entrada: Aprobación de SE-446 y SE-443; usa el hueco temporal de SE-428 (no abre otra iniciativa en curso); si S0 encuentra una vía abierta, S1 de SE-446 pasa a P0 y adelanta a todo lo demás de Space.
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
  Entrada: Aprobación de cada spec; se ejecutan por separado, uno por vez; sin hueco WIP nuevo.
  Salida: Cada slice publica su evidencia (render, tribunal, auditoría) y no activa nada por defecto sin medición. Los invariantes de SE-454 llevan caso negativo y declaran lo que no demuestran.
  Necesidad: media; urgencia: baja; valor: medio; desbloqueo: reduce superficie sin bloquear otras fases; esfuerzo: cinco slices pequeños independientes.

- **S20 · P2 · fase D** — Integridad de evaluación, vigencia nocturna y lecciones revocables
  Acción: SE-470: etiqueta eval-integrity en CI y detector determinista de trazas. SE-472: check de grant antes de cada tarea del bucle nocturno. SE-473 S0: medir lecciones sin ámbito, evidencia ni fecha.
  Entrada: Aprobación de cada spec; SE-470 condicionada a H3/H4; SE-472 a SE-343; SE-473 S1-S2 al resultado de S0.
  Salida: Cada slice publica su medición y sus tests con caso negativo; nada pasa a bloqueo sin datos.
  Necesidad: media; urgencia: baja; valor: medio; desbloqueo: cierra vectores documentados fuera pero no observados aún; cada slice decide si sube o se mata; esfuerzo: tres slices pequeños independientes; SE-473 S2 medio.

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
  Entrada: Aprobación de SE-447; S2 y S4 esperan a que SE-439 salga de F0.
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
- SE-403 [APPROVED] Benchmark evidence: trazas, frontera, hash de selección — evidencia: PR #1171 mergeada 2026-09-28 sin review registrada; graduación pendiente de revisión humana (completion.human_review). Spec: docs/specs/SE-403-benchmark-evidence-frontier.spec.md · integrada #1171; revisar evidencia/graduación
- SE-404 [APPROVED] Proceso proporcional: G13 v2 y una corrección por revisión — evidencia: PR #1170 mergeada 2026-09-28 sin review registrada; graduación pendiente de revisión humana (completion.human_review). Spec: docs/specs/SE-404-proportional-process-gates.spec.md · integrada #1170; revisar evidencia/graduación
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
- SE-444 [APPROVED] Autoridad del verificador en los criterios de aceptación y cobertura no verificada explícita — evidencia: docs/specs/SE-444-verifier-authority-ac-closure.spec.md
- SE-445 [APPROVED] Salvaguardas de ejecución autónoma: repetición bloqueante, presupuesto de turnos, revisor de acciones y criterio de éxito — evidencia: docs/specs/SE-445-autonomous-execution-safeguards.spec.md
- SE-451 [APPROVED] Gobernanza de contribuciones: DCO frente a CLA y metadatos de licencia por fichero — evidencia: docs/specs/SE-451-contribution-governance-dco.spec.md
- SE-453 [APPROVED] Contrato de resultado de los gates: limpio, hallazgos y desconocido — evidencia: docs/specs/SE-453-gate-result-contract.spec.md
- SE-455 [APPROVED] Ingeniería inversa para la soberanía tecnológica: REA como herramienta externa opcional con puerta de autorización — evidencia: docs/specs/SE-455-reverse-engineering-sovereignty.spec.md
- SE-456 [APPROVED] Tests que no pueden fallar: detector de vacuidad y criterio de evidencia de REA en la QA — evidencia: docs/specs/SE-456-test-vacuity-evidence-criteria.spec.md
