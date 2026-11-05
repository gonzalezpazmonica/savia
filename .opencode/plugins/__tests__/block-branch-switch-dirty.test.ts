import { test, expect } from "bun:test";
import { parseSwitchTargets, switchTargets, blockBranchSwitchDirty } from "../guards/block-branch-switch-dirty.ts";

// Revisión #1483 (3.ª): el detector por regex del respaldo TS se quitó; las mismas
// entradas se comprueban contra el resolvedor que usa el guard (`--switch`).
function isSwitch(cmd: string): boolean {
  const t = switchTargets(cmd, "/tmp");
  expect(t).not.toBeNull();
  return (t as string[]).length > 0;
}

// 2026-11-04: `git checkout --merge -- <rutas>` restaura ficheros y no cambia
// de rama, pero el guard lo trataba como cambio de rama con el árbol sucio.
// Misma entrada que el hook bash (tests/test-block-branch-switch-dirty.bats).

test("file restore with options before -- is not a branch change", () => {
  for (const cmd of [
    "git checkout -- a.txt",
    "git checkout --merge -- a.txt b.txt",
    "git checkout -m -- a.txt",
    "git checkout --ours -- a.txt",
    "git checkout main -- a.txt",
    "git -C /tmp/r checkout --merge -- a.txt",
  ]) {
    expect(isSwitch(cmd)).toBe(false);
  }
});

test("branch changes are still detected", () => {
  for (const cmd of [
    "git checkout feature",
    "git checkout --merge feature",
    "git checkout -b nueva",
    "git switch feature",
    "git switch -- feature",
    "git -C /tmp/r checkout feature",
  ]) {
    expect(isSwitch(cmd)).toBe(true);
  }
});

test("a restore earlier in the command does not excuse a later branch change", () => {
  for (const cmd of [
    "git checkout -- a.txt; git checkout feature",
    "git checkout --merge -- a.txt && git switch feature",
    "git checkout -- a.txt\ngit checkout feature",
  ]) {
    expect(isSwitch(cmd)).toBe(true);
  }
});

test("`--` with no paths after it is a branch change (`git checkout main --`)", () => {
  expect(isSwitch("git checkout feature --")).toBe(true);
  expect(isSwitch("git checkout feature -- && echo ok")).toBe(true);
});

test("a `--` belonging to another command does not count", () => {
  expect(isSwitch("git checkout feature; grep -- x f")).toBe(true);
  expect(isSwitch("git checkout feature | cat -- f")).toBe(true);
});

// 2026-11-05 (revisión #1483): redirecciones y comentarios no son pathspecs;
// `git checkout feature -- >/dev/null` ejecuta `checkout feature --` y cambia de rama.
test("redirections or comments after `--` are not paths", () => {
  for (const cmd of [
    "git checkout feature -- >/dev/null",
    "git checkout feature -- > /dev/null",
    "git checkout feature -- 2>&1",
    "git checkout feature # -- x",
    "git checkout feature -- # comentario",
  ]) {
    expect(isSwitch(cmd)).toBe(true);
  }
  // Una ruta real con redirección detrás sigue siendo restauración.
  expect(isSwitch("git checkout -- a.txt >/dev/null")).toBe(false);
  expect(isSwitch("git checkout -- a.txt 2>&1")).toBe(false);
});

// Revisión de seguridad #1483 (P1-1): `-- $X` o `-- $(…)` pueden expandirse a nada
// y dejar `git checkout feature --`, que cambia de rama.
test("expansions after `--` are not known paths", () => {
  for (const cmd of [
    "git checkout feature -- $FILES",
    'git checkout feature -- "$FILES"',
    "git checkout origin/main -- $(git diff --name-only x)",
    "git checkout origin/main -- $(git diff --name-only x | grep y)",
    "git checkout feature -- `true`",
  ]) {
    expect(isSwitch(cmd)).toBe(true);
  }
  // Con una ruta conocida junto a la expansión sigue siendo restauración.
  expect(isSwitch("git checkout feature -- a.txt $FILES")).toBe(false);
});

test("line continuation inside a restore keeps it a restore; newline separates", () => {
  expect(isSwitch("git checkout HEAD \\\n -- a.txt")).toBe(false);
  expect(isSwitch("git checkout feature --\necho x")).toBe(true);
});

test("commands without checkout/switch are ignored", () => {
  expect(isSwitch("git status")).toBe(false);
  expect(isSwitch("echo checkout feature")).toBe(false);
});

// Revisión de corrección #1483 (3.ª, P2-1): expansiones anidadas o entre comillas
// tras `--` engañaban al regex del respaldo; el resolvedor no se deja.
test("nested or quoted expansions after `--` are not known paths", () => {
  expect(isSwitch("git checkout feature -- $(echo $(true))")).toBe(true);
  expect(isSwitch('git checkout feature -- "$(true)"')).toBe(true);
});

// Revisión de seguridad #1483 (3.ª, P2-4): una línea inesperada del resolvedor
// no se descarta: cuenta como destino incierto, igual que en el hook bash.
test("unexpected resolver lines become an uncertain target", () => {
  expect(parseSwitchTargets("switch\t/tmp/a\n")).toEqual(["/tmp/a"]);
  expect(parseSwitchTargets("switch\t/tmp/a\nb\n")).toEqual(["/tmp/a", ""]);
  expect(parseSwitchTargets("basura\n")).toEqual([""]);
  expect(parseSwitchTargets("")).toEqual([]);
});

// Revisión de seguridad #1483 (3.ª, P2-5): sin resolvedor (python3 fuera del PATH)
// el guard bloquea en vez de caer a un regex que no ve `-c k=v` ni alias.
test("without the resolver, a git command is blocked (fail-closed)", async () => {
  const run = (command: string) => blockBranchSwitchDirty({ tool: "bash", args: { command } } as any, {} as any);
  const prev = process.env.PATH;
  process.env.PATH = "/nonexistent";
  try {
    for (const cmd of ["git -c k=v checkout feature", "git checkout -- a.txt", 'git -C "/a b" checkout x']) {
      await expect(run(cmd)).rejects.toThrow(/resolvedor de destinos no disponible/);
    }
    // negativo: sin `git` ni `checkout|switch` el prefiltro no llega al resolvedor
    await expect(run("ls -la")).resolves.toBeUndefined();
  } finally {
    process.env.PATH = prev;
  }
});
