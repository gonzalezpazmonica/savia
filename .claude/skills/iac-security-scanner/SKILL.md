---
layer: peripheral
name: iac-security-scanner
description: "Usar cuando se escanea IaC (Terraform, Bicep, Dockerfile, docker-compose) con Trivy config para detectar misconfiguraciones de seguridad antes del merge."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: security
  savia.maturity: stable
  savia.context: fork
  savia.context_cost: low
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Escanea ficheros IaC con Trivy config mode. Detecta S3 públicos, SGs abiertos, IAM wildcards, cifrado ausente. Bloqueante: CRITICAL/HIGH → exit 1. Informativo: MEDIUM/LOW → exit 0. Genera report JSON + summary MD en output/security/."
  savia.tags: "security, iac, terraform, trivy, misconfiguration, devops"
  savia.trigger_keywords: "escanea el terraform, seguridad del IaC, iac scan, trivy config, misconfiguración terraform, dockerfile scan, bicep security, kubernetes security scan"
---

## Subagent Scope Guard

> Si fuiste invocado como subagente para una tarea concreta, ejecuta solo esa
> tarea, reporta DONE / DONE_WITH_CONCERNS / BLOCKED y retorna. No actives
> el workflow de orquestación completo.

# IaC Security Scanner Skill

## §0 Cuándo usar

- Después de que `terraform-developer` o `infrastructure-agent` genera IaC
- Antes de presentar una propuesta `terraform plan` al humano
- En CI antes de merge de PRs que tocan `*.tf`, `Dockerfile`, `*.bicep`, `docker-compose*.yml`
- Cuando el humano pide explícitamente revisar la seguridad del IaC

## §1 Integración con terraform-developer

Tras generar IaC, `terraform-developer` debe incluir en su output:

```
Antes de ejecutar terraform plan/apply, ejecuta:
  bash scripts/iac-security-scan.sh --path <directorio_infra>
```

El humano recibe siempre el IaC junto con su security score.

## §2 Uso básico

```bash
# Escanear directorio IaC
bash scripts/iac-security-scan.sh --path ./infra/

# Solo CRITICAL (más estricto)
bash scripts/iac-security-scan.sh --path ./infra/ --severity CRITICAL

# Incluir escaneo de imagen Docker
bash scripts/iac-security-scan.sh --path ./infra/ --image myapp:latest

# Sin actualizar DB (modo offline)
bash scripts/iac-security-scan.sh --path ./infra/ --skip-update
```

## §3 Auto-detección de tipos IaC

El script detecta automáticamente:
- **Terraform**: ficheros `*.tf`
- **Bicep**: ficheros `*.bicep`
- **Dockerfile**: ficheros `Dockerfile*`
- **docker-compose**: `docker-compose*.yml`
- **Kubernetes**: manifests YAML con `kind:`

## §4 Configurar Trivy sin instalación local

Si Trivy no está disponible, el script usa Docker automáticamente:

```bash
docker run --rm -v "$(pwd):/workspace" aquasec/trivy:latest config /workspace
```

## §5 Gestión de falsos positivos

```bash
# Generar baseline de misconfiguraciones conocidas
bash scripts/iac-security-baseline.sh --path ./infra/ --output .trivyignore
# → Revisar el fichero antes de commitear
# → Cada supresión requiere justificación en comentario
```

## §6 Output

```
output/security/iac-scan-YYYYMMDD.json   ← report completo
output/security/iac-scan-YYYYMMDD.md     ← summary para humano
```

## §7 Misconfiguraciones más comunes en IaC generado por LLMs

| Recurso | Misconfig habitual | ID Trivy |
|---|---|---|
| S3 Bucket | ACL pública | AVD-AWS-0089 |
| Security Group | 0.0.0.0/0 ingress all ports | AVD-AWS-0105 |
| IAM Role | `*` en actions/resources | AVD-AWS-0057 |
| RDS / Storage | Sin cifrado en reposo | AVD-AWS-0077 |
| Container | Ejecuta como root | DS002 |

Ver política completa: `docs/rules/domain/iac-security-policy.md`
