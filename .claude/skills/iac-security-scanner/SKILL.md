---
layer: peripheral
name: iac-security-scanner
description: "Usar cuando se escanea IaC (Terraform, Bicep, Dockerfile, docker-compose) con Trivy config para detectar misconfiguraciones de seguridad antes del merge."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: security
  savia.maturity: beta
  savia.context: fork
  savia.context_cost: low
  savia.priority: high
  savia.summary: "Escanea ficheros IaC con Trivy config mode. Detecta S3 públicos, SGs abiertos, IAM wildcards, cifrado ausente. Bloqueante: CRITICAL/HIGH → exit 1. Informativo: MEDIUM/LOW → exit 0. Error de herramienta o JSON inválido → exit 2 (nunca PASS). Genera report JSON + summary MD en output/security/."
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
# Escanear directorio IaC (bloquean CRITICAL y HIGH)
bash scripts/iac-security-scan.sh --path ./infra/

# Solo CRITICAL bloquea (MÁS permisivo: HIGH pasa a informativo)
bash scripts/iac-security-scan.sh --path ./infra/ --severity CRITICAL

# Más estricto: MEDIUM también bloquea
bash scripts/iac-security-scan.sh --path ./infra/ --severity CRITICAL,HIGH,MEDIUM

# Incluir escaneo de imagen Docker (CVE + misconfig de la imagen)
bash scripts/iac-security-scan.sh --path ./infra/ --image myapp:latest

# Supresiones de otro fichero / salida JSON en stdout / sin actualizar checks
bash scripts/iac-security-scan.sh --path ./infra/ --ignorefile ./sec/.trivyignore
bash scripts/iac-security-scan.sh --path ./infra/ --format json
bash scripts/iac-security-scan.sh --path ./infra/ --skip-update
```

`--severity` acepta `CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN` (mayúsculas o minúsculas);
es el conjunto **bloqueante**. Trivy se ejecuta una sola vez con todas las
severidades: lo no bloqueante se lista como `[INFO]`. `--skip-update` pasa
`--skip-check-update` en modo config y `--skip-db-update` en modo imagen.

## §3 Auto-detección de tipos IaC

El script detecta (hasta 5 niveles, rutas con espacios incluidas):
- **Terraform**: ficheros `*.tf`
- **Bicep**: ficheros `*.bicep`
- **Dockerfile**: ficheros `Dockerfile*`
- **docker-compose**: `docker-compose*.yml|yaml`, `compose.yml|yaml`
- **Kubernetes**: `*.yaml|*.yml` con una línea `kind: <Tipo>`

Si no detecta IaC y Trivy no reporta nada, el resultado es `NO_IAC` (exit 0)
y no `PASS`. Revisa el `--path`. Límite: un path solo con CloudFormation, ARM
o Helm que Trivy escanee limpio también sale como `NO_IAC` (exit 0).

## §4 Configurar Trivy sin instalación local

Si `trivy` no está en el PATH, el script usa Docker (`aquasec/trivy:latest`),
montando el path en solo lectura y leyendo el JSON por stdout:

```bash
docker run --rm -v "$(pwd)/infra:/workspace:ro" aquasec/trivy:latest config --format json /workspace
```

Sin Trivy ni Docker, o si cualquiera de los dos falla: **exit 2** con ERROR.
La primera ejecución por Docker descarga la imagen (requiere red).

## §5 Gestión de falsos positivos

```bash
# Generar baseline de misconfiguraciones conocidas
bash scripts/iac-security-baseline.sh --path ./infra/   # → ./infra/.trivyignore (lo que aplica el scan)
# → Cada entrada lleva severidad, título y ficheros afectados; justificar antes de commitear
# → Si el --output ya existe, se niega (exit 2) salvo --force
```

- El scan solo aplica `<path>/.trivyignore` o el `--ignorefile` explícito. Un
  `.trivyignore` del directorio actual **no** se aplica de forma implícita.
- Las supresiones se informan (`[SUPRIMIDO]`); un CRITICAL suprimido emite WARN
  (requiere aprobación de security-guardian). `ID exp:YYYY-MM-DD` caduca la
  supresión; las caducadas o con fecha no ISO no se aplican y se avisan. Las que no casan con ningún
  hallazgo se listan como candidatas a borrar. Se casa por `ID` o `AVDID`.
- La supresión es por ID en todo el path: una nueva aparición del mismo ID en
  otro fichero también queda suprimida.
- El baseline es fail-closed: si Trivy falla o el JSON es inválido, exit 2 y no
  escribe ningún fichero.

## §6 Output y exit codes

```
output/security/iac-scan-YYYYMMDD.json        ← report normalizado (--path)
output/security/iac-image-scan-YYYYMMDD.json  ← report normalizado (--image)
output/security/iac-scan-YYYYMMDD.md          ← summary para humano
```

El report lleva `status` (`PASS`/`FAIL`/`NO_IAC`/`ERROR`), `summary`
(bloqueantes, informativos, suprimidos, caducados, no usados) y `findings`.
Un fallo sobrescribe el report del mismo día con `status: ERROR`.

| Exit | Significado |
|---|---|
| 0 | Sin hallazgos bloqueantes (`PASS`) o sin IaC (`NO_IAC`) |
| 1 | Hallazgos en las severidades bloqueantes — bloquea CI |
| 2 | Error: argumentos, Trivy/Docker ausente o fallido, salida vacía o JSON inválido |

## §7 Misconfiguraciones más comunes en IaC generado por LLMs

| Recurso | Misconfig habitual | ID Trivy |
|---|---|---|
| S3 Bucket | ACL pública | AVD-AWS-0089 |
| Security Group | 0.0.0.0/0 ingress all ports | AVD-AWS-0105 |
| IAM Role | `*` en actions/resources | AVD-AWS-0057 |
| RDS / Storage | Sin cifrado en reposo | AVD-AWS-0077 |
| Container | Ejecuta como root | DS002 |

Ver política completa: `docs/rules/domain/iac-security-policy.md`
Tests: `tests/test-iac-security-scanner.bats` (trivy y docker falsos).
