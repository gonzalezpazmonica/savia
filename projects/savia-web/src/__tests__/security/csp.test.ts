// SE-528 S1, AC-1.5: el servidor estático (`serve dist`) lee dist/serve.json,
// que Vite copia desde public/. La política no admite scripts en línea.
import { describe, it, expect } from 'vitest'
import serveRaw from '../../../public/serve.json?raw'

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
