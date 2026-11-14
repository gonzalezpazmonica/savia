// SE-528 (lado web del S2): el token no se guarda en el navegador, la sesión
// por cookie la emite el puente (HttpOnly) y un enlace con credencial en la
// dirección lleva al formulario con una línea que dice por qué.
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useAuthStore } from '../../stores/auth'
import { authHeaders, hasLegacyCredentialInUrl, stripLegacyCredentialFromUrl } from '../../utils/bridgeAuth'

const TOKEN = 'secret-token-abc'

function clearAllCookies() {
  for (const c of document.cookie.split('; ')) {
    const name = c.split('=')[0]
    if (name) document.cookie = `${name}=; path=/; max-age=0`
  }
}

function browserStorageText(): string {
  const parts = [document.cookie]
  for (const s of [localStorage, sessionStorage]) {
    for (let i = 0; i < s.length; i++) {
      const k = s.key(i)!
      parts.push(k, s.getItem(k) || '')
    }
  }
  return parts.join('\n')
}

describe('SE-528 sesión web', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    clearAllCookies()
    localStorage.clear()
    sessionStorage.clear()
  })
  afterEach(() => { vi.restoreAllMocks() })

  it('login en modo memoria: el token no llega al almacenamiento del navegador', () => {
    const auth = useAuthStore()
    auth.login('http://localhost:8922', '@alice', TOKEN, null, 'memory')
    expect(auth.isLoggedIn).toBe(true)
    expect(auth.token).toBe(TOKEN)
    expect(browserStorageText()).not.toContain(TOKEN)
  })

  it('login con sesión por cookie: el cliente no conserva el token', () => {
    const auth = useAuthStore()
    auth.login('https://localhost:8922', '@alice', TOKEN, null, 'cookie')
    expect(auth.isLoggedIn).toBe(true)
    expect(auth.token).toBe('')
    expect(browserStorageText()).not.toContain(TOKEN)
  })

  it('una sesión antigua con el token en cookie legible se borra y pide el token (Q3)', () => {
    const legacy = encodeURIComponent(JSON.stringify({ serverUrl: 'https://localhost:8922', username: '@alice', token: TOKEN }))
    document.cookie = `savia_session=${legacy}; path=/`
    document.cookie = `savia_connection=${legacy}; path=/`
    const auth = useAuthStore()
    expect(auth.token).toBe('')
    expect(auth.isLoggedIn).toBe(false)
    expect(browserStorageText()).not.toContain(TOKEN)
    // Conserva lo no secreto para no obligar a reescribirlo.
    expect(auth.serverUrl).toBe('https://localhost:8922')
    expect(auth.username).toBe('@alice')
  })

  it('tras recargar en modo memoria vuelve al formulario', async () => {
    const first = useAuthStore()
    first.login('http://localhost:8922', '@alice', TOKEN, null, 'memory')
    setActivePinia(createPinia())
    const auth = useAuthStore()
    const fetchSpy = vi.spyOn(globalThis, 'fetch')
    expect(await auth.restore()).toBe(false)
    expect(auth.isLoggedIn).toBe(false)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('tras recargar con sesión por cookie comprueba /auth/session con credenciales', async () => {
    const first = useAuthStore()
    first.login('https://localhost:8922', '@alice', TOKEN, null, 'cookie')
    setActivePinia(createPinia())
    const auth = useAuthStore()
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{"authenticated":true}', { status: 200 }))
    expect(await auth.restore()).toBe(true)
    expect(auth.isLoggedIn).toBe(true)
    const [url, init] = fetchSpy.mock.calls[0] as [string, RequestInit]
    expect(url).toBe('https://localhost:8922/auth/session')
    expect(init.credentials).toBe('include')
    expect(JSON.stringify(init.headers || {})).not.toContain('Authorization')
  })

  it('con la cookie caducada o manipulada (401) vuelve al formulario', async () => {
    const first = useAuthStore()
    first.login('https://localhost:8922', '@alice', TOKEN, null, 'cookie')
    setActivePinia(createPinia())
    const auth = useAuthStore()
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{}', { status: 401 }))
    expect(await auth.restore()).toBe(false)
    expect(auth.isLoggedIn).toBe(false)
  })

  it('logout invalida la sesión en el puente', async () => {
    const auth = useAuthStore()
    auth.login('https://localhost:8922', '@alice', TOKEN, null, 'cookie')
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }))
    await auth.logout()
    const [url, init] = fetchSpy.mock.calls[0] as [string, RequestInit]
    expect(url).toBe('https://localhost:8922/auth/logout')
    expect(init.method).toBe('POST')
    expect(init.credentials).toBe('include')
    expect(auth.isLoggedIn).toBe(false)
  })

  it('authHeaders no manda «Bearer » vacío', () => {
    expect(authHeaders('')).toEqual({})
    expect(authHeaders(TOKEN)).toEqual({ Authorization: `Bearer ${TOKEN}` })
  })

  it('detecta credenciales en la dirección y las quita del historial (Q5)', () => {
    expect(hasLegacyCredentialInUrl('?token=abc')).toBe(true)
    expect(hasLegacyCredentialInUrl('?x=1&Access_Token=abc')).toBe(true)
    expect(hasLegacyCredentialInUrl('?project=alpha')).toBe(false)
    expect(hasLegacyCredentialInUrl('')).toBe(false)
    window.history.replaceState(null, '', `/chat?token=${TOKEN}&project=alpha#top`)
    expect(stripLegacyCredentialFromUrl()).toBe(true)
    expect(window.location.href).not.toContain(TOKEN)
    expect(window.location.search).toBe('?project=alpha')
    expect(window.location.hash).toBe('#top')
    expect(stripLegacyCredentialFromUrl()).toBe(false)
  })
})
