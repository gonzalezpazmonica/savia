# Skills Schema — Savia pm-workspace

> Generado automáticamente por `scripts/skills-schema-generate.sh` (SE-238).
> 119 skills indexados.

| skill_id | description | tags |
|----------|-------------|------|
| adversarial-security | Usar cuando se necesita auditar la seguridad de un proyecto con pipeline Red Tea | security, adversarial, red-team, blue-team |
| agent-code-map | Usar cuando un agente necesita conocer la arquitectura del proyecto sin leer fic | acm, agent-maps, codemap, context, sdd, architecture |
| agent-file-map | Usar cuando se trabaja con ficheros externos al workspace que los agentes deben  | afm, agent-maps, external-files, context, file-index |
| ai-labor-impact | Usar cuando se analiza el impacto de la IA en el trabajo del equipo o la organiz | ai-impact, labor, reskilling, workforce |
| android-autonomous-debugger | Usar cuando se depuran o testean apps Android contra dispositivos físicos via US | android, debugging, adb, mobile-testing |
| architecture-intelligence | Usar cuando se diseña o revisa la arquitectura de un proyecto nuevo o existente. | architecture, patterns, detection, recommendations |
| ast-comprehension | Usar cuando se explora código desconocido y se necesita comprensión estructural  | ast, comprehension, legacy, rlm, structural-analysis, pre-edit |
| ast-quality-gate | Usar cuando se verifica la calidad de código generado por IA antes de merge. | ast, static-analysis, quality-gates, llm-patterns, sdd |
| attack-surface-mapper | Mapear la superficie de ataque de un dominio: subdominios, OSINT, typosquatting. | attack-surface, subdominios, osint, dnstwist, subfinder |
| azure-devops-queries | Usar cuando se necesitan consultas WIQL, actualización de work items o datos de  | azure-devops, wiql, work-items, api |
| azure-pipelines | Usar cuando se gestiona o depura CI/CD con Azure Pipelines. | pipelines, ci-cd, azure, deployment |
| backlog-git-tracker | Usar cuando se capturan o comparan snapshots del backlog para detectar drift. | backlog, snapshot, audit, tracking |
| banking-architecture | Usar cuando se diseña o revisa arquitectura para proyectos del sector bancario. | banking, architecture, finance, compliance |
| bus-factor-analysis | > | bus-factor, knowledge-graph, git-analysis, risk, resilience |
| capacity-planning | Usar cuando se calcula la capacidad del equipo para un sprint o periodo. | capacity, team, workload, planning |
| caveman | Strips all sugar-coating and marketing. Gives the brutally honest truth in the f | — |
| client-profile-manager | Usar cuando se crean, actualizan o consultan perfiles de cliente en SaviaHub. | client, profile, crud, savia-hub |
| code-comprehension-report | Usar cuando se ha completado una implementación SDD y se necesita documentar el  | comprehension, mental-model, debugging, documentation |
| code-improvement-loop | Usar cuando se quiere ejecutar mejora autónoma de código en segundo plano con PR | autonomous, improvement, refactoring, pr-draft |
| codebase-map | Usar cuando se necesita un mapa de dependencias del workspace (comandos→agentes→ | indexing, routing, dependencies, discovery |
| codegraph | Usar cuando se necesita indexación AST persistente para navegación de callers/ca | mcp, ast, tree-sitter, indexing, callers, impact, acm-engine |
| company-messaging | Usar cuando se envían mensajes internos cifrados entre miembros de la organizaci | messaging, company, encryption, privacy |
| consensus-validation | Usar cuando una decisión técnica o recomendación necesita validación por panel d | consensus, validation, multi-judge, quality |
| content-fingerprint | Usar cuando se necesita un identificador corto, deterministico y reproducible de | — |
| context-caching | Usar cuando se optimiza el orden de carga de contexto para maximizar cache hits. | caching, performance, tokens, cost-optimization |
| context-dome | > | context-dome, bus-factor, documentation, knowledge-transfer, resilience |
| context-interview-conductor | Usar cuando se necesita recopilar contexto estructurado de un usuario mediante e | interview, context, structured, discovery |
| context-optimized-dev | Usar cuando se desarrolla con presupuesto de contexto limitado. | context, optimization, dev-session, slicing |
| context-rot-strategy | Usar cuando una sesión larga se aproxima al límite de contexto y hay que decidir | context, 1M, rot, compact, session, opus-4-7 |
| context-task-classifier | Usar antes de compactar contexto para clasificar la tarea del turno actual. | — |
| cost-management | Usar cuando se gestionan timesheets, presupuestos, facturas o forecasting de cos | cost, budget, forecasting, invoicing |
| dag-scheduling | Usar cuando se orquestan múltiples agentes SDD con dependencias entre ellos. | dag, parallel, orchestration, pipeline |
| dependency-scanner | Usar cuando se escanean vulnerabilidades en dependencias de proyectos (Node, Pyt | security, dependencies, trivy, sbom, cve, supply-chain |
| design-an-interface | Design-an-interface skill with N=3 parallel alternatives and architectural vocab | architecture, interface-design, parallel-agents, sdd |
| developer-experience | Usar cuando se mide o mejora la experiencia de desarrollo del equipo. | dx, developer-experience, space, core4 |
| devops-validation | Usar cuando se conecta un proyecto nuevo a Azure DevOps para validar su configur | validation, azure-devops, agile, configuration |
| diagram-generation | Usar cuando se necesita generar diagramas de arquitectura o flujo desde código o | diagrams, architecture, mermaid, draw-io |
| diagram-import | Usar cuando se importa un diagrama existente para extraer entidades y crear PBIs | diagram-import, parsing, work-items, entities |
| doc-quality-feedback | Usar cuando se recopila feedback de calidad de documentación tras usar skills y  | feedback, documentation, self-improvement |
| dynamic-web-tester | Testing dinámico de endpoints web: XSS (DalFox), SQLi (sqlmap), Nuclei. | xss, sqli, dalfox, sqlmap, nuclei, pentest-web, dynamic-testing |
| ecosystem-watcher | Usar una vez al mes para detectar cambios relevantes en el ecosistema de herrami | watch, monthly, intelligence, excellent, cron |
| emergency-mode | Usar cuando la API de Anthropic está caída y se necesita continuar operando con  | emergency, localai, sovereignty, spec-122 |
| enterprise-analytics | Usar cuando se necesitan métricas SPACE, aggregación de portfolio o forecasting  | analytics, space-metrics, portfolio, forecasting |
| enterprise-onboarding | Usar cuando se incorporan múltiples personas a la organización de forma masiva. | onboarding, enterprise, batch-import, knowledge-transfer |
| epistemic-humility | Usar cuando se detecta riesgo de adulación, cesión sin evidencia, o claim repeti | sycophancy, illusory-truth, epistemic, honesty, spec-192 |
| evaluations-framework | Usar cuando se diseñan o ejecutan evaluaciones de calidad de agentes y prompts. | evaluations, quality, g-eval, scoring |
| executive-reporting | Usar cuando se genera un informe ejecutivo multi-proyecto para dirección. | executive, reports, powerpoint, word |
| feasibility-probe | Usar cuando se necesita validar si una spec es técnicamente viable antes de impl | feasibility, estimation, prototype, spec, planning |
| git-secret-scanner | Escanea el historial git o los commits pendientes de push buscando secrets con g | security, gitleaks, secret, git-history, pre-push |
| governance-enterprise | Usar cuando se audita compliance, se registran decisiones o se certifican proces | governance, audit-trail, certification, enterprise |
| grill-me | Adversarial review that hunts every weakness, assumption, edge case, and missing | — |
| human-code-map | Usar cuando se incorpora un dev nuevo, se toca un módulo sin mapa, o alguien re- | comprehension, cognitive-debt, documentation, onboarding, mental-model |
| iac-security-scanner | Usar cuando se escanea IaC (Terraform, Bicep, Dockerfile, docker-compose) con Tr | security, iac, terraform, trivy, misconfiguration, devops |
| knowledge-graph | Usar cuando se construye o consulta el grafo de conocimiento de entidades del pr | knowledge-graph, entities, relations, queries |
| legal-compliance | Usar cuando se audita compliance legal contra legislación española consolidada. | legal, compliance, legislación, BOE, LOPDGDD, LSSI |
| managed-content | Usar cuando se regeneran secciones auto-generadas en documentos con marcadores d | managed-content, markers, auto-generated, sync |
| meeting-transcript-extract | Usar cuando se necesita extraer la transcripción de una reunión Teams desde el b | — |
| memvid-backup | Usar cuando se crea un backup portable de la memoria externa de Savia. | backup, memvid, portable, travel, integrity |
| meta-reflection | Protocolo de las 4 meta-preguntas para cuestionar el encuadre de una tarea antes | meta-reflection, criterion-simulation, spec-194, frame, governance |
| mobile-security-scanner | Usar cuando se escanea un APK/AAB Android en busca de vulnerabilidades de seguri | android, mobile, apk, MobSF, manifest, security, static-analysis |
| model-upgrade-audit | Usar cuando hay un modelo nuevo disponible y se quiere detectar prompt debt en e | model, upgrade, prompt-debt, simplification, audit |
| mutation-audit | Usar cuando se quiere medir la calidad real de los tests mediante mutation testi | testing, mutation, quality, zombies, ai-generated |
| network-recon | Reconocimiento de red: port scan con nmap/RustScan + HTTP detection con httpx. | nmap, rustscan, httpx, port-scan, network-recon, recon |
| nuclei-scanning | Usar cuando se escanean vulnerabilidades conocidas (CVEs, misconfigs) con Nuclei | — |
| onboarding-dev | Usar cuando se incorpora un desarrollador nuevo al proyecto y necesita buddy IA. | onboarding, buddy-ia, documentation, ramp-up |
| org-meeting-capture | Captura de Conocimiento Tácito de Reunión: extrae decisores, acuerdos informales | reuniones, conocimiento-tácito, transcripciones, org-intelligence, acuerdos-informales |
| org-political-landscape | Análisis de Paisaje Político Interno: detecta tensiones, alianzas y centros de p | política-organizativa, alianzas, tensiones, poder, org-intelligence |
| org-stakeholder-mapper | Mapeador de Stakeholders y Decisores: extrae roles formales y reales, motivacion | stakeholders, org-intelligence, poder, decisores, análisis-organizativo |
| orgchart-import | Usar cuando se importa un organigrama para extraer la estructura del equipo. | orgchart, import, teams, hierarchy |
| overnight-sprint | Usar cuando se quiere ejecutar tareas de bajo riesgo de forma autónoma durante l | autonomous, overnight, batch, low-risk |
| pbi-decomposition | Usar cuando se descompone un PBI en tasks y se estiman las horas. | pbi, decomposition, estimation, assignment |
| pentesting | Usar cuando se ejecuta un pentest contra una aplicación o infraestructura. | pentesting, security, owasp, proof-based |
| performance-audit | Usar cuando se audita el rendimiento estático de código para detectar hotspots. | performance, hotspots, async, optimization |
| personal-vault | Usar cuando se lee o escribe el repositorio personal del usuario (perfil, prefer | — |
| pr-agent-judge | Usar cuando se añade pr-agent como juez externo en el Code Review Court. | — |
| product-discovery | Usar antes de descomponer PBIs, cuando se necesita análisis JTBD y PRD del produ | discovery, jtbd, prd, product |
| professional-domain | Family index for professional-domain skills (controlling, finance, labour, legal | — |
| project-update | Usar cuando se necesita una actualización integral del proyecto activo desde tod | — |
| prompt-optimizer | Usar cuando se optimiza el prompt de un skill o agente para mejorar su efectivid | optimization, autoresearch, prompt-engineering, self-improvement |
| rbac-management | Usar cuando se gestionan roles, permisos o se audita el acceso de usuarios. | rbac, permissions, roles, access-control |
| reflection-validation | Usar cuando una respuesta o decisión importante necesita validación metacognitiv | reflection, meta-cognitive, system2, assumptions |
| regulatory-compliance | Usar cuando se valida el cumplimiento de marcos regulatorios sectoriales. | compliance, regulatory, sector-detection, gdpr |
| reranker | Usar cuando se recibe un top-K ruidoso de búsqueda en memoria y se necesita reor | reranking, retrieval, memory, cross-encoder, tokens |
| resource-references | Usar cuando se necesitan referencias a recursos y plantillas del workspace. | resources, references, resolution, lazy-load |
| risk-scoring | Usar cuando se calcula el riesgo de una tarea para decidir el nivel de revisión  | risk, scoring, escalation, review-routing |
| rules-traceability | Usar cuando se mapean reglas de negocio a PBIs para trazabilidad completa. | traceability, business-rules, pbi, matrix |
| savia-dual | Usar cuando la inferencia cloud falla, es lenta o está rate-limited y se necesit | — |
| savia-flow-practice | Usar cuando se implementa Savia Flow con dual-track y métricas de flujo en un pr | savia-flow, dual-track, methodology, outcomes |
| savia-hub-sync | Usar cuando se sincroniza el repositorio SaviaHub con el workspace local. | sync, savia-hub, repository, backup |
| savia-identity | Usar al inicio de sesión para cargar la identidad completa y las reglas de compo | — |
| savia-memory | Usar cuando se lee, escribe, busca o consolida la memoria persistente entre sesi | — |
| savia-school | Usar cuando el workspace se adapta para un entorno educativo con estudiantes men | education, gdpr, minors, school, privacy, rubrics |
| scaling-operations | Usar cuando se analiza el tier de escala de un servicio o se necesitan optimizac | scaling, tier-analysis, benchmark, optimization |
| scheduled-messaging | Usar cuando se configuran mensajes automáticos programados a plataformas de comu | scheduled, messaging, notifications, automation |
| skill-evaluation | Usar cuando se necesita seleccionar el skill más apropiado para una tarea dada. | skill-eval, prompt-analysis, scoring, activation |
| smart-calendar | Usar cuando se gestiona la agenda inteligente con sincronización Outlook/Teams. | calendar, outlook, teams, focus, scheduling, deadlines, ceremonies |
| smart-routing | Usar cuando se necesita descubrir o enrutar a un comando específico entre los 40 | routing, discovery, commands, intent |
| sovereignty-auditor | Usar cuando se audita el grado de dependencia cognitiva del equipo respecto a he | sovereignty, lock-in, ai-governance, audit |
| spec-driven-development | Usar cuando se escribe, valida o implementa una spec ejecutable SDD. | sdd, specs, development, agents |
| sprint-management | Usar cuando se consulta el estado del sprint, se actualizan items o se genera el | sprint, planning, scrum, velocity |
| tdd-vertical-slices | Test-driven development with vertical-slice red-green-refactor cycles. Use when  | — |
| team-coordination | Usar cuando se coordinan múltiples equipos, se asignan miembros o se detectan bl | team, coordination, multi-team, blockers |
| team-onboarding | Usar cuando se incorpora un nuevo miembro al equipo y se evalúan sus competencia | onboarding, competencies, ramp-up, team |
| tech-research-agent | Usar cuando se necesita investigación técnica autónoma sobre un tema específico. | research, autonomous, investigation, reports |
| test-architect | Usar cuando se diseñan o generan tests de alta calidad en cualquier lenguaje. | testing, quality, bats, multi-language, test-strategy |
| tier3-probes | Usar cuando se valida la viabilidad de herramientas Tier 3 antes de adoptarlas e | probes, viability, tier3, dependencies, feasibility |
| time-tracking-report | Usar cuando se generan informes de imputación de horas en Excel o Word. | time-tracking, hours, excel, reporting |
| tls-security-checker | Usar cuando se verifica TLS/SSL o security headers HTTP de un servidor web. Invo | tls, ssl, web-security, headers, testssl, wafw00f, deploy |
| topic-cluster | Usar cuando se agrupan retros, PBIs o incidentes en topics para detectar patrone | clustering, bertopic, retrospectives, patterns, memory |
| ubiquitous-language | Usar cuando se necesita extraer o consolidar el glosario de términos de dominio  | ddd, glossary, domain, context, ubiquitous-language |
| verification-lattice | Usar cuando se necesita verificación multi-capa más allá del code review estánda | verification, multi-layer, pipeline, quality-gate |
| voice-inbox | Usar cuando se procesan mensajes de voz para transcribirlos y convertirlos en ac | voice, transcription, audio, whatsapp |
| web-research | Usar cuando se necesita buscar en la web para resolver gaps de contexto (docs, v | search, web, cache, searxng, citations, gap-detection |
| weekly-report | Usar cuando se genera el informe semanal de estado del proyecto. | — |
| wellbeing-guardian | Usar cuando se monitorizan señales de bienestar individual en el equipo. | wellbeing, burnout, sustainable-pace, team-health |
| workspace-integrity | Usar cuando se audita la integridad del workspace (drift, reglas, agentes, basel | integrity, audit, drift, workspace, hygiene |
| write-a-skill | Guia para crear una nueva skill correctamente en pm-workspace. Usar cuando una t | meta, skill-authoring, quality-gate |
| zoom-out | Elevates perspective from trees to forest. Maps architecture, dependencies, and  | — |
