import { test, expect } from "bun:test";
import { blockForcePush } from "../guards/block-force-push.ts";

// ── Should BLOCK ─────────────────────────────────────────────────────────────

test("blockForcePush: blocks git push --force", async () => {
  const input = { tool: "bash", args: { command: "git push origin my-branch --force" } };
  await expect(blockForcePush(input as any, {} as any)).rejects.toThrow(/BLOCKED \[force-push\]/);
});

test("blockForcePush: blocks git push -f", async () => {
  const input = { tool: "bash", args: { command: "git push origin my-branch -f" } };
  await expect(blockForcePush(input as any, {} as any)).rejects.toThrow(/BLOCKED \[force-push\]/);
});

test("blockForcePush: blocks push directly to origin/main", async () => {
  const input = { tool: "bash", args: { command: "git push origin main" } };
  await expect(blockForcePush(input as any, {} as any)).rejects.toThrow(/BLOCKED \[force-push\]/);
});

test("blockForcePush: blocks --force-with-lease to origin/main", async () => {
  const input = { tool: "bash", args: { command: "git push origin main --force-with-lease" } };
  await expect(blockForcePush(input as any, {} as any)).rejects.toThrow(/BLOCKED \[force-push\]/);
});

test("blockForcePush: blocks git reset --hard", async () => {
  const input = { tool: "bash", args: { command: "git reset --hard HEAD~1" } };
  await expect(blockForcePush(input as any, {} as any)).rejects.toThrow(/BLOCKED \[force-push\]/);
});

test("blockForcePush: blocks git rebase origin/main", async () => {
  const input = { tool: "bash", args: { command: "git rebase origin/main" } };
  await expect(blockForcePush(input as any, {} as any)).rejects.toThrow(/BLOCKED \[force-push\]/);
});

// ── Should ALLOW ─────────────────────────────────────────────────────────────

test("blockForcePush: allows --force-with-lease to feature branch", async () => {
  const input = { tool: "bash", args: { command: "git push origin agent/my-feature --force-with-lease" } };
  await expect(blockForcePush(input as any, {} as any)).resolves.toBeUndefined();
});

test("blockForcePush: allows --force-with-lease with refspec to feature branch", async () => {
  const input = { tool: "bash", args: { command: "git push origin agent/local-branch:agent/remote-branch --force-with-lease" } };
  await expect(blockForcePush(input as any, {} as any)).resolves.toBeUndefined();
});

test("blockForcePush: allows normal push to feature branch", async () => {
  const input = { tool: "bash", args: { command: "git push origin agent/my-feature" } };
  await expect(blockForcePush(input as any, {} as any)).resolves.toBeUndefined();
});

test("blockForcePush: silent on non-bash tools", async () => {
  const input = { tool: "edit", args: { command: "git push --force something" } };
  await expect(blockForcePush(input as any, {} as any)).resolves.toBeUndefined();
});

test("blockForcePush: silent on empty input", async () => {
  await expect(blockForcePush({} as any, {} as any)).resolves.toBeUndefined();
});

test("blockForcePush: allows git push without force flags", async () => {
  const input = { tool: "bash", args: { command: "git push origin feature/my-branch" } };
  await expect(blockForcePush(input as any, {} as any)).resolves.toBeUndefined();
});

// ── SE-453 S2: paridad con el hook bash ─────────────────────────────────────

test("blockForcePush: blocks force push with git global options (git -C dir push --force)", async () => {
  const input = { tool: "bash", args: { command: "git -C /tmp/x push --force origin feat" } };
  await expect(blockForcePush(input as any, {} as any)).rejects.toThrow(/BLOCKED \[force-push\]/);
});

test("blockForcePush: blocks git commit --amend (as the bash hook does)", async () => {
  const input = { tool: "bash", args: { command: "git commit --amend -m x" } };
  await expect(blockForcePush(input as any, {} as any)).rejects.toThrow(/BLOCKED \[force-push\]/);
});

test("blockForcePush: allows push to a branch whose name starts with main", async () => {
  const input = { tool: "bash", args: { command: "git push origin main-fix" } };
  await expect(blockForcePush(input as any, {} as any)).resolves.toBeUndefined();
});
