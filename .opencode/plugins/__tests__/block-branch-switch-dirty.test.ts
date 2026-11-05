import { test, expect } from "bun:test";
import { hasBranchChange } from "../guards/block-branch-switch-dirty.ts";

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
    expect(hasBranchChange(cmd)).toBe(false);
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
    expect(hasBranchChange(cmd)).toBe(true);
  }
});

test("a restore earlier in the command does not excuse a later branch change", () => {
  for (const cmd of [
    "git checkout -- a.txt; git checkout feature",
    "git checkout --merge -- a.txt && git switch feature",
    "git checkout -- a.txt\ngit checkout feature",
  ]) {
    expect(hasBranchChange(cmd)).toBe(true);
  }
});

test("`--` with no paths after it is a branch change (`git checkout main --`)", () => {
  expect(hasBranchChange("git checkout feature --")).toBe(true);
  expect(hasBranchChange("git checkout feature -- && echo ok")).toBe(true);
});

test("a `--` belonging to another command does not count", () => {
  expect(hasBranchChange("git checkout feature; grep -- x f")).toBe(true);
  expect(hasBranchChange("git checkout feature | cat -- f")).toBe(true);
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
    expect(hasBranchChange(cmd)).toBe(true);
  }
  // Una ruta real con redirección detrás sigue siendo restauración.
  expect(hasBranchChange("git checkout -- a.txt >/dev/null")).toBe(false);
  expect(hasBranchChange("git checkout -- a.txt 2>&1")).toBe(false);
});

test("line continuation inside a restore keeps it a restore; newline separates", () => {
  expect(hasBranchChange("git checkout HEAD \\\n -- a.txt")).toBe(false);
  expect(hasBranchChange("git checkout feature --\necho x")).toBe(true);
});

test("commands without checkout/switch are ignored", () => {
  expect(hasBranchChange("git status")).toBe(false);
  expect(hasBranchChange("echo checkout feature")).toBe(false);
});
