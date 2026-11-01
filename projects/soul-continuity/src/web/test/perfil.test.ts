import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { comprobarPerfilDedicado, crearHogarCanario, crearPerfilDedicado, diferenciasHuella, huella, rutasPerfilPersonal } from "../cortafuegos/perfil.ts";

test("el perfil dedicado se acepta", () => {
  const p = crearPerfilDedicado();
  try { comprobarPerfilDedicado(p, rutasPerfilPersonal("/home/x")); } finally { rmSync(p, { recursive: true }); }
});

test("el perfil personal o algo dentro de él se rechaza, aunque lleve la marca", () => {
  const { hogar, perfilPersonal } = crearHogarCanario();
  try {
    writeFileSync(join(perfilPersonal, ".perfil-soul"), "");
    const personales = rutasPerfilPersonal(hogar);
    assert.throws(() => comprobarPerfilDedicado(perfilPersonal, personales), /perfil personal/);
    assert.throws(() => comprobarPerfilDedicado(join(perfilPersonal, "Default"), personales), /perfil personal/);
  } finally { rmSync(hogar, { recursive: true }); }
});

test("un directorio sin la marca de Soul se rechaza", () => {
  const d = mkdtempSync(join(tmpdir(), "otro-"));
  try { assert.throws(() => comprobarPerfilDedicado(d, []), /no es un perfil dedicado/); } finally { rmSync(d, { recursive: true }); }
});

test("un hermano con nombre parecido no se confunde con el perfil personal", () => {
  const { hogar } = crearHogarCanario();
  try {
    const hermano = join(hogar, ".config", "google-chrome-soul");
    mkdirSync(hermano);
    writeFileSync(join(hermano, ".perfil-soul"), "");
    comprobarPerfilDedicado(hermano, rutasPerfilPersonal(hogar));
  } finally { rmSync(hogar, { recursive: true }); }
});

test("la huella detecta ficheros nuevos y cambios", () => {
  const { hogar, perfilPersonal } = crearHogarCanario();
  try {
    const a = huella(hogar);
    assert.deepEqual(diferenciasHuella(a, huella(hogar)), []);
    writeFileSync(join(perfilPersonal, "Crash Reports"), "x");
    assert.deepEqual(diferenciasHuella(a, huella(hogar)), [join(".config", "google-chrome", "Crash Reports")]);
  } finally { rmSync(hogar, { recursive: true }); }
});

test("la huella anota enlaces colgantes sin reventar (Chrome deja SingletonCookie)", () => {
  const { hogar, perfilPersonal } = crearHogarCanario();
  try {
    const a = huella(hogar);
    symlinkSync("no-existe-12345", join(perfilPersonal, "SingletonCookie"));
    assert.deepEqual(diferenciasHuella(a, huella(hogar)), [join(".config", "google-chrome", "SingletonCookie")]);
  } finally { rmSync(hogar, { recursive: true }); }
});

// --- Perfil persistente en el directorio de datos (producto) ---
import { dataDir } from "../../core/store.ts";
import { directorioDatos, fijarPreferencias, prepararPerfilSoul, MARCA as MARCA_SOUL } from "../cortafuegos/perfil.ts";

test("directorio de datos por sistema; SOUL_DATA_DIR manda", () => {
  assert.equal(directorioDatos({ SOUL_DATA_DIR: "/d" }, "linux", "/h"), "/d");
  // H-4: el mismo directorio que el núcleo, para que `soul uninstall` borre también `<datos>/web`.
  assert.equal(directorioDatos({}, "linux", "/h"), join("/h", ".local", "share", "savia", "soul-continuity"));
  assert.equal(directorioDatos({ XDG_DATA_HOME: "/x" }, "linux", "/h"), join("/x", "savia", "soul-continuity"));
  assert.equal(directorioDatos({}, "darwin", "/h"), join("/h", "Library", "Application Support", "Savia", "soul-continuity"));
  assert.equal(directorioDatos({ LOCALAPPDATA: "C:/L" }, "win32", "/h"), join("C:/L", "Savia", "soul-continuity"));
  for (const [env, pl] of [[{}, "linux"], [{}, "darwin"], [{ LOCALAPPDATA: "C:/L" }, "win32"]] as const) {
    assert.equal(directorioDatos(env, pl, "/h"), dataDir({ platform: pl, env, home: "/h" }));
  }
});

test("prepararPerfilSoul: perfil persistente con marca y sin gestor de contraseñas", () => {
  const datos = mkdtempSync(join(tmpdir(), "soul-datos-"));
  const hogar = mkdtempSync(join(tmpdir(), "soul-h-"));
  try {
    const p = prepararPerfilSoul(datos, hogar);
    assert.equal(p, join(datos, "web", "perfil"));
    assert.ok(existsSync(join(p, MARCA_SOUL)));
    const pref = JSON.parse(readFileSync(join(p, "Default", "Preferences"), "utf8"));
    assert.equal(pref.credentials_enable_service, false);
    assert.equal(pref.profile.password_manager_enabled, false);
    // Persistente: una segunda preparación no lo borra y reimpone las preferencias.
    writeFileSync(join(p, "Default", "Preferences"), JSON.stringify({ credentials_enable_service: true, otra: 1, profile: { x: 2 } }));
    prepararPerfilSoul(datos, hogar);
    const p2 = JSON.parse(readFileSync(join(p, "Default", "Preferences"), "utf8"));
    assert.deepEqual([p2.credentials_enable_service, p2.otra, p2.profile.x, p2.profile.password_manager_enabled], [false, 1, 2, false]);
  } finally {
    rmSync(datos, { recursive: true, force: true });
    rmSync(hogar, { recursive: true, force: true });
  }
});

test("prepararPerfilSoul rechaza un directorio de datos dentro del perfil personal", () => {
  const hogar = mkdtempSync(join(tmpdir(), "soul-h-"));
  try {
    assert.throws(() => prepararPerfilSoul(join(hogar, ".config", "google-chrome", "x"), hogar), /perfil personal/);
  } finally { rmSync(hogar, { recursive: true, force: true }); }
});

test("fijarPreferencias tolera Preferences corrupto (lo reescribe con las de Soul)", () => {
  const p = mkdtempSync(join(tmpdir(), "soul-p-"));
  try {
    mkdirSync(join(p, "Default"));
    writeFileSync(join(p, "Default", "Preferences"), "{roto");
    fijarPreferencias(p);
    assert.equal(JSON.parse(readFileSync(join(p, "Default", "Preferences"), "utf8")).credentials_enable_service, false);
  } finally { rmSync(p, { recursive: true, force: true }); }
});

// --- H-5: claves de cookies del perfil persistente en el llavero del sistema ---
import { almacenClaves } from "../cortafuegos/perfil.ts";

test("H-5: perfil persistente en Linux → llavero del sistema; temporal → basic; otros sistemas sin indicador", () => {
  assert.deepEqual(almacenClaves({ persistente: true, plataforma: "linux", env: { DBUS_SESSION_BUS_ADDRESS: "unix:path=/run/user/1/bus" } }), ["--password-store=gnome-libsecret"]);
  const rt = mkdtempSync(join(tmpdir(), "soul-rt-"));
  writeFileSync(join(rt, "bus"), "");
  assert.deepEqual(almacenClaves({ persistente: true, plataforma: "linux", env: { XDG_RUNTIME_DIR: rt } }), ["--password-store=gnome-libsecret"], "con el socket del bus en XDG_RUNTIME_DIR");
  rmSync(rt, { recursive: true, force: true });
  assert.deepEqual(almacenClaves({ persistente: false, plataforma: "linux", env: {} }), ["--password-store=basic"]);
  assert.deepEqual(almacenClaves({ persistente: true, plataforma: "darwin", env: {} }), []);
  assert.deepEqual(almacenClaves({ persistente: true, plataforma: "win32", env: {} }), []);
});

test("H-5: perfil persistente en Linux sin bus de sesión no se abre (no cae a la clave fija)", () => {
  assert.throws(() => almacenClaves({ persistente: true, plataforma: "linux", env: {} }), /llavero/);
  // Una sesión systemd sin bus (p. ej. SSH) tiene XDG_RUNTIME_DIR pero no el socket: tampoco se abre.
  const rt = mkdtempSync(join(tmpdir(), "soul-rt-"));
  try { assert.throws(() => almacenClaves({ persistente: true, plataforma: "linux", env: { XDG_RUNTIME_DIR: rt } }), /llavero/); }
  finally { rmSync(rt, { recursive: true, force: true }); }
});
