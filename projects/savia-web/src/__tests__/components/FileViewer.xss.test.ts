import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import FileViewer from '../../components/files/FileViewer.vue'
import { PAYLOADS, findActiveContent } from '../security/activeContent'

function mountMd(content: string) {
  return mount(FileViewer, { props: { content, filename: 'nota.md' } })
}

describe('FileViewer: markdown no ejecuta HTML activo (SE-528 S1)', () => {
  beforeEach(() => {
    delete (window as unknown as Record<string, unknown>).__pwned
  })

  for (const [name, payload] of Object.entries(PAYLOADS)) {
    it(`payload ${name}: el visor no contiene nada ejecutable`, () => {
      const wrapper = mountMd(`# t\n\n${payload}\n\nfin`)
      const root = wrapper.find('.viewer-markdown').element
      // el botón de copiar del bloque de código es UI propia, sin atributos on*
      expect(findActiveContent(root)).toEqual([])
      expect((window as unknown as Record<string, unknown>).__pwned).toBeUndefined()
    })
  }

  it('bloque de código: botón Copy sin onclick en línea y con el texto del bloque', async () => {
    const wrapper = mountMd('```js\nconst a = 1\n```')
    const btn = wrapper.find('.code-copy-btn')
    expect(btn.exists()).toBe(true)
    expect(btn.attributes('onclick')).toBeUndefined()
    expect(wrapper.find('.viewer-markdown pre code').text()).toContain('const')
  })

  it('markdown legítimo se renderiza igual (enlace https externo con rel noopener)', () => {
    const wrapper = mountMd('# Hola\n\n[web](https://example.com)\n\n- a\n- b')
    const html = wrapper.find('.viewer-markdown').html()
    expect(html).toContain('<h1>Hola</h1>')
    expect(html).toContain('href="https://example.com"')
    expect(html).toContain('target="_blank"')
    expect(html).toContain('rel="noopener')
    expect(html).toContain('<li>a</li>')
  })
})
