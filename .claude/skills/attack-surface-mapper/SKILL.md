---
layer: peripheral
name: attack-surface-mapper
description: "Mapear la superficie de ataque de un dominio: subdominios, OSINT, typosquatting."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.authorization_required: true
  savia.maturity: stable
  savia.category: security
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: high
  savia.summary: "OSINT y enumeracion de subdominios con subfinder, httpx, theHarvester y dnstwist. REQUIERE autorizacion explicita del propietario del dominio antes de ejecutar. Output: subdomains.txt + typosquatting.json + surface-map-{target}-YYYYMMDD.json"
  savia.tags: "attack-surface, subdominios, osint, dnstwist, subfinder"
---

# Attack Surface Mapper — SE-243

## AVISO: AUTORIZACIÓN OBLIGATORIA

Este skill ejecuta herramientas activas contra infraestructura real.
Escanear dominios sin autorización escrita puede ser ilegal.

**Antes de usar:**
```bash
bash scripts/surface-map-authorize.sh --target <domain>
```

## Triggers

- "mapea la superficie de ataque de..."
- "subdominios de..."
- "attack surface mapping"
- "dnstwist typosquatting"
- "theHarvester OSINT"

## Flujo

```
1. Verificar autorización → output/security/authorization-{domain}.txt
2. subfinder  — enumeración pasiva de subdominios
3. httpx      — HTTP probing de subdominios encontrados
4. theHarvester — OSINT: emails, IPs, tecnologías
5. dnstwist   — typosquatting: dominios similares registrados
6. Report     → output/security/surface-map-{domain}-YYYYMMDD.json
```

## Uso

```bash
# Paso 1: autorizar
bash scripts/surface-map-authorize.sh --target ejemplo.com

# Paso 2: mapear
bash scripts/attack-surface-map.sh \
  --target ejemplo.com \
  --tools subfinder,httpx,theharvester,dnstwist
```

## Herramientas (Docker fallback automático)

| Herramienta | Imagen Docker | Función |
|---|---|---|
| subfinder | projectdiscovery/subfinder | Enumeración pasiva subdominios |
| httpx | projectdiscovery/httpx | HTTP probing |
| theHarvester | secsi/theharvester | OSINT emails/IPs |
| dnstwist | elceef/dnstwist | Typosquatting detection |

## Output

```
output/security/
  authorization-{domain}.txt          ← gate de autorización
  surface-map-{domain}-YYYYMMDD.json  ← report consolidado
  attack-surface-{domain}-YYYYMMDD/
    subdomains.txt     ← input para pentesting skill Fase 2
    raw/httpx.json
    raw/dnstwist.json
    raw/harvest.txt
```

## Integración

- Salida `subdomains.txt` es input para `pentesting` skill Fase 2
- Complementa SE-246 (network-recon) y SE-245 (dynamic-web-testing)
- Reports marcados N3 — no incluir en repos públicos

## Gate de autorización

Sin `output/security/authorization-{domain}.txt` con contenido "AUTHORIZED"
y antigüedad < 30 días, el script aborta con exit 1.

El fichero se crea con `surface-map-authorize.sh` que pide confirmación interactiva.
