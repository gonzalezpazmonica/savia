import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { STOP_FILE, StoppedError, assertRunning, resume, stop, stopState } from "../src/core/failsafe.ts";

const T = "2026-10-31T10:00:00Z";
const tmp = () => mkdtempSync(join(tmpdir(), "soul-fs-"));

test("sin STOP, el núcleo corre", () => {
  const d = tmp();
  assert.deepEqual(stopState(d), { stopped: false });
  assert.doesNotThrow(() => assertRunning(d));
});

test("STOP persiste en disco y sobrevive a un «reinicio» (nueva lectura del directorio)", () => {
  const d = tmp();
  stop(d, "lo pide el operador", T);
  assert.ok(existsSync(join(d, STOP_FILE)));
  // Un proceso nuevo solo tiene el directorio: el estado sale del disco, no de memoria.
  const again = stopState(d);
  assert.equal(again.stopped, true);
  assert.equal(again.reason, "lo pide el operador");
  assert.throws(() => assertRunning(d), StoppedError);
});

test("STOP corrupto cuenta como STOP (fail-closed)", () => {
  const d = tmp();
  writeFileSync(join(d, STOP_FILE), "{no es json");
  const s = stopState(d);
  assert.equal(s.stopped, true);
  assert.equal(s.corrupt, true);
  assert.throws(() => assertRunning(d), StoppedError);
});

test("STOP vacío también cuenta como STOP", () => {
  const d = tmp();
  writeFileSync(join(d, STOP_FILE), "");
  assert.equal(stopState(d).stopped, true);
});

test("solo resume levanta el STOP y queda registrado", () => {
  const d = tmp();
  stop(d, "x", T);
  const s = resume(d, "2026-10-31T11:00:00Z");
  assert.equal(s.stopped, false);
  assert.doesNotThrow(() => assertRunning(d));
  const log = readFileSync(join(d, "failsafe.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.deepEqual(log.map((r) => r.action), ["stop", "resume"]);
});

test("resume sin STOP no deja rastro de reanudación", () => {
  const d = tmp();
  resume(d, T);
  assert.equal(existsSync(join(d, "failsafe.jsonl")), false);
});
