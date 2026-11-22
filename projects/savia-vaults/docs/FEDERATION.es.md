# Savia Federate — Guia de Federacion

> **Como conectar multiples cupulas de contexto para busqueda unificada en todo tu conocimiento.**

Savia Federate permite registrar vaults remotos como cupulas federadas. Una vez conectadas, buscar en tu vault local incluye automaticamente resultados de todas las cupulas federadas sanas — fusionados, deduplicados y rankeados como si fueran parte de tu propio vault.

## Inicio Rapido

```bash
# 1. Iniciar vault A (con autenticacion)
savia-vaults serve --transport a2a --port 8923 --name alpha

# 2. Iniciar vault B (sin autenticacion)
savia-vaults serve --transport a2a --port 8924 --name beta

# 3. Registrar B como cupula federada en A
savia-vaults federate add beta http://localhost:8924

# 4. Buscar en ambos vaults
savia-vaults search "arquitectura" --federated
# Devuelve resultados de alpha (local) + beta (federada)
```

## Comandos

| Comando | Descripcion |
|---|---|
| `savia-vaults federate add <id> <url>` | Registrar una cupula remota |
| `savia-vaults federate add <id> <url> --token <t>` | Registrar con token de autenticacion |
| `savia-vaults federate add <id> <url> --weight 2.0` | Registrar con mayor prioridad |
| `savia-vaults federate list` | Listar todas las cupulas federadas |
| `savia-vaults federate remove <id>` | Eliminar cupula federada |
| `savia-vaults federate health` | Verificar salud de todas las cupulas |
| `savia-vaults search "q" --federated` | Buscar en local + todas las federadas |

## Configuracion

La configuracion de federacion vive en `savia-vaults.config.json`:

```json
{
  "federation": {
    "enabled": true,
    "domes": [
      {
        "id": "docs-equipo",
        "name": "Documentacion del Equipo",
        "url": "http://192.168.1.50:8923",
        "authToken": "${SAVIA_TEAM_DOCS_TOKEN}",
        "timeout": 5000,
        "weight": 1.5,
        "tags": ["docs", "equipo"]
      },
      {
        "id": "vault-specs",
        "name": "Especificaciones",
        "url": "http://localhost:8924",
        "weight": 1.0,
        "tags": ["specs", "tecnico"]
      }
    ]
  }
}
```

| Campo | Por defecto | Descripcion |
|---|---|---|
| `id` | obligatorio | Identificador unico de la cupula |
| `url` | obligatorio | URL del servidor A2A (http://host:puerto) |
| `authToken` | — | Token Bearer para cupulas autenticadas |
| `timeout` | 5000 | Milisegundos maximos por consulta remota |
| `weight` | 1.0 | Peso de prioridad (0.1-2.0), mas alto = mas resultados |
| `enabled` | true | Activar/desactivar sin eliminar |
| `tags` | [] | Etiquetas de metadatos para filtrado |

## Como Funciona la Federacion

```
1. Usuario busca "microservicios"
       │
2. Busqueda local BM25 se ejecuta inmediatamente (< 10ms)
       │
3. Consultas A2A paralelas a todas las cupulas federadas sanas
   ├── GET http://docs-equipo:8923/search?q=microservicios (timeout 5s)
   └── GET http://vault-specs:8924/search?q=microservicios (timeout 5s)
       │
4. Resultados fusionados:
   ├── Deduplicacion por hash de contenido (mismo contenido → un resultado)
   ├── Intercalado: round-robin de cada fuente, ponderado
   └── Maximo: maxResults × (1 + cupulas federadas)
       │
5. Resultados cacheados (TTL 5 min), devueltos con atribucion de origen
```

## Seguridad

- **Solo lectura**: Las cupulas federadas solo reciben GET (nunca escrituras)
- **1 salto maximo**: Las cupulas remotas NO propagan busquedas a sus federadas
- **Auth por cupula**: Cada cupula puede requerir su propio token Bearer
- **Timeout**: 5s por cupula remota (configurable)
- **Degradacion controlada**: Cupulas caidas se omiten, resultados locales siempre
- **Seguimiento de salud**: Las cupulas pasan automaticamente healthy → degraded → unhealthy
- **Sin verificacion de integridad**: Los resultados remotos no van firmados y `contentHash` lo calcula el cliente local a partir del snippet recibido; solo sirve para deduplicar. La proteccion en transito depende de TLS y del token Bearer. Federa solo cupulas de confianza.

## Mejores Practicas

- Usa URLs `https://` en produccion
- Almacena tokens de autenticacion en variables de entorno, no en archivos de configuracion
- Asigna weight=2.0 a cupulas de alta prioridad, weight=0.5 a las auxiliares
- Monitoriza salud: `savia-vaults federate health` periodicamente
- TTL de cache de 5 min equilibra frescura y rendimiento
- Federa cupulas en la misma maquina o red local para baja latencia

## Solucion de Problemas

| Sintoma | Causa Probable | Solucion |
|---|---|---|
| Resultados federados no aparecen | Cupula caida o auth incorrecta | `savia-vaults federate health` |
| Busquedas lentas | Latencia de cupula remota | Reducir timeout, aumentar TTL de cache |
| Resultados duplicados | Mismo contenido en multiples cupulas | Normal — dedup por hash de contenido |
| Errores 401 | Token de auth ausente o incorrecto | Verificar `authToken` en config |
| Errores de timeout | Cupula inalcanzable | Verificar red, aumentar timeout |
