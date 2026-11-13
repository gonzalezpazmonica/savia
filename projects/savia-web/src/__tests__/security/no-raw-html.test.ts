// SE-528 S1, AC-1.4: toda inyección de HTML de la web pasa por renderSafeMarkdown.
// La lista blanca está VACÍA: no se admite ninguna excepción.
import { describe, it, expect } from 'vitest'

// Todo el código de src (sin tests) como texto, vía Vite (sin depender de tipos de Node).
const RAW = import.meta.glob(['../../**/*.{vue,ts,tsx,js}', '!../../__tests__/**'], {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>
const FILES = Object.entries(RAW).map(([k, v]) => [k.replace('../../', ''), v] as const)
const SAFE_FILE = 'utils/safeMarkdown.ts'
export const WHITELIST: string[] = []

const RAW_SINKS = /\b(innerHTML|outerHTML|insertAdjacentHTML|document\.write(ln)?|srcdoc|createContextualFragment)\b|dangerouslySetInnerHTML|domProps\s*:\s*\{\s*innerHTML/

/** Devuelve los problemas de un fichero (vacío = correcto). */
export function audit(rel: string, src: string): string[] {
  if (WHITELIST.includes(rel)) return []
  const problems: string[] = []
  const code = rel === SAFE_FILE ? src.replace(/\binnerHTML\b/g, '') : src
  if (RAW_SINKS.test(code)) problems.push(`${rel}: usa un sumidero de HTML crudo`)
  const isVue = rel.endsWith('.vue')
  for (const m of isVue ? src.matchAll(/v-html\s*=\s*"([^"]*)"/g) : []) {
    const id = /^\s*([A-Za-z_$][\w$]*)/.exec(m[1])?.[1]
    const def = id ? new RegExp(`(function\\s+${id}\\b|const\\s+${id}\\s*=)[\\s\\S]{0,400}`).exec(src)?.[0] : undefined
    if (!def || !def.includes('renderSafeMarkdown(')) {
      problems.push(`${rel}: v-html="${m[1]}" no deriva de renderSafeMarkdown`)
    }
  }
  if (isVue && (/v-html\s*=\s*[^"\s]/.test(src) || /v-html(?!\s*=)/.test(src))) problems.push(`${rel}: v-html con forma no analizable`)
  if (/\bh\(\s*['"][a-z0-9]+['"]\s*,\s*\{[^}]*innerHTML/.test(src)) problems.push(`${rel}: h() con innerHTML`)
  return problems
}

describe('toda inyección de HTML pasa por renderSafeMarkdown (AC-1.4)', () => {
  it('la lista blanca está vacía', () => {
    expect(WHITELIST).toEqual([])
  })

  it('el recorrido ve ficheros reales (no es un test vacío)', () => {
    const files = FILES.map(([f]) => f)
    expect(files.length).toBeGreaterThan(20)
    expect(files.some(f => f.includes('__tests__'))).toBe(false)
    expect(files).toContain('pages/ChatPage.vue')
    expect(files).toContain('components/files/FileViewer.vue')
  })

  it('el código de src no tiene inyecciones fuera del punto de saneado', () => {
    const problems = FILES.flatMap(([f, src]) => audit(f, src))
    expect(problems).toEqual([])
  })

  it('el auditor detecta casos malos (puede fallar)', () => {
    expect(audit('x.vue', '<div v-html="userText" />').length).toBeGreaterThan(0)
    expect(audit('x.vue', '<div v-html="marked.parse(t)" />').length).toBeGreaterThan(0)
    expect(audit('x.ts', 'el.innerHTML = s').length).toBeGreaterThan(0)
    expect(audit('x.ts', 'el.insertAdjacentHTML("beforeend", s)').length).toBeGreaterThan(0)
    expect(audit('x.vue', '<iframe :srcdoc="s" />').length).toBeGreaterThan(0)
    expect(audit('x.vue', '<div v-html=raw />').length).toBeGreaterThan(0)
  })

  it('el auditor acepta el uso correcto', () => {
    const ok = `function renderMd(t){ return renderSafeMarkdown(t) }\n<div v-html="renderMd(m)" />`
    expect(audit('x.vue', ok)).toEqual([])
  })
})
