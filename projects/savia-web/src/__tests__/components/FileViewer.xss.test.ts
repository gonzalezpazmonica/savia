import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { flushPromises } from '@vue/test-utils'
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

  describe('clic en Copy (listener delegado onViewerClick)', () => {
    const original = Object.getOwnPropertyDescriptor(navigator, 'clipboard')
    function setClipboard(value: unknown) {
      Object.defineProperty(navigator, 'clipboard', { value, configurable: true })
    }
    afterEach(() => {
      if (original) Object.defineProperty(navigator, 'clipboard', original)
      else delete (navigator as unknown as Record<string, unknown>).clipboard
    })

    it('copia el texto del bloque y anuncia Copied!', async () => {
      const writeText = vi.fn().mockResolvedValue(undefined)
      setClipboard({ writeText })
      const wrapper = mountMd('```js\nconst a = 1\n```')
      await wrapper.find('.code-copy-btn').trigger('click')
      await flushPromises()
      expect(writeText).toHaveBeenCalledWith(expect.stringContaining('const a = 1'))
      expect(wrapper.find('.code-copy-btn').text()).toBe('Copied!')
    })

    it('clic fuera del botón no copia nada', async () => {
      const writeText = vi.fn().mockResolvedValue(undefined)
      setClipboard({ writeText })
      const wrapper = mountMd('```js\nconst a = 1\n```\n\ntexto')
      await wrapper.find('.viewer-markdown p').trigger('click')
      await flushPromises()
      expect(writeText).not.toHaveBeenCalled()
    })

    for (const [name, clip] of [
      ['sin portapapeles', undefined],
      ['portapapeles que rechaza', { writeText: () => Promise.reject(new Error('denied')) }],
    ] as const) {
      it(`${name}: sin excepción sin capturar y sin anunciar copiado`, async () => {
        setClipboard(clip)
        const errorHandler = vi.fn()
        const wrapper = mount(FileViewer, {
          props: { content: '```js\nconst a = 1\n```', filename: 'nota.md' },
          global: { config: { errorHandler } },
        })
        await wrapper.find('.code-copy-btn').trigger('click')
        await flushPromises()
        expect(errorHandler).not.toHaveBeenCalled()
        expect(wrapper.find('.code-copy-btn').text()).toBe('Copy')
      })
    }
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

  describe('bloque de código sin resaltado (mutante W10)', () => {
    const ATAQUE = '<img src=x onerror=alert(1)>'

    it('lenguaje desconocido: los ángulos se muestran como texto y no hay elementos activos', () => {
      const wrapper = mountMd('```zzz\n' + ATAQUE + '\n```')
      const root = wrapper.find('.viewer-markdown').element
      expect(root.querySelectorAll('img')).toHaveLength(0)
      expect(findActiveContent(root)).toEqual([])
      expect(wrapper.find('.viewer-markdown pre code').text()).toContain(ATAQUE)
    })

    it('sin lenguaje: igual', () => {
      const wrapper = mountMd('```\n' + ATAQUE + '\n```')
      expect(wrapper.find('.viewer-markdown').element.querySelectorAll('img')).toHaveLength(0)
      expect(wrapper.find('.viewer-markdown pre code').text()).toContain(ATAQUE)
    })

    it('control positivo: lenguaje conocido resalta y conserva el texto', () => {
      const wrapper = mountMd('```js\nconst a = 1\n```')
      expect(wrapper.find('.viewer-markdown pre code .hljs-keyword').exists()).toBe(true)
      expect(wrapper.find('.viewer-markdown pre code').text()).toContain('const a = 1')
    })
  })
})
