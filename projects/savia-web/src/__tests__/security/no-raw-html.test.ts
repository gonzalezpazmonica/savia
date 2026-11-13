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

/** Cuerpo de la definición `function id` / `const id =` (llaves balanceadas) o la expresión de una flecha sin llaves. */
function bodyOf(src: string, id: string): string | undefined {
  const def = new RegExp(`function\\s+${id}\\b|const\\s+${id}\\s*=`).exec(src)
  if (!def) return undefined
  let i = def.index + def[0].length
  if (!def[0].startsWith('function')) {
    const arrow = src.indexOf('=>', i)
    if (arrow < 0) return undefined
    i = arrow + 2
    const rest = src.slice(i)
    if (!/^\s*\{/.test(rest)) return `return ${rest.split('\n')[0]}`
  }
  const open = src.indexOf('{', i)
  if (open < 0) return undefined
  let depth = 0
  for (let j = open; j < src.length; j++) {
    if (src[j] === '{') depth++
    else if (src[j] === '}' && --depth === 0) return src.slice(open + 1, j)
  }
  return undefined
}

const LITERAL_RETURN = /^\s*(['"`])[^'"`$\\]*\1\s*[;)]*\s*$/

/** `renderSafeMarkdown(...)` como expresión completa del return (nada concatenado detrás). */
function isSafeCall(ret: string): boolean {
  const m = /^\s*renderSafeMarkdown\(/.exec(ret)
  if (!m) return false
  let depth = 1
  for (let j = m[0].length; j < ret.length; j++) {
    if (ret[j] === '(') depth++
    else if (ret[j] === ')' && --depth === 0) return /^[\s;)]*$/.test(ret.slice(j + 1))
  }
  return false
}

/**
 * v-html solo admite `id` o `id(args)` cuyo cuerpo devuelve SIEMPRE renderSafeMarkdown(...)
 * o un literal constante. Cualquier otra forma (concatenación, rama con texto crudo,
 * llamada sin usar su resultado) es un problema. Sigue siendo análisis léxico, no AST.
 */
function vHtmlProblem(src: string, expr: string): string | undefined {
  const shape = /^\s*([A-Za-z_$][\w$]*)\s*(\([^()]*\))?\s*$/.exec(expr)
  if (!shape) return 'no es un identificador ni una llamada simple'
  const body = bodyOf(src, shape[1])
  if (body === undefined) return 'no tiene definición analizable'
  const returns = Array.from(body.matchAll(/\breturn\b([^\n;]*)/g), r => r[1])
  if (!returns.some(isSafeCall)) return 'no deriva de renderSafeMarkdown'
  if (returns.some(r => !isSafeCall(r) && !LITERAL_RETURN.test(r))) return 'tiene un return que no pasa por renderSafeMarkdown'
  return undefined
}

/** Devuelve los problemas de un fichero (vacío = correcto). */
export function audit(rel: string, src: string): string[] {
  if (WHITELIST.includes(rel)) return []
  const problems: string[] = []
  const code = rel === SAFE_FILE ? src.replace(/\binnerHTML\b/g, '') : src
  if (RAW_SINKS.test(code)) problems.push(`${rel}: usa un sumidero de HTML crudo`)
  const isVue = rel.endsWith('.vue')
  for (const m of isVue ? src.matchAll(/v-html\s*=\s*"([^"]*)"/g) : []) {
    const why = vHtmlProblem(src, m[1])
    if (why) problems.push(`${rel}: v-html="${m[1]}" ${why}`)
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
    const def = 'function renderMd(t){ return renderSafeMarkdown(t) }\n'
    expect(audit('x.vue', `${def}<div v-html="renderMd(m) + userText" />`).length).toBeGreaterThan(0)
    expect(audit('x.vue', 'function f(t){ if (t) return t\n return renderSafeMarkdown(t) }\n<div v-html="f(m)" />').length).toBeGreaterThan(0)
    expect(audit('x.vue', 'function f(t){ renderSafeMarkdown(t)\n return t }\n<div v-html="f(m)" />').length).toBeGreaterThan(0)
    expect(audit('x.vue', 'const b = computed(() => { return `${raw}` })\n<div v-html="b" />').length).toBeGreaterThan(0)
    expect(audit('x.vue', '<div v-html="sinDefinir" />').length).toBeGreaterThan(0)
    expect(audit('x.vue', 'function f(t){ return renderSafeMarkdown(t) + raw }\n<div v-html="f(m)" />').length).toBeGreaterThan(0)
  })

  it('el auditor acepta el uso correcto', () => {
    const ok = `function renderMd(t){ return renderSafeMarkdown(t) }\n<div v-html="renderMd(m)" />`
    expect(audit('x.vue', ok)).toEqual([])
    const lit = `function renderMd(t){\n  if (!t) return '...'\n  return renderSafeMarkdown(t, { breaks: true })\n}\n<div v-html="renderMd(m)" />`
    expect(audit('x.vue', lit)).toEqual([])
    const comp = `const body = computed(() => {\n  if (!x) return ''\n  return renderSafeMarkdown(b, { highlight: h })\n})\n<div v-html="body" />`
    expect(audit('x.vue', comp)).toEqual([])
    expect(audit('x.vue', 'const b = computed(() => renderSafeMarkdown(t))\n<div v-html="b" />')).toEqual([])
  })
})
