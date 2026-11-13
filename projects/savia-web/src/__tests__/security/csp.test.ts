// SE-528 S1, AC-1.5: el servidor estático (`serve dist`) lee dist/serve.json,
// que Vite copia desde public/. La política no admite scripts en línea.
import { describe, it, expect } from 'vitest'
import serveRaw from '../../../public/serve.json?raw'
import pkgRaw from '../../../package.json?raw'
import viteRaw from '../../../vite.config.ts?raw'

const cfg = JSON.parse(serveRaw)

export function cspOf(c: { headers?: { source: string; headers: { key: string; value: string }[] }[] }): string | undefined {
  const rule = c.headers?.find(h => h.source === '**')
  return rule?.headers.find(h => h.key.toLowerCase() === 'content-security-policy')?.value
}

function directive(csp: string, name: string): string[] | undefined {
  const d = csp.split(';').map(s => s.trim()).find(s => s.startsWith(name + ' '))
  return d?.split(/\s+/).slice(1)
}

describe('Content-Security-Policy del servidor estático (AC-1.5)', () => {
  const csp = cspOf(cfg)

  it('la cabecera existe para todas las rutas', () => {
    expect(csp).toBeTruthy()
  })

  it('script-src no admite unsafe-inline ni unsafe-eval ni comodines', () => {
    const src = directive(csp!, 'script-src')
    expect(src).toEqual(["'self'"])
  })

  it('sin default-src permisivo y con object-src none y frame-ancestors none', () => {
    expect(directive(csp!, 'default-src')).toEqual(["'self'"])
    expect(directive(csp!, 'object-src')).toEqual(["'none'"])
    expect(directive(csp!, 'frame-ancestors')).toEqual(["'none'"])
  })

  it('el detector rechaza una política con unsafe-inline en scripts (puede fallar)', () => {
    const bad = { headers: [{ source: '**', headers: [{ key: 'Content-Security-Policy', value: "script-src 'self' 'unsafe-inline'" }] }] }
    expect(directive(cspOf(bad)!, 'script-src')).not.toEqual(["'self'"])
    expect(cspOf({})).toBeUndefined()
  })
})

// La CSP solo existe si serve.json acaba en dist/ y el servidor sirve ese directorio.
export function deliveryProblems(pkgJson: string, viteCfg: string): string[] {
  const problems: string[] = []
  const serve = JSON.parse(pkgJson).scripts?.serve ?? ''
  if (!/\bserve\s+dist(\s|$)/.test(serve)) problems.push(`scripts.serve no sirve dist con serve: "${serve}"`)
  if (/\bpublicDir\s*:/.test(viteCfg)) problems.push('vite.config cambia publicDir: serve.json puede no copiarse')
  if (/\boutDir\s*:/.test(viteCfg)) problems.push('vite.config cambia outDir: serve dist no leería serve.json')
  return problems
}

describe('la CSP llega al servidor (serve.json en dist/)', () => {
  it('package.json sirve dist con serve y Vite copia public/ a dist/', () => {
    expect(deliveryProblems(pkgRaw, viteRaw)).toEqual([])
  })

  it('el detector rechaza otro servidor u otro directorio (puede fallar)', () => {
    const pkg = (serve: string) => JSON.stringify({ scripts: { serve } })
    expect(deliveryProblems(pkg('vite preview'), '')).not.toEqual([])
    expect(deliveryProblems(pkg('npx serve build -l 1'), '')).not.toEqual([])
    expect(deliveryProblems(pkg('npx serve dist -l 1'), "build: { outDir: 'out' }")).not.toEqual([])
    expect(deliveryProblems(pkg('npx serve dist -l 1'), "publicDir: false")).not.toEqual([])
    expect(deliveryProblems('{}', '')).not.toEqual([])
  })
})
