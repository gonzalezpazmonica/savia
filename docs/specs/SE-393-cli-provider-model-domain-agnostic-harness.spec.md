---
id: SE-393
status: IMPLEMENTING
priority: P0
created: 2026-09-07
developer_type: agent-single
depends_on: [SE-375, SE-380, SE-383, SE-388, SE-391, SE-392]
---
# SE-393 — Savia: contratos de un harness agnóstico

## 1. Objetivo y límites

Permitir sustituir CLI, proveedor, modelo y dominio independientemente, preservando política, estado, evidencias y autoridad humana. Agnosticismo significa contratos extensibles y sustitución verificable; no implica idénticas respuestas, capacidades universales ni acceso automático a L3/L4.

Entrega actual: implementación incremental de contratos y tests locales. No autoriza instalaciones, migración de memoria, publicación de capacidades ni certificación de proveedores sin runs reales. Las decisiones transversales siguen sujetas a revisión humana.

## 2. Método, baseline y confianza

Revisión estática de rutas críticas de arranque, bridge, protocolo, policy, configuración, resolución de modelos, skills y certificación. Baseline: `5c754f794619c79d68d1783d8275f6118b39bf96`. Se inspeccionó también el árbol local con cambios previos en tres skills y cuatro archivos de SE-391; estos cambios no son código mergeado. No se modifican en esta auditoría.

No es una inspección exhaustiva de cada script, un pentest ni una certificación de proveedores. Las referencias de línea corresponden al árbol inspeccionado; las funciones son el ancla estable. No se verificaron prestaciones actuales de modelos ni compatibilidad upstream. No hubo nuevas llamadas a modelos, redes ni pruebas de acceso a secretos. Las observaciones de cold start de la sesión anterior son evidencia secundaria, no una nueva reproducción.

Confianza alta en los acoplamientos citados; media en su extensión al conjunto del harness. Herramientas de cúpulas/grafo no expuestas en esta sesión: se usaron fuentes locales de configuración y código. La arquitectura observada es un conjunto de scripts y extensiones por frontend con un plano de control común experimental; no un núcleo hexagonal consolidado.

## 3. Valoración arquitectónica

Escala cualitativa: 0 = único binding; 1 = extensiones parciales; 2 = contrato común operativo; 3 = sustitución demostrada; 4 = regresión continua en varios bindings. Las puntuaciones son juicio arquitectónico, no un benchmark.

| Eje | Valoración | Fundamento |
|---|---|---|
| CLI | 1/4 | Hay proyecciones y protocolo, pero lista cerrada y ejecución común pendiente. |
| Proveedor | 1/4 | Gateway local y opciones de configuración; rutas de ejecución aún específicas. |
| Modelo | 1/4 | Registry existente; identidad incompleta y defaults no observados. |
| Dominio | 1/4 | Skills profesionales diversas; arranque y flujo base siguen orientados a PM/SDD. |

Valoración global: extensibilidad real, independencia operacional todavía no demostrada. Riesgo dominante: confundir disponibilidad/configuración con enforcement y evidencia efectiva. Fortalezas que conservar: `.scm`, fuentes compartidas, parser acotado, journal SQLite, preflight que rechaza falta de evidencia y separación declarada entre ejecución y criterio.

## 4. Hallazgos y reparación requerida

P0 = integridad de seguridad/evidencia; P1 = bloqueo de sustitución; P2 = claridad y mantenimiento. Severidad describe impacto arquitectónico, no explotación demostrada.

| Gap | Prioridad | Evidencia local | Reparación y propietario |
|---|---|---|---|
| G01. Lista cerrada de CLI y versiones en núcleo | P1 | `scripts/dual-cli/protocol.py:59` admite sólo codex/opencode; `preflight.py:11` exige diccionario de dos versiones exactas. | SE-393: registro de adapters y evidencia por versión; añadir adapter sin editar parser/policy. Preservar invalidación de evidencia al actualizar. |
| G02. Plano común sin ejecución integrada | P1 | `scripts/dual-cli/runtime.py:35` declara adapters/supervisor pendientes; `handle` devuelve deny/UNSUPPORTED_CAPABILITY para dispatch. | SE-392 es propietario de ejecución, leases, ACK y recuperación; SE-393 define extensibilidad del contrato. No crear otro runtime. |
| G03. Semántica de gates diverge | P0 | `scripts/opencode-plugin/savia-gates/lib/shell-bridge.ts:50` omite handlers no-command; `:250` traduce timeout a exit 0; catch final no bloquea. `scripts/dual-cli/policy.py:hook_decision` deniega fallos. | Reparar en SE-392 y probar con SE-383; distinguir gate crítico de telemetría y compartir decisión normalizada. No atribuir estos fallos a todos los hooks sin inventario. |
| G04. Bridge de servicio ligado a Claude | P1 | `scripts/savia-bridge.py:790` find_claude_cli; `:1539` stream_claude_response construye claude -p; `:3595` arranque exige CLI. | SE-393: inyectar adapter de ejecución y normalizar streaming/cancelación; Claude permanece implementación compatible. |
| G05. No hay contrato único de ruta de inferencia en las rutas revisadas | P1 | `scripts/model-gateway.py:Handler.do_POST` ofrece subset local; bridge usa CLI; `config/model-registry.json` se deriva de OpenCode. | SE-393: distinguir inferencia gestionada por CLI de inferencia directa. Descriptor común; traducción de wire protocol sólo en adapters directos. |
| G06. Colisión de identidad y capacidades supuestas | P1 | `scripts/model-capability-resolver.sh:22` elimina prefijo de proveedor; `:30` y `:58` usan 200000 tokens como fallback; YAML y model-registry tienen alcances distintos. | SE-393: identidad cualificada, capacidades con procedencia/vigencia; unknown explícito y presupuesto conservador declarado. Integrar registries existentes. |
| G07. Selección lógica expresa marcas de modelo | P2 | `scripts/surrogate/llm-router.py:decide` devuelve CLAUDE_MODEL_FAST/MID/AGENT; `docs/rules/domain/autonomous-safety.md` expresa escalación con tiers Claude. | SE-393: roles/capacidades abstractos resueltos a modelos; aliases legacy sólo en borde. Piloto surrogate no se considera router efectivo universal. |
| G08. Recibos confunden decisión con ejecución | P0 | `scripts/dual-cli/autonomy.py:49` fija frontend=codex; `write_receipt` emite PASS por PROCEED y copia external_effects de la acción solicitada. | SE-393 con SE-391: separar decision, execution y observation; frontend observado, efectos intentados/confirmados y enlace a evidencia. |
| G09. Doctor no demuestra todo lo que etiqueta | P0 | `scripts/dual-cli/codex_profile.py:probe` deriva workspace_write de --help y usa true como control; `autonomy_doctor.py:report` reutiliza booleano para L0/L1/L2/aprobaciones. | SE-391 propietario; exigir pruebas reales diferenciadas y ámbito host/sesión/sandbox anidado. Fix local del control L4 es parcial y no está mergeado. |
| G10. Frontera de secretos específica y sensible al arranque | P0 | `scripts/dual-cli/codex_profile.py:PROFILE` protege un path Codex concreto; no describe otros almacenes. Corrida anterior con override legacy y corrida nativa dieron resultados distintos. | SE-391/393: adaptar referencias privadas a fronteras nativas verificadas; validar configuración efectiva tras overrides. No construir nuevo vault ni inferir cobertura universal. |
| G11. Dominio PM/SDD incrustado en arranque | P1 | `CLAUDE.md` Rol/Reglas críticas fija PM, Azure DevOps, sprint y SDD; plantilla SDD usa C#/pacientes; `professional-domain/SKILL.md` ofrece familias separadas. | SE-393: contexto común mínimo y packs de dominio opt-in. PM/SDD sigue pack compatible; namespaces y memoria aislados por proyecto/dominio. |
| G12. Contexto y catálogo no son identidad efectiva | P1 | `docs/critical-facts.md` fija frontend/modelo; `docs/AGENTS.md` describe 33 roles frente a otro catálogo raíz; `scripts/dual-cli/config.py:build_manifest` depende de .claude/settings.json. | SE-375 propietario de vistas; SE-393 separa identidad runtime de hechos persistentes y permite adapters de fuentes. Mantener rutas legacy durante migración. |

Los directorios `.claude/` y `.opencode/` por sí solos no demuestran lock-in: el problema es que su formato o semántica resulte obligatorio en el núcleo. Tampoco múltiples proveedores en un YAML demuestran sustitución de ejecución.

## 5. Arquitectura propuesta y decisiones

Dirección de dependencias: interfaces de usuario/CLI → adapters → contratos y política comunes → puertos de ejecución, estado y evidencia. Los packs aportan tareas y reglas de negocio mediante esos contratos. Ninguna decisión del modelo concede permisos.

- Evolucionar `scripts/dual-cli/` y `.scm`; conservar aliases hasta retirar consumidores legacy con evidencia. No renombrar masivamente el workspace ni añadir un segundo daemon/catálogo.
- Un adapter declara capacidades observadas y limitaciones. Registro explícito y versionado; no autoejecutar plugins descubiertos en disco ni confiar por nombre.
- La ruta CLI puede ocultar proveedor/modelo efectivos: registrar unknown si no los expone. No inventar acceso a su API ni exigir que todo tráfico pase por el gateway local.
- El resolver filtra primero por privacidad, autoridad, capabilities y presupuesto; después por coste/calidad. Fallback entre proveedores exige estar preautorizado para ese dato y no repite efectos externos inciertos.
- Dominios agregan restricciones; no relajan política global. Domain pack vacío permite leer contexto, planificar y generar un artefacto local. Jira/Azure, sprint, lenguaje de programación y jurisdicción no son requisitos del núcleo.
- Evidencia certifica combinaciones concretas de versiones, entorno y policy. El núcleo debe aceptar extensiones verificadas, sin convertir “extensible” en “todos soportados”.

## 6. Contratos propuestos v2

JSON UTF-8; máximo 1 MiB por mensaje, identificadores no vacíos de hasta 256 caracteres, rechazo de claves duplicadas y números no finitos. Reusar validadores v1. Campos adicionales sólo dentro de `extensions` con namespace; incompatibilidad devuelve UNSUPPORTED_SCHEMA. Ninguna credencial va en el contrato público.

| Tipo | Campos requeridos y semántica |
|---|---|
| ExecutionContext | schema=2; run_id, session_id, repo_id, frontend_id, adapter_version, policy_revision, effective_config_hash: string; provider_id, model_id, model_revision: string o null; inference_mode: cli_managed/direct; domain_ids: string[]; authority_ceiling: L0/L1/L2. null significa unknown. |
| CapabilityObservation | capability_id: string; status: verified/unsupported/unknown/failed; mechanism: native/mediated; observed_at: UTC RFC3339; environment_hash, subject_version, evidence_ref: string. verified requiere evidencia satisfactoria del mismo ámbito. |
| ExecutionRequest | request_id, capability_id, context_ref, scope_ref: string; input_ref: referencia privada de artefacto tipado por capability; required_capabilities: string[]; deadline_ms: entero positivo; external_effect_intent: bool. |
| ExecutionResult | request_id: string; state: succeeded/failed/cancelled/blocked/unknown; reason: string; artifacts: referencias[]; usage: input_tokens/output_tokens enteros >=0 o null; external_effect_observed: true/false/null. |
| Receipt | schema=2; context: ExecutionContext; request_id, event_id, decision_id: string; decision: proceed/deny/needs_human; execution: ExecutionResult o null; observation_refs: string[]; human_gate_count: entero >=0 observado; delegated_execution: bool; decision_authority=human. |
| DomainPack | id, version: string; capability_ids, rule_refs, context_refs, test_refs: string[]; memory_namespace: string; dependencies: IDs versionados; compatibility_schema=2. Conflictos de reglas bloquean activación. |

Puertos: `describe()`, `preflight(context)`, `execute(request)`, `cancel(request_id)`, `observe(request_id)`. Cancelar es idempotente; recibir cancel no acredita fin del proceso. Antes de repetir una ejecución tras desconexión debe reconciliarse su resultado. Aplicar leases/supervisión de SE-392.

Errores mínimos: UNKNOWN_ADAPTER, UNSUPPORTED_CAPABILITY, UNSUPPORTED_SCHEMA, STALE_EVIDENCE, CONFIG_CONFLICT, SECRET_BOUNDARY_UNVERIFIED, SCOPE_EXPANSION, EXTERNAL_EFFECT, DECISION_AUTHORITY, UNKNOWN_EXECUTION_RESULT. Todo error crítico bloquea el efecto. Cambios de schema requieren negociación; cliente v1 no recibe estructuras v2 silenciosamente.

## 7. Criterios de aceptación de reparación

| AC / gaps | Given → When → Then |
|---|---|
| AC01 / G01,G02 | Tres adapters registrados, uno nuevo de prueba → incorporar el tercero → parser/policy no cambian; adapter desconocido queda bloqueado. E2E posterior con al menos dos CLI reales. |
| AC02 / G03 | Mismo corpus de eventos en adapters → timeout, crash, JSON inválido, handler ausente y gate async → mismo deny para críticos; cero efectos. Telemetría fallida se distingue. |
| AC03 / G04,G05 | Bridge configurado con cada adapter certificado → iniciar, emitir stream, cancelar y reconectar → mismo contrato y resultado; no se exige binario Claude con otro adapter. |
| AC04 / G05,G06 | Dos proveedores registrados comparten nombre corto de modelo → resolver y ejecutar rutas autorizadas → identidades diferentes preservadas; proveedor oculto sigue unknown. |
| AC05 / G06,G07 | Modelo desconocido o metadata caducada → planificar contexto/fallback → no se declara una ventana verificada; presupuesto explícito conservador o bloqueo por requisitos insuficientes. Cambio de modelo no cambia autoridad. |
| AC06 / G08 | Decisión proceed seguida de fallo, o push denegado → emitir recibo → fallo no es PASS; push no ejecutado no acredita efecto externo. IDs correlacionan request/decisión/resultado. |
| AC07 / G09,G10 | Arranque limpio con perfil efectivo y control benigno → pruebas de escritura, ciclo fail/fix y siete vías de secreto → distinguir éxito, DENY, error de infraestructura y unknown; un sandbox roto nunca prueba bloqueo. |
| AC08 / G10 | Override que elimina deny o cambia red → preflight → bloqueo antes de tarea protegida. Autoridad L3/L4 permanece humana/bloqueada; no aceptar aprobación inferida. |
| AC09 / G11 | Pack vacío, PM y edición documental no técnica → misma tarea local de artefacto → funcionan sin ADO, sprint o toolchain .NET obligatorios; packs inactivos no inyectan reglas. |
| AC10 / G11,G12 | Dos dominios/proyectos activos → escritura y consulta de memoria → namespaces y permisos impiden contaminación; no se copia historial nativo entre CLI. |
| AC11 / G01,G12 | Cambio de modelo, adapter, policy, trust, configuración o sandbox → reusar recibo anterior → STALE_EVIDENCE hasta validar ejes afectados; vistas derivadas deterministas sin identidad de sesión persistida globalmente. |
| AC12 / todos | Matriz de dos CLI reales, dos proveedores, dos modelos por proveedor disponibles/autorizados y tres packs → cubrir cada eje y cada par compatible → informe por celda, incluyendo incompatibles; ninguna celda skipped/unknown permite certificar su combinación. |

No se exige producto cartesiano de combinaciones imposibles. Tests de contrato con doubles prueban diseño; sólo runs reales certifican ejecución. AC12 requiere disponibilidad y autorización de proveedores; ausencia bloquea esa certificación, no justifica nuevas cuentas ni gasto automático. Congelar fixtures, versiones, corpus y hashes antes de evaluar. Registrar también fallos y redacciones; resultados no se sobrescriben para simular verde.

## 8. Secuencia de reparación y alcance previsto

| Slice | Entrega futura | Archivos existentes / nuevos propuestos |
|---|---|---|
| S0 | Baseline, ownership y matriz por eje | `.scm/registry.json`, `scripts/generate-capability-map.py`, `docs/frontend-compatibility.md`; nuevo `tests/dual-cli/test_harness_contracts.py`. |
| S1 | Contratos v2, adapters extensibles y negociación | `scripts/dual-cli/protocol.py`, `preflight.py`, `config.py`, `audit.py`; nuevo `scripts/dual-cli/contracts.py`. |
| S2 | Enforcement/recibos/observaciones correctas | `scripts/dual-cli/policy.py`, `autonomy.py`, `codex_profile.py`, `autonomy_doctor.py`; `tests/dual-cli/test_autonomy.py`, `test_doctor.py`. Ejecución/bridge hooks bajo SE-392. |
| S3 | Ejecución desacoplada e identidad de modelos | `scripts/savia-bridge.py`, `model-gateway.py`, `model-capability-resolver.sh`, `config/model-registry.json`, `config/model-capabilities.yaml`; adapters sobre runtime SE-392. |
| S4 | Packs, contexto y compatibilidad legacy | `CLAUDE.md`, `docs/critical-facts.md`, `docs/rules/domain/spec-opencode-implementation-plan.md`, plantilla SDD; nuevo `config/domain-packs.json` como vista de `.scm`, no autoridad paralela. |
| S5 | Certificación y migración incremental | `tests/dual-cli/`, suite SE-383 y evidencia privada; nuevos `tests/dual-cli/test_domain_packs.py` y `test_provider_identity.py`. |

S0 precede S1; S2 y S3 requieren S1 y mecanismos de SE-392; S4 requiere contratos de activación de S1; S5 valida cada slice y cierre. Reusar tests existentes y retirar duplicidades mediante SE-380. No migrar memoria real ni configuración personal antes de probar rollback y compatibilidad en fixtures.

Estimación orientativa, confianza baja: 4–8 semanas-persona para el delta SE-393, además del trabajo pendiente de SE-391/392. Reestimar tras S0. No incluye obtener cuentas, APIs, hardware, soporte de todos los sistemas operativos ni implementar dominios nuevos.

## 9. Relación con specs existentes y cierre

SE-375 mantiene autoridad de catálogo; SE-380 presupuesto y lifecycle; SE-383 caos; SE-388 adapter Codex; SE-391 autonomía L2 y doctor; SE-392 runtime/concurrencia/paridad. Esta spec aporta separación de los cuatro ejes, contrato extensible, identidad completa, packs y certificación transversal. Los gaps compartidos se cierran con evidencia de su spec propietaria, sin segunda implementación.

Cierre requiere AC01–AC12 trazables, revisión humana de seguridad/arquitectura, compatibilidad legacy demostrada y CI verde. Registrar soportado por combinación, nunca “Savia soporta cualquier modelo”. No promover SE-388/391 ni otorgar L3/L4 como efecto colateral. Estado actual: IMPLEMENTING; la matriz AC12 continúa pendiente de proveedores/CLI reales autorizados.

## 10. OpenCode Implementation Plan

### Bindings touched

OpenCode: savia-gates y traducción de eventos; Codex: perfiles/hooks que su versión efectiva exponga; Claude: adapter del bridge existente. Núcleo sin dependencias de estos SDK. Inferencia directa tiene adapters separados; CLI-managed conserva protocolos nativos.

### Verification protocol

Contratos comunes y runs por combinación AC12; registrar mecanismos ausentes como unsupported/unknown. No asumir expansión de imports, hooks heredados ni hot reload. Los overrides deben probarse en el entorno efectivo y la regeneración de contexto respetar SE-371.

### Portability classification

DUAL_BINDING según taxonomía vigente, extendida explícitamente a tres adapters; no es una declaración de paridad implementada. Revisar la taxonomía binaria bajo G12 cuando se apruebe la reparación.
