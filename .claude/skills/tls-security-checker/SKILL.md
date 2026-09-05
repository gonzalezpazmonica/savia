---
layer: peripheral
name: tls-security-checker
description: Usar cuando se verifica TLS/SSL o security headers HTTP de un servidor web. Invocable pre-deploy o en auditorías periódicas.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: security
  savia.maturity: stable
  savia.context: skill
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Verifica configuración TLS y security headers de un endpoint web. Usa testssl.sh (Docker fallback) para análisis TLS completo. Verifica headers con curl: CSP, HSTS, X-Frame-Options, X-Content-Type-Options, etc. Output: grade TLS (A-F), score headers (0-100), JSON report en output/security/."
  savia.tags: "tls, ssl, web-security, headers, testssl, wafw00f, deploy"
---

# TLS Security Checker

## Triggers

- "verifica TLS", "check TLS", "testssl", "análisis SSL"
- "check seguridad web", "security headers", "headers de seguridad"
- "HSTS", "Content-Security-Policy", "CSP check"
- Pre-deploy de savia-web o cualquier endpoint HTTP expuesto

## Prerequisitos

- `curl` — siempre disponible (requerido para headers check)
- `testssl.sh` o `testssl` — opcional; si no está: Docker fallback automático
- `wafw00f` — opcional; si no está: detección WAF omitida
- `docker` — opcional; fallback para testssl.sh

## Flujo de ejecución

### 1. Verificar security headers (sin dependencias externas)

```bash
bash scripts/web-headers-check.sh --url https://TARGET_URL [--follow-redirects]
```

Verifica: Content-Security-Policy, Strict-Transport-Security, X-Content-Type-Options,
X-Frame-Options, Referrer-Policy, Permissions-Policy.
Score 0-100 basado en headers presentes y valores correctos.

### 2. Análisis TLS completo

```bash
bash scripts/tls-security-check.sh --host TARGET_HOST [--port 443] [--severity MEDIUM]
```

Si testssl.sh no está instalado, muestra el comando Docker equivalente.

### 3. Interpretar grade TLS

| Grade | Condición |
|-------|-----------|
| A | TLS 1.3, ECDHE, HSTS, sin cipher suites débiles |
| B | TLS 1.2 mínimo, cipher suites modernas, HSTS |
| C | TLS 1.2 pero cipher suites débiles o sin HSTS |
| D | TLS 1.1 o 1.0 activo |
| F | SSLv3 activo o certificado inválido/expirado |

### 4. Severidades

| Severidad | Ejemplo |
|-----------|---------|
| CRITICAL | Certificado expirado, SSLv2/3 activo |
| HIGH | TLS 1.0/1.1 activo, CSP ausente |
| MEDIUM | Cipher suite débil, HSTS max-age insuficiente |
| LOW | Server header con versión expuesta |

## Output

- TLS report: `output/security/tls-check-{hostname}-YYYYMMDD.json`
- Headers report: `output/security/headers-check-{hostname}-YYYYMMDD.json`
- Ambos ficheros son N3 (confidencial) — no versionar

## Integración con pipeline savia-web

Invocar tras cada deploy a staging/producción:

```bash
# En CI post-deploy:
bash scripts/web-headers-check.sh --url "$DEPLOY_URL" --follow-redirects
bash scripts/tls-security-check.sh --host "$DEPLOY_HOST" --severity HIGH
```

Grade D o F → bloquear deploy. Grade C → warning, continuar con ticket.

## Instalación testssl.sh (opcional)

```bash
# Opción 1: Desde repo oficial
git clone https://github.com/drwetter/testssl.sh /opt/testssl.sh
ln -s /opt/testssl.sh/testssl.sh /usr/local/bin/testssl.sh

# Opción 2: Docker (no requiere instalación)
docker run --rm drwetter/testssl.sh --severity HIGH example.com:443
```

## Relación con otras herramientas

- `nuclei-scanning` skill — CVEs conocidos (complementario, no TLS específico)
- `adversarial-security` skill — pipeline Red/Blue Team completo
- `security-auditor` agent — incluye grade TLS en auditorías
