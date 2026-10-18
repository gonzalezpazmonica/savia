type RequestBody = Record<string, unknown>;
type RequestTransformer = (body: RequestBody) => RequestBody;

export function normalizeGpt56Request(body: RequestBody): RequestBody {
  if (body.max_tokens != null) {
    body.max_completion_tokens ??= body.max_tokens;
    delete body.max_tokens;
  }

  delete body.reasoning_effort;
  return body;
}

async function configV1(config: any): Promise<void> {
  for (const provider of Object.values(config.provider ?? {}) as any[]) {
    const isOpenAiCompatible = provider.npm === "@ai-sdk/openai-compatible";
    const hasGpt56Model = Object.entries(provider.models ?? {}).some(
      ([id, model]: [string, any]) =>
        `${id} ${model?.name ?? ""}`.toLowerCase().includes("gpt-5.6"),
    );
    if (!isOpenAiCompatible || !hasGpt56Model || !provider.options) continue;

    const previous = provider.options.transformRequestBody as
      | RequestTransformer
      | undefined;
    provider.options.transformRequestBody = (body: RequestBody) =>
      normalizeGpt56Request(previous ? previous(body) : body);
  }
}

// SPEC-OC2-01: export dual. V1 llama server(); V2 lee id + setup.
const Gpt56OpenAiCompatPlugin = {
  id: "gpt56-openai-compat",
  async setup(ctx: any) {
    try {
      if (typeof ctx?.session?.hook === "function") {
        await ctx.session.hook("model.request", (event: any) => {
          if (event?.body && typeof event.body === "object") normalizeGpt56Request(event.body);
        });
      }
    } catch {
      // Un runtime sin hook de sesión no debe romper el arranque.
    }
  },
  async server() {
    return { config: configV1 };
  },
};

export default Gpt56OpenAiCompatPlugin;
