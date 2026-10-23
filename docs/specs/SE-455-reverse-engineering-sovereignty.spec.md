---
status: APPROVED
approved_at: 2026-10-23
approved_by: "operadora, AskUserQuestion 2026-10-23"
priority: P2
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L3
related_specs: [SE-450, SE-444, SE-456]
origin: vaults/SaviaLabs/labs/research/20261020-learnings-goose-gentledot-rea.md (R7)
resource: https://github.com/morluto/rea
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-455 — Ingeniería inversa para la soberanía tecnológica (REA como herramienta externa opcional)

## Problema

Hay preguntas que solo se responden mirando el programa que de verdad se ejecuta, no su documentación ni la palabra del
proveedor:

- **¿Qué envía esta aplicación, y a quién?** La política de privacidad dice una cosa; el binario hace otra.
- **¿Cómo salgo de aquí?** Para migrar a una alternativa abierta hay que leer los formatos y los protocolos que el
  proveedor no documenta.
- **¿Cómo mantengo esto sin fuentes?** El proveedor ha desaparecido o ya no da soporte.

Savia ya plantea estas preguntas, pero solo tiene herramientas para el código fuente:

- `sovereignty-auditor` mide la dependencia del equipo respecto a la IA, pero no qué hace el software opaco que usa.
- `/legacy-assess` y `cobol-developer` dan por hecho que hay fuentes.
- `mobile-security-scanner` (MobSF) cubre APK, pero no Electron, .NET, binarios nativos ni firmware.

La soberanía tecnológica de un pueblo, de una administración o de una comunidad empieza por poder **comprobar** lo que
hace el software del que depende, y por poder **salir** de él.

## Valor y evidencia

- **REA (Reverse Engineer Anything, MIT)** es un MCP y una CLI locales de ingeniería inversa: binarios nativos con
  Ghidra, Hopper o IDA; JavaScript y Electron; .NET; APK con JADX; firmware; capturas de red y de procesos.
  - Su salida es evidencia, y separa cuatro clases: observación, derivación, inferencia y desconocido.
  - Funciona en local, sin servicio en la nube.
  - Su instalador enseña el plan, hace copia de seguridad y pide aprobación antes de escribir.
  - No instala Java, Ghidra ni Node (`AGENTS.md`, `docs/installation.md`).
- **El fork de la operadora** (`gonzalezpazmonica/rea`) no tiene commits propios. REA es de terceros: se usa como
  proceso externo instalado por la persona, nunca embebido ni redistribuido.
- **Marco legal.** En España y la UE la ley protege usos concretos de la ingeniería inversa:
  - Observar, estudiar y verificar el funcionamiento de un programa del que se tiene licencia: art. 100.3 de la Ley de
    Propiedad Intelectual (LPI) y art. 5.3 de la Directiva 2009/24/CE.
  - Descompilar para conseguir interoperabilidad, con condiciones: art. 100.5 y 100.6 de la LPI y art. 6 de la
    Directiva.
  - Saltarse medidas tecnológicas de protección no está protegido (art. 160 LPI).
  - **Verificar con `legal-compliance` antes de aprobar.** El corpus `legalize-es` no está instalado en esta máquina:
    las citas salen del conocimiento previo y no se han contrastado con el texto consolidado.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Skill `reverse-engineering-sovereignty` (`.claude/skills/`). Cubre propósito, autorización, flujo por tipo de objetivo, clases de evidencia, salida e integración. No instala nada: la persona registra REA siguiendo su `setup --dry-run` y lo aprueba. |
| S2 | Puerta de autorización en la skill, antes de cualquier análisis. Se clasifica el objetivo: **A** software propio o de la organización de la persona; **B** de terceros con autorización escrita; **C** de terceros dentro de un uso que la ley permite (estudiar el funcionamiento de una copia con licencia, o interoperabilidad); **D** cualquier otro caso, que se rechaza. B y C exigen doble confirmación y que quede registrada la base legal. |
| S3 | Líneas que no se cruzan, escritas en la skill: no saltar medidas de protección, licencias ni DRM; no extraer credenciales ni secretos de terceros; no redistribuir el código descompilado; no crear malware ni exploits contra terceros; no subir artefactos de nivel N3 o superior a la nube. |
| S4 | Integración. `sovereignty-auditor` gana una dimensión opcional, «software opaco»: qué componentes críticos no se pueden comprobar ni sustituir. `/legacy-assess` remite a la skill cuando no hay fuentes. |
| S5 | Plantilla de informe: hallazgos separados en observación, derivación, inferencia y desconocido; una sección «Lo que no demuestra»; base legal y autorización; recomendaciones de salida (formatos, protocolos y alternativas abiertas). |

## Fuera de alcance

- Instalar REA, Ghidra, Java, JADX o cualquier motor: lo hace la persona.
- Ejecutar análisis reales en este PR: la skill da instrucciones, no hace llamadas.
- Pentesting de terceros: sigue con `pentesting` y su propia autorización.
- Publicar resultados de análisis de software de terceros: necesita revisión legal aparte.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bash scripts/skill-catalog-auditor.sh` sin FAIL para la skill nueva; descripción de 200 caracteres o menos, con «Usar cuando…». |
| AC2 | `bats tests/test-se-455-reverse-engineering-sovereignty.bats` pasa: la skill contiene las clases A, B, C y D, la doble confirmación de B y C, y las cinco líneas que no se cruzan de S3 (`grep` literal por cada una; si falta una, el test falla). |
| AC3 | El mismo test comprueba que la skill no contiene órdenes de instalación sin `--dry-run` (`npx … setup` sin `--dry-run` hace fallar el test) ni rutas personales. |
| AC4 | `sovereignty-auditor/SKILL.md` documenta la dimensión «software opaco» como opcional y sin peso por defecto. Su test sigue en verde. |
| AC5 | La plantilla de informe tiene las secciones de S5 (`grep` de los cuatro encabezados de evidencia y de «Lo que no demuestra»). |
| AC6 | `capability-entropy.py --check` PASS; `sam.py check` FRESH; `confidentiality-scan --pr` sin bloqueo. |

## Riesgos

- **Uso dual.** La ingeniería inversa sirve para comprobar y para atacar. Mitigación: la puerta de S2, las líneas de S3,
  la doble confirmación y la base legal registrada. Riesgo L3: el merge requiere revisión humana explícita.
- **Error legal.** Las citas están pendientes de verificación con `legal-compliance` (decisión D1).
- **Dependencia de un proyecto de terceros muy activo**, con cambios de API frecuentes. Mitigación: la skill remite a la
  ayuda de REA (`--help`, `doctor`) y fija versión en el registro manual; no duplica su documentación.

## Licencia de lo reutilizado

REA es MIT; sus motores (`third_party/`) conservan sus licencias. No se copia código: la skill describe cómo usar la
herramienta externa y enlaza a su documentación.

## Esfuerzo

S1 a S3: S. S4: S. S5: S.

## Decisiones pendientes de la operadora

- **D1**: revisión legal antes del merge (propuesta: `legal-compliance` sobre S2 y S3, con el corpus `legalize-es`
  instalado).
- **D2**: nombre de la skill (propuesta: `reverse-engineering-sovereignty`).

## Referencias cruzadas

SE-450 (higiene de instaladores, también aprendida de REA), SE-444 (autoridad del verificador),
SE-456 (criterio de evidencia de REA aplicado a la QA de Savia), `docs/rules/domain/savia-ethical-principles.md`,
`.claude/skills/sovereignty-auditor/`, `.claude/skills/mobile-security-scanner/`.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Skill `reverse-engineering-sovereignty` | `.claude/skills/reverse-engineering-sovereignty/SKILL.md` | `.opencode/skills` es un enlace a `.claude/skills`: la misma skill |
| MCP de REA (opcional, lo registra la persona) | `rea setup --client claude_code` | `rea setup --client opencode` (REA escribe la entrada `mcp.rea` que cargan OpenCode V1 y V2) |

### Verification protocol

- [ ] La skill se descubre en los dos frontends (mismo directorio).
- [ ] Los tests BATS no dependen del frontend.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: skill en Markdown y tests BATS; el registro del MCP lo hace REA para los dos clientes.
