// SE-392 S3: plain (non-JSON) stdout of a lifecycle hook is context or ignored, never a block.
// Before, session-init.sh printing text stopped the SessionStart loop and the later hooks never ran.
import { afterEach, expect, test } from "bun:test"
import { existsSync } from "node:fs"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { loadHookMap, runHooksForEvent } from "../lib/shell-bridge"

const roots: string[] = []
afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })))
})

async function rootWith(event: string, commands: string[]): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "savia-plain-"))
  roots.push(root)
  await mkdir(join(root, ".claude"))
  const hooks = commands.map((command) => ({ type: "command", command }))
  await writeFile(join(root, ".claude/settings.json"), JSON.stringify({ hooks: { [event]: [{ hooks }] } }))
  return root
}

async function run(event: string, commands: string[]) {
  const root = await rootWith(event, commands)
  const map = await loadHookMap(root)
  return { root, result: await runHooksForEvent(root, map, event, null, JSON.stringify({ hook_event_name: event })) }
}

test("SessionStart: plain text is context and later hooks still run", async () => {
  const { root, result } = await run("SessionStart", ["echo '[SPEC-SH02] aviso'", "touch second-ran"])
  expect(result.blocked).toBe(false)
  expect(result.contexts?.map((c) => c.text)).toEqual(["[SPEC-SH02] aviso"])
  expect(existsSync(join(root, "second-ran"))).toBe(true)
})

test("UserPromptSubmit: plain text is context without a level", async () => {
  const { result } = await run("UserPromptSubmit", ["echo 'recordatorio'"])
  expect(result.blocked).toBe(false)
  expect(result.contexts).toEqual([{ text: "recordatorio", level: undefined }])
})

test("other lifecycle events ignore plain text", async () => {
  const { result } = await run("PreCompact", ["echo 'backup done'"])
  expect(result.blocked).toBe(false)
  expect(result.contexts).toBeUndefined()
})

test("broken JSON still blocks, and authority events still reject plain text", async () => {
  expect((await run("SessionStart", ["echo '{broken'"])).result.blocked).toBe(true)
  const pre = (await run("PreToolUse", ["echo 'plain'"])).result
  expect([pre.blocked, pre.stderr]).toEqual([true, "INVALID_HOOK_OUTPUT"])
})
