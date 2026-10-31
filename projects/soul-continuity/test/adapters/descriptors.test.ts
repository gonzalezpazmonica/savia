import { test } from "node:test";
import assert from "node:assert/strict";
import { ADAPTERS, DEFAULT_SENSITIVITY } from "../../src/contract/adapter.ts";
import { DESCRIPTORS, isApiAdapter } from "../../src/adapters/descriptors.ts";

const API = ADAPTERS.filter((a) => a !== "web");

test("cada adaptador de API declara propósito, nivel, TTL, permisos y revocación", () => {
  for (const n of API) {
    const d = DESCRIPTORS[n as keyof typeof DESCRIPTORS];
    assert.ok(d, `falta ${n}`);
    assert.equal(d!.name, n);
    assert.ok(d!.purpose.length > 10, `${n}: propósito`);
    assert.ok(d!.ttl_s > 0 && d!.ttl_s <= 24 * 3600, `${n}: TTL`);
    assert.ok(d!.scopes.length > 0 && d!.scopes.every((s) => s.length > 0), `${n}: permisos`);
    assert.match(d!.revocation, /caché/);
    assert.match(d!.revocation, /tokens/);
  }
});

test("nivel: N4 para empresa y nunca por debajo del contrato", () => {
  const rank = (l: string) => Number(l.slice(1));
  for (const n of API) {
    const d = DESCRIPTORS[n as keyof typeof DESCRIPTORS]!;
    assert.ok(rank(d.sensitivity) >= rank(DEFAULT_SENSITIVITY[n]), n);
    if (n !== "github") assert.equal(d.sensitivity, "N4", n);
  }
});

test("ningún permiso de escritura ni de lectura de otros buzones", () => {
  for (const n of API) {
    for (const s of DESCRIPTORS[n as keyof typeof DESCRIPTORS]!.scopes.flat()) {
      assert.doesNotMatch(s, /ReadWrite|Write|Send|Manage|Shared|gmail\.modify|gmail\.readonly|\/auth\/calendar$|\/auth\/drive$|write:/i, `${n}: ${s}`);
      // `.All` solo para ficheros compartidos conmigo (sharedWithMe lo exige en delegado).
      if (s.endsWith(".All")) assert.equal(s, "Files.Read.All", `${n}: ${s}`);
    }
  }
});

test("isApiAdapter distingue los de API del web y de nombres desconocidos", () => {
  assert.equal(isApiAdapter("m365-mail"), true);
  assert.equal(isApiAdapter("web"), false);
  assert.equal(isApiAdapter("toString"), false);
  assert.equal(isApiAdapter("otro"), false);
});
