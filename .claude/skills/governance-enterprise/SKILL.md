---
layer: peripheral
name: governance-enterprise
description: "Revisa governance enterprise. Usar cuando se audita compliance o se registran decisiones; nunca emite certificaciones."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: governance
  savia.context: fork
  savia.context_cost: medium
  savia.dependencies: 
  savia.memory: project
  savia.priority: high
  savia.summary: "Gobernanza empresarial: audit trail, revisión preliminar de compliance y registro de decisiones."
  savia.tags: "governance, audit-trail, certification, enterprise"
---

# Skill: Enterprise Governance

> Prerequisito: @docs/rules/domain/governance-enterprise.md, @docs/rules/domain/audit-trail-schema.md

Orquesta audit trail, revisión preliminar de cumplimiento y registro de decisiones. Para evaluaciones basadas en evidencia, usar `grc-auditor`.

## Qué es ejecutable y qué es prosa

Los flujos 1-3 son procedimientos que sigue el modelo; no hay script que los implemente (`.audit-trail/actions.jsonl` no lo escribe ningún ejecutable del repo). Lo único ejecutable y probado (`tests/test-governance-enterprise.bats`) son estos dos scripts de SPEC-SE-006:

| Script | Qué hace de verdad | Exit |
|---|---|---|
| `scripts/enterprise/governance-audit-trail.sh` | `append` / `verify [--anchor H]` / `export md\|json` / `chain-status` sobre `${CLAUDE_ENTERPRISE_AUDIT_BASE:-.claude/enterprise/audit}/{tenant}/audit-trail.jsonl` | 0 íntegro · 1 manipulado, vacío o fallo · 2 argumentos |
| `scripts/enterprise/compliance-check.sh` | Revisión documental por marco (`eu-ai-act`, `gdpr`, `nis2`, `dora`, `all`); JSON con `score = aprobados*100/total` | 0 solo si todo marco da 100 · 1 brechas · 2 argumentos o salida no escribible |

Garantías del audit trail:

- Append bajo lock (fichero `<trail>.lock` creado con `O_EXCL`; no `mkdir`, que en uutils-coreutils 0.10 no era exclusivo): escrituras concurrentes producen una cadena válida. Un lock ajeno agota `AUDIT_LOCK_TRIES` (100 × 0,1 s) y falla sin escribir.
- Cada línea tiene forma canónica exacta; `verify` rechaza claves duplicadas, campos extra, líneas en blanco, CRLF, BOM, bytes NUL (el fichero entero) y la última línea aunque no acabe en salto de línea. Revalida cada campo (sin tabuladores ni vacíos) y exige `ts` con rangos de calendario válidos y sin retroceder.
- `verify --tenant T` falla si alguna entrada es de otro tenant (trail copiado a un directorio ajeno). `append` se niega a escribir si el reloj es anterior a la última entrada.
- El hash cubre `ts`, `tenant`, `actor`, `action`, `spec` y `prev_hash`, un campo por línea (sin fronteras ambiguas). `prev_hash` es el hash hexadecimal de la entrada previa.
- Campos validados al escribir: tenant `[A-Za-z0-9][A-Za-z0-9._-]{0,63}` (sin path traversal); actor/action/spec de 1-256 caracteres sin comillas, barras invertidas ni caracteres de control.
- `append` se niega a encadenar sobre una cola corrupta; nunca reinicia la cadena desde génesis.
- `verify` sobre un trail vacío falla (`CHAIN EMPTY`): no hay nada que demuestre integridad.

Límite: es sha256 sin clave ni firma. Quien pueda escribir el fichero puede recalcular la cadena entera, y truncar la cola deja una cadena válida. Para detectarlo, publicar fuera del trail el hash completo de `chain-status` y verificar con `verify --anchor <hash>`. El ancla solo protege hasta la entrada anclada: lo escrito después del último ancla publicado puede reescribirse sin detección.

Garantías de `compliance-check`: ningún check aprueba por mera presencia de un fichero o directorio. Exige contenido:

- Documentos de política: al menos 3 líneas sustantivas (sin títulos, citas, separadores ni vacías) y las palabras clave del tema (revisión humana, audit trail, sesgo, niveles N4, un plazo de retención concreto, gates de `agent/`/PR Draft/merge). PII, postura de seguridad y política de parches buscan en `docs/` documentos que cumplan lo mismo.
- Model cards: todas con contenido y secciones `Purpose` y `Limitations`; una card hueca suspende el check.
- Incidentes: al menos un postmortem `.md` con contenido en `output/postmortems/`.
- `manifest.json`: objeto JSON no vacío con `modules` no vacío; manifiesto GLM: objeto no vacío. `null`, `[]` y `{}` suspenden; sin `python3` no se pueden analizar y suspenden.
- `audit_trail_exists`: al menos un trail y todos pasan `verify --tenant <directorio>` (incluidos los enlazados simbólicamente). Sin `--anchor` la evidencia lo dice («without anchor: truncation or full recomputation not excluded»); `--tenant T --anchor H` exige que el ancla siga en la cadena. Sin verificador disponible suspende como «not verified».

Las palabras clave siguen siendo una heurística: no juzgan la calidad del texto ni prueban eficacia operativa. La salida lleva `"tenant": "all"` salvo con `--tenant`. `SAVIA_COMPLIANCE_ROOT` permite evaluar otro workspace.

## Flujo 1 — Audit Trail (`audit-trail`)

1. Leer `.audit-trail/actions.jsonl` (activo) + archive/YYYY-MM.jsonl (histórico)
2. Permitir queries por: usuario, rango fechas, tipo acción, target
3. Generar resumen: total acciones, distribution por tipo, failures
4. Output: tabla de acciones + query stats

**Query examples**:
```
/governance-enterprise audit-trail --user @monica --since 2026-02-01
/governance-enterprise audit-trail --action delete --from 2026-01 --to 2026-03
/governance-enterprise audit-trail --target pbi --result failure
```

## Flujo 2 — Compliance Check (`compliance-check`)

1. Leer governance-enterprise.md (matriz de controles)
2. Por cada control: verificar evidencia más reciente
3. Calcular score por control (0-100 basado en fecha de última ejecución):
   - Fresh (< 30 días) = 100
   - Valid (31-90 días) = 75
   - Stale (91-180 días) = 50
   - Missing (> 180 días) = 0
4. Agregar por categoría (GDPR, ISO, AI, AEPD)
5. Generar `output/governance/compliance-check-YYYYMMDD.md`
6. Output: tabla scores + recomendaciones + remediation plan si needed

## Flujo 3 — Decision Registry (`decision-registry`)

1. Leer decision-registry.md
2. Por cada decisión: validar que tiene evidencia en file system
3. Listar decisiones activas + superseded + revoked
4. Detectar decisiones sin evidencia (gap warning)
5. Generar resumen: total decisiones, distribution por status
6. Output: registry formatted + gaps + next decisions needed

## Flujo 4 — Solicitud de certificación (`certify`)

No emitir certificados ni declaraciones de conformidad, con independencia del score. Responder con un paquete de preparación: alcance, marcos y versiones, controles, evidencias trazadas, brechas y decisiones pendientes. Remitir la certificación formal a la entidad competente. Un umbral numérico interno no prueba eficacia operativa ni otorga autoridad certificadora.

## Errores

| Error | Acción |
|---|---|
| Audit trail no encontrado | Informarlo como gap; el trail SE-006 se inicializa con `governance-audit-trail.sh append` |
| Control sin evidencia | Marcar como gap; ningún score habilita una certificación |
| Decision registry corrupto | Validar YAML; mostrar errores |
| Solicitud de certificado oficial | Preparar dossier de evidencias; no certificar |

## Seguridad

- NUNCA exponér audit trail en reports públicos
- Los informes preliminares no se presentan como certificaciones
- Decision registry puede ser compartida (referencias a evidencia, no datos)
- Respect user privacy: después 4 años, anonimizar user field en audit trail
