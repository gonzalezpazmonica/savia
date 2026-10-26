// tdd-gate.ts — SPEC-127 Slice 2b-ii
//
// Port of `.opencode/hooks/tdd-gate.sh`. Blocks Edit/Write to a production
// code file when no corresponding test file exists. Production = the
// language extensions cs/py/ts/tsx/js/jsx/go/rs/rb/php/java/kt/swift/dart.
//
// The path-classification logic is exposed as `tddGateForPath` for unit
// testing. The full hook (`tddGate`) additionally calls out to the
// filesystem to look for matching test files; that runtime probe is
// integration-tested via the bash hook fixture under Claude Code.

import { extractToolName, extractFilePath, type ToolInput, type ToolOutput } from "../lib/hook-input.ts";

const PRODUCTION_EXT = new Set([
  "cs", "py", "ts", "tsx", "js", "jsx", "go", "rs", "rb", "php",
  "java", "kt", "swift", "dart",
]);

const EXEMPT_BASENAME_PATTERNS = [
  /Test/i, /Spec/i, /_test\./i, /\.test\./i, /\.spec\./i,
  /Migration/i, /\.dto\./i, /DTO/i, /\.config\./i, /Config\./i,
  /^Program\.cs$/, /^Startup\.cs$/, /^appsettings/, /\.csproj$/, /\.sln$/,
  /\.d\.ts$/, /^tsconfig/, /^package\.json$/, /^bun\.lock/,
  /^Dockerfile$/, /^docker-compose/, /\.tf$/, /\.tfvars$/, /\.ya?ml$/,
  /\.md$/, /\.txt$/, /\.json$/, /\.xml$/, /\.html$/, /\.css$/, /\.scss$/,
];

const EXEMPT_PATH_PATTERNS = [
  /\/tests?\//i, /\/__tests__\//,
  /\/specs?\//i, /\/fixtures\//, /\/mocks\//, /\/stubs\//, /\/fakes\//,
  /\/migrations\//i, /\/seeds\//,
  /\/config\//i, /\/scripts\//,
];

function ext(path: string): string {
  const i = path.lastIndexOf(".");
  return i >= 0 ? path.slice(i + 1).toLowerCase() : "";
}

function basename(path: string): string {
  const i = path.lastIndexOf("/");
  return i >= 0 ? path.slice(i + 1) : path;
}

export type TddVerdict = { needsTest: boolean; nameNoExt: string; ext: string };

// Windows paths arrive with "\\"; the classifier and the walk-up use "/" only.
function toSlash(path: string): string {
  return path.replaceAll("\\", "/");
}

export function tddGateForPath(rawPath: string): TddVerdict {
  const filePath = toSlash(rawPath);
  const e = ext(filePath);
  const bn = basename(filePath);
  const nameNoExt = bn.replace(new RegExp(`\\.${e}$`), "");

  if (!PRODUCTION_EXT.has(e)) return { needsTest: false, nameNoExt, ext: e };
  if (EXEMPT_BASENAME_PATTERNS.some((rx) => rx.test(bn))) {
    return { needsTest: false, nameNoExt, ext: e };
  }
  if (EXEMPT_PATH_PATTERNS.some((rx) => rx.test(filePath))) {
    return { needsTest: false, nameNoExt, ext: e };
  }
  return { needsTest: true, nameNoExt, ext: e };
}

/**
 * Full TDD gate: classifies the path, then probes the filesystem for a
 * matching test file when classification says one is needed. Throws when
 * production code lacks a test partner.
 *
 * Test-name lookup mirrors the bash hook: `${name}Test.*`,
 * `${name}.test.*`, `${name}.spec.*`, `${name}_test.*`, `test_${name}.*`.
 */
export async function tddGate(input: ToolInput, output: ToolOutput): Promise<void> {
  const tool = extractToolName(input);
  if (tool !== "edit" && tool !== "write") return;
  const rawPath = extractFilePath(input, output);
  if (!rawPath) return;
  const filePath = toSlash(rawPath);

  const verdict = tddGateForPath(filePath);
  if (!verdict.needsTest) return;

  // Filesystem probe via Bun's filesystem (compatible with Node async fs).
  // Lazy import to keep the test-only path classifier fast.
  const { readdir } = await import("node:fs/promises");
  const candidatePatterns = [
    `${verdict.nameNoExt}Test.`,
    `${verdict.nameNoExt}Tests.`,
    `${verdict.nameNoExt}.test.`,
    `${verdict.nameNoExt}.spec.`,
    `${verdict.nameNoExt}_test.`,
    `test_${verdict.nameNoExt}.`,
  ];

  // Walk up from the file's directory toward repo root. At each level we
  // scan the directory itself AND its conventional sibling test directories
  // (__tests__, tests, test, spec, specs) — this mirrors Bun/Vitest/Jest
  // conventions where production code lives in src/ and tests in __tests__/.
  // Pre-fix bug: only top-level dirs were scanned, missing tests colocated
  // in __tests__/ siblings. (Documented in RESUME-se-221-opencode-port.md.)
  const TEST_SUBDIRS = ["__tests__", "tests", "test", "spec", "specs"];
  let dir = filePath.slice(0, filePath.lastIndexOf("/")) || "/";
  for (let depth = 0; depth < 8 && dir && dir !== "/"; depth++) {
    const candidates: string[] = [dir, ...TEST_SUBDIRS.map((sub) => `${dir}/${sub}`)];
    for (const probe of candidates) {
      try {
        const entries = await readdir(probe);
        for (const e of entries) {
          if (candidatePatterns.some((p) => e.startsWith(p))) {
            return; // test exists nearby — pass
          }
        }
      } catch {
        // dir unreadable — keep walking
      }
    }
    const next = dir.slice(0, dir.lastIndexOf("/")) || "/";
    if (next === dir) break;
    dir = next;
  }

  throw new Error(
    `TDD GATE: no tests found for '${verdict.nameNoExt}.${verdict.ext}'. ` +
      `Write tests BEFORE production code. Create: ${verdict.nameNoExt}Test.${verdict.ext} ` +
      `or ${verdict.nameNoExt}.test.${verdict.ext}.`,
  );
}
