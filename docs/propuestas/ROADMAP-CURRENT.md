# Roadmap Current (GENERATED — no editar; fuente: planning-state.json)

Fase A · WIP 4/4. Estado y cola canónicos; ADR-002.

## Cola de sesiones (orden por gates, sin fechas)

- **S01 · P0 · fase A** — Estado consistente y baseline reproducible
  Acción: Hecho: SE-407 S1–S4 integrados (#1208–#1210, #1214) e IMPLEMENTED; SE-425 (#1220) cierra el hueco de lockfiles. Siguiente: mantener validate-ci-local como predicado.
  Entrada: Disponible dentro del WIP actual; no ampliar superficie.
  Salida: Predicado único reproducible, artefactos frescos, fallos desglosados con RCA y recibo de cierre; ninguna suite fallida ocultada.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: desbloquea todo el cierre; esfuerzo: slice pequeño; baseline variable.

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

- **S04 · P0 · fase B** — Graduación operacional del harness
  Acción: Ejecutar H04 con autorización específica; revisión humana H09 y procedencia A01c; actualizar completion por AC y decidir cierre.
  Entrada: Baseline A demostrado; H04 real requiere autorización y coste; sin autograduación.
  Salida: H04/H09 y regresión operacional documentadas; completion y revisión humana; límites L3/L4 intactos.
  Necesidad: alta; urgencia: alta; valor: alto; desbloqueo: abre frontera TEE/AEK; esfuerzo: 4-8 h de análisis compartido históricamente estimadas; costes de canaries a acordar.

- **S05 · P1 · fase B** — TEE v1.1 y frontera AEK en solo lectura
  Acción: Reescribir SE-401 a Sufficiency/Commitment/Outcome/Disposition/AuthorityLease; mapear issuer/EEP/evidence con L31 F0 y contrato común de tres frontends. Revisar entregas existentes de contratos/proceso.
  Entrada: SE-396 graduada; contrato/frontera y spec aprobados; Labs máximo una línea activa.
  Salida: Mapa revisado, exclusiones y bypass explícitos, pruebas negativas READ_ONLY, contrato EEP común; namespace AEK- ya decidido.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: evita duplicar autoridad; esfuerzo: F0 L31 8-16 h estimadas; implementación aparte.

- **S06 · P1 · fase C** — Un laboratorio de conformidad y benchmark
  Acción: Unificar matriz negativa, bypass, caos, receipts y replay; graduar cierres parciales; baseline con trazas/selección fijadas.
  Entrada: Gate B y corpus/contratos pinned; no ejecutar todos los experimentos Labs a la vez.
  Salida: Cero violaciones de invariantes bajo fallos en los tres frontends y cuatro niveles de replay; evidencia auditable.
  Necesidad: alta; urgencia: media; valor: alto; desbloqueo: evidencia para portabilidad y pilotos; esfuerzo: slices por frontend/invariante.

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
