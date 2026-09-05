---
layer: peripheral
name: adversarial-security
description: Usar cuando se necesita auditar la seguridad de un proyecto con pipeline Red Team / Blue Team.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: security-attacker
  savia.maturity: stable
  savia.category: governance
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Pipeline Red Team + Blue Team + Auditor independiente. Scoring CVSS, mapeo STRIDE, gap analysis. Output: informe con score 0-100 y recomendaciones."
  savia.tags: "security, adversarial, red-team, blue-team"
  savia.trigger_keywords: "vulnerabilidad, pentest, sql injection, xss, inyeccion, security audit, red team, blue team"
---

## Subagent Scope Guard

> If you were dispatched as a subagent to execute a specific delegated task,
> **skip this skill's full orchestration workflow**. Execute only the assigned
> task, report result (DONE / DONE_WITH_CONCERNS / BLOCKED), and return.
> This guard prevents runaway skill activation in nested agent contexts.

# Adversarial Security Skill

## §0 Prerequisitos (gate de arranque)

```
Doble opt-in (SPEC-186):                     → si no: ❌ ABORT
  bash scripts/savia-double-optin-check.sh \
    --skill adversarial-security --confirm-autonomous
Requiere AMBOS: ADVERSARIAL_SECURITY_ENABLED=true Y flag explicito.
```

## §1 Vulnerability Scoring

**CVSS simplificado para proyectos internos**:

| Factor | Peso | Valores |
|--------|------|---------|
| Attack Vector | 0.3 | Network (1.0), Adjacent (0.7), Local (0.5), Physical (0.2) |
| Complexity | 0.2 | Low (1.0), High (0.5) |
| Privileges | 0.2 | None (1.0), Low (0.6), High (0.3) |
| Impact | 0.3 | High (1.0), Medium (0.6), Low (0.3) |

score = sum(factor × peso) × 10 → escala 0-10

## §2 STRIDE Mapping

| Categoría | Pregunta clave | Controles típicos |
|-----------|---------------|-------------------|
| Spoofing | ¿Puedo suplantar a otro? | Auth, MFA, tokens |
| Tampering | ¿Puedo modificar datos? | Integridad, signing, HMAC |
| Repudiation | ¿Puedo negar una acción? | Audit logs, timestamps |
| Info Disclosure | ¿Puedo acceder a datos? | Encryption, access control |
| DoS | ¿Puedo tumbar el servicio? | Rate limiting, WAF |
| Elevation | ¿Puedo escalar privilegios? | RBAC, least privilege |

## §3 OWASP Top 10 Checklist

1. Broken Access Control
2. Cryptographic Failures
3. Injection
4. Insecure Design
5. Security Misconfiguration
6. Vulnerable Components
7. Auth Failures
8. Software/Data Integrity Failures
9. Logging Failures
10. SSRF

## §4 Dependency Audit

```bash
# npm: audit de dependencias
npm audit --json 2>/dev/null | jq '.vulnerabilities | length'
# pip: safety check
pip-audit --format=json 2>/dev/null
# dotnet: audit
dotnet list package --vulnerable --format json 2>/dev/null
```

## §5 Security Score Formula

score = 100 - (critical×25 + high×10 + medium×3 + low×1)
Cada fix verificado recupera los puntos. Floor: 0.
