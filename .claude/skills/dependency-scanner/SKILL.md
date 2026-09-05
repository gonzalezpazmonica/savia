---
layer: peripheral
name: dependency-scanner
description: "Usar cuando se escanean vulnerabilidades en dependencias de proyectos (Node, Python, C#, Java, Go, Rust, Ruby) con Trivy fs. Genera SBOM CycloneDX."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: security
  savia.maturity: stable
  savia.context: fork
  savia.context_cost: low
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Escanea manifiestos de dependencias con Trivy filesystem mode. Detecta CVEs en npm, pip, nuget, maven, cargo, go.mod, bundler. Genera SBOM CycloneDX JSON como artefacto de release. Bloqueante: CRITICAL/HIGH → exit 1. Informativo: MEDIUM/LOW. Output en output/security/."
  savia.tags: "security, dependencies, trivy, sbom, cve, supply-chain"
  savia.trigger_keywords: "escanea dependencias, vulnerabilidades en paquetes, dep scan, SBOM, supply chain security, CVE en npm, CVE en pip, vulnerabilidades node, vulnerabilidades python, dependency vulnerability"
---

## Subagent Scope Guard

> Si fuiste invocado como subagente para una tarea concreta, ejecuta solo esa
> tarea, reporta DONE / DONE_WITH_CONCERNS / BLOCKED y retorna.

# Dependency Scanner Skill

## §0 Cuándo usar

- Después de que un agente de lenguaje genera un proyecto con dependencias
- En CI en cada PR que toca `package*.json`, `requirements*.txt`, `*.csproj`, etc.
- Antes de un release para generar el SBOM obligatorio (proyectos enterprise)
- Cuando el humano pide revisar vulnerabilidades en dependencias

## §1 Activación por language pack

Este skill se activa automáticamente cuando se trabaja con:

| Language Pack | Manifiestos escaneados |
|---|---|
| TypeScript/Node | package.json, package-lock.json, yarn.lock |
| Python | requirements.txt, Pipfile, pyproject.toml |
| .NET/C# | *.csproj, packages.config, packages.lock.json |
| Java | pom.xml, build.gradle |
| Go | go.mod, go.sum |
| Rust | Cargo.toml, Cargo.lock |
| Ruby | Gemfile, Gemfile.lock |

## §2 Uso básico

```bash
# Escanear proyecto
bash scripts/dependency-scan.sh --path ./project/

# Generar SBOM CycloneDX además del report
bash scripts/dependency-scan.sh --path ./project/ --generate-sbom

# Solo CRITICAL (más estricto para CI)
bash scripts/dependency-scan.sh --path ./project/ --severity CRITICAL

# Modo offline (DB ya descargada)
bash scripts/dependency-scan.sh --path ./project/ --skip-update
```

## §3 Auto-detección de tipo de proyecto

El script detecta automáticamente el tipo de proyecto buscando manifiestos
conocidos. No requiere configuración manual del lenguaje.

## §4 Fallback Docker

Si Trivy no está instalado localmente:

```bash
docker run --rm -v "$(pwd):/workspace" aquasec/trivy:latest fs /workspace
```

## §5 SBOM — Software Bill of Materials

El SBOM en formato CycloneDX es un artefacto de release obligatorio para
proyectos enterprise. Documenta exactamente qué dependencias incluye el
software. Generarlo no requiere conectividad extra (DB local).

```
output/security/sbom-YYYYMMDD.json     ← SBOM CycloneDX
output/security/dep-scan-YYYYMMDD.json ← Report de CVEs
```

## §6 Gestión de vulnerabilidades encontradas

1. **CRITICAL**: siempre actualizar la dependencia afectada
2. **HIGH con fix disponible**: actualizar en el sprint actual
3. **HIGH sin fix**: suprimir en `.trivyignore` con justificación y fecha
4. **MEDIUM/LOW**: informativo — planificar en el backlog

Ver política completa: `docs/rules/domain/dependency-security-policy.md`
