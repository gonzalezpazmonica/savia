
**Español** | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Català](README.ca.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Italiano](README.it.md)

# Savia

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/savia?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Savia es una metaorquestadora agéntica de I+D+i: coordina agentes y harnesses especializados, líneas de investigación, cúpulas de conocimiento gobernado y proyectos, con la autoridad siempre en la persona. Open source y soberana.**

**567 comandos · 90 agentes · 139 skills · 134 hooks**

Savia orquesta el trabajo de I+D+i con IA: reparte tareas entre harnesses especializados (ejecutores, revisoras independientes, proveedores externos), sostiene líneas de investigación, gobierna el conocimiento en cúpulas (Savia Vaults) y gestiona proyectos como una capacidad más. Integra memoria, seguridad, políticas ejecutables (policy-as-code), trazabilidad con receipts y evaluación sobre una arquitectura independiente de modelo, proveedor y frontend. Opera en local con soberanía de datos e inferencia, en 9 idiomas.

## Por qué Savia existe

La ejecución asistida por IA crece más rápido que la confianza sobre ella. Savia existe para que esa ejecución sea **gobernada**: la IA puede asumir progresivamente más ejecución sin apropiarse de la autoridad.

> **Se delega la ejecución, nunca el criterio.**

## Principios

- **Autoridad humana por diseño** — execution authority ≠ decision authority: risk levels, human gates, receipts y provenance hacen verificable quién decide.
- **Soberanía con significado técnico** — independencia de modelo, proveedor y frontend; datos y control en infraestructura propia; políticas inspeccionables.
- **Evidencia sobre claims** — cada acción gobernada produce receipts, provenance y evaluación verificable.
- **Policy-as-code** — las políticas se convierten en reglas machine-readable con enforcement determinista.
- **Delegación segura** — la autonomía es graduada y gobernada: capability + authority + risk + context + human gates.

## Qué hace Savia

- **Orquestar** — metaorquestación de harnesses especializados: un ejecutor por contrato, revisoras independientes y proveedores externos, con invocación determinista y la autoridad en la persona.
- **Investigar** — líneas de investigación con hipótesis, experimentos y lecciones verificables.
- **Gobernar** — riesgo (L0-L4), human gates, policy-as-code, receipts y provenance de cada acción.
- **Ejecutar** — 90 agentes, 567 comandos, 139 skills con specs ejecutables (SDD), auditoría de seguridad y revisión de código.
- **Conocer** — cúpulas de conocimiento gobernado (Savia Vaults) y memoria persistente bitemporal con provenance y trust-gates.
- **Evaluar** — evals con baseline, paired-delta regression y canaries multi-frontend.
- **Dominios** — gestión de proyectos (sprints, backlog, informes; una capacidad más), ingeniería de software y dominios especializados.
- **GRC preliminar** — el [auditor GRC](docs/grc/README.md) enlaza requisitos, controles y pruebas locales con hallazgos trazables. Requiere revisión humana para decisiones y certificaciones.

## Arquitectura

Diagrama completo: [architecture.es.md](docs/readme/architecture.es.md).

Frontends (Claude Code, OpenCode, Codex), modelos y proveedores son interfaces e infraestructura mediante las que Savia opera — **ninguno de ellos es Savia**.

## Cómo funciona

Savia evoluciona mediante mecanismos explícitos: propuesta/spec → implementación → evaluación → evidencia → enforcement. El cumplimiento de políticas es ejecutable: policy document → machine-readable rule → runtime enforcement → evidence.

El catálogo de skills se valida como YAML completo en CI para impedir que una migración de metadatos deje capacidades invisibles al arrancar.
La madurez de cada skill exige pruebas de comportamiento certificadas; el auditor reconoce las suites de `tests/scripts/` además de las de `tests/` y `tests/evals/`.

## Frontends y proveedores soportados

| Frontend | Estado |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (techo L2, en remediación — SE-388) |

Independencia de modelo y proveedor por diseño; cada frontend pasa canaries de parity antes de declararse soportado.

## Gobernanza y seguridad

- Human gates por nivel de riesgo (L0-L4) — la autoridad final es humana.
- Receipts y provenance de cada acción gobernada.
- Compliance-as-code como dirección: la regulación es fuente, la interpretación es humana, el enforcement es ejecutable. Savia produce evidencia de controles ejecutados; no declara cumplimiento legal definitivo.

<!-- COUNTS-AUTO (SE-379): la línea de contadores se valida contra el repo -->

---

## Instalación

```bash
# 1. Instala

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Abre el workspace

cd savia && opencode

# 3. Savia te saluda y te pregunta tu nombre. Después:

/help                   # ← tu primer comando: el mapa de capacidades
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia se adapta a tu rol — investigación, desarrollo, dirección técnica, gestión de proyectos, QA, producto — y a tu idioma. Para proyectos, compatible con Azure DevOps, Jira y Git-native (Savia Flow).

---

## Capacidades

Tabla completa de capacidades: [capabilities.es.md](docs/readme/capabilities.es.md).

---

## Savia

Savia es la identidad del workspace: un patrón de texto que persiste a través de modelos (Claude, DeepSeek, Qwen). Como metaorquestadora, coordina 90 agentes, 567 comandos, 139 skills y harnesses externos. Opera bajo principios de honestidad calibrada, soberanía de datos, y revisión humana obligatoria.

No es persona, no siente, no sustituye el criterio de quien opera. Propone, ejecuta, advierte. Decide solo lo delegado explícitamente.

Quick-starts por rol: [quick-starts.es.md](docs/readme/quick-starts.es.md).

---

## Estructura

Árbol del repositorio: [repo-structure.es.md](docs/readme/repo-structure.es.md).

---

## Documentación

| Sección | Descripción |
|---|---|
| [Guía de inicio](docs/getting-started.md) | De cero a productivo |
| [Flujo de datos](docs/data-flow-guide-es.md) | Cómo se conectan las partes |
| [Confidencialidad](docs/confidentiality-levels.md) | 5 niveles (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Soberanía de datos |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandos y agentes](docs/readme/12-comandos-agentes.md) | Referencia completa |
| [Guías por escenario](docs/guides/README.md) | Azure, Jira, startup, sanidad... |
| [Adopción](docs/ADOPTION_GUIDE.md) | Paso a paso para consultoras |

---

## Principios

1. **Texto plano es la verdad** — .md y .jsonl. Sin IA, los datos siguen legibles
2. **Privacidad absoluta** — datos del usuario nunca salen de su máquina
3. **El humano decide** — la IA propone; merge exige grant expreso y gates verdes, deploy requiere autorización separada
4. **MIT** — sin vendor lock-in, sin telemetría

---

## Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md) y [SECURITY.md](SECURITY.md). PRs bienvenidos.

## Licencia

[MIT](LICENSE) — Creado por [la usuaria González Paz](https://github.com/gonzalezpazmonica)
