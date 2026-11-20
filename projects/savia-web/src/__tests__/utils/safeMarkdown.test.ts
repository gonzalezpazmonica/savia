import { describe, it, expect } from 'vitest'
import { renderSafeMarkdown, safeUrl, escapeHtml } from '../../utils/safeMarkdown'
import { PAYLOADS, findActiveContent } from '../security/activeContent'

function dom(html: string): HTMLElement {
  const host = document.createElement('div')
  host.innerHTML = html
  return host
}

describe('safeMarkdown: punto único de saneado (SE-528 S1, AC-1.1/1.2/1.3)', () => {
  for (const [name, payload] of Object.entries(PAYLOADS)) {
    for (const hl of [false, true]) {
      it(`payload ${name} (${hl ? 'con' : 'sin'} resaltado): sin elementos ni atributos ejecutables`, () => {
        const html = renderSafeMarkdown(`x\n\n${payload}\n\ny`, {
          breaks: true,
          highlight: hl ? () => null : undefined,
        })
        expect(findActiveContent(dom(html))).toEqual([])
      })
    }
  }

  it('el HTML crudo se muestra como texto escapado', () => {
    const html = renderSafeMarkdown('<img src=x onerror=alert(1)>')
    expect(html).toContain('&lt;img src=x onerror=alert(1)&gt;')
    expect(html).not.toMatch(/<img/)
  })

  it('SVG activo: ni como HTML crudo ni como imagen data:image/svg+xml', () => {
    const html = renderSafeMarkdown('<svg onload=alert(1)></svg>\n\n![x](data:image/svg+xml;base64,AAAA)')
    expect(html).not.toMatch(/<svg/i)
    expect(html).not.toMatch(/<img/i)
  })

  it('esquemas ejecutables: el enlace queda como texto, sin <a>', () => {
    const html = renderSafeMarkdown('[a](javascript:alert(1)) [b](JaVaScRiPt:alert(1)) [c](vbscript:x) [d](data:text/html,<b>)')
    expect(html).not.toMatch(/<a /)
    // el texto de cada enlace se conserva como texto plano
    expect(html).toBe('<p>a b c d</p>\n')
  })

  it('texto tras un tag en línea <pre>/<script>/<kbd>/<code> sale escapado (inRawBlock)', () => {
    for (const tag of ['pre', 'script', 'kbd', 'code']) {
      const html = renderSafeMarkdown(`x <${tag}> <img/src=x onerror=alert(1)>`)
      expect(html).toBe(`<p>x &lt;${tag}&gt; &lt;img/src=x onerror=alert(1)&gt;</p>\n`)
    }
  })

  it('el texto conserva las entidades ya escritas y escapa el resto', () => {
    expect(renderSafeMarkdown('a &amp; b &#39; < c')).toBe('<p>a &amp; b &#39; &lt; c</p>\n')
  })

  it('caché por función highlight: dos resaltadores distintos no se mezclan', () => {
    const md = '```js\nx\n```'
    const a = renderSafeMarkdown(md, { highlight: () => 'HL-A' })
    const b = renderSafeMarkdown(md, { highlight: () => 'HL-B' })
    expect(a).toContain('HL-A')
    expect(b).toContain('HL-B')
    expect(b).not.toContain('HL-A')
  })

  it('safeUrl: casos límite', () => {
    expect(safeUrl('https://x.org/a', 'link')).toBe('https://x.org/a')
    expect(safeUrl('HTTP://x.org', 'link')).toBe('HTTP://x.org')
    expect(safeUrl('mailto:a@b.c', 'link')).toBe('mailto:a@b.c')
    expect(safeUrl('mailto:a@b.c', 'image')).toBeNull()
    expect(safeUrl('/docs/a.md', 'link')).toBe('/docs/a.md')
    expect(safeUrl('java\tscript:alert(1)', 'link')).toBeNull()
    expect(safeUrl('  javascript:alert(1)', 'link')).toBeNull()
    expect(safeUrl('data:image/png;base64,AAAA', 'image')).not.toBeNull()
    expect(safeUrl('data:image/svg+xml;base64,AAAA', 'image')).toBeNull()
    expect(safeUrl('data:image/png;base64,AAAA', 'link')).toBeNull()
    expect(safeUrl('', 'link')).toBeNull()
  })

  it('escapeHtml escapa comillas y ángulos', () => {
    expect(escapeHtml(`<a href="x" b='y'>&`)).toBe('&lt;a href=&quot;x&quot; b=&#39;y&#39;&gt;&amp;')
  })

  it('caso positivo: markdown legítimo se renderiza', () => {
    const md = '# T\n\n- a\n- b\n\n| h1 | h2 |\n|----|----|\n| 1 | 2 |\n\n`c`\n\n```py\nprint(1)\n```\n\n[w](https://example.com "tt")\n\n![i](https://example.com/i.png)\n\n**n** _e_'
    const html = renderSafeMarkdown(md)
    expect(html).toContain('<h1>T</h1>')
    expect(html).toContain('<li>a</li>')
    expect(html).toContain('<table>')
    expect(html).toContain('<code>c</code>')
    expect(html).toContain('<pre><code class="language-py">')
    expect(html).toContain('<a href="https://example.com" title="tt" target="_blank" rel="noopener noreferrer">w</a>')
    expect(html).toContain('<img src="https://example.com/i.png" alt="i" loading="lazy">')
    expect(html).toContain('<strong>n</strong>')
  })

  it('texto vacío o nulo no rompe', () => {
    expect(renderSafeMarkdown('')).toBe('')
    expect(renderSafeMarkdown(undefined as unknown as string)).toBe('')
  })
})

describe('safeMarkdown: bloque de código sin resaltado disponible (mutante W10)', () => {
  const ATAQUE = '<img src=x onerror=alert(1)>'
  const sinResaltado = () => null

  it('lenguaje desconocido y resaltador que devuelve null: los ángulos se ven como texto, sin elementos activos', () => {
    const html = renderSafeMarkdown('```zzz\n' + ATAQUE + '\n```', { highlight: sinResaltado })
    const host = dom(html)
    expect(host.querySelectorAll('img')).toHaveLength(0)
    expect(findActiveContent(host)).toEqual([])
    expect(html).toContain('&lt;img src=x onerror=alert(1)&gt;')
    expect(host.querySelector('code')?.textContent).toContain(ATAQUE)
  })

  it('sin lenguaje (vacío) y resaltador null: igual de escapado', () => {
    const html = renderSafeMarkdown('```\n' + ATAQUE + '\n```', { highlight: sinResaltado })
    const host = dom(html)
    expect(host.querySelectorAll('img')).toHaveLength(0)
    expect(html).toContain('&lt;img')
  })

  it('el lenguaje que trae el ataque tampoco se cuela por la cabecera del bloque', () => {
    const html = renderSafeMarkdown('```<img\nx\n```', { highlight: sinResaltado })
    expect(dom(html).querySelectorAll('img')).toHaveLength(0)
  })

  it('control positivo: código legítimo sin ángulos se conserva tal cual', () => {
    const html = renderSafeMarkdown('```zzz\nconst a = 1\n```', { highlight: sinResaltado })
    expect(dom(html).querySelector('code')?.textContent).toContain('const a = 1')
    expect(html).toContain('language-plaintext')
  })

  it('control positivo: si el resaltador devuelve HTML, se usa ese HTML y no el escapado', () => {
    const html = renderSafeMarkdown('```js\na < b\n```', { highlight: () => '<span class="hljs-k">a &lt; b</span>' })
    const host = dom(html)
    expect(host.querySelectorAll('span.hljs-k')).toHaveLength(1)
    expect(host.querySelector('code')?.className).toContain('language-js')
  })
})
