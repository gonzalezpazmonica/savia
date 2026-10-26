import { test, expect } from "bun:test";
import { bashExecutable } from "./bash-runtime.ts";

const none = () => false;

test("fuera de Windows usa bash del PATH", () => {
  expect(bashExecutable({}, "linux", none)).toBe("bash");
});

test("SAVIA_BASH tiene prioridad en cualquier plataforma", () => {
  expect(bashExecutable({ SAVIA_BASH: "/opt/bash" }, "linux", none)).toBe("/opt/bash");
  expect(bashExecutable({ SAVIA_BASH: "D:\\bash.exe", ProgramFiles: "C:\\PF" }, "win32", () => true)).toBe("D:\\bash.exe");
});

test("en Windows prefiere el bash de Claude Code si existe", () => {
  const env = { CLAUDE_CODE_GIT_BASH_PATH: "E:\\Git\\bin\\bash.exe", ProgramFiles: "C:\\PF" };
  expect(bashExecutable(env, "win32", (p) => p === "E:\\Git\\bin\\bash.exe")).toBe("E:\\Git\\bin\\bash.exe");
});

test("en Windows encuentra Git Bash en Program Files y nunca el lanzador WSL", () => {
  const env = { ProgramFiles: "C:\\Program Files", CLAUDE_CODE_GIT_BASH_PATH: "X:\\no-existe.exe" };
  const got = bashExecutable(env, "win32", (p) => p === "C:\\Program Files\\Git\\bin\\bash.exe");
  expect(got).toBe("C:\\Program Files\\Git\\bin\\bash.exe");
});

test("en Windows encuentra la instalación por usuario en LOCALAPPDATA", () => {
  const env = { LOCALAPPDATA: "C:\\Users\\u\\AppData\\Local" };
  const want = "C:\\Users\\u\\AppData\\Local\\Programs\\Git\\bin\\bash.exe";
  expect(bashExecutable(env, "win32", (p) => p === want)).toBe(want);
});

test("en Windows sin Git Bash cae a bash del PATH", () => {
  expect(bashExecutable({ ProgramFiles: "C:\\PF" }, "win32", none)).toBe("bash");
});
