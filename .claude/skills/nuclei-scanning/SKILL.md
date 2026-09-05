---
layer: peripheral
name: nuclei-scanning
description: "Usar cuando se escanean vulnerabilidades conocidas (CVEs, misconfigs) con Nuclei."
allowed-tools: [Bash, Read, Write]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.context: Invocado por /security-pipeline y /pentesting. Complementa security-attacker con deteccion basada en templates.
  savia.disable-model-invocation: false
  savia.user-invocable: False
---

# Nuclei Scanner — Skill de Seguridad Complementario

## Proposito

Complementar el analisis LLM (security-attacker, pentester) con un scanner
basado en templates que detecta CVEs conocidos, misconfiguraciones estandar
y paneles expuestos. El LLM encuentra vulnerabilidades logicas; Nuclei
encuentra las conocidas que el LLM podria pasar por alto.

## Verificacion de instalacion

```bash
if command -v nuclei &>/dev/null; then
  NUCLEI_VERSION=$(nuclei -version 2>&1 | head -1)
  echo "OK: Nuclei disponible — $NUCLEI_VERSION"
else
  echo "SKIP: Nuclei no instalado. Scan complementario omitido."
  echo "Instalar: go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  # Degradacion graceful — el pipeline continua sin Nuclei
fi
```

## Ejecucion del scan

```bash
nuclei -u "${TARGET_URL}" \
  -severity critical,high,medium \
  -silent -json \
  -rate-limit 50 \
  -timeout 10 \
  -o "output/security/nuclei-$(date +%Y%m%d-%H%M%S).json"
```

### Parametros obligatorios
- `-severity critical,high,medium` — no reportar low/info (ruido)
- `-silent -json` — output estructurado, sin banners
- `-rate-limit 50` — maximo 50 requests/segundo
- `-timeout 10` — timeout por request en segundos

## Parseo de resultados

Cada linea JSON contiene:

| Campo | Uso |
|-------|-----|
| `template-id` | Identificador del template (ej: `CVE-2024-1234`) |
| `info.severity` | critical, high, medium |
| `info.name` | Nombre legible de la vulnerabilidad |
| `info.classification.cwe-id` | CWE para deduplicacion con hallazgos LLM |
| `matched-at` | URL donde se detecto |
| `curl-command` | Comando para reproducir manualmente |

## Deduplicacion con hallazgos LLM

Mapear hallazgos por CWE:
1. Extraer `cwe-id` de cada hallazgo Nuclei
2. Comparar contra CWEs del security-attacker
3. Si coinciden: marcar como "confirmado por ambas fuentes" (mayor confianza)
4. Si solo Nuclei: anadir como hallazgo nuevo con `source: nuclei`
5. Si solo LLM: mantener con `source: llm`

## Integracion con scoring

Misma formula que el pipeline adversarial:
```
score = 100 - (critical * 25 + high * 10 + medium * 3 + low * 1)
```

Hallazgos Nuclei se marcan con `source: nuclei` en el informe.

## Restricciones por entorno

| Entorno | Permitido | Prohibido |
|---------|-----------|-----------|
| DEV | Scan completo | — |
| PRE | Scan sin DoS templates | `-exclude-tags dos,fuzzing` |
| PROD | Solo pasivo | `-type http -exclude-tags dos,fuzzing,intrusive` |

**NUNCA ejecutar contra produccion sin confirmacion explicita del PM.**

## Degradacion graceful

| Nuclei | Target accesible | Resultado |
|--------|-----------------|-----------|
| Instalado | Si | Scan completo |
| Instalado | No | Solo templates de config local |
| No instalado | — | Skip con aviso, pipeline continua |

## Instalacion de Nuclei

```bash
# Opcion 1: Go install
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Opcion 2: Binario directo (Linux amd64)
curl -sL https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei_linux_amd64.zip \
  -o /tmp/nuclei.zip && unzip -o /tmp/nuclei.zip -d /usr/local/bin/ nuclei
```

## Output

Fichero: `output/security/nuclei-{fecha}.json`
Resumen en informe del pipeline: seccion "Hallazgos Nuclei" con tabla.
