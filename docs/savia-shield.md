# Savia Shield — Sistema de Soberania de Datos para IA Agéntica

> Los datos de tu cliente nunca abandonan tu máquina sin tu permiso.

---

## Qué es Savia Shield

Savia Shield es un sistema de **7 capas** que protege los datos confidenciales
de proyectos de cliente cuando se trabaja con asistentes de IA (Claude,
GPT, etc.). Un proxy intercepta todo el trafico hacia la API y enmascara
entidades automaticamente. Hooks locales clasifican cada dato antes de
que pueda escribirse en ficheros publicos.

**Problema que resuelve:** Las herramientas de IA envian prompts a
servidores externos. Si el prompt contiene nombres de clientes, IPs
internas, credenciales o datos de reuniones, se produce una fuga de datos
que viola NDAs y RGPD.

**Como lo resuelve:** 7 capas independientes, cada una observable y
auditable por humanos. La numeracion es la misma que muestra Savia Monitor
en el dashboard de Shield (1-6, 8).

---

## Arquitectura — Daemon + Proxy + Fallback

### Flujo de prompts (Capa 0 — proxy)

```
Claude Code / OpenCode → ANTHROPIC_BASE_URL=localhost:8443
  → savia-shield-proxy.py intercepta el prompt
  → enmascara entidades (personas, empresas, IPs, proyectos)
  → envia prompt limpio a api.anthropic.com
  → recibe respuesta → desenmascara → devuelve al usuario
```

### Flujo de escritura de ficheros (Capas 1-3 — hooks)

```
Claude Code / OpenCode → hook PreToolUse → data-sovereignty-gate.sh
  → curl POST localhost:8444/gate (daemon unificado)
  → daemon: regex + NER + NFKC + base64 + cross-write → BLOCK/ALLOW
```

### Fallback (daemon caido)

```
gate.sh → inline regex + NFKC + base64 + cross-write + Ollama Layer 2
```

Shield **siempre protege**, incluso sin daemon.

---

## Las 7 capas (numeracion canonica, alineada con Savia Monitor)

### Capa 1 — Regex Gate (hook PreToolUse)

Gate determinista que escanea contenido antes de escribir ficheros publicos:

- `.opencode/hooks/data-sovereignty-gate.sh`
- Regex para credenciales, IPs, tokens, claves privadas, SAS tokens
- Normalizacion Unicode NFKC (detecta digitos fullwidth)
- Cross-write: combina contenido existente en disco + nuevo para detectar splits
- Normalizacion de path (resuelve `../` traversal)
- Daemon-first: si daemon activo, una sola llamada HTTP hace todo
- Fallback: si daemon caido, regex inline con mismas detecciones
- Siempre activa cuando Shield esta enabled

### Capa 2 — NER Filter (Presidio + spaCy)

Reconocimiento de entidades nombradas embebido en el daemon:

- Bilingue (espanol + ingles)
- Detecta personas, organizaciones, entidades del glosario del proyecto
- Latencia ~100ms warm
- Estado: campo `ner` del endpoint `http://127.0.0.1:8444/health`
- Degrada a solo Capa 1 si daemon caido

### Capa 3 — Ollama Classifier (LLM local)

Clasificador semantico para texto que pasa regex y NER:

- Modelo `qwen2.5:7b` en `localhost:11434`
- Clasifica como CONFIDENTIAL / PUBLIC / AMBIGUOUS
- Los datos **nunca salen** de localhost
- Triple defensa anti-injection: delimitadores, sandwich, validacion estricta
- Degrada a Capas 1+2 si Ollama no disponible

### Capa 4 — Proxy Interceptor (puerto 8443)

Intercepta TODO el trafico entre Claude Code / OpenCode y la API de Anthropic:

- `savia-shield-proxy.py` en localhost:8443
- Enmascara entidades en prompts salientes (personas, empresas, IPs, proyectos)
- Desenmascara respuestas entrantes antes de devolverlas al usuario
- Activacion: `export ANTHROPIC_BASE_URL=http://127.0.0.1:8443`
- Audit log de cada request interceptado

### Capa 5 — Audit Logger (hook PostToolUse)

Hook asincrono que re-escanea el fichero completo en disco tras escribirlo:

- `.opencode/hooks/data-sovereignty-audit.sh`
- No bloquea el flujo de trabajo
- NFKC + regex sobre fichero COMPLETO (no truncado)
- Append-only en `output/data-sovereignty-audit.jsonl`
- Alerta inmediata si detecta fuga
- Siempre activa cuando Shield esta enabled

### Capa 6 — Security Hooks (deterministas, sin daemon)

Hooks de seguridad que bloquean acciones peligrosas:

- `.opencode/hooks/block-force-push.sh` — bloquea `git push --force` y push a main
- Bloqueo de credenciales en bash (PreToolUse en Bash)
- Bloqueo de `terraform destroy` sin confirmacion
- Siempre activos, no necesitan daemon ni Ollama

### Capa 7 — [DEPRECATED] Masking Engine removido

El Masking Engine manual (`scripts/sovereignty-mask.py` / `.sh`) fue removido
el 2026-05-05 por no estar funcionando correctamente. Esta capa queda reservada
para una futura alternativa. La Capa 4 (Proxy) mantiene su propio masking
interno y no se ve afectada por esta remocion.

### Capa 8 — Base64 Decoder (integrado en Capa 1)

Decodificador anti-bypass que cierra el vector de credenciales codificadas:

- Logica embebida en `scripts/savia-shield-daemon.py` (`base64.b64decode(blob)`)
- Detecta blobs base64 sospechosos en cualquier escritura
- Decodifica el blob y re-aplica regex sobre el contenido decodificado
- Bloquea credenciales codificadas en YAML/JSON/configs
- Siempre activa cuando el daemon esta arriba; en fallback regex se desactiva

---

## 5 niveles de confidencialidad

| Nivel | Nombre | Quién ve | Ejemplo |
|-------|--------|----------|---------|
| N1 | Público | Internet | Código del workspace, templates |
| N2 | Empresa | La organización | Config de la org, herramientas |
| N3 | Usuario | Solo tú | Tu perfil, preferencias |
| N4 | Proyecto | Equipo del proyecto | Datos del cliente, reglas |
| N4b | PM-Only | Solo la PM | One-to-ones, evaluaciones |

**Savia Shield protege las fronteras N4/N4b → N1.**
Escribir datos sensibles en ubicaciones privadas (N2-N4b) siempre está permitido.

---

## Que detecta (Capas 1, 4, 8)

- Connection strings (JDBC, MongoDB, SQL Server)
- Claves AWS (AK​IA...), GitHub (gh​p_, github​_pat_), OpenAI (sk​-...)
- Tokens Azure SAS (sv=20XX-)
- Google API Keys (AIza...)
- Claves privadas (-----BEG​IN...PRIVATE KEY-----)
- IPs privadas RFC 1918 (10.x, 172.16-31.x, 192.168.x)
- Secretos codificados en base64

---

## Cómo usarlo

### Verificar que el gate funciona

```bash
# Ejecutar tests
bats tests/test-data-sovereignty.bats tests/test-data-sovereignty-extended.bats

# Verificar que Ollama está en localhost
netstat -an | grep 11434
```

---

## Auditabilidad — Zero cajas negras

Cada componente es un fichero de texto plano legible por humanos:

| Componente | Fichero | Descripcion |
|-----------|---------|-------------|
| Daemon unificado | `scripts/savia-shield-daemon.py` | Scan/health en localhost:8444 |
| Proxy API | `scripts/savia-shield-proxy.py` | Intercepta prompts Claude, enmascara/desenmascara |
| NER daemon | `scripts/shield-ner-daemon.py` | Presidio+spaCy persistente en RAM (~100ms) |
| Gate hook | `.opencode/hooks/data-sovereignty-gate.sh` | PreToolUse: daemon-first, fallback regex |
| Auditoria hook | `.opencode/hooks/data-sovereignty-audit.sh` | PostToolUse async: re-scan fichero completo |
| Clasificador LLM | `scripts/ollama-classify.sh` | Capa 2 Ollama (fallback si daemon caido) |
| Pre-commit git | `scripts/pre-commit-sovereignty.sh` | Scan staged files antes de commit |
| Setup | `scripts/savia-shield-setup.sh` | Instalador: deps, modelos, token, daemons |
| Force-push guard | `.opencode/hooks/block-force-push.sh` | Bloquea force-push, push a main, amend |
| Regla de dominio | `docs/rules/domain/data-sovereignty.md` | Arquitectura y politicas |

**Logs de auditoría:**
- `output/data-sovereignty-audit.jsonl` — decisiones de las capas 1-3
- `output/data-sovereignty-validation/classifier-decisions.jsonl` — decisiones del LLM

---

## Calidad y testing

- Suite automatizada de tests (BATS) con cobertura de core, edge cases y mocks
- Auditorias de seguridad independientes (Red Team, Confidencialidad, Code Review)
- Mapping a frameworks de compliance (RGPD, ISO 27001, EU AI Act)

---

## Capacidades de deteccion avanzadas

- **Base64**: decodifica blobs sospechosos y re-escanea el contenido decodificado
- **Unicode NFKC**: normaliza caracteres fullwidth y variantes antes de aplicar regex
- **Cross-write**: combina contenido existente en disco con nuevo para detectar patterns divididos entre escrituras
- **Proxy API**: intercepta todos los prompts salientes y enmascara entidades automaticamente
- **NER bilingue**: analisis en espanol e ingles combinado, con deny-list por proyecto
- **Anti-injection**: triple defensa en el clasificador local (delimitadores, sandwich, validacion estricta)

---

## Documentacion tecnica (EN, para comite de seguridad)

- `docs/data-sovereignty-architecture.md` — Arquitectura tecnica
- `docs/data-sovereignty-operations.md` — Compliance y riesgo
- `docs/data-sovereignty-auditability.md` — Guia de auditoria
- `docs/data-sovereignty-finetune-plan.md` — Plan de modelo fine-tuned

---

## Requisitos

- Ollama instalado (`ollama --version`)
- Modelo descargado (`ollama pull qwen2.5:7b`)
- jq instalado (para JSON parsing)
- Python 3.12+ (para masking y NER)
- Presidio (`pip install presidio-analyzer`) — para Capa 2 NER
- spaCy modelo espanol (`python3 -m spacy download es_core_news_md`)
- 8 GB RAM mínimo (16+ recomendado)


---

## Instalacion rapida

```bash
bash scripts/savia-shield-setup.sh
export ANTHROPIC_BASE_URL=http://127.0.0.1:8443
```

El instalador:
1. Verifica dependencias (python3, jq, ollama, presidio, spacy)
2. Descarga modelos necesarios (qwen2.5:7b, es_core_news_md)
3. Genera token de autenticacion (`~/.savia/shield-token`)
4. Arranca `savia-shield-daemon.py` en localhost:8444 (scan/health)
5. Arranca `savia-shield-proxy.py` en localhost:8443 (proxy API)
6. Arranca `shield-ner-daemon.py` (NER persistente en RAM)

Tras ejecutar, toda comunicacion con la API pasa por el proxy que
enmascara entidades sensibles automaticamente.

**Token obligatorio:** el daemon nunca sirve sin token. Si
`~/.savia/shield-token` no existe, lo crea con permisos 0600 (los hooks lo
leen en cada llamada, sin reinicios); si el fichero esta vacio o no se puede
crear, el daemon no arranca. Arrancar el daemon a mano o con
`shield-launcher.py` sin pasar por el instalador funciona igual.

**Lectura acotada al workspace:** la deteccion de credencial partida
(cross-write) del `/gate` solo lee el fichero existente si su ruta, resuelta
con `realpath` (relativas contra el workspace, `..` y enlaces simbolicos
incluidos), queda dentro de `CLAUDE_PROJECT_DIR`. Fuera de el no se lee nada
y solo se escanea el contenido nuevo; asi ningun proceso local obtiene un
oraculo sobre ficheros ajenos (alertas CodeQL #30-#32).

**Sin daemon:** los hooks de gate y auditoria siguen funcionando en
modo fallback (regex + NFKC + base64 + cross-write). Claude Code
nunca se bloquea por falta de daemon.

---

## Estado por defecto — Desactivado

Savia Shield esta **desactivado por defecto**. Los hooks estan instalados
pero no se ejecutan hasta que los actives. Esto evita latencia innecesaria
en maquinas sin proyectos privados.

Activalo cuando empieces a trabajar con datos de clientes.

## Activar y desactivar

```bash
# Con el comando slash (recomendado)
/savia-shield enable    # Activar
/savia-shield disable   # Desactivar
/savia-shield status    # Verificar estado e instalacion
```

O editando `.claude/settings.local.json` directamente:

```json
{
  "env": {
    "SAVIA_SHIELD_ENABLED": "true"
  }
}
```

Para desactivar, cambiar `"true"` por `"false"`.
