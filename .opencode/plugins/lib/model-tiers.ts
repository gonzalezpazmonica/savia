// model-tiers.ts — provider-agnostic model tiers for OpenCode (SPEC-127 / PV-06).
// Sources declare `model_tier: heavy|mid|fast`; the concrete model comes from the
// LOCAL tier definition in ~/.savia/preferences.yaml. Precedence:
// `tiers.opencode.<tier>` (per-frontend block) > legacy top-level `model_<tier>`.
// NO vendor names here. See docs/rules/domain/model-alias-schema.md.
import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const TIER_NAMES = ["heavy", "mid", "fast"];
const PREFS_PATH = () => join(homedir(), ".savia", "preferences.yaml");

let cacheMtime = -1;
let cacheMap: Record<string, string> = {};

const unquote = (v: string) => v.replace(/\s+#.*$/, "").replace(/^["']|["']$/g, "").trim();

export function parseModelTierMap(raw: string, frontend = "opencode"): Record<string, string> {
  const legacy: Record<string, string> = {};
  const scoped: Record<string, string> = {};
  let inTiers = false;
  let inFrontend = false;
  for (const line of raw.split(/\r?\n/)) {
    if (/^\s*(#|$)/.test(line)) continue;
    const top = line.match(/^(\w[\w-]*)\s*:\s*(.*)$/);
    if (top) {
      inTiers = top[1] === "tiers";
      inFrontend = false;
      const lm = top[1].match(/^model_(heavy|mid|fast)$/);
      if (lm && unquote(top[2])) legacy[lm[1]] = unquote(top[2]);
      continue;
    }
    if (!inTiers) continue;
    const fe = line.match(/^ {2}([\w-]+)\s*:\s*$/);
    if (fe) { inFrontend = fe[1] === frontend; continue; }
    const t = line.match(/^ {4}(heavy|mid|fast)\s*:\s*(.+)$/);
    if (t && inFrontend && unquote(t[2])) scoped[t[1]] = unquote(t[2]);
  }
  return { ...legacy, ...scoped };
}

export function getModelTierMap(): Record<string, string> {
  try {
    const mtime = statSync(PREFS_PATH()).mtimeMs;
    if (mtime !== cacheMtime) {
      cacheMap = parseModelTierMap(readFileSync(PREFS_PATH(), "utf8"));
      cacheMtime = mtime;
    }
  } catch {
    cacheMap = {};
    cacheMtime = -1;
  }
  return cacheMap;
}

// `model_tier` (neutral field, kept by OpenCode under `options`) or legacy `model: <tier>`.
export function resolveTierInPlace(def: any, tierMap: Record<string, string>): void {
  if (!def || typeof def !== "object") return;
  const legacy = TIER_NAMES.includes(def.model) ? def.model : undefined;
  const tier = def.model_tier ?? def.options?.model_tier ?? legacy;
  if (!tier || !tierMap[tier]) return;
  if (!def.model || legacy) def.model = tierMap[tier];
}

// OpenCode drops unknown frontmatter keys from commands: read `model_tier` from the file.
function commandTierFromFile(directory: string, name: string): string | undefined {
  try {
    const raw = readFileSync(join(directory, ".opencode", "commands", `${name}.md`), "utf8");
    const fm = raw.match(/^---\r?\n([\s\S]*?)\r?\n---/);
    return fm?.[1].match(/^model_tier:\s*(heavy|mid|fast)\s*$/m)?.[1];
  } catch {
    return undefined;
  }
}

// Config hook body: agents and commands get a concrete model from their tier.
export function applyModelTiers(cfg: any, directory: string): void {
  const tierMap = getModelTierMap();
  if (cfg?.agent && typeof cfg.agent === "object") {
    for (const def of Object.values(cfg.agent) as any[]) resolveTierInPlace(def, tierMap);
  }
  if (cfg?.command && typeof cfg.command === "object") {
    for (const [name, def] of Object.entries(cfg.command) as [string, any][]) {
      if (!def) continue;
      if (!def.model_tier && !def.model) def.model_tier = commandTierFromFile(directory, name);
      resolveTierInPlace(def, tierMap);
      delete def.model_tier;
    }
  }
}
