import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { setActivePinia, createPinia } from 'pinia'
import { useChatStore } from '../../stores/chat'
import { PAYLOADS, findActiveContent } from '../security/activeContent'

vi.mock('../../composables/useSSE', () => ({
  useSSE: () => ({
    isStreaming: { value: false },
    streamChat: vi.fn(),
    sendPermission: vi.fn(),
    cancelStream: vi.fn(),
  }),
}))

const { default: ChatPage } = await import('../../pages/ChatPage.vue')

function mountWith(content: string) {
  const store = useChatStore()
  store.messages = [
    { id: '1', role: 'assistant', content, timestamp: Date.now(), isStreaming: false },
  ]
  return mount(ChatPage)
}

describe('ChatPage: contenido del asistente no ejecuta HTML activo (SE-528 S1)', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    delete (window as unknown as Record<string, unknown>).__pwned
  })

  it('el detector de la prueba sí detecta HTML activo (la prueba puede fallar)', () => {
    const host = document.createElement('div')
    host.innerHTML = PAYLOADS.imgOnerror + PAYLOADS.htmlAnchorJs
    expect(findActiveContent(host).length).toBeGreaterThan(0)
  })

  for (const [name, payload] of Object.entries(PAYLOADS)) {
    it(`payload ${name}: la burbuja no contiene nada ejecutable`, () => {
      const wrapper = mountWith(`antes\n\n${payload}\n\ndespués`)
      const bubble = wrapper.find('.bubble-content').element
      expect(findActiveContent(bubble)).toEqual([])
      expect((window as unknown as Record<string, unknown>).__pwned).toBeUndefined()
    })
  }

  it('markdown legítimo se renderiza igual (títulos, listas, tabla, código, enlace https)', () => {
    const md = '# Título\n\n- uno\n- dos\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n`x`\n\n```\nbloque\n```\n\n[web](https://example.com/a?b=1&c=2)'
    const html = mountWith(md).find('.bubble-content').html()
    expect(html).toContain('<h1>Título</h1>')
    expect(html).toContain('<li>uno</li>')
    expect(html).toContain('<table>')
    expect(html).toContain('<code>x</code>')
    expect(html).toContain('<pre><code>bloque')
    expect(html).toContain('href="https://example.com/a?b=1&amp;c=2"')
  })
})
