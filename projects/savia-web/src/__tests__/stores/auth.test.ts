import { describe, it, expect, beforeEach } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useAuthStore } from '../../stores/auth'

describe('useAuthStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    // Clear cookies
    document.cookie = 'savia_session=; path=/; max-age=0'
  })

  it('defaults to localhost serverUrl', () => {
    const auth = useAuthStore()
    expect(auth.serverUrl).toContain('localhost')
  })

  it('defaults to empty token', () => {
    const auth = useAuthStore()
    expect(auth.token).toBe('')
  })

  it('defaults connected to false', () => {
    const auth = useAuthStore()
    expect(auth.connected).toBe(false)
  })

  it('computes host from serverUrl', () => {
    const auth = useAuthStore()
    auth.save('myserver', '9000', 'tok', false)
    expect(auth.host).toBe('myserver')
    expect(auth.port).toBe('9000')
  })

  it('computes useTls from serverUrl', () => {
    const auth = useAuthStore()
    auth.save('srv', '443', '', true)
    expect(auth.useTls).toBe(true)
  })

  describe('login', () => {
    it('sets connected, profile, and a connection cookie without the token (SE-528)', () => {
      const auth = useAuthStore()
      auth.login('https://localhost:8922', '@alice', 'tok-abc', { slug: 'alice', name: 'Alice', role: 'PM' })
      expect(auth.connected).toBe(true)
      expect(auth.profileName).toBe('Alice')
      expect(auth.isLoggedIn).toBe(true)
      expect(document.cookie).toContain('savia_connection')
      expect(document.cookie).not.toContain('tok-abc')
    })
  })

  describe('logout', () => {
    it('clears state and cookie', () => {
      const auth = useAuthStore()
      auth.login('https://localhost:8922', '@alice', 'tok', { slug: 'alice', name: 'Alice' })
      auth.logout()
      expect(auth.connected).toBe(false)
      expect(auth.token).toBe('')
      expect(auth.username).toBe('')
      expect(auth.profile).toBeNull()
      expect(auth.isLoggedIn).toBe(false)
    })
  })

  describe('save (legacy compat)', () => {
    it('updates serverUrl from host/port', () => {
      const auth = useAuthStore()
      auth.save('newhost', '9000', 'tok-abc', true)
      expect(auth.serverUrl).toBe('https://newhost:9000')
      expect(auth.token).toBe('tok-abc')
    })
  })

  describe('setConnected', () => {
    it('sets connected state', () => {
      const auth = useAuthStore()
      auth.setConnected(true)
      expect(auth.connected).toBe(true)
      auth.setConnected(false)
      expect(auth.connected).toBe(false)
    })
  })
})
