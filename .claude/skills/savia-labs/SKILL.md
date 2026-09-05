---
layer: peripheral
name: savia-labs
description: "Usar cuando se investiga, experimenta o audita epistemicamente. Triggers: 'investiga', 'experimento', 'hipotesis', 'preregistro', 'labs', 'divergencia', 'certificado de ignorancia', 'corpus de desconocidos', 'auditoria de reclutamiento', 'federacion epistemica', 'diversidad de calidad', 'desconocidos desconocidos', 'punto ciego', 'preregistrar'."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: research
  savia.maturity: stable
  savia.context: project
  savia.maturity: experimental
  savia.priority: medium
  savia.tags: "labs, investigacion, epistemologia, experimentos, preregistro, divergencia"
---

# Savia Labs — Investigacion Epistemica

Cupula de investigacion sobre desconocidos desconocidos.

## Disciplina

1. **Preregistro obligatorio**: toda hipotesis se registra ANTES de ejecutar
2. **Resultados negativos de primera clase**: confirmacion, refutacion e inconcluso
3. **Reproducibilidad**: version de modelo, revision vault, semilla, hash corpus
4. **Validacion humana**: descubrimiento maquina, validacion humano
5. **Presupuesto por ciclo**: tokens y horas declarados antes de empezar

## Comandos

- `/labs preregister` — preregistrar hipotesis
- `/labs hypotheses` — listar hipotesis activas
- `/labs results` — consultar resultados
- `/labs notebook` — leer cuaderno de laboratorio
- `/labs protocol <line>` — ver protocolo de una linea
- `/labs health` — estado del laboratorio

## Lineas de investigacion

| Linea | Hipotesis |
|---|---|
| L1 | Divergencia grafo-modelo predice error mejor que confianza declarada |
| L2 | Certificados estructurados de ignorancia producen mas resoluciones |
| L3 | Preguntas cross-dominio producen mayor confabulacion |
| L4 | Brecha entre capacidad aislada y despliegue bajo carga |
| L5 | Divergencia entre instancias federadas localiza infradeterminacion |
| L6 | Busqueda por diversidad descubre clases de fallo no aleatorias |

## Vault

- Cúpula: `SaviaLabs` (SaviaVaults)
- **IMPORTANTE (decisión 2026-08-21)**: la cúpula SaviaLabs ES la persistencia
  viva e inmediata, NO un destino de copia ni un backup. Todo artefacto de
  trabajo (preregistro, hipótesis, protocolo, experimento, resultado, notebook)
  se escribe DIRECTAMENTE en la cúpula en el momento del trabajo.
- **Acceso SIEMPRE por MCP, nunca por filesystem**: usar las herramientas
  `savia-vaults_*` (`vault_write`, `vault_read`, `vault_search`, `vault_list`,
  `vault_graph`) para leer y escribir la cúpula. El directorio
  `vaults/SaviaLabs/` es la implementación interna del servidor; otros Savias
  consumen la cúpula vía MCP y este workspace ES el servidor que las sirve.
  Escribir por `Read`/`Edit`/`Write`/`cp` sobre el directorio rompe el contrato
  (no indexa, no commitea con content-hash, no propaga). Lección ya persistida:
  `LP-20260820-ac39b5b5` ("usar tools MCP, no filesystem").
- `labs/` raíz es symlink a la cúpula SOLO como comodidad de los scripts bash
  del bucle (PURE_BASH no habla MCP); el consumo de conocimiento es por MCP.
- Schema: `projects/savia-vaults/schema/entities/`
- Tipos: hypothesis, experiment, result, protocol
