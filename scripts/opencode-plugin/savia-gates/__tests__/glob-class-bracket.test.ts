import { afterEach, expect, test } from "bun:test"
import { mkdtempSync, mkdirSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { globMatcher, protectedTarget } from "../lib/shell-targets"

// P2 de la revisión de la PR #1672: en POSIX (y en fnmatch, que usa find) un `]` justo después de `[`
// o de `[!`/`[^` es literal y la clase sigue hasta el siguiente `]`. globAtoms buscaba el cierre desde
// i+1, generaba `[]` (clase vacía en JS, nunca casa) y `find . -name '[]h]ooks' -delete` quedaba sin
// protección aunque find real borra `hooks`. El gemelo Python daba INVALID_EVENT: los dos divergían.

const roots: string[] = []
afterEach(() => {
  for (const r of roots.splice(0)) rmSync(r, { recursive: true, force: true })
})

test("find -name '[]h]ooks' -delete alcanza la puerta hooks", () => {
  const root = mkdtempSync(join(tmpdir(), "glob-bracket-"))
  roots.push(root)
  mkdirSync(join(root, "hooks"))
  expect(protectedTarget("find . -name '[]h]ooks' -delete", root, root, ["hooks"])).toBe(".")
  expect(protectedTarget("find . -name '[!]x]ooks' -delete", root, root, ["hooks"])).toBe(".")
  expect(protectedTarget("find . -iname '[]H]OOKS' -delete", root, root, ["hooks"])).toBe(".")
})

test("control: una clase con ] inicial que no admite la h no alcanza la puerta", () => {
  const root = mkdtempSync(join(tmpdir(), "glob-bracket-"))
  roots.push(root)
  mkdirSync(join(root, "hooks"))
  expect(protectedTarget("find . -name '[]x]ooks' -delete", root, root, ["hooks"])).toBe(null)
  expect(protectedTarget("find . -name '[!]h]ooks' -delete", root, root, ["hooks"])).toBe(null)
})

test("globMatcher: ] tras [ o [! es literal dentro de la clase", () => {
  expect(globMatcher("[]h]ooks").test("hooks")).toBe(true)
  expect(globMatcher("[]h]ooks").test("]ooks")).toBe(true)
  expect(globMatcher("[]h]ooks").test("xooks")).toBe(false)
  expect(globMatcher("[!]x]ooks").test("hooks")).toBe(true)
  expect(globMatcher("[!]x]ooks").test("]ooks")).toBe(false)
  expect(globMatcher("[^]x]ooks").test("xooks")).toBe(false)
  // Sin cierre tras el ] literal, el [ es literal (fnmatch y find).
  expect(globMatcher("[]").test("[]")).toBe(true)
  expect(globMatcher("[!]").test("[!]")).toBe(true)
  expect(globMatcher("[]").test("")).toBe(false)
})

test("paridad con find real en patrones con ] inicial", () => {
  const found = Bun.spawnSync(["find", "--version"])
  if (found.exitCode !== 0) return // sin GNU find no hay oráculo; el resto de tests cubre el contrato
  const root = mkdtempSync(join(tmpdir(), "glob-bracket-"))
  roots.push(root)
  const names = ["hooks", "]ooks", "xooks", "[]", "[!]", "!ooks", "^ooks"]
  for (const n of names) mkdirSync(join(root, n))
  const patterns = ["[]h]ooks", "[!]x]ooks", "[^]x]ooks", "[]x]ooks", "[!]h]ooks", "[]", "[!]", "[]!]ooks", "[]^]ooks"]
  for (const p of patterns) {
    const run = Bun.spawnSync(["find", root, "-mindepth", "1", "-maxdepth", "1", "-name", p, "-printf", "%f\n"])
    const real = run.stdout.toString().split("\n").filter(Boolean).sort()
    const ours = names.filter((n) => globMatcher(p).test(n)).sort()
    expect({ p, ours }).toEqual({ p, ours: real })
  }
})
