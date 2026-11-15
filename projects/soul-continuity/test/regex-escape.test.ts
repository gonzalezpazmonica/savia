import { test } from "node:test";
import assert from "node:assert/strict";
import { escapeRegExp } from "./regex-escape.ts";

test("escapeRegExp: la cadena escapada casa solo con el literal, incluida la barra invertida", () => {
  for (const lit of ["100.101.7.3", "a\\b", "C:\\x\\.y", "a+b(c)[d]{e}|f^$*?/"]) {
    assert.match(lit, new RegExp(`^${escapeRegExp(lit)}$`));
  }
});

test("escapeRegExp: el punto no casa con otro carácter (caso negativo)", () => {
  assert.doesNotMatch("100x101x7x3", new RegExp(`^${escapeRegExp("100.101.7.3")}$`));
  assert.doesNotMatch("ab", new RegExp(`^${escapeRegExp("a\\b")}$`));
});
