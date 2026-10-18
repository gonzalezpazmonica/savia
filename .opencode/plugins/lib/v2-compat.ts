// v2-compat.ts — SPEC-OC2-01
//
// Puente entre el contrato de hooks de OpenCode V2 y los guards de Savia,
// que se escribieron contra V1 (`tool.execute.before|after` con `(input, output)`).
//
// Contrato V1:
//   input  = { tool, args }
//   output = { args, title?, output?, metadata? }
//
// Contrato V2 (docs oficiales):
//   execute.before: { tool, input }
//   execute.after : { status: "completed" | "error", tool, input, result | error }
//
// Los runtimes además renombraron dos tools: `bash` → `shell` y `task` → `subagent`.
// Sin normalizar, ningún guard de comandos (force-push, credenciales, soberanía)
// dispararía en V2. La normalización es deliberada y vive solo aquí.

export type V1Input = { tool?: string; args?: Record<string, unknown> };
export type V1Output = {
  args?: Record<string, unknown>;
  title?: string;
  output?: string;
  metadata?: Record<string, unknown>;
};

/** Nombres de tool V2 → nombres que esperan los guards (V1). */
export function normalizeToolName(tool: unknown): string {
  const t = String(tool ?? "").toLowerCase();
  if (t === "shell") return "bash";
  if (t === "subagent") return "task";
  return t;
}

/**
 * Convierte un evento `execute.before` de V2 en el par (input, output) de V1.
 * `output.args` es el MISMO objeto que `event.input`: las mutaciones de los
 * guards (redacción de secretos, escapado) llegan al runtime.
 */
export function toV1Before(event: any): { input: V1Input; output: V1Output } {
  const args: Record<string, unknown> =
    event && typeof event.input === "object" && event.input !== null ? event.input : {};
  return {
    input: { tool: normalizeToolName(event?.tool), args },
    output: { args },
  };
}

/**
 * Convierte un evento `execute.after` de V2 en (input, output) de V1.
 * El contenido del resultado se expone como `output.output` cuando es texto;
 * los after-guards son de auditoría/observabilidad y nunca bloquean.
 */
export function toV1After(event: any): { input: V1Input; output: V1Output } {
  const args: Record<string, unknown> =
    event && typeof event.input === "object" && event.input !== null ? event.input : {};
  const result = event?.result;
  let text = "";
  if (typeof result === "string") text = result;
  else if (result && typeof result === "object" && typeof (result as any).output === "string") {
    text = (result as any).output;
  }
  const metadata =
    result && typeof result === "object" && (result as any).metadata
      ? ((result as any).metadata as Record<string, unknown>)
      : {};
  return {
    input: { tool: normalizeToolName(event?.tool), args },
    output: { args, output: text, metadata },
  };
}
