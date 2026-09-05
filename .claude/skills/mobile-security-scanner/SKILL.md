---
layer: peripheral
name: mobile-security-scanner
description: Usar cuando se escanea un APK/AAB Android en busca de vulnerabilidades de seguridad. Integra con MobSF (Docker) y análisis básico como fallback.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: security
  savia.maturity: stable
  savia.context: skill
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Pipeline de seguridad para apps Android. Análisis estático con MobSF (Docker) o fallback básico (apktool + grep). Auditoría de AndroidManifest sin necesidad de MobSF. Output: findings clasificados CRITICAL/HIGH/MEDIUM/LOW en output/security/."
  savia.tags: "android, mobile, apk, MobSF, manifest, security, static-analysis"
---

# Mobile Security Scanner

## Triggers

- "escanea el APK", "analiza la app Android", "seguridad android"
- "mobile security", "MobSF", "análisis APK"
- "permisos peligrosos", "android:debuggable", "allowBackup"
- Post-build de la app Android (complementa android-autonomous-debugger)

## Prerequisitos

- `python3` o `xmllint` — para android-manifest-audit.sh (siempre disponible)
- `apktool` — opcional; para decompilación y análisis de código
- `docker` — opcional; para MobSF análisis completo
- `adb` — sólo para modo dynamic

## Flujo de ejecución

### 1. Auditoría rápida del AndroidManifest (sin dependencias externas)

```bash
bash scripts/android-manifest-audit.sh path/to/AndroidManifest.xml
```

Detecta: debuggable=true (CRITICAL), allowBackup=true (HIGH),
exported components sin permission (HIGH), permisos peligrosos (MEDIUM).

### 2. Análisis estático completo del APK

```bash
bash scripts/mobile-security-scan.sh --apk path/to/app.apk --mode static
```

Con MobSF disponible: análisis completo vía API.
Sin MobSF: análisis básico con apktool + grep de patterns.

### 3. Análisis dinámico (requiere dispositivo ADB)

```bash
bash scripts/mobile-security-scan.sh --apk path/to/app.apk --mode dynamic
```

Requiere dispositivo Android conectado via USB con ADB habilitado.
Si no hay dispositivo, degrada automáticamente a modo static.

## MobSF — Arranque Docker

```bash
# Iniciar MobSF localmente (sin cuenta ni API key externa):
docker run --rm -p 8000:8000 opensecurity/mobile-security-framework-mobsf

# Configurar API key (extraer desde la UI en http://localhost:8000):
export MOBSF_API_KEY="tu-api-key"
export MOBSF_URL="http://localhost:8000"
```

MobSF corre completamente offline. No envía datos a servicios externos.

## Severidades y umbrales

| Severidad | Ejemplo | Gate |
|-----------|---------|------|
| CRITICAL | debuggable=true en release, keys hardcodeadas | Bloquea deploy |
| HIGH | allowBackup=true, exported sin permission | Bloquea deploy |
| MEDIUM | Permisos peligrosos innecesarios | Warning, ticket |
| LOW | Configuración subóptima | Informativo |

Bloqueante: CRITICAL o HIGH. MEDIUM y LOW no bloquean el pipeline.

## Patterns detectados en análisis básico

- Hardcoded secrets: `password`, `api_key`, `secret`, `private_key` en strings.xml
- Código de debug: `Log.d`, `Log.v`, `BuildConfig.DEBUG` en smali/Java
- Permisos peligrosos: lista completa en android-manifest-audit.sh
- Componentes exportados sin protección de permisos

## Output

- `output/security/mobile-scan-YYYYMMDD.json` — findings del APK
- Clasificación por OWASP Mobile Top 10 2024 (cuando MobSF disponible)
- Report N3 (confidencial) — no versionar

## Integración con android-autonomous-debugger

```bash
# Obtener APK path desde build:
APK_PATH=$(./gradlew buildAndPublish 2>&1 | grep "APK:" | awk '{print $2}')
# Escanear:
bash scripts/mobile-security-scan.sh --apk "$APK_PATH"
```

## Instalación MobSF sin Docker

```bash
pip3 install mobsf
mobsf  # arranca en http://localhost:8000
```
