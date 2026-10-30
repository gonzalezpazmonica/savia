// SE-480 R1 — recarga en caliente del registro de cúpulas (AC-2, AC-3) en registro y A2A
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { DomeRegistry } from '../../../src/registry/domes.js';
import { A2AServer } from '../../../src/server/a2a.js';

describe('DomeRegistry.reloadIfChanged (SE-480)', () => {
  let tmp: string;
  let file: string;
  const dome = (name: string, extra: object = {}) => ({ name, path: name, description: '', confidentiality: 'N2', ...extra });
  const write = (domes: Record<string, object>, f = file, defaultDome = 'A') => {
    fs.writeFileSync(f, JSON.stringify({ version: 1, defaultDome, domes }));
    // mtime estrictamente distinto aunque el sistema de ficheros tenga resolución gruesa
    const t = new Date(Date.now() + (++tick) * 5000);
    fs.utimesSync(f, t, t);
  };
  let tick = 0;
  const registry = () => {
    const r = new DomeRegistry(file);
    r.reloadMinIntervalMs = 0;
    r.load();
    return r;
  };

  beforeEach(() => {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-reload-'));
    for (const n of ['A', 'B', 'C']) fs.mkdirSync(path.join(tmp, n));
    file = path.join(tmp, 'domes.json');
    write({ A: dome('A', { rag: { enabled: false } }), B: dome('B') });
  });
  afterEach(() => { fs.rmSync(tmp, { recursive: true, force: true }); vi.restoreAllMocks(); });

  it('sin cambios no recarga', () => {
    expect(registry().reloadIfChanged()).toBe(false);
  });

  it('cambia rag.enabled, añade y elimina cúpulas', () => {
    const r = registry();
    expect(r.get('A')?.rag?.enabled).toBe(false);
    write({ A: dome('A', { rag: { enabled: true } }), C: dome('C') });
    expect(r.reloadIfChanged()).toBe(true);
    expect(r.get('A')?.rag?.enabled).toBe(true);
    expect(r.get('B')).toBeUndefined();
    expect(r.get('C')?.active).toBe(true);
    expect(r.reloadIfChanged()).toBe(false);
  });

  it('el fichero local también se vigila y gana al base', () => {
    const r = registry();
    write({ A: dome('A', { rag: { enabled: true } }) }, path.join(tmp, 'domes.local.json'));
    expect(r.reloadIfChanged()).toBe(true);
    expect(r.get('A')?.rag?.enabled).toBe(true);
    expect(r.get('B')?.name).toBe('B');
  });

  it('AC-3: fichero corrupto conserva el último válido y expone el error; al arreglarlo se limpia', () => {
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    const r = registry();
    fs.writeFileSync(file, '{ esto no es json');
    const t = new Date(Date.now() + 99_000);
    fs.utimesSync(file, t, t);
    expect(r.reloadIfChanged()).toBe(false);
    expect(r.list().map(d => d.name).sort()).toEqual(['A', 'B']);
    expect(r.getState().error).toMatch(/Invalid JSON/);
    expect(err).toHaveBeenCalledTimes(1);
    expect(r.reloadIfChanged()).toBe(false); // mismo contenido roto: no se reintenta ni se vuelve a registrar
    expect(err).toHaveBeenCalledTimes(1);
    write({ A: dome('A') });
    expect(r.reloadIfChanged()).toBe(true);
    expect(r.getState().error).toBeUndefined();
    expect(r.list().map(d => d.name)).toEqual(['A']);
  });

  it('P1 #1418: tras una recarga rechazada, un save() (dome create) deja el registro válido y limpia el error', () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const r = registry();
    fs.writeFileSync(file, '{ roto');
    const t = new Date(Date.now() + 99_000);
    fs.utimesSync(file, t, t);
    r.reloadIfChanged();
    expect(r.getState().error).toBeDefined();
    r.save();
    expect(r.getState().error).toBeUndefined();
    expect(JSON.parse(fs.readFileSync(file, 'utf8')).domes.A).toBeDefined();
  });

  it('un fichero que parsea pero no valida no deja el registro a medias', () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const r = registry();
    write({ A: dome('A'), B: dome('B', { confidentiality: 'N9' }) });
    expect(r.reloadIfChanged()).toBe(false);
    expect(r.getState().error).toMatch(/Invalid confidentiality/);
    expect(r.list().map(d => d.name).sort()).toEqual(['A', 'B']);
    expect(r.get('B')?.confidentiality).toBe('N2');
  });

  it('el límite de una comprobación por intervalo evita stats repetidos', () => {
    const r = registry();
    r.reloadMinIntervalMs = 60_000;
    expect(r.reloadIfChanged()).toBe(false); // primera comprobación consume el intervalo
    write({ A: dome('A') });
    expect(r.reloadIfChanged()).toBe(false);
    r.reloadMinIntervalMs = 0;
    expect(r.reloadIfChanged()).toBe(true);
  });

  it('getState informa fichero, carga y mtime', () => {
    const s = registry().getState();
    expect(s.file).toBe(file);
    expect(Date.parse(s.loadedAt!)).toBeGreaterThan(0);
    expect(Date.parse(s.mtime!)).toBeGreaterThan(0);
    expect(s.error).toBeUndefined();
  });

  it('AC-2 (A2A): una cúpula eliminada deja de servirse en la llamada siguiente, sin reiniciar', () => {
    fs.writeFileSync(path.join(tmp, 'B', 'n.md'), '# n\n\nmanzana secreta');
    const r = registry();
    const server = new A2AServer({ name: 'v', path: path.join(tmp, 'v'), allowedExtensions: [], deniedPaths: [], maxDepth: 10, maxFileSize: 1e6 }, r);
    expect(server.listDomes().map(d => d.name).sort()).toEqual(['A', 'B']);
    expect(server.searchAll({ query: 'manzana' }).map(h => h.dome)).toEqual(['B']);
    write({ A: dome('A') });
    expect(server.listDomes().map(d => d.name)).toEqual(['A']);
    expect(server.searchAll({ query: 'manzana' })).toEqual([]);
  });
});
