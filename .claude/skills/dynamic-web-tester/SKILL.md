---
layer: peripheral
name: dynamic-web-tester
description: "Testing dinámico de endpoints web: XSS (DalFox), SQLi (sqlmap), Nuclei."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.authorization_required: true
  savia.maturity: stable
  savia.category: security
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Testing dinamico controlado contra endpoints web en staging. REQUIERE autorizacion explicita. Modo conservador por defecto (level 1, safe). Complementa pentesting skill con deteccion activa de XSS y SQLi."
  savia.tags: "xss, sqli, dalfox, sqlmap, nuclei, pentest-web, dynamic-testing"
---

# Dynamic Web Security Tester — SE-245

## AVISO: AUTORIZACIÓN OBLIGATORIA

Este skill ejecuta herramientas de testing activo contra endpoints HTTP.
Nunca ejecutar contra producción directamente.
Requiere autorización escrita del propietario.

## Triggers

- "test dinámico web"
- "XSS scan"
- "SQLi test"
- "pentest web endpoint"
- "dalfox"
- "sqlmap"

## Flujo

```
1. Verificar autorización → output/security/authorization-{host}.txt
2. DalFox  — XSS scanning (reflected, DOM, stored)
3. sqlmap  — SQL injection (level 1 risk 1 batch — conservador)
4. Nuclei  — templates web: xss, sqli, lfi
5. Report  → output/security/dynamic-test-{host}-YYYYMMDD.json
```

## Uso

```bash
# Crear autorización primero
echo "AUTHORIZED" > output/security/authorization-localhost.txt

# Ejecutar en modo seguro (default)
bash scripts/dynamic-web-security-test.sh \
  --target http://localhost:8080 \
  --tools xss,sqli,nuclei \
  --safe
```

## Herramientas (Docker fallback automático)

| Herramienta | Imagen Docker | Función |
|---|---|---|
| DalFox | ghcr.io/hahwul/dalfox:latest | XSS detection |
| sqlmap | paoloo/sqlmap | SQL injection |
| Nuclei | projectdiscovery/nuclei | CVE/web templates |

## Modo conservador (siempre activo)

- sqlmap: `--level 1 --risk 1 --batch` — sin payloads destructivos
- dalfox: `--silence` — solo findings
- nunca modifica datos, nunca extrae datos

## Output

```
output/security/
  authorization-{host}.txt
  dynamic-test-{host}-YYYYMMDD.json   ← report consolidado
  dynamic-test-{host}-YYYYMMDD/
    dalfox-results.json
    sqlmap/
    nuclei-results.json
```

## Integración

- Complementa `nuclei-scanning` skill (CVEs de tech stack)
- Recibe endpoints de SE-243 attack-surface-mapper
- Reports marcados N3 — contienen evidencias de vulnerabilidades

## Gate de autorización

Sin `output/security/authorization-{host}.txt` con "AUTHORIZED" y < 30 días,
el script aborta con exit 1.
