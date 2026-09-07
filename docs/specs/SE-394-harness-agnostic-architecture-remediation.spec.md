---
id: SE-394
status: IMPLEMENTING
priority: P0
created: 2026-09-07
developer_type: human
depends_on: [SE-393]
related_specs: [SE-375, SE-380, SE-383, SE-388, SE-391, SE-392]
---
# SE-394 — Harness agnóstico: integración y evidencia verificable

## 1. Objetivo y alcance

Reparar los gaps de independencia entre CLI, proveedor, modelo y dominio encontrados después del merge de SE-393. Esta entrega implementa el delta acotado de confianza, composición local, procedencia de modelos, gates fail-closed y cobertura CI; no aprueba decisiones pendientes ni modifica estados de specs anteriores. SE-393 sigue siendo la especificación funcional; este delta concreta defectos y requisitos de cierre, sin duplicar runtime, catálogo, vault ni sistema de memoria.

Baseline local: `e2f35276146b732ee951cdce89ea1035e5ed48be`, árbol inicialmente limpio. Auditoría: 2026-09-07, observaciones hasta `2026-09-07T17:53:38Z`. No se verificó el estado remoto actual. Se inspeccionaron imports, entrypoints, políticas, configuración, manifests, tests y workflows; se ejecutaron comprobaciones locales con datos ficticios. No hubo inferencia, acceso a credenciales, pentest ni certificación real de frontends. No se ejecutó la suite global en esta auditoría.

Herramientas de cúpulas/grafo no expuestas; la evidencia técnica procede de código/configuración local, no de memoria privada. Confianza alta en los defectos reproducidos; media en cobertura transversal: no se revisó cada script del repositorio. Las referencias usan funciones estables y líneas del baseline. Los ejemplos son fixtures, no datos de operación.

## 2. Arquitectura observada y valoración

Patrón observado: scripts modulares con integraciones específicas y un plano de control experimental. Existen piezas de ports/adapters; su composición operacional está incompleta. La evaluación usa dirección de dependencias, configuración y consumidores reales; el nombre de una clase o carpeta no acredita arquitectura hexagonal.

| Eje | Madurez observada | Motivo |
|---|---|---|
| CLI | 1/4 | Registro extensible aislado; protocolo v1 cerrado; bridge ejecuta Claude; runtime común no ejecuta. |
| Proveedor | 1/4 | IDs y rutas locales existen; no hay selección/validación de ruta integrada con política y evidencia. |
| Modelo | 1/4 | Se conserva el prefijo, pero capacidades se buscan por nombre corto y se declaran verificadas sin procedencia/vigencia. |
| Dominio | 1/4 | Dos descriptores de packs; activación no conectada a arranque, reglas o memoria. |

Escala cualitativa: 0 = binding único; 1 = extensiones parciales; 2 = contrato común operativo; 3 = sustitución real demostrada; 4 = regresión continua entre bindings. No son porcentajes de implementación ni benchmarks. Los cambios de SE-393 mejoran estructura, pero todavía no permiten subir de nivel operacional.

Conservar: parser v1 acotado, política común de hooks, registro explícito, journal y leases SQLite, configuración con detección de conflictos y separación nominal entre decisión/ejecución. Riesgo dominante: evidencia que afirma más de lo observado y puntos de entrada que no consumen el contrato común. Que el daemon rechace toda ejecución limita efectos, pero no demuestra autonomía útil.

## 3. Hallazgos trazables

P0 = corregir antes de usar evidencia para autorizar/graduar; P1 = reparación necesaria para sustitución operacional; P2 = mantenimiento. No son CVSS ni afirmaciones de explotación de secretos. E = lectura estática; R = reproducción local; I = instrumentación con doubles, sin certificación.

| Gap | Prioridad / evidencia | Causa, impacto y reparación requerida |
|---|---|---|
| H01 — Contrato fuera del camino de ejecución | P1/E; `scripts/dual-cli/contracts.py:109`, `protocol.py:51`, `runtime.py:21` | `AdapterRegistry` sólo exige `describe`; los consumidores encontrados están en tests. `decode_event` sólo admite codex/opencode; dispatch siempre deniega. Registrar capacidades no habilita ejecución. Integrar negociación y puertos en SE-392; exigir interface completa antes del registro. |
| H02 — Bridge e inferencia específicos | P1/E; `scripts/savia-bridge.py:790,1539,3597`; `scripts/model-gateway.py:_proxy,Handler.do_POST` | Bridge localiza y ejecuta Claude; gateway es POC local separado. El campo `inference_mode` carece de consumidor integrado. Inyectar adapters en entrypoints existentes; normalizar streaming, cancelación, reanudación y observación, preservando sesiones nativas. |
| H03 — Gates todavía divergen | P0/E; `scripts/opencode-plugin/savia-gates/lib/shell-bridge.ts:32,364`; `scripts/dual-cli/policy.py:hook_decision` | Settings ausentes/corruptos producen mapa vacío; exit 1, stdout inválido, `continue:false` y `permissionDecision:deny/ask` no bloquean en el bridge como en policy. Timeout y excepciones sí fueron corregidos. Clasificar gate crítico vs telemetría explícitamente; `async` no puede rebajar un gate. Propietario SE-392, corpus SE-383. |
| H04 — Validación v2 incompleta | P0/R; `scripts/dual-cli/contracts.py:37,53,77,91` | Admite schema `2.0`, efecto entero `1` y fecha sin hora/zona; enums de tipo lista pueden escapar como TypeError. No aplica límite de bytes/duplicados en un decoder v2 común; `extensions` previsto en SE-393 se rechaza. Definir y aplicar parsing estricto y errores normalizados en todo ingreso v2. |
| H05 — Recibos sin consistencia ni observación | P0/R,E; `contracts.py:receipt`; `scripts/dual-cli/autonomy.py:write_receipt` | Se acepta deny + succeeded e IDs distintos. Writer inventa IDs `local`, contexto `unknown`, usa scope como config hash y deriva gate count de decisión. V1 aún emite PASS por PROCEED y efectos desde intención. Exigir contexto observado, correlación, transición válida y contador de eventos; compatibilidad v1 no puede certificar ejecución. |
| H06 — Certificación basada en afirmaciones del input | P0/E,R; `contracts.py:capability_observation`; `preflight.py:_required_adapters,validate` | `verified` acepta una referencia inexistente; preflight usa truthiness, admite lista de adapters filtrada/sobrescrita y recibe `runtime_status.certified` del caller. El validador de forma no es verificador de evidencia. Separar ambos y validar procedencia, digest, ámbito y vigencia contra registro confiable; rechazar duplicados, campos ausentes y tipos incorrectos. |
| H07 — Invalidación no cubre código efectivo | P0/I,E; `scripts/dual-cli/config.py:build_manifest`; `scripts/generate-capability-map.py:scan_scripts` | Selección de fuentes omite contracts/policy/runtime Python, shell-bridge TS y model-capabilities YAML. Scanner sólo enumera shell a profundidad 1; incorporar domain-packs no cubre sus refs. Añadir cierre explícito de dependencias de seguridad/ejecución y configuración efectiva por sesión, sin registrar bibliotecas internas como capabilities públicas. |
| H08 — Identidad preservada, capacidades confundidas | P1/R; `scripts/model-capability-resolver.sh:73` | Proveedor ficticio + `deepseek-v4-pro` recibe ventana 128000 y status verified igual al proveedor registrado. Falta binding cualificado, fuente, fecha y revisión. Resolver por tupla proveedor/modelo/revisión/ruta; distinguir declarado de observado; metadata desconocida/caducada bloquea requisitos o usa presupuesto conservador explícito. |
| H09 — Roles abstractos sin resolución efectiva | P1/E; `scripts/surrogate/llm-router.py:decide,main`; `docs/rules/domain/autonomous-safety.md` | `fast/mid/agent` son ahora valores del campo `model` en un piloto report-only, sin integración de selección; la regla de escalación conserva aliases Claude. Resolver roles antes de ejecutar según privacidad, capabilities, presupuesto y bindings autorizados. No elevar autoridad ni repetir un efecto incierto al cambiar de modelo. |
| H10 — Doctor sobredeclara autonomía y bloqueo | P0/E; `scripts/dual-cli/codex_profile.py:real_l4_probe,probe`; `autonomy_doctor.py:report` | Workspace write deriva de help; L0/L1/L2/aprobaciones comparten booleano; L4 considera cualquier exit no cero como deny, sin control benigno dentro del mismo sandbox. Techo verificado se fija en L2 incluso si falla. Restaurar pruebas diferenciadas SE-391, distinguir infraestructura, denegación, unknown y nivel realmente observado. |
| H11 — Packs sin activación ni aislamiento efectivo | P1/R,E; `scripts/dual-cli/domain_packs.py:load,activate`; `config/domain-packs.json`; `CLAUDE.md` | PM activa sin `core-local@1`; dependencias/versiones/ciclos y conflictos de reglas no se resuelven. Namespace único en una lista no enforza acceso de memoria entre proyectos. Pack core vacío no cambia arranque PM/SDD. Implementar composición, restricciones monotónicas y aislamiento a través del store existente. |
| H12 — Catálogo y contexto no representan runtime | P1/E; `config/domain-packs.json`; `scripts/generate-capability-map.py:write_registry_json`; `docs/critical-facts.md` | No se encuentra generación de domain-packs desde `.scm`; el JSON es entrada manual de facto. Anchor persistente declara frontend/proveedor/modelo concretos. Hacer única la autoridad del catálogo y generar la vista; identidad efectiva por sesión, con unknown explícito y hashes. Regeneración de anchors debe respetar SE-371. |
| H13 — CI verde no verifica estos contratos | P0/E; `.github/workflows/ci.yml` job BATS; `tests/run-all.sh`; `tests/structure/test-opencode-savia-gates-plugin.bats:235` | No se encontró invocación de tests/dual-cli en workflows ni wrappers BATS/shell inspeccionados. Tests del plugin buscan textos; uno exige `return {}`. Falta corpus de comportamiento TS y matriz real. Incorporar jobs explícitos y trazabilidad AC→test→run; un smoke/grep no acredita enforcement. |

## 4. Reproducciones y límites de la evidencia

Ejecutadas mediante `python3 -B` e imports locales, con fixtures de `tests/dual-cli/test_harness_contracts.py` y `test_core.py`, sin editar tests ni módulos. Repetición desde raíz: añadir `scripts/dual-cli` y `tests/dual-cli` a sys.path; importar CONTEXT, RESULT y validadores. Salidas se limitan a estados/fixtures.

| Entrada / comprobación | Resultado observado | Resultado exigido |
|---|---|---|
| `execution_context(dict(CONTEXT,schema=2.0))` | ACCEPTED | UNSUPPORTED_SCHEMA |
| `execution_result(dict(RESULT,external_effect_observed=1))` | ACCEPTED | UNSUPPORTED_SCHEMA |
| Observación status=verified, fecha `2026-09-07`, evidence_ref=`nonexistent-fixture` | ACCEPTED | Fecha inválida; evidencia inexistente jamás certifica |
| Receipt schema=2, request_id=a, decision=deny; execution request_id=b, state=succeeded | ACCEPTED | Inconsistencia de correlación/transición |
| Registrar objeto con sólo `describe()` | ACCEPTED | Falta de puertos bloquea registro de ejecución |
| `activate(load('config/domain-packs.json'),['pm-sdd-legacy'])` | ACCEPTED | Resolver dependencia o bloquear |
| `decode_event` v1 con frontend=fixture | ProtocolError | v1 conserva compatibilidad; extensión por schema negociado |
| Resolver `deepseek/deepseek-v4-pro` y `fixture-unregistered/deepseek-v4-pro` | Ambos status=verified, context=128000 | Segundo unknown/bloqueado |

`build_manifest('.')` real falló con `UNTRUSTED_SOURCE`: no acredita manifest válido. Para H07 se instrumentó únicamente `_safe` con archivos ficticios en memoria y se capturaron las rutas solicitadas: los cinco archivos citados en H07 quedaron fuera. Es evidencia de selección de fuentes, no un run real de certificación. La causa exacta del fallo del manifest real queda fuera del diagnóstico realizado.

## 5. Contrato de reparación propuesto (delta de SE-393)

ADDED: camino verificable `entrada → contexto efectivo → policy → adapter autorizado → supervisor/estado → observación → receipt`. Ninguna entrada protegida puede saltar policy o aceptar nombres de capabilities como autoridad. SE-392 conserva ejecución/leases/recuperación; SE-393 conserva puertos. No introducir daemon adicional ni exigir un único proveedor de inferencia.

MODIFIED: decoder v2 comparte límite 1 MiB y rechazo de duplicados/no finitos con v1; valida tipos exactos (bool no es int), listas, UTC RFC3339 y referencias tipadas. Campos extra sólo bajo `extensions` con claves namespace `owner:key`, sin alterar semántica de seguridad. Datos malformados producen error tipado, nunca excepción no normalizada/allow. Cambios incompatibles requieren negociación; no emitir v2 a clientes v1.

ADDED: descriptor de adapter versionado, registro explícito y validación de puertos `describe/preflight/execute/cancel/observe`; evidencia por capability y ámbito, no por presencia de método. `preflight` valida identidad efectiva tras overrides, sandbox/red/secret boundary y permisos aplicables antes de ejecutar. Cancel solicitado no equivale a proceso terminado. Reconexión con resultado desconocido exige reconciliación y bloquea retry de efectos inciertos.

MODIFIED: separar `validate_observation_shape` de `verify_observation`. El verificador compara digest del artefacto, identidad/versiones del sujeto, contexto/config/policy/entorno/trust y fecha de observación contra valores confiables; `verified` del caller no basta. Cambio de cualquiera de esos ejes invalida sólo las observaciones dependientes. Referencias privadas jamás incluyen contenido de secretos. Plazo de vigencia y bindings permitidos se fijan por capability en el catálogo aprobado, no en el prompt.

MODIFIED: writer recibe contexto real y correlación completa. `request_id` coincide en solicitud, resultado y recibo; decisión y resultado tienen eventos/digests enlazados. Un deny con efecto observado se registra como incidente, nunca como ejecución autorizada. Conteo de gates deriva de eventos observados. V1 queda marcado como evidencia de decisión, incapaz de probar éxito; lector normalizado conserva historia. Registros append-only e IDs únicos impiden sobrescritura silenciosa.

MODIFIED: tupla de modelo conserva proveedor, ID, revisión y modo de inferencia. Metadata incluye fuente y vigencia, diferenciando declarada/observada/unknown. Configuración de roles usa IDs cualificados; aliases legacy sólo en adapters. Fallback necesita autorización de datos y ruta antes del envío. CLI que oculta proveedor/modelo conserva null y no certifica esos ejes.

MODIFIED: packs son vistas deterministas del catálogo SE-375. Activación resuelve dependencias/versiones/ciclos y conflictos antes de inyectar contexto; sólo agrega restricciones. Memoria incorpora proyecto y dominio al control de acceso en lecturas/escrituras, no sólo al nombre del namespace. Core permite artefactos locales sin ADO/Jira/sprint/.NET; PM/SDD permanece pack compatible y opt-in.

## 6. Criterios de aceptación y estrategia de pruebas

| AC / gaps | Given → When → Then |
|---|---|
| AC01 / H01 | Tres adapters explícitos, tercero fixture → handshake/dispatch v2 → mismo camino policy/supervisor; desconocido o sin puertos bloqueado; v1 sigue negociando sólo v1. |
| AC02 / H02 | Dos CLI reales autorizadas → iniciar/stream/cancelar/reconectar → recibos correlacionados; seleccionar alternativa no requiere binario Claude; cancel/retry no duplica efectos. |
| AC03 / H03 | Corpus común con exit 1/2, timeout, crash, JSON inválido, deny/ask/continue:false, settings ausentes y async crítico → ejecutar cada adapter → mismo deny y cero efectos; fallo de telemetría separado. |
| AC04 / H04 | Casos de §4, bool/int, null, lista como enum, duplicados y mensaje >1 MiB → decodificar → error tipado; UTC válida y extensions permitidas pasan. |
| AC05 / H05 | Proceed seguido de fallo, deny sin ejecución, efecto posterior a deny e IDs cruzados → emitir/leer → estados fieles; inconsistencia rechazada o incidente explícito; cero PASS inferido; gate count observado. |
| AC06 / H06 | Ref inexistente, digest alterado, fuente no confiable, evidencia caducada, strings truthy, adapters duplicados → certificar → bloqueo; fixture validada explícitamente no se mezcla con evidencia operacional. |
| AC07 / H07 | Mutar cada dependencia Python/TS/model config/pack ref en copia temporal → recalcular manifest y verificar evidencia previa → digest cambia y STALE_EVIDENCE; symlink no confiable sigue bloqueado. |
| AC08 / H08,H09 | Dos proveedores con mismo ID corto, modelo desconocido y metadata caducada → resolver/planificar/fallback → capacidades separadas; cero transmisión a ruta no autorizada; techo no cambia. |
| AC09 / H10 | Cold start, control benigno en sandbox efectivo, escritura y ciclo fail/fix reales → doctor → estados diferenciados; sandbox roto produce infraestructura/unknown; siete vías protegidas usan sentinelas sin secretos reales. |
| AC10 / H10 | Override elimina deny o habilita red → preflight protegido → bloqueo; L3 human gate y L4 deny se registran como garantías, nunca capacidad graduada. |
| AC11 / H11,H12 | Packs vacío, PM y documental + dependencias ausentes/cíclicas y reglas conflictivas → activar → tarea local independiente o bloqueo explícito; dos proyectos/dominos no leen ni escriben memoria ajena. |
| AC12 / H12 | Mismos inputs de catálogo y dos sesiones de frontends distintos → generar vistas/contexto → vistas idénticas, identidad de sesión separada; sin identidad runtime persistida en anchor global. |
| AC13 / H13 | Romper deliberadamente validator, gate TS o correlación en fixture de CI → checks pertinentes fallan; CI invoca suites Python/TS directamente y conserva resultado, cobertura y hash del corpus. |
| AC14 / todos | Matriz autorizada con dos CLI, dos proveedores, dos modelos por proveedor y tres packs → runs reales por eje y pares compatibles → celda con versión/contexto/recibo/resultado; unknown/skipped no certifica esa celda. |

Unitarios y corpus adversarial primero; integración local con procesos/archivos temporales después; operacional real al final. Los doubles demuestran contratos, no enforcement de CLI ni prestaciones de modelo. AC14 mantiene SE-393 AC12, sin exigir combinaciones imposibles ni crear cuentas/gasto automático. Baseline, harness, corpus y artefactos de cada ejecución deben quedar congelados antes de comparar resultados. CI verde es requisito adicional al cumplimiento de ACs.

## 7. Slices, ownership y archivos previstos

| Slice | Archivos existentes a reparar / propuesta nueva | Ownership y salida |
|---|---|---|
| S0 — Confianza | `scripts/dual-cli/contracts.py`, `autonomy.py`, `preflight.py`, `tests/dual-cli/test_harness_contracts.py`, `test_autonomy.py`, `test_config.py` | SE-393/394: AC04–06; primero bloquear falsos positivos. |
| S1 — Enforcement | `scripts/opencode-plugin/savia-gates/lib/shell-bridge.ts`, `scripts/dual-cli/policy.py`, `codex_profile.py`, `autonomy_doctor.py`, `tests/dual-cli/test_doctor.py`; nuevo `tests/dual-cli/test_gate_parity.py` | SE-391/392/383: AC03,09,10; pruebas TS de comportamiento junto al plugin. |
| S2 — Composición | `scripts/dual-cli/runtime.py`, `protocol.py`, `client.py`, `state.py`, `scripts/savia-bridge.py`, `scripts/model-gateway.py`, `tests/dual-cli/test_runtime.py` | SE-392/393: AC01,02; concretar adapters por CLI autorizada antes de implementar slice. |
| S3 — Modelos | `scripts/model-capability-resolver.sh`, `scripts/surrogate/llm-router.py`, `config/model-registry.json`, `config/model-capabilities.yaml`, `tests/dual-cli/test_provider_identity.py` | SE-393: AC08; resolver roles/bindings con procedencia. |
| S4 — Dominio/config | `scripts/dual-cli/domain_packs.py`, `config.py`, `config/domain-packs.json`, `scripts/generate-capability-map.py`, `CLAUDE.md`, `docs/critical-facts.md`, `tests/dual-cli/test_domain_packs.py` | SE-375/393: AC07,11,12; concretar punto de enforcement de memoria con su propietario. |
| S5 — Cierre | `.github/workflows/ci.yml`, `tests/dual-cli/README.md`, `docs/frontend-compatibility.md`; evidencia privada y manifiesto público redactado | SE-380/383/393: AC13,14; trazabilidad de cada AC y estado real de soporte. |

S0 precede a consumo de evidencia; S1 y S2 preceden a certificación; S3/S4 necesitan contexto integrado; S5 verifica cada slice y cierre. Los nombres abreviados en celdas conservan el directorio del primer archivo; los módulos dual-cli no se duplican. Esta es una spec de reparación transversal PROPOSED, no un contrato ya aprobado para ejecución autónoma completa. Antes de implementar S2/S4 deben concretarse bindings, archivos de adapters y punto de control de memoria mediante slices revisables.

## 8. Decisiones, límites y cierre

Decisiones humanas de aprobación: combinaciones objetivo y versiones; procedencia/vigencia de evidencia por capability; compatibilidad de consumidores del resolver; autoridad y migración del catálogo de packs; mecanismo de aislamiento de memoria existente. Esta auditoría propone contratos y opciones acotadas, pero no asigna nuevas autoridades ni cambia datos privados.

No tocar durante esta entrega: AGENTS.md, memoria, índices generados o lifecycle previo. No implementar L3/L4 autónomos, nuevo sistema de secretos, otro runtime/catálogo, refactor masivo ni sincronización de historiales nativos. El código y tests reparados quedan limitados a los archivos de los slices descritos; AC02/AC14 requieren todavía adapters y evidencia operacional real. Futuro cierre: AC01–14 trazables, revisión arquitectura/seguridad, compatibilidad y CI verde, evidencia real por combinación. Mantener Codex DEGRADED_SAFE y autoridad máxima L2; nivel observado se declara sólo con evidencia válida.

Estimación orientativa del conjunto pendiente: 4–8 semanas-persona incluyendo integración y verificación, confianza baja; no se suma mecánicamente a SE-391/392 porque comparten trabajo. Agent-capable: parcial, contexto alto; esfuerzo agente no estimable hasta concretar slices. Reservar revisión humana por slice, no una única aprobación final de un cambio transversal.

## 9. OpenCode Implementation Plan

Bindings afectados en futura reparación: OpenCode (plugin y gates), Codex (perfil efectivo/doctor) y Claude (bridge compatible); proveedores directos mediante adapters separados. Clasificación legacy DUAL_BINDING extendida explícitamente a los tres frontends, sin reclamar paridad. Verificación: corpus común, pruebas nativas y matriz AC14; imports, hooks, secretos y reanudación se observan por frontend. Regeneraciones respetan SE-371. Estado de esta entrega: S0–S5 implementados de forma acotada en contratos, preflight, runtime local, packs, manifest, resolver de modelos, bridge fail-closed y CI. La sustitución operacional de dos CLIs/proveedores y la matriz real AC14 permanecen pendientes de evidencia y aprobación; no se certifican por estos cambios.
