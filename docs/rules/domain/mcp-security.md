---
context_tier: L2
token_budget: 1500
---

# Regla: Seguridad en configuraciones MCP

> Fuente de aprendizaje: Prime Agent `docs/mcp-integrations.md` (SE-347 lección PMA, 2026-08-27).
> Aplica a TODA configuración de servidores MCP del workspace (~/.config/opencode/opencode.jsonc, opencode.json, configs de agentes).

## Principios

1. **Secrets solo por referencia a variable de entorno.** NUNCA valores
   literales de tokens/keys en la config (rule #1 CLAUDE.md se extiende a MCP).
   - HTTP: `bearerTokenEnvVar: "NOMBRE_VAR"` (nunca el token inline).
   - Stdio: `env: { TOKEN: { env: "NOMBRE_VAR" } }` — referencia, no literal.
   - Si la herramienta no soporta referencia, el valor va en fichero local
     gitignored (`~/.savia/...` o `config.local`), nunca versionado.

2. **Precedencia proyecto-vs-usuario: el proyecto NUNCA arranca procesos ni
   sombrea servers del usuario.** Un repositorio no confiable puede inyectar
   `mcpServers` con un comando `stdio` malicioso. Por tanto:
   - Los `mcpServers` declarados en el proyecto (opencode.json del repo) se
     ignoran para ejecución local de comandos, o se revisan manualmente antes
     de permitir `command`/`args`.
   - Los servers del usuario (`~/.config/opencode/`) tienen precedencia; un
     nombre duplicado en el proyecto NO reconfigura el del usuario.
   - Regla práctica: **nunca aceptes `command`/`args`/`cwd` de un
     `mcpServers` versionado en el repo** sin revisión humana.

3. **Tool allowlist por server.** Usa `enabledTools`/`disabledTools` para
   exponer solo lo necesario. Un server conectado no debería exponer delete/
   write si el caso de uso solo lee.

4. **Enable por login / credenciales.** Un server cuya credencial no existe
   debe estar deshabilitado (no "fallback a anónimo").

5. **Malware de paquetes antes de habilitar (SE-443 S2).** Un MCP `npx`/`uvx`
   se comprueba con `scripts/mcp-security-audit.sh --osv <npx|uvx> <pkg@versión>`
   antes del alta: avisos `MAL-*` de OSV → no se habilita (exit 1); OSV no
   comprobable, sin versión exacta y canónica o con opciones del ejecutor que cambian lo
   instalado (`--package`, `-p`, `--from`, `--with`, `--registry`…) → exit 2
   (`ASK`), nunca limpio. Solo sale
   `{ecosystem, name, version}` (N1); recibo en `output/mcp-osv-receipts.jsonl`
   sin la entrada cruda (las opciones rechazadas no se repiten).
   Nunca se ejecuta al arrancar. Typosquatting aún no marcado en OSV: límite.

## Check CRIT-001

- Los servers MCP de Savia son locales (codebase-memory, codegraph,
  savia-vaults). Ningún dato N3+ cruza hacia un server MCP remoto.
- Si un server remoto es imprescindible, revisar que su tráfico no incluya
  datos del workspace (p.ej. prompts de herramientas) — igual criterio que los
  providers.

## Enforcement

- Hook / revisión de PR: cualquier PR que toque config MCP con secretos
  literales → block. (Script de validación: `scripts/opencode-config-validate.sh`
  debe cubrirlo.)
- Auditoría `security-guardian` en pre-commit verifica que no hay literales.

## Referencias

- Regla #1: `CLAUDE.md` · `docs/rules/domain/critical-rules-extended.md`
- Aprendizaje PMA: `output/research/prime-agent-eval/lecciones-prime-agent-20260827.md` §8
- Spec: SE-347 · CRIT-001
- Diseño de las herramientas que sirve un MCP (forma, efectos, catálogo, argumentos): `mcp-tool-design.md` (SE-443)
