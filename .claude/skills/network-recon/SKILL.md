---
layer: peripheral
name: network-recon
description: "Reconocimiento de red: port scan con nmap/RustScan + HTTP detection con httpx."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.authorization_required: true
  savia.maturity: stable
  savia.category: security
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Escaneo conservador de puertos y deteccion de servicios para infraestructura propia. REQUIERE autorizacion explicita. Modo discovery (enumeracion, sin explotacion). Output: ports-open.txt + services.json + network-recon-{target}-YYYYMMDD.json"
  savia.tags: "nmap, rustscan, httpx, port-scan, network-recon, recon"
---

# Network Recon — SE-246

## AVISO: AUTORIZACIÓN OBLIGATORIA

Este skill ejecuta escaneos de red activos.
Escanear redes sin autorización escrita es ilegal en la mayoría de jurisdicciones.
Solo para infraestructura propia.

## Triggers

- "escanea la red"
- "recon de red"
- "port scan"
- "nmap"
- "puertos abiertos"
- "RustScan"

## Flujo

```
1. Verificar autorización → output/security/authorization-{target}.txt
2. RustScan  — descubrimiento rápido de puertos (Docker fallback: nmap)
3. nmap -sV  — fingerprinting de servicios (conservador: -T3, sin -A ni -O)
4. httpx     — detección de servicios HTTP/HTTPS en puertos abiertos
5. Report    → output/security/network-recon-{target}-YYYYMMDD.json
```

## Uso

```bash
# Crear autorización
echo "AUTHORIZED" > output/security/authorization-mi-servidor.txt

# Escanear (modo discovery)
bash scripts/network-recon.sh \
  --target mi-servidor \
  --ports top-1000 \
  --mode discovery
```

## Herramientas (Docker fallback automático)

| Herramienta | Imagen Docker | Función |
|---|---|---|
| RustScan | rustscan/rustscan | Port discovery rápido |
| nmap | instrumentisto/nmap | Service fingerprinting |
| httpx | projectdiscovery/httpx | HTTP service detection |

## Modo conservador (siempre activo en discovery)

- nmap: `-sV -T3 --open` — sin `-A`, sin `-O`, sin `--script=exploit`
- RustScan: `--batch-size 2500` conservador
- Sin flags agresivos de nmap (-A, -O, --script vuln)

## IPs nunca hardcodeadas

Los targets se referencian por hostname/alias.
La resolución a IP se hace en runtime desde config local git-ignorada.

## Output

```
output/security/
  authorization-{target}.txt
  network-recon-{target}-YYYYMMDD.json   ← report consolidado
  network-recon-{target}-YYYYMMDD/
    ports-open.txt     ← input para pentesting skill
    services.json
    http-services.json
```

## Integración

- Output `services.json` es input para `pentesting` skill Fase 1
- Complementa SE-243 (attack-surface-mapper)
- Reports marcados N3

## Gate de autorización

Sin `output/security/authorization-{target}.txt` con "AUTHORIZED" y < 30 días,
el script aborta con exit 1.
