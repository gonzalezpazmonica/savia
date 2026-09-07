# Revisión de integración — runtime dual CLI

Fecha: 2026-09-07. Implementación delegada a Sol; revisión separada por raíz.
Esta revisión no sustituye E1 humano ni certificación E2E.

## Evidencia del entorno

- `codex --version`: 0.153.4; `opencode --version`: 1.18.21.
- `codex sandbox -- /usr/bin/true`: exit 1, stderr
  `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`.
- El aislamiento nativo está bloqueado incluso para una operación inocua.
  Ejecutar tests con escalación no acredita AC8.

## Condiciones de integración

1. No liberar por TTL, PID del padre muerto ni grupo vacío si pudieron escapar
   descendientes. Se requiere evidencia de supervisión completa o conservar reserva.
2. El hash debe cubrir contenido de fuentes ejecutables y dependencias relevantes;
   un hash de inventario no representa una revisión completa de política.
3. Los tokens no aparecerán en status, journal público ni errores. El socket privado
   y tokens separan sesiones cooperativas, no usuarios hostiles con el mismo UID.
4. Los transportes de prompt/HTTP deben estar explícitamente configurados. Una
   respuesta simulada no cubre el handler ni autoriza activar el adaptador.
5. Timeout de un callback no demuestra cancelación de su efecto. Conservar la
   incertidumbre y exigir reconciliación para mutaciones externas.
6. El registro de una decisión no demuestra ejecución idempotente de su efecto.
7. Instalar configuración no acredita confianza ni ejecución. El preflight debe
   rechazar versiones, revisiones, cobertura o confianza sin evidencia.
8. No modificar los hooks activos hasta resolver viabilidad y revisión local.

## Diferencias nativas comprobadas en documentación

Codex omite hooks nuevos o cambiados hasta la revisión nativa por hash.
En PreToolUse, campos no soportados como `ask` o `continue` pueden hacer fallar
el hook sin bloquear la herramienta. Traducir bloqueos a exit 2 o al objeto
`permissionDecision: deny` soportado. Para Bash/apply_patch las mutaciones
requieren `updatedInput.command`. `write_stdin` no repite PreToolUse y los
subagentes comparten session_id del padre: mantener actor y reserva separados.
Fuente: [Hooks de Codex](https://learn.chatgpt.com/docs/hooks).

OpenCode documenta `tool.execute.before` con excepción para bloquear y
modificación de `output.args`. Las notificaciones posteriores no revierten
escrituras; no sustituir el gate previo por `tool.execute.after`.
Fuente: [Plugins OpenCode](https://opencode.ai/docs/plugins/).

## Estado de cierre

La aprobación de componentes aislados exige pruebas de fallo y revisión del diff.
AC1–AC10 se mantienen abiertos hasta contar con evidencia de los dos CLI reales.
El fallo actual de sandbox impide cerrar la spec aunque los tests locales pasen.
