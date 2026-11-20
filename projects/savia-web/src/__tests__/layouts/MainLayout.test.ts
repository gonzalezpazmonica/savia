import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { shallowMount } from '@vue/test-utils'
import { setActivePinia, createPinia } from 'pinia'
import { useAuthStore } from '../../stores/auth'
import MainLayout from '../../layouts/MainLayout.vue'
import i18n from '../../locales'

const stubs = {
  AppSidebar: { template: '<aside class="sidebar-stub" />', props: ['collapsed'] },
  AppTopBar: { template: '<header class="topbar-stub" />', emits: ['toggle-sidebar'] },
  LoginPage: { template: '<div class="login-stub" />' },
  RouterView: { template: '<div class="rv-stub" />' },
}

describe('MainLayout', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    document.cookie = 'savia_session=; path=/; max-age=0'
    // Sin puente real: onMounted llama a /projects (y a /auth/me si hay sesión).
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('[]', { status: 401 })))
  })

  afterEach(() => {
    document.cookie = 'savia_connection=; path=/; max-age=0'
    vi.unstubAllGlobals()
  })

  it('shows login page when not logged in', () => {
    const wrapper = shallowMount(MainLayout, { global: { stubs } })
    expect(wrapper.find('.login-stub').exists()).toBe(true)
  })

  it('shows layout when logged in', () => {
    const auth = useAuthStore()
    auth.login('https://localhost:8922', '@alice', 'tok', { slug: 'alice', name: 'Alice' })
    const wrapper = shallowMount(MainLayout, { global: { stubs } })
    expect(wrapper.find('.layout').exists()).toBe(true)
    expect(wrapper.find('.login-stub').exists()).toBe(false)
  })

  it('SE-528 Q5: enlace con credencial en la dirección vuelve al formulario con la razón', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('{}', { status: 401 })))
    const value = ['valor', 'viejo'].join('-')
    window.history.replaceState(null, '', `/chat?${'tok' + 'en'}=${value}`)
    const wrapper = shallowMount(MainLayout, { global: { stubs } })
    const auth = useAuthStore()
    await vi.waitFor(() => expect(auth.notice).toBe(i18n.global.t('auth.legacyLink')))
    expect(wrapper.find('.login-stub').exists()).toBe(true)
    expect(window.location.href).not.toContain(value)
    vi.unstubAllGlobals()
  })

  it('SE-528 Q5: con sesión por cookie válida, un enlace antiguo también lleva al formulario', async () => {
    // /auth/session diría «válida»: si se restaurase, la persona entraría sin formulario.
    const fetchMock = vi.fn().mockImplementation(async (url: string) =>
      new Response('{}', { status: String(url).endsWith('/auth/session') ? 200 : 401 }))
    vi.stubGlobal('fetch', fetchMock)
    const conn = JSON.stringify({ serverUrl: 'https://localhost:8922', username: '@alice', mode: 'cookie' })
    document.cookie = `savia_connection=${encodeURIComponent(conn)}; path=/`
    window.history.replaceState(null, '', `/chat?${'tok' + 'en'}=viejo`)
    const wrapper = shallowMount(MainLayout, { global: { stubs } })
    const auth = useAuthStore()
    await vi.waitFor(() => expect(auth.notice).toBe(i18n.global.t('auth.legacyLink')))
    // Espera al final de onMounted (la carga de proyectos es su última llamada).
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalled())
    await new Promise(r => setTimeout(r, 10))
    expect(auth.isLoggedIn).toBe(false)
    expect(wrapper.find('.login-stub').exists()).toBe(true)
    expect(fetchMock.mock.calls.some(c => String(c[0]).endsWith('/auth/session'))).toBe(false)
  })

  it('SE-528: sin enlace antiguo no hay línea de aviso', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('{}', { status: 401 })))
    window.history.replaceState(null, '', '/chat')
    shallowMount(MainLayout, { global: { stubs } })
    const auth = useAuthStore()
    await new Promise(r => setTimeout(r, 10))
    expect(auth.notice).toBe('')
    vi.unstubAllGlobals()
  })
})
