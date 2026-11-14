import { useAuthStore } from '../stores/auth'

export function useBridge() {
  function baseUrl(): string {
    const auth = useAuthStore()
    const proto = auth.useTls ? 'https' : 'http'
    return `${proto}://${auth.host}:${auth.port}`
  }

  function headers(): HeadersInit {
    const auth = useAuthStore()
    const h: HeadersInit = { 'Content-Type': 'application/json' }
    if (auth.token) h['Authorization'] = `Bearer ${auth.token}`
    return h
  }

  async function get<T>(path: string): Promise<T | null> {
    try {
      const res = await fetch(`${baseUrl()}${path}`, { headers: headers(), credentials: 'include' })
      if (!res.ok) return null
      return await res.json() as T
    } catch {
      return null
    }
  }

  async function post<T>(path: string, body: unknown): Promise<T | null> {
    try {
      const res = await fetch(`${baseUrl()}${path}`, {
        method: 'POST', headers: headers(), credentials: 'include', body: JSON.stringify(body)
      })
      if (!res.ok) return null
      return await res.json() as T
    } catch {
      return null
    }
  }

  async function healthCheck(): Promise<boolean> {
    try {
      const res = await fetch(`${baseUrl()}/dashboard`, { headers: headers(), credentials: 'include' })
      return res.ok
    } catch {
      return false
    }
  }

  return { get, post, healthCheck, baseUrl, headers }
}
