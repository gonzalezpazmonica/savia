# Regla: Savia School — Seguridad y Privacidad Educativa
# CRÍTICA: Menores de edad — GDPR/LOPD estricto

```
# Core Flags
SCHOOL_MODE_ENABLED=true SCHOOL_ENCRYPTION_ENABLED=true SCHOOL_STUDENT_ISOLATION=true
SCHOOL_CONSENT_REQUIRED=true SCHOOL_AUDIT_ENABLED=true SCHOOL_STORE_PII=false

# Encryption
SCHOOL_ENCRYPTION_ALGORITHM="AES-256-CBC+PBKDF2+HMAC-SHA256" SCHOOL_KEY_FILE="$HOME/.school-keys/encryption.key"
SCHOOL_KEY_FILE_PERMISSIONS="0600" SCHOOL_ENCRYPT_EVALUATIONS=true

# Content & GDPR
SCHOOL_AGE_APPROPRIATE_FILTER=true SCHOOL_FORBIDDEN_KEYWORDS="violence|adult|explicit|hate"
SCHOOL_GDPR_ARTICLE15_ENABLED=true SCHOOL_GDPR_ARTICLE17_ENABLED=true

# Data & Retention
SCHOOL_USE_ALIASES=true SCHOOL_RETENTION_AFTER_EXIT="0 days"
SCHOOL_GDPR_AUDIT_RETENTION="30 days" SCHOOL_INCIDENT_RETENTION="7 years"

# Teacher/Parent
SCHOOL_TEACHER_MFA_REQUIRED=true SCHOOL_TEACHER_SESSION_TIMEOUT="1 hour"
SCHOOL_NO_EXTERNAL_MESSAGING=true SCHOOL_DIARY_PARENT_ACCESS=false
```

## ⚠️ OPERACIONES CRÍTICAS

1. **Eliminación (Art. 17)** — Requiere consentimiento parental + firma
2. **Desencriptación** — Solo profesor + audit trail
3. **Acceso multi-estudiante** — Verificar rol docente
4. **Exportación GDPR** — Canal seguro, NO email

## ✅ PRE-COMANDO CHECKS

```bash
# Encryption: [ -f "$SCHOOL_KEY_FILE" ] && [ "$(stat -c '%a' "$SCHOOL_KEY_FILE")" = "600" ] (encrypt-eval lo exige)
# Isolation: bash scripts/savia-school-security.sh check-isolation "$ALIAS"
# Consent: bash scripts/savia-school-security.sh gdpr-consent "$ALIAS" (si aplica)
# Audit: bash scripts/savia-school-security.sh audit-access "$ALIAS" "$ACTION"
```

## 📚 Referencias Legales

- **GDPR**: Arts. 5 (principios), 13 (transparencia), 15 (acceso), 17 (olvido)
- **AEPD**: Protección de menores en entornos educativos
- **LOPD**: Ley Orgánica 3/2018
- **LSSI-CE**: Privacidad online
