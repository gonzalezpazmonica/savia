// SE-410 P3/P7 — CLI `rag sync --all --check`: disparador programado (cron) sin script aparte
import { afterEach, describe, expect, it } from 'vitest';
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

const folders: string[] = [];
afterEach(() => { for (const f of folders.splice(0)) fs.rmSync(f, { recursive: true, force: true }); });

function setup(enabled: Record<string, boolean> = { a: true, b: true }) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-cli-rag-'));
  folders.push(root);
  const domes: Record<string, unknown> = {};
  for (const name of ['a', 'b']) {
    const folder = path.join(root, name);
    fs.mkdirSync(folder);
    fs.writeFileSync(path.join(folder, `${name}.md`), `# ${name}\n\n${'contenido de prueba para el índice. '.repeat(10)}`);
    domes[name] = { name, path: folder, description: '', confidentiality: 'N2', rag: { enabled: enabled[name] ?? true } };
  }
  const registry = path.join(root, 'domes.json');
  fs.writeFileSync(registry, JSON.stringify({ version: 1, defaultDome: 'a', domes }));
  const home = path.join(root, 'rag-home');
  const run = (...args: string[]) => spawnSync(process.execPath, [
    '--import', pathToFileURL(path.resolve('node_modules/tsx/dist/loader.mjs')).href,
    path.resolve('src/cli/index.ts'), 'rag', ...args, '--domes-file', registry,
  ], { env: { PATH: process.env.PATH || '', SAVIA_RAG_HOME: home, SAVIA_RAG_TEST_PROVIDER: 'hash' }, encoding: 'utf-8', timeout: 30000 });
  const disable = (...names: string[]) => {
    const reg = JSON.parse(fs.readFileSync(registry, 'utf-8'));
    for (const n of names) reg.domes[n].rag.enabled = false;
    fs.writeFileSync(registry, JSON.stringify(reg));
  };
  return { root, home, run, disable };
}

describe('SE-410 CLI rag sync --all --check', () => {
  it('sincroniza todas las cúpulas y sale 0 con el SLO en verde', () => {
    const { run } = setup();
    const r = run('sync', '--all', '--check');
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('[a]');
    expect(r.stdout).toContain('[b]');
  }, 30000);

  it('status --check sale 2 si una cúpula habilitada no tiene generación', () => {
    const { run } = setup();
    expect(run('status', '--check').status).toBe(2);
    run('sync', '--all');
    expect(run('status', '--check').status).toBe(0);
  }, 30000);

  it('un lock ajeno no es fallo: se omite esa cúpula y sigue con el resto', () => {
    const { run, home } = setup();
    fs.mkdirSync(path.join(home, 'a'), { recursive: true });
    fs.writeFileSync(path.join(home, 'a', 'sync.lock'), JSON.stringify({ pid: process.pid, ts: Date.now() }));
    const r = run('sync', '--all');
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('[a] sync en curso en otro proceso');
    expect(r.stdout).toContain('[b] gen=');
  }, 30000);

  it('con --check tras un sync parcial el SLO falla (exit 2)', () => {
    const { run, home } = setup();
    fs.mkdirSync(path.join(home, 'a'), { recursive: true });
    fs.writeFileSync(path.join(home, 'a', 'sync.lock'), JSON.stringify({ pid: process.pid, ts: Date.now() }));
    expect(run('sync', '--all', '--check').status).toBe(2);
  }, 30000);

  it('sin --dome ni --all falla con INVALID_INPUT', () => {
    const { run } = setup();
    const r = run('sync');
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('INVALID_INPUT');
  }, 30000);
});

describe('L32 registro sin cúpulas habilitadas y gc --all', () => {
  const off = { a: false, b: false };

  it('sync --all --check sin cúpulas rag.enabled sale 2 con ALERTA', () => {
    const { run } = setup(off);
    const r = run('sync', '--all', '--check');
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('ALERTA');
  }, 30000);

  it('sync --all sin --check y sin cúpulas habilitadas sale 1 con ALERTA', () => {
    const { run } = setup(off);
    const r = run('sync', '--all');
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('ALERTA');
  }, 30000);

  it('gc --all solo toca las cúpulas habilitadas', () => {
    const { run } = setup({ a: true, b: false });
    const r = run('gc', '--all');
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('[a]');
    expect(r.stdout).not.toContain('[b]');
  }, 30000);

  it('negativo: gc sin flags sigue recorriendo todas las cúpulas', () => {
    const { run } = setup({ a: true, b: false });
    const r = run('gc');
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('[a]');
    expect(r.stdout).toContain('[b]');
  }, 30000);
});

describe('L32 SLO y sync ruidosos con cúpulas deshabilitadas pero indexadas', () => {
  it('status --check sale 2 con alerta en stderr si una cúpula con índice se deshabilita', () => {
    const { run, disable } = setup();
    run('sync', '--all');
    expect(run('status', '--check').status).toBe(0);
    disable('a');
    const r = run('status', '--check');
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('[a] ALERTA');
    expect(r.stderr).toContain('rag.enabled=false');
  }, 30000);

  it('status --json: slo.ok=false con staleRatio alto en cúpula deshabilitada indexada', () => {
    const { run, disable, root } = setup();
    run('sync', '--all');
    disable('a');
    fs.writeFileSync(path.join(root, 'a', 'nuevo.md'), `# nuevo\n\n${'texto nuevo sin indexar. '.repeat(10)}`);
    const st = JSON.parse(run('status', '--json').stdout) as Array<{ name: string; staleRatio: number; slo: { ok: boolean; alerts: string[] } }>;
    const a = st.find(x => x.name === 'a')!;
    expect(a.staleRatio).toBeGreaterThan(0.1);
    expect(a.slo.ok).toBe(false);
    expect(a.slo.alerts.length).toBeGreaterThanOrEqual(2);
  }, 30000);

  it('sync --all con cúpulas indexadas pero todas deshabilitadas sale distinto de 0 con stderr', () => {
    const { run, disable } = setup();
    run('sync', '--all');
    disable('a', 'b');
    const r = run('sync', '--all');
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('ALERTA');
    expect(r.stderr).toContain('a, b');
  }, 30000);

  it('sync --all con una cúpula habilitada y otra indexada deshabilitada: sincroniza la primera y falla', () => {
    const { run, disable } = setup();
    run('sync', '--all');
    disable('b');
    const r = run('sync', '--all');
    expect(r.status).toBe(1);
    expect(r.stdout).toContain('[a] gen=');
    expect(r.stderr).toContain('b');
    expect(run('sync', '--all', '--check').status).toBe(2);
  }, 30000);

  it('la alerta queda en rag.jsonl para el morning brief', () => {
    const { run, disable, home } = setup();
    run('sync', '--all');
    disable('a', 'b');
    run('sync', '--all', '--check');
    const lines = fs.readFileSync(path.join(home, 'logs', 'rag.jsonl'), 'utf-8').trim().split('\n').map(l => JSON.parse(l));
    expect(lines.some(l => l.event === 'alert')).toBe(true);
  }, 30000);

  it('negativo: sin cúpulas indexadas deshabilitadas, sync --all sale 0', () => {
    const { run } = setup({ a: true, b: true });
    expect(run('sync', '--all').status).toBe(0);
  }, 30000);
});
