import { afterEach, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"

// Alerta #116 (js/polynomial-redos): el guard traducía cada `*` de un `find -name` a `[^/]*` y probaba la
// regex contra los nombres de las puertas. `a*a*…*b` contra un nombre largo de `a` es exponencial con un
// motor con retroceso y cuelga el hilo del guard: denegación de servicio sobre la puerta. El matcher nuevo
// es lineal y da las mismas respuestas que la regex anterior en los patrones normales.

const HERE = import.meta.dir
const LIB = join(HERE, "..", "lib", "shell-targets.ts")
const VOCAB = join(HERE, "..", "lib", "hook-vocabulary.ts")
const roots: string[] = []

afterEach(async () => {
  await Promise.all(roots.splice(0).map((r) => rm(r, { recursive: true, force: true })))
})

// Copia literal de globRegex/rx antes del arreglo: el oráculo de equivalencia.
const escapeRegex = (c: string) => c.replace(/[.*+?^${}()|[\]\\/-]/g, "\\$&")
function oldGlobRegex(pattern: string): string {
  let out = ""
  const n = pattern.length
  for (let i = 0; i < n; i++) {
    const c = pattern[i]
    if (c === "*") out += "[^/]*"
    else if (c === "?") out += "[^/]"
    else if (c === "[") {
      const j = pattern.indexOf("]", i + 1 < n && "!^".includes(pattern[i + 1]) ? i + 2 : i + 1)
      if (j < 0) out += "\\["
      else {
        let body = pattern.slice(i + 1, j)
        const neg = body.startsWith("!") || body.startsWith("^")
        if (neg) body = body.slice(1)
        out += "[" + (neg ? "^" : "") + body.replace(/([\\\]\[^])/g, "\\$1") + "]"
        i = j
      }
    } else out += escapeRegex(c)
  }
  return out
}
const oldRx = (p: string, ci = false) => new RegExp(`^(?:${oldGlobRegex(p)})$`, ci ? "si" : "s")

/** Runs `code` in a child bun with a hard timeout, so a hang fails the test instead of freezing it. */
function child(code: string, timeoutMs = 5000): { ok: boolean; out: string; ms: number } {
  const t0 = performance.now()
  const run = Bun.spawnSync(["bun", "-e", code], { timeout: timeoutMs, stdout: "pipe", stderr: "pipe" })
  return { ok: run.exitCode === 0, out: run.stdout.toString().trim() + run.stderr.toString().trim(), ms: performance.now() - t0 }
}

test("30 estrellas contra un nombre de 5 000 caracteres resuelve en menos de 100 ms", () => {
  const pattern = "a*".repeat(30) + "b"
  const name = "a".repeat(5000)
  const run = child(`
    const { globMatcher } = await import(${JSON.stringify(LIB)})
    const m = globMatcher(${JSON.stringify(pattern)})
    const t0 = performance.now()
    const r = m.test(${JSON.stringify(name)})
    const r2 = globMatcher(${JSON.stringify("*".repeat(30) + "?")}).test(${JSON.stringify(name)})
    console.log(JSON.stringify({ r, r2, ms: performance.now() - t0 }))
  `)
  expect(run.ok).toBe(true)
  const got = JSON.parse(run.out)
  expect(got.r).toBe(false)
  expect(got.r2).toBe(true)
  expect(got.ms).toBeLessThan(100)
}, 15000)

test("un find -name hostil no cuelga el guard de punta a punta", async () => {
  const root = await mkdtemp(join(tmpdir(), "glob-redos-"))
  roots.push(root)
  await mkdir(join(root, ".claude", "hooks"), { recursive: true })
  // 255 bytes: el máximo de un nombre en disco. El nombre es parte de los nombres de puerta del guard.
  await writeFile(join(root, ".claude", "hooks", "a".repeat(250) + ".sh"), "")
  const hostile = "a*".repeat(30) + "b"
  const matching = "a*".repeat(30) + ".sh"
  const run = child(`
    const { protectedTarget } = await import(${JSON.stringify(LIB)})
    const { PROTECTED_GATE_PATHS } = await import(${JSON.stringify(VOCAB)})
    const root = ${JSON.stringify(root)}
    const miss = protectedTarget("find .claude -name '${hostile}' -delete", root, root, PROTECTED_GATE_PATHS)
    const hit = protectedTarget("find .claude -name '${matching}' -delete", root, root, PROTECTED_GATE_PATHS)
    console.log(JSON.stringify({ miss, hit }))
  `)
  expect(run.ok).toBe(true)
  expect(run.ms).toBeLessThan(3000)
  // Ningún nombre de puerta casa con el hostil: el find no borra ninguna. El que casa sí alcanza la puerta.
  expect(JSON.parse(run.out)).toEqual({ miss: null, hit: ".claude" })
}, 15000)

const PATTERNS = [
  "*", "**", "***", "?", "??", "*.sh", "*.json", "settings*", "settings.*", "*settings*", "s*t*n*s.json",
  "hooks", "HOOKS", "hook?", "[hH]ooks", "[!x]ooks", "[^x]ooks", "[a-z]*", "[a-z]ooks", "[]", "[!]", "[",
  "[abc", "a]b", "*[", "]", "\\", "\\*", ".claude", ".*", "*.", "a/b", "*/hooks", ".claude/*", ".claude/**",
  "*/*", "?/?", "[/]", "a[/]b", "[!a]", "x*y*z", "*.*.*", "opencode.json*", "*.jsonc", "$x", "(a)", "a|b",
  "a+", "a{1}", "^a", "a$", "-", "[a-]", "[-a]", "é*", "[é]", "😀", "?😀", "[😀]", "dual-cli", "dual?cli",
]
const NAMES = [
  "", "hooks", "HOOKS", "Hooks", "hook", "hooksx", "settings.json", "settings.local.json", "SETTINGS.JSON",
  ".claude", ".codex", "a/b", "a\\b", "ab", "a]b", "]", "[", "\\", "*", "a.b.c", "x/y/z", "xyz", "opencode.json",
  "opencode.jsonc", "dual-cli", "dual_cli", "dual/cli", "é", "éa", "😀", "a😀", "x", "a", "-", "aa", "$x", "(a)",
  "a|b", "a+", "a{1}", "^a", "a$", "/", "//", ".", "..", "plugin", "scripts", "x.sh", "\n", "a\nb",
]

test("mismas respuestas que la regex anterior en una batería de patrones normales", async () => {
  const { globMatcher } = await import(LIB)
  let compared = 0
  for (const ci of [false, true]) {
    for (const p of PATTERNS) {
      let ref: RegExp | null = null
      try {
        ref = oldRx(p, ci)
      } catch {
        ref = null
      }
      if (ref === null) {
        expect(() => globMatcher(p, ci)).toThrow("INVALID_EVENT")
        continue
      }
      const m = globMatcher(p, ci)
      for (const n of NAMES) {
        const want = ref.test(n)
        if (m.test(n) !== want) throw new Error(`${JSON.stringify(p)} ci=${ci} ${JSON.stringify(n)}: want ${want}`)
        compared += 1
      }
    }
  }
  expect(compared).toBeGreaterThan(4000)
})

test("casos límite: **, ?, rutas con / y rango inválido", async () => {
  const { globMatcher } = await import(LIB)
  expect(globMatcher("**").test("a/b")).toBe(false)
  expect(globMatcher("**").test("ab")).toBe(true)
  expect(globMatcher("**").test("")).toBe(true)
  expect(globMatcher("*/*").test("a/b")).toBe(true)
  expect(globMatcher("*/*").test("a/b/c")).toBe(false)
  expect(globMatcher("?").test("/")).toBe(false)
  expect(globMatcher("?").test("é")).toBe(true)
  expect(globMatcher("[/]").test("/")).toBe(true)
  expect(globMatcher("[!a]").test("/")).toBe(true)
  expect(globMatcher(".claude/*").test(".claude/hooks")).toBe(true)
  expect(globMatcher(".claude/*").test(".claude/hooks/x")).toBe(false)
  expect(globMatcher("HOOKS", true).test("hooks")).toBe(true)
  expect(globMatcher("HOOKS").test("hooks")).toBe(false)
  expect(() => globMatcher("[z-a]")).toThrow("INVALID_EVENT")
})

// Un patrón de `find -name` con una expansión ($VAR, ${VAR}, $(cmd)) no se conoce hasta ejecutar: el guard
// no puede descartar ninguna puerta y tiene que tratarlo como «alcanza» (fallo cerrado). Entre comillas
// simples el `$` es literal y el patrón sí se puede comparar.
test("un find -name con expansión desconocida falla cerrado", async () => {
  const root = await mkdtemp(join(tmpdir(), "glob-dyn-"))
  roots.push(root)
  await mkdir(join(root, ".claude", "hooks"), { recursive: true })
  await writeFile(join(root, ".claude", "hooks", "guard.sh"), "")
  const { protectedTarget } = await import(LIB)
  const { PROTECTED_GATE_PATHS } = await import(VOCAB)
  for (const name of ['"$PATTERN"', "$PATTERN", "'*.'$EXT", '"${P}.sh"', '"$(cat p)"', "`cat p`"]) {
    expect(protectedTarget(`find .claude -name ${name} -delete`, root, root, PROTECTED_GATE_PATHS)).toBe(".claude")
    expect(protectedTarget(`find .claude -iname ${name} -delete`, root, root, PROTECTED_GATE_PATHS)).toBe(".claude")
  }
  expect(protectedTarget("find .claude -name '$PATTERN' -delete", root, root, PROTECTED_GATE_PATHS)).toBe(null)
  expect(protectedTarget("find .claude -name '*.py' -delete", root, root, PROTECTED_GATE_PATHS)).toBe(null)
  expect(protectedTarget('find .claude -name "$PATTERN" -print', root, root, PROTECTED_GATE_PATHS)).toBe(null)
})

// Auditoría de mutación 2026-11-27, T9: sin el recorte de barras finales en `inside`, `/` + sep es `//` y
// ninguna puerta empieza por ahí; el borrado recursivo de la raíz del sistema dejaba de ser «puerta».
test("el borrado recursivo de /, // y /// alcanza las puertas", async () => {
  const { protectedTarget } = await import(LIB)
  const { PROTECTED_GATE_PATHS } = await import(VOCAB)
  const root = await mkdtemp(join(tmpdir(), "glob-redos-root-"))
  roots.push(root)
  for (const target of ["/", "//", "///", "/.", "//./"]) {
    for (const verb of ["rm -rf", "rm -r", "rm -fr --"]) {
      expect(protectedTarget(`${verb} ${target}`, root, root, PROTECTED_GATE_PATHS)).toBe(target)
    }
  }
  // Una escritura no destructiva sobre la raíz no toca ninguna puerta.
  expect(protectedTarget("touch /", root, root, PROTECTED_GATE_PATHS)).toBe(null)
})

// Auditoría de mutación 2026-11-27, T3: sin colapsar `**…*` en un átomo, `add` recorre todas las estrellas
// desde cada estrella viva y cada carácter cuesta O(estrellas²): 4 000 estrellas eran 2,7 s por nombre.
test("4 000 estrellas seguidas contra un nombre de 255 caracteres resuelven en menos de 100 ms", () => {
  const name = "a".repeat(252) + ".sh"
  const run = child(`
    const { globMatcher } = await import(${JSON.stringify(LIB)})
    const t0 = performance.now()
    const miss = globMatcher(${JSON.stringify("*".repeat(4000) + "b")}).test(${JSON.stringify(name)})
    const hit = globMatcher(${JSON.stringify("*".repeat(4000) + ".sh")}).test(${JSON.stringify(name)})
    console.log(JSON.stringify({ miss, hit, ms: performance.now() - t0 }))
  `)
  expect(run.ok).toBe(true)
  const got = JSON.parse(run.out)
  expect(got.miss).toBe(false)
  expect(got.hit).toBe(true)
  expect(got.ms).toBeLessThan(100)
}, 15000)
