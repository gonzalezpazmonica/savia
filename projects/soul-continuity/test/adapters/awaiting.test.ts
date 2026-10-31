import { test } from "node:test";
import assert from "node:assert/strict";
import { type Msg, awaitingReply, senderAuth } from "../../src/adapters/awaiting.ts";

const ME = ["yo@alfa.example"];
const m = (over: Partial<Msg>): Msg => ({
  id: "m1", conv: "c1", from: "ana@alfa.example", to: ["yo@alfa.example"], cc: [],
  at: "2026-11-01T10:00:00Z", sent: false, subject: "s", auth: "unknown", ...over,
});
const ids = (xs: Msg[]) => xs.map((x) => x.id).sort();

test("esperando: último ajeno, yo en To y sin enviado posterior", () => {
  assert.deepEqual(ids(awaitingReply([m({})], ME)), ["m1"]);
});

test("esperando: CC no cuenta y la lista de distribución tampoco", () => {
  assert.deepEqual(awaitingReply([m({ to: ["equipo@alfa.example"], cc: ["yo@alfa.example"] })], ME), []);
});

test("esperando: una respuesta desde otro cliente aparece en enviados y cierra el hilo", () => {
  const reply = m({ id: "r1", from: "yo@alfa.example", to: ["ana@alfa.example"], at: "2026-11-01T11:00:00Z", sent: true });
  assert.deepEqual(awaitingReply([m({}), reply], ME), []);
});

test("esperando: un enviado anterior no cierra un mensaje nuevo", () => {
  const before = m({ id: "r0", from: "yo@alfa.example", at: "2026-11-01T09:00:00Z", sent: true });
  assert.deepEqual(ids(awaitingReply([before, m({})], ME)), ["m1"]);
});

test("esperando: a igual instante, lo mío cierra", () => {
  const reply = m({ id: "r1", from: "yo@alfa.example", sent: true });
  assert.deepEqual(awaitingReply([m({}), reply], ME), []);
});

test("esperando: un mensaje mío a mí misma no crea espera", () => {
  assert.deepEqual(awaitingReply([m({ from: "YO@alfa.example" })], ME), []);
});

test("esperando: identidades sin distinguir mayúsculas y varias direcciones", () => {
  assert.deepEqual(ids(awaitingReply([m({ to: ["Alias@ALFA.example"] })], ["yo@alfa.example", "alias@alfa.example"])), ["m1"]);
});

test("esperando: un hilo por conversación, con el último mensaje entrante", () => {
  const second = m({ id: "m2", at: "2026-11-01T12:00:00Z" });
  assert.deepEqual(ids(awaitingReply([m({}), second], ME)), ["m2"]);
});

test("esperando: un mensaje sin fecha válida no decide el hilo (fail-closed)", () => {
  assert.deepEqual(awaitingReply([m({ at: "no-es-fecha" })], ME), []);
});

const AR = (v: string) => [{ name: "Authentication-Results", value: v }];

test("remitente: interno del mismo inquilino", () => {
  assert.equal(senderAuth("cfo@alfa.example", [{ name: "X-MS-Exchange-Organization-AuthAs", value: "Internal" }], "alfa.example"), "tenant");
});

test("remitente: Internal con dominio ajeno no es del inquilino", () => {
  assert.equal(senderAuth("cfo@otra.example", [{ name: "X-MS-Exchange-Organization-AuthAs", value: "Internal" }], "alfa.example"), "unauthenticated");
});

test("remitente: DKIM y DMARC superados con header.from igual al From", () => {
  assert.equal(senderAuth("s@ext.example", AR("dkim=pass header.d=ext.example; dmarc=pass header.from=ext.example"), "alfa.example"), "dkim_dmarc");
});

test("remitente: From falsificado (header.from de otro dominio) no autentica", () => {
  assert.equal(senderAuth("cfo@alfa.example", AR("dkim=pass; dmarc=pass header.from=malo.example"), "beta.example"), "unauthenticated");
});

test("remitente: DMARC fallido no autentica", () => {
  assert.equal(senderAuth("s@ext.example", AR("dkim=pass; dmarc=fail header.from=ext.example"), "alfa.example"), "unauthenticated");
});

test("remitente: una cabecera forjada por el remitente bajo la real con dmarc=fail no autentica", () => {
  const h = [
    { name: "Authentication-Results", value: "dkim=none; dmarc=fail action=none header.from=alfa.example" },
    { name: "Authentication-Results", value: "x; dkim=pass header.d=alfa.example; dmarc=pass header.from=alfa.example" },
  ];
  assert.equal(senderAuth("cfo@alfa.example", h, "beta.example"), "unauthenticated");
  // La real de arriba manda: si es la buena, autentica aunque debajo haya ruido.
  assert.equal(senderAuth("cfo@alfa.example", [h[1], h[0]], "beta.example"), "dkim_dmarc");
});

test("remitente: no se combinan dkim de una cabecera y dmarc de otra", () => {
  const h = [
    { name: "Authentication-Results", value: "dkim=pass header.d=ext.example; dmarc=none" },
    { name: "Authentication-Results", value: "dmarc=pass header.from=ext.example" },
  ];
  assert.equal(senderAuth("s@ext.example", h, "alfa.example"), "unauthenticated");
});

test("remitente: dos resultados DMARC discordantes en la misma cabecera no autentican", () => {
  assert.equal(senderAuth("s@ext.example", AR("dkim=pass; dmarc=fail header.from=ext.example; dmarc=pass header.from=ext.example"), "alfa.example"), "unauthenticated");
});

test("remitente: con authserv-id exigido, solo vale el del receptor", () => {
  const v = "dkim=pass header.i=@ext.example; dmarc=pass header.from=ext.example";
  assert.equal(senderAuth("s@ext.example", AR(`mx.google.com; ${v}`), "", ["mx.google.com"]), "dkim_dmarc");
  assert.equal(senderAuth("s@ext.example", AR(`mx.malo.example; ${v}`), "", ["mx.google.com"]), "unauthenticated");
  assert.equal(senderAuth("s@ext.example", AR(v), "", ["mx.google.com"]), "unauthenticated");
});

test("remitente: AuthAs duplicado (Internal y Anonymous) no es del inquilino", () => {
  const h = [{ name: "X-MS-Exchange-Organization-AuthAs", value: "Internal" }, { name: "X-MS-Exchange-Organization-AuthAs", value: "Anonymous" }];
  assert.equal(senderAuth("cfo@alfa.example", h, "alfa.example"), "unauthenticated");
});

test("remitente: sin cabeceras es desconocido", () => {
  assert.equal(senderAuth("s@ext.example", undefined, "alfa.example"), "unknown");
});

test("esperando: un enviado desde un alias que no está en mis identidades también cierra", () => {
  const reply = m({ id: "r1", from: "alias-equipo@alfa.example", to: ["ana@alfa.example"], at: "2026-11-01T11:00:00Z", sent: true });
  assert.deepEqual(awaitingReply([m({}), reply], ME), []);
});
