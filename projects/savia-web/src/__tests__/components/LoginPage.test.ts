import { describe, it, expect, vi, beforeEach } from 'vitest'
import { shallowMount } from '@vue/test-utils'
import { setActivePinia, createPinia } from 'pinia'
import LoginPage from '../../components/LoginPage.vue'

vi.stubGlobal('fetch', vi.fn())

describe('LoginPage', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.mocked(fetch).mockReset()
  })

  it('renders the login overlay', () => {
    const wrapper = shallowMount(LoginPage)
    expect(wrapper.find('.login-overlay').exists()).toBe(true)
  })

  it('shows the Savia logo and title', () => {
    const wrapper = shallowMount(LoginPage)
    expect(wrapper.find('.login-logo').exists()).toBe(true)
    expect(wrapper.find('h1').text()).toBe('Savia')
  })

  it('renders server URL, username and token inputs', () => {
    const wrapper = shallowMount(LoginPage)
    expect(wrapper.find('input[placeholder*="localhost"]').exists()).toBe(true)
    expect(wrapper.find('input[placeholder="@your-handle"]').exists()).toBe(true)
    expect(wrapper.find('input[type="password"]').exists()).toBe(true)
  })

  it('shows error if username does not start with @', async () => {
    const wrapper = shallowMount(LoginPage)
    await wrapper.find('input[placeholder="@your-handle"]').setValue('alice')
    await wrapper.find('.btn-connect').trigger('click')
    expect(wrapper.find('.error-msg').text()).toContain('must start with @')
  })

  it('shows error when bridge is not reachable', async () => {
    vi.mocked(fetch).mockResolvedValueOnce({ ok: false } as Response)
    const wrapper = shallowMount(LoginPage)
    await wrapper.find('input[placeholder="@your-handle"]').setValue('@alice')
    await wrapper.find('.btn-connect').trigger('click')
    await vi.waitFor(() => {
      expect(wrapper.find('.error-msg').exists()).toBe(true)
    })
  })
})

describe('LoginPage — SE-528 sesión del puente', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.mocked(fetch).mockReset()
  })

  function json(body: unknown, ok = true): Response {
    return { ok, json: async () => body } as Response
  }

  async function connectWith(loginBody: unknown) {
    vi.mocked(fetch)
      .mockResolvedValueOnce(json({ status: 'ok' }))                        // /health
      .mockResolvedValueOnce(json({ members: [{ slug: 'alice', name: 'Alice' }] })) // /team
      .mockResolvedValueOnce(json({}, false))                               // /auth/register
      .mockResolvedValueOnce(json(loginBody))                               // /auth/login
    const wrapper = shallowMount(LoginPage)
    await wrapper.find('input[placeholder="@your-handle"]').setValue('@alice')
    await wrapper.find('input[type="password"]').setValue('tok-secret')
    await wrapper.find('.btn-connect').trigger('click')
    const { useAuthStore } = await import('../../stores/auth')
    const auth = useAuthStore()
    await vi.waitFor(() => expect(auth.isLoggedIn).toBe(true))
    const loginCall = vi.mocked(fetch).mock.calls[3] as [string, RequestInit]
    return { auth, loginCall }
  }

  function setPage(url: string) {
    (window as unknown as { happyDOM: { setURL(u: string): void } }).happyDOM.setURL(url)
  }

  it('web en otro sitio: aunque el puente diga cookie, el token queda en memoria', async () => {
    setPage('https://127.0.0.1:5173/')  // puente por defecto en https://localhost:8922
    const { auth } = await connectWith({ status: 'ok', session: 'cookie' })
    expect(auth.sessionMode).toBe('memory')
    expect(auth.token).toBe('tok-secret')
  })

  it('con sesión por cookie pide /auth/login con credenciales y no conserva el token', async () => {
    setPage('https://localhost:5173/')
    const { auth, loginCall } = await connectWith({ status: 'ok', session: 'cookie' })
    expect(loginCall[0]).toMatch(/\/auth\/login$/)
    expect(loginCall[1].method).toBe('POST')
    expect(loginCall[1].credentials).toBe('include')
    expect(auth.sessionMode).toBe('cookie')
    expect(auth.token).toBe('')
  })

  it('sin sesión por cookie el token queda solo en memoria', async () => {
    const { auth } = await connectWith({ status: 'ok', session: 'none' })
    expect(auth.sessionMode).toBe('memory')
    expect(auth.token).toBe('tok-secret')
    expect(document.cookie).not.toContain('tok-secret')
  })

  it('muestra la línea que explica por qué se vuelve al formulario', async () => {
    const { useAuthStore } = await import('../../stores/auth')
    const auth = useAuthStore()
    const wrapper = shallowMount(LoginPage)
    expect(wrapper.find('[data-testid="login-notice"]').exists()).toBe(false)
    auth.notice = 'acceso antiguo'
    await wrapper.vm.$nextTick()
    expect(wrapper.find('[data-testid="login-notice"]').text()).toBe('acceso antiguo')
  })
})
