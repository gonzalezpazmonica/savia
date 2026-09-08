import { afterEach, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { createServer, type Server } from "node:http"
import { loadHookMap, runHooksForEvent } from "../lib/shell-bridge"

const roots: string[] = []
const servers: Server[] = []
const envNames: string[] = []

afterEach(async () => {
  for (const name of envNames.splice(0)) delete process.env[name]
  for (const server of servers.splice(0)) {
    server.closeAllConnections?.()
    await new Promise<void>((resolve) => server.close(() => resolve()))
  }
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })))
})

async function listen(
  responder: (request: import("node:http").IncomingMessage, response: import("node:http").ServerResponse) => void,
): Promise<{ server: Server; url: string }> {
  const server = createServer(responder)
  servers.push(server)
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve))
  const address = server.address()
  if (!address || typeof address === "string") throw new Error("test server has no TCP address")
  return { server, url: `http://127.0.0.1:${address.port}/gate` }
}

async function projectWithHook(hook: Record<string, unknown>): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "savia-http-gate-test-"))
  roots.push(root)
  await mkdir(join(root, ".claude"))
  await writeFile(join(root, ".claude", "settings.json"), JSON.stringify({
    hooks: { PreToolUse: [{ matcher: "Edit|Write", hooks: [hook] }] },
  }))
  return root
}

function httpHook(url: string, tokenEnv: string, timeout = 1): Record<string, unknown> {
  return {
    type: "http",
    url,
    headers: { "X-Shield-Token": `$${tokenEnv}` },
    allowedEnvVars: [tokenEnv],
    timeout,
  }
}

async function run(root: string) {
  const hookMap = await loadHookMap(root)
  const payload = JSON.stringify({
    hook_event_name: "PreToolUse",
    tool_name: "Edit",
    tool_input: { file_path: "src/example.ts", new_string: "safe content" },
  })
  return {
    hookMap,
    payload,
    result: await runHooksForEvent(root, hookMap, "PreToolUse", "Edit", payload),
  }
}

function token(name: string): string {
  const value = `secret-${name}`
  process.env[name] = value
  envNames.push(name)
  return value
}

test("HTTP Shield ALLOW passes and receives the original hook_input with auth", async () => {
  const expectedToken = token("P02_ALLOW_TOKEN")
  let receivedBody = ""
  let receivedToken: string | undefined
  const { url } = await listen((request, response) => {
    receivedToken = request.headers["x-shield-token"] as string | undefined
    request.on("data", (chunk) => { receivedBody += chunk })
    request.on("end", () => {
      response.writeHead(200, { "Content-Type": "application/json" })
      response.end(JSON.stringify({ verdict: "ALLOW" }))
    })
  })
  const root = await projectWithHook(httpHook(url, "P02_ALLOW_TOKEN"))

  const { hookMap, payload, result } = await run(root)

  expect(hookMap.PreToolUse[0].type).toBe("http")
  expect(result.blocked).toBe(false)
  expect(receivedBody).toBe(payload)
  expect(receivedToken).toBe(expectedToken)
})

test("HTTP Shield explicit BLOCK blocks", async () => {
  token("P02_BLOCK_TOKEN")
  const { url } = await listen((_request, response) => {
    response.writeHead(200, { "Content-Type": "application/json" })
    response.end(JSON.stringify({ verdict: "BLOCK" }))
  })
  const root = await projectWithHook(httpHook(url, "P02_BLOCK_TOKEN"))

  expect((await run(root)).result).toMatchObject({ blocked: true, stderr: "HTTP_GATE_BLOCK" })
})

test("HTTP Shield cannot be downgraded to fire-and-forget", async () => {
  token("P02_ASYNC_TOKEN")
  const { url } = await listen((_request, response) => {
    response.writeHead(200, { "Content-Type": "application/json" })
    response.end(JSON.stringify({ verdict: "BLOCK" }))
  })
  const root = await projectWithHook({
    ...httpHook(url, "P02_ASYNC_TOKEN"),
    async: true,
  })

  const { hookMap, result } = await run(root)

  expect(hookMap.PreToolUse[0].async).toBe(false)
  expect(result).toMatchObject({ blocked: true, stderr: "HTTP_GATE_BLOCK" })
})

test("HTTP Shield daemon down blocks", async () => {
  token("P02_DOWN_TOKEN")
  const { server, url } = await listen(() => {})
  await new Promise<void>((resolve) => server.close(() => resolve()))
  servers.splice(servers.indexOf(server), 1)
  const root = await projectWithHook(httpHook(url, "P02_DOWN_TOKEN", 0.1))

  expect((await run(root)).result).toMatchObject({ blocked: true, stderr: "HTTP_GATE_UNREACHABLE" })
})

test("HTTP Shield timeout blocks with a typed reason", async () => {
  token("P02_TIMEOUT_TOKEN")
  const { url } = await listen(() => {})
  const root = await projectWithHook(httpHook(url, "P02_TIMEOUT_TOKEN", 0.02))

  expect((await run(root)).result).toMatchObject({ blocked: true, stderr: "HTTP_GATE_TIMEOUT" })
})

for (const status of [403, 500]) {
  test(`HTTP Shield status ${status} blocks`, async () => {
    token(`P02_STATUS_${status}_TOKEN`)
    const { url } = await listen((_request, response) => {
      response.writeHead(status, { "Content-Type": "application/json" })
      response.end(JSON.stringify({ verdict: "ALLOW" }))
    })
    const root = await projectWithHook(httpHook(url, `P02_STATUS_${status}_TOKEN`))

    expect((await run(root)).result).toMatchObject({ blocked: true, stderr: `HTTP_GATE_STATUS_${status}` })
  })
}

test("HTTP Shield invalid JSON blocks", async () => {
  token("P02_INVALID_TOKEN")
  const { url } = await listen((_request, response) => {
    response.writeHead(200, { "Content-Type": "application/json" })
    response.end("not-json")
  })
  const root = await projectWithHook(httpHook(url, "P02_INVALID_TOKEN"))

  expect((await run(root)).result).toMatchObject({ blocked: true, stderr: "HTTP_GATE_INVALID_RESPONSE" })
})

test("HTTP Shield unknown verdict blocks", async () => {
  token("P02_UNKNOWN_TOKEN")
  const { url } = await listen((_request, response) => {
    response.writeHead(200, { "Content-Type": "application/json" })
    response.end(JSON.stringify({ verdict: "MAYBE" }))
  })
  const root = await projectWithHook(httpHook(url, "P02_UNKNOWN_TOKEN"))

  expect((await run(root)).result).toMatchObject({ blocked: true, stderr: "HTTP_GATE_UNKNOWN_VERDICT" })
})

test("HTTP Shield redirect blocks without contacting the destination", async () => {
  token("P02_REDIRECT_TOKEN")
  let destinationRequests = 0
  const destination = await listen((_request, response) => {
    destinationRequests++
    response.writeHead(200, { "Content-Type": "application/json" })
    response.end(JSON.stringify({ verdict: "ALLOW" }))
  })
  const source = await listen((_request, response) => {
    response.writeHead(302, { Location: destination.url })
    response.end()
  })
  const root = await projectWithHook(httpHook(source.url, "P02_REDIRECT_TOKEN"))

  const result = (await run(root)).result

  expect(result.blocked).toBe(true)
  expect(["HTTP_GATE_UNREACHABLE", "HTTP_GATE_STATUS_0"]).toContain(result.stderr)
  expect(destinationRequests).toBe(0)
})

test("HTTP Shield missing token blocks before sending an invented credential", async () => {
  let requests = 0
  let receivedToken: string | undefined
  const { url } = await listen((request, response) => {
    requests++
    receivedToken = request.headers["x-shield-token"] as string | undefined
    response.writeHead(200, { "Content-Type": "application/json" })
    response.end(JSON.stringify({ verdict: "ALLOW" }))
  })
  const root = await projectWithHook(httpHook(url, "P02_MISSING_TOKEN"))

  const result = (await run(root)).result

  expect(result).toMatchObject({ blocked: true, stderr: "HTTP_GATE_MISSING_TOKEN" })
  expect(requests).toBe(0)
  expect(receivedToken).toBeUndefined()
})

test("HTTP Shield token never appears in captured output or result", async () => {
  const expectedToken = token("P02_LEAK_TOKEN")
  const { url } = await listen((_request, response) => {
    response.writeHead(403, { "Content-Type": "application/json" })
    response.end(JSON.stringify({ error: expectedToken }))
  })
  const root = await projectWithHook(httpHook(url, "P02_LEAK_TOKEN"))
  let capturedStdout = ""
  let capturedStderr = ""
  const stdoutWrite = process.stdout.write
  const stderrWrite = process.stderr.write
  process.stdout.write = ((chunk: unknown) => { capturedStdout += String(chunk); return true }) as typeof process.stdout.write
  process.stderr.write = ((chunk: unknown) => { capturedStderr += String(chunk); return true }) as typeof process.stderr.write
  let result
  try {
    result = (await run(root)).result
  } finally {
    process.stdout.write = stdoutWrite
    process.stderr.write = stderrWrite
  }

  expect(`${capturedStdout}${capturedStderr}${JSON.stringify(result)}`).not.toContain(expectedToken)
})

test("unsupported synchronous hook remains fail-closed", async () => {
  const root = await projectWithHook({ type: "unknown-critical-type" })

  expect((await run(root)).result).toMatchObject({ blocked: true, stderr: "UNSUPPORTED_CRITICAL_HOOK" })
})

test("HTTP hooks outside the local Shield boundary remain unsupported and fail-closed", async () => {
  const root = await projectWithHook(httpHook("http://example.invalid/gate", "P02_EXTERNAL_TOKEN"))

  expect((await run(root)).result).toMatchObject({ blocked: true, stderr: "UNSUPPORTED_CRITICAL_HOOK" })
})

test("command hook exit 0 regression passes", async () => {
  const root = await projectWithHook({ type: "command", command: "exit 0" })

  expect((await run(root)).result.blocked).toBe(false)
})

test("command hook hard-block exit regression blocks", async () => {
  const root = await projectWithHook({ type: "command", command: "exit 2" })

  expect((await run(root)).result.blocked).toBe(true)
})
