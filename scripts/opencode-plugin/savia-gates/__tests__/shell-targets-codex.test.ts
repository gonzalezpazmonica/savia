import { afterEach, beforeEach, expect, test } from "bun:test"
import { mkdtempSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { protectedTarget } from "../lib/shell-targets"

// Alerta #116 / SE-442: contrato público, sin copiar globRegex ni modificar producto.
// find/rm son texto para el analizador: nunca se ejecutan estas órdenes.
// Los casos ReDoS corren en un hijo: el timeout de bun:test no interrumpe una regex síncrona.
let root: string
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "savia-redos-codex-"))
  mkdirSync(join(root, "gates/nested/inner"), { recursive: true })
  for (const name of ["guard.ts", "audit.sh", "README.md", "settings.json", "a", "ab", "a.b",
    "literal+name.ts", "Case.TS", ".hidden", "two\nlines.ts", "ñ.ts", "nested/deep.ts", "nested/inner/deep.ts"]) {
    writeFileSync(join(root, "gates", name), "fixture\n")
  }
})
afterEach(() => rmSync(root, { recursive: true, force: true }))

// Expectativas congeladas contra main; incluyen positivos y negativos para impedir
// que una implementación que siempre diga «alcanza» pase por equivalencia.
const normal: [string, boolean][] = [
  ["*", true], ["**", true], ["***", true], ["*.ts", true], ["*.py", false],
  ["guard.ts", true], ["guard.ts.bak", false], ["*guard*", true], ["*missing*", false],
  ["guard*.ts", true], ["guard?ts", true], ["guard??ts", false],
  ["?", true], ["??", true], ["????????????????", false], ["", false],
  ["a*", true], ["a?", true], ["a??", true], ["a???", false],
  ["[ag]*.ts", true], ["[xz]*.ts", false], ["[!a]*.sh", false], ["[!x]*.sh", true],
  ["[a-z]*.sh", true], ["[0-9]*", false], ["[[]*.ts", false], ["[", false],
  ["literal+name.ts", true], ["literalname.ts", false], ["literal.name.ts", false],
  ["Case.TS", true], ["case.ts", false], [".hidden", true], ["*.hidden", true],
  ["two?lines.ts", true], ["two*lines.ts", true], ["ñ.ts", true],
  ["nested/deep.ts", false], ["*/*", false], ["**/deep.ts", false], ["/", false],
]
for (const [pattern, reaches] of normal) {
  test(`equivalencia find -name ${JSON.stringify(pattern)}: alcanza=${reaches}`, () => {
    expect(protectedTarget(`find . -name '${pattern}' -delete`, root, root, ["gates"]))
      .toBe(reaches ? "." : null)
  })
}

for (const [pattern, reaches] of [["case.ts", true], ["CASE.*", true], ["*.tS", true],
  ["*.PY", false], ["CASE/TS", false]] as [string, boolean][]) {
  test(`equivalencia find -iname ${pattern}: alcanza=${reaches}`, () => {
    expect(protectedTarget(`find . -iname '${pattern}' -delete`, root, root, ["gates"]))
      .toBe(reaches ? "." : null)
  })
}

const paths: [string, string, boolean][] = [
  ["gates/*.ts", "gates/guard.ts", true],
  ["gates/*.ts", "gates/nested/deep.ts", false],
  ["gates/**.ts", "gates/nested/deep.ts", false],
  ["gates/**/deep.ts", "gates/nested/deep.ts", true],
  ["gates/**/deep.ts", "gates/nested/inner/deep.ts", false],
  ["gates/*/*/deep.ts", "gates/nested/inner/deep.ts", true],
  ["gates/guard?ts", "gates/guard.ts", true],
  ["gates?guard.ts", "gates/guard.ts", false],
  ["gates/guard??ts", "gates/guard.ts", false],
  ["gates/[ag]*.ts", "gates/guard.ts", true],
  ["gates/[xz]*.ts", "gates/guard.ts", false],
  ["gates/../gates/*.ts", "gates/guard.ts", true],
  ["other/*.ts", "gates/guard.ts", false],
]
for (const [pattern, gate, reaches] of paths) {
  test(`equivalencia de ruta ${pattern} frente a ${gate}: alcanza=${reaches}`, () => {
    expect(protectedTarget(`rm ${pattern}`, root, root, [gate])).toBe(reaches ? pattern : null)
  })
}

test("un patrón citado en una ruta conserva el asterisco literal", () => {
  expect(protectedTarget("rm 'gates/*.ts'", root, root, ["gates/guard.ts"])).toBe(null)
  expect(protectedTarget("rm gates/guard.ts", root, root, ["gates/guard.ts"])).toBe("gates/guard.ts")
})

test("un find sin escritura no alcanza aunque el patrón coincida", () => {
  expect(protectedTarget("find . -name '*.ts' -print", root, root, ["gates"])).toBe(null)
  expect(protectedTarget("find . -name '*.ts' -delete", root, root, ["gates"])).toBe(".")
})

test("sin gates no se inventa una coincidencia", () => {
  expect(protectedTarget("find . -name '*' -delete", root, root, [])).toBe(null)
  expect(protectedTarget("find . -name '*' -delete", root, root, ["gates"])).toBe(".")
})

test("falla cerrado si no se puede interpretar el filtro de find", () => {
  expect(protectedTarget("find . -type f -mtime +7 -delete", root, root, ["gates"])).toBe(".")
  expect(protectedTarget("find . -name '*.py' -delete", root, root, ["gates"])).toBe(null)
})

test("falla cerrado si el patrón de find es una variable desconocida", () => {
  expect(protectedTarget('find . -name "$PATTERN" -delete', root, root, ["gates"])).toBe(".")
  expect(protectedTarget("find . -name '*.py' -delete", root, root, ["gates"])).toBe(null)
})

test("glob inválido y orden incompleta rechazan el evento; nunca permiten por error", () => {
  for (const command of ["find . -name '[z-a]' -delete", "find . -name 'unterminated"]) {
    expect(() => protectedTarget(command, root, root, ["gates"])).toThrow("INVALID_EVENT")
  }
})

test("límite del inventario: 5000 nombres permiten descartar, 5001 fuerzan alcanza", () => {
  // Incluye los nombres ya presentes: contar entradas del recorrido, no el Set de nombres únicos.
  function entries(dir: string): number {
    return readdirSync(dir, { withFileTypes: true }).reduce((n, e) =>
      n + 1 + (e.isDirectory() ? entries(join(dir, e.name)) : 0), 0)
  }
  const initial = entries(join(root, "gates"))
  for (let i = initial; i < 5000; i++) writeFileSync(join(root, "gates", `entry-${i}.txt`), "")
  const command = "find . -name '*.missing' -delete"
  expect(protectedTarget(command, root, root, ["gates"])).toBe(null)
  writeFileSync(join(root, "gates/overflow.txt"), "")
  expect(protectedTarget(command, root, root, ["gates"])).toBe(".")
})

type Probe = { command: string; gates: string[]; expected?: string | null }
async function boundedProbe(probe: Probe): Promise<void> {
  const modulePath = new URL("../lib/shell-targets.ts", import.meta.url).pathname
  const source = `
    import { protectedTarget } from ${JSON.stringify(modulePath)};
    const { command, gates } = ${JSON.stringify(probe)};
    const root = ${JSON.stringify(root)};
    const start = performance.now();
    const result = protectedTarget(command, root, root, gates);
    console.log(JSON.stringify({ result, elapsedMs: performance.now() - start }));
  `
  const child = Bun.spawn([process.execPath, "--eval", source], { stdout: "pipe", stderr: "pipe" })
  let timedOut = false
  const watchdog = setTimeout(() => {
    timedOut = true
    child.kill("SIGKILL")
  }, 2000)
  try {
    const [stdout, stderr, code] = await Promise.all([
      new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited,
    ])
    expect(timedOut, "ReDoS: protectedTarget bloqueado más de 2000 ms (presupuesto: <100 ms)").toBe(false)
    expect(code, stderr).toBe(0)
    const measured = JSON.parse(stdout)
    expect(measured.elapsedMs, `medición del guard: ${stdout.trim()}`).toBeLessThan(100)
    // Un matcher exacto puede descartar un no-match; un límite conservador puede bloquearlo.
    // Una coincidencia real siempre debe alcanzar. Errores/ausencia de respuesta nunca son PASS.
    if ("expected" in probe) expect(measured.result).toBe(probe.expected)
    else expect([null, probe.command.startsWith("find ") ? "." : probe.command.slice(3)]).toContain(measured.result)
  } finally {
    clearTimeout(watchdog)
    if (child.exitCode === null) child.kill("SIGKILL")
    await child.exited
  }
}

for (const [label, pattern, match] of [
  ["30 estrellas consecutivas, fallo al final", "*".repeat(30) + "b", false],
  ["30 estrellas intercaladas, fallo al final", "a*".repeat(30) + "b", false],
  ["30 estrellas intercaladas, coincidencia real", "a*".repeat(30), true],
] as [string, string, boolean][]) {
  test(`ReDoS reaches: ${label} contra nombre de 5000 caracteres en <100 ms`, async () => {
    // El nombre sintético entra por protectedRel (gateNames lo inventaría incluso sin existir).
    // No se intenta crear un basename de 5000 bytes: excedería NAME_MAX en el filesystem.
    await boundedProbe({ command: `find . -name '${pattern}' -delete`, gates: ["a".repeat(5000)],
      ...(match ? { expected: "." } : {}) })
  })
}

test("ReDoS reaches -iname: 30 estrellas intercaladas sin coincidencia, 5000 caracteres, <100 ms", async () => {
  await boundedProbe({ command: `find . -iname '${"a*".repeat(30)}b' -delete`, gates: ["A".repeat(5000)] })
})

test("ReDoS globHits: ruta con 30 estrellas intercaladas y nombre de 5000 caracteres en <100 ms", async () => {
  await boundedProbe({ command: `rm ${"a*".repeat(30)}b`, gates: ["a".repeat(5000)] })
})
