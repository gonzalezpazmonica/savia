import { test, expect } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseModelTierMap, resolveTierInPlace, applyModelTiers } from "./model-tiers.ts";

const PREFS = `version: 1
model_heavy: legacy/h
model_mid:   legacy/m   # comment
model_fast: "legacy/f"
tiers:
  claude-code:
    heavy: opus
  opencode:
    heavy: oc/h
    fast: oc/f
other: x
`;

test("parseModelTierMap: tiers.opencode wins over legacy model_<tier>", () => {
  expect(parseModelTierMap(PREFS)).toEqual({ heavy: "oc/h", mid: "legacy/m", fast: "oc/f" });
});

test("parseModelTierMap: scopes by frontend and strips quotes/comments", () => {
  expect(parseModelTierMap(PREFS, "claude-code")).toEqual({ heavy: "opus", mid: "legacy/m", fast: "legacy/f" });
  expect(parseModelTierMap("")).toEqual({});
});

test("resolveTierInPlace: model_tier (top-level or options) and legacy model: <tier>", () => {
  const map = parseModelTierMap(PREFS);
  const a: any = { options: { model_tier: "mid" } };
  const b: any = { model: "heavy" };
  const c: any = { model: "pinned/x", model_tier: "fast" };
  const d: any = { model_tier: "ultra" };
  [a, b, c, d].forEach((def) => resolveTierInPlace(def, map));
  expect([a.model, b.model, c.model, d.model]).toEqual(["legacy/m", "oc/h", "pinned/x", undefined]);
});

test("applyModelTiers: resolves commands from their file frontmatter", () => {
  const dir = mkdtempSync(join(tmpdir(), "tiers-"));
  mkdirSync(join(dir, ".opencode", "commands"), { recursive: true });
  writeFileSync(join(dir, ".opencode", "commands", "x.md"), "---\nname: x\nmodel_tier: fast\n---\nbody\n");
  const cfg: any = { command: { x: { template: "t" }, y: { template: "t" } }, agent: null };
  applyModelTiers(cfg, dir);
  expect(cfg.command.y.model).toBeUndefined();
  expect(cfg.command.x.model_tier).toBeUndefined();
});
