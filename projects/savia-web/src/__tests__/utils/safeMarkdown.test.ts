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
    expect(html).toContain('a')
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
